import UIKit

struct ImageSendParams {
    let localId: String
    let channelIdStr: String
    let clanId: Int64
    let channelId: Int64
    let mode: Int32
    let isPublic: Bool
    let topicId: Int64
    let hasText: Bool
    let contentStr: String
    let outgoingContentData: Data
    let mentionList: [Mezon_Api_MessageMention]
    let mentionsPayload: Data
    let references: [Mezon_Api_MessageRef]
    let pendingReferencesData: Data
    let avatar: String
    let pendingSenderDisplayName: String
    let pendingSenderAvatarURL: String?
    let images: [UIImage]
    let fileURLs: [Int: URL]
    let files: [PickedFileInfo]
}

enum ImageUploadItemState {
    case uploading
    case uploaded(Mezon_Api_MessageAttachment)
    case failed

    var isUploading: Bool { if case .uploading = self { return true } else { return false } }
    var isFailed: Bool { if case .failed = self { return true } else { return false } }
    var uploadedAttachment: Mezon_Api_MessageAttachment? {
        if case let .uploaded(att) = self { return att } else { return nil }
    }
}

final class ImageUploadItem {
    let image: UIImage
    let fileURL: URL?
    var state: ImageUploadItemState = .uploading

    init(image: UIImage, fileURL: URL?) {
        self.image = image
        self.fileURL = fileURL
    }
}

final class ImageUploadSession {
    let params: ImageSendParams
    var items: [ImageUploadItem]
    var fileAttachments: [Mezon_Api_MessageAttachment] = []
    var serverMessageId: Int64 = 0
    var hasSent = false
    var aborted = false
    var finished = false
    var lastSentAttachmentCount = 0

    init(params: ImageSendParams) {
        self.params = params
        self.items = params.images.enumerated().map { idx, img in
            ImageUploadItem(image: img, fileURL: params.fileURLs[idx])
        }
    }
}

final class AttachmentUploadCoordinator {

    static let shared = AttachmentUploadCoordinator()
    private init() {}

    private static let editBatchSize = 4
    private static let maxConcurrentUploads = 4

    private let lock = NSLock()
    private var sessionsByKey: [String: ImageUploadSession] = [:]

    // MARK: - Store

    private func register(_ session: ImageUploadSession, key: String) {
        lock.lock(); defer { lock.unlock() }
        sessionsByKey[key] = session
    }

    private func session(forKey key: String) -> ImageUploadSession? {
        lock.lock(); defer { lock.unlock() }
        return sessionsByKey[key]
    }

    private func remove(_ session: ImageUploadSession) {
        lock.lock(); defer { lock.unlock() }
        sessionsByKey = sessionsByKey.filter { $0.value !== session }
    }

    func activeMessageIds() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(sessionsByKey.keys)
    }

    func pruneSessions(keepingMessageIds keep: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        sessionsByKey = sessionsByKey.filter { keep.contains($0.key) }
    }

    // MARK: - Overlay for rendering

    func imageOverlay(for messageId: String) -> [ParsedAttachment]? {
        guard let session = session(forKey: messageId) else { return nil }
        return session.items.map { item -> ParsedAttachment in
            switch item.state {
            case let .uploaded(att):
                return ParsedAttachment(
                    url: att.url,
                    filename: att.filename,
                    filetype: att.filetype,
                    width: att.width != 0 ? Int(att.width) : Int(item.image.size.width),
                    height: att.height != 0 ? Int(att.height) : Int(item.image.size.height),
                    durationSeconds: att.duration != 0 ? Int(att.duration) : nil,
                    localImage: item.image,
                    isUploading: false,
                    uploadFailed: false
                )
            case .uploading:
                return ParsedAttachment(
                    url: "",
                    filename: "uploading.jpg",
                    filetype: "image/jpeg",
                    width: Int(item.image.size.width),
                    height: Int(item.image.size.height),
                    durationSeconds: nil,
                    localImage: item.image,
                    isUploading: true,
                    uploadFailed: false
                )
            case .failed:
                return ParsedAttachment(
                    url: "",
                    filename: "failed.jpg",
                    filetype: "image/jpeg",
                    width: Int(item.image.size.width),
                    height: Int(item.image.size.height),
                    durationSeconds: nil,
                    localImage: item.image,
                    isUploading: false,
                    uploadFailed: true
                )
            }
        }
    }

    // MARK: - Public API

    @MainActor
    func startImageSend(
        context: AccountContext,
        params: ImageSendParams,
        prepare: ((String) async -> Void)? = nil
    ) {
        let session = ImageUploadSession(params: params)
        register(session, key: params.localId)

        if let sender = context.currentUser {
            let record = MessageRecord.pending(
                localId: params.localId,
                text: "",
                channelId: params.channelIdStr,
                clanId: params.clanId,
                sender: sender,
                displayName: params.pendingSenderDisplayName,
                avatarURL: params.pendingSenderAvatarURL,
                referencesData: params.pendingReferencesData,
                mentionsData: params.mentionsPayload,
                contentData: params.outgoingContentData
            )
            context.account.postbox.write { tx in tx.addMessages([record]) }
        }

        Task { @MainActor in
            await self.runUploads(session, context: context, prepare: prepare)
        }
    }

    @MainActor
    func retry(context: AccountContext, messageId: String, itemIndex: Int) {
        guard let session = session(forKey: messageId) else { return }
        guard itemIndex >= 0, itemIndex < session.items.count else { return }
        guard session.items[itemIndex].state.isFailed, !session.aborted else { return }

        session.items[itemIndex].state = .uploading
        session.finished = false
        nudge(session, context: context)

        Task { @MainActor in
            guard let token = await context.getToken() else {
                session.items[itemIndex].state = .failed
                self.nudge(session, context: context)
                return
            }
            let att = await self.uploadOneImage(session.items[itemIndex], context: context, token: token)
            session.items[itemIndex].state = att.map { .uploaded($0) } ?? .failed
            self.nudge(session, context: context)
            await self.afterStateChange(session, context: context, token: token, forceFlush: true)
        }
    }

    // MARK: - Orchestration

    @MainActor
    private func runUploads(
        _ session: ImageUploadSession,
        context: AccountContext,
        prepare: ((String) async -> Void)?
    ) async {
        guard let token = await context.getToken() else {
            for item in session.items where item.state.isUploading { item.state = .failed }
            finalizeAllFailed(session, context: context)
            return
        }

        await uploadFiles(session, context: context, token: token)
        await prepare?(token)

        var nextIndex = 0
        await withTaskGroup(of: (Int, Mezon_Api_MessageAttachment?).self) { group in
            func addNext() {
                guard nextIndex < session.items.count else { return }
                let index = nextIndex
                nextIndex += 1
                let item = session.items[index]
                group.addTask {
                    let att = await self.uploadOneImage(item, context: context, token: token)
                    return (index, att)
                }
            }

            for _ in 0..<Self.maxConcurrentUploads { addNext() }

            for await (index, att) in group {
                session.items[index].state = att.map { .uploaded($0) } ?? .failed
                self.nudge(session, context: context)
                addNext()
                await self.afterStateChange(session, context: context, token: token)
            }
        }

        await afterStateChange(session, context: context, token: token, forceFlush: true)
    }

    @MainActor
    private func afterStateChange(
        _ session: ImageUploadSession,
        context: AccountContext,
        token: String,
        forceFlush: Bool = false
    ) async {
        guard !session.aborted else { return }

        let completedCount = session.items.filter { !$0.state.isUploading }.count
        let allResolved = completedCount == session.items.count
        let ready = readyAttachments(session)

        if !session.hasSent {
            let canSend = !ready.isEmpty || (allResolved && session.params.hasText)
            if !canSend {
                if allResolved { finalizeAllFailed(session, context: context) }
                return
            }
            session.lastSentAttachmentCount = ready.count
            await doFirstSend(session, context: context, token: token, attachments: ready)
        } else if session.serverMessageId != 0 {
            let pendingNew = ready.count - session.lastSentAttachmentCount
            let shouldUpdate = pendingNew > 0 && (forceFlush || pendingNew >= Self.editBatchSize || allResolved)
            guard shouldUpdate else { return }
            session.lastSentAttachmentCount = ready.count
            await doUpdate(session, context: context, token: token, attachments: ready)
        }

        if allResolved { finalizeSuccessIfNeeded(session, context: context, ready: ready) }
    }

    @MainActor
    private func doFirstSend(
        _ session: ImageUploadSession,
        context: AccountContext,
        token: String,
        attachments: [Mezon_Api_MessageAttachment]
    ) async {
        let p = session.params
        do {
            let ack = try await context.account.network.sendChannelMessage(
                clanId: p.clanId,
                channelId: p.channelId,
                mode: p.mode,
                isPublic: p.isPublic,
                content: p.contentStr,
                mentions: p.mentionList,
                attachments: attachments,
                references: p.references,
                anonymous: false,
                mentionEveryone: false,
                avatar: p.avatar,
                topicId: p.topicId,
                token: token
            )
            session.hasSent = true
            session.serverMessageId = ack.messageID
            if ack.messageID != 0 {
                register(session, key: "\(ack.messageID)")
            }
            context.account.postbox.write { tx in
                if tx.getMessageById(p.localId) != nil {
                    tx.markMessageSent(id: p.localId)
                }
            }
            ClanOnboardingChannelCache.markCreatorSentWelcomeMessageIfNeeded(
                postbox: context.account.postbox,
                clanId: p.clanId,
                channelId: p.channelId,
                messageId: ack.messageID
            )
            nudge(session, context: context)
        } catch {
            session.aborted = true
            SentryLogger.capture(error, extras: [
                "where": "AttachmentUploadCoordinator.doFirstSend",
                "channelId": p.channelId,
                "clanId": p.clanId,
            ])
            context.account.postbox.write { tx in tx.markMessageFailed(id: p.localId) }
        }
    }

    @MainActor
    private func doUpdate(
        _ session: ImageUploadSession,
        context: AccountContext,
        token: String,
        attachments: [Mezon_Api_MessageAttachment]
    ) async {
        let p = session.params
        do {
            _ = try await context.account.network.updateChannelMessage(
                clanId: p.clanId,
                channelId: p.channelId,
                mode: p.mode,
                isPublic: p.isPublic,
                messageId: session.serverMessageId,
                content: p.contentStr,
                mentions: p.mentionList,
                attachments: attachments,
                hideEditted: true,
                topicId: p.topicId,
                isUpdateMsgTopic: false,
                token: token
            )
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "AttachmentUploadCoordinator.doUpdate",
                "channelId": p.channelId,
                "messageId": session.serverMessageId,
            ])
        }
    }

    @MainActor
    private func finalizeSuccessIfNeeded(
        _ session: ImageUploadSession,
        context: AccountContext,
        ready: [Mezon_Api_MessageAttachment]
    ) {
        let anyFailed = session.items.contains { $0.state.isFailed }
        if !anyFailed, session.hasSent, session.serverMessageId != 0 {
            writeFinalAttachments(session, context: context, attachments: ready)
            clearDocumentPlaceholders(session)
            remove(session)
        } else {
            session.finished = true
            nudge(session, context: context)
        }
    }

    @MainActor
    private func finalizeAllFailed(_ session: ImageUploadSession, context: AccountContext) {
        session.finished = true
        let id = session.serverMessageId != 0 ? "\(session.serverMessageId)" : session.params.localId
        context.account.postbox.write { tx in tx.markMessageFailed(id: id) }
        nudge(session, context: context)
    }

    @MainActor
    private func writeFinalAttachments(
        _ session: ImageUploadSession,
        context: AccountContext,
        attachments: [Mezon_Api_MessageAttachment]
    ) {
        let serverKey = "\(session.serverMessageId)"
        let localId = session.params.localId
        context.account.postbox.write { tx in
            guard let old = tx.getMessageById(serverKey) ?? tx.getMessageById(localId) else { return }
            let newAttachmentsJSON: Data = {
                guard !attachments.isEmpty else { return old.attachmentsJSON }
                var list = Mezon_Api_MessageAttachmentList()
                list.attachments = attachments
                return (try? list.serializedData()) ?? old.attachmentsJSON
            }()
            let updated = MessageRecord(
                id: old.id,
                channelId: old.channelId,
                clanId: old.clanId,
                senderId: old.senderId,
                content: old.content,
                createdAt: old.createdAt,
                editedAt: old.editedAt,
                isDeleted: old.isDeleted,
                code: old.code,
                senderDisplayName: old.senderDisplayName,
                senderAvatarURL: old.senderAvatarURL,
                sendingState: .sent,
                attachmentsJSON: newAttachmentsJSON,
                reactionsJSON: old.reactionsJSON,
                referencesData: old.referencesData,
                mentionsJSON: old.mentionsJSON
            )
            tx.addMessages([updated])
        }
    }

    // MARK: - Upload primitives

    private func readyAttachments(_ session: ImageUploadSession) -> [Mezon_Api_MessageAttachment] {
        var result = session.items.compactMap { $0.state.uploadedAttachment }
        result.append(contentsOf: session.fileAttachments)
        return result
    }

    @MainActor
    private func uploadFiles(_ session: ImageUploadSession, context: AccountContext, token: String) async {
        for file in session.params.files {
            guard let size = await Self.fileSize(of: file.url) else { continue }
            let sanitized = file.filename.replacingOccurrences(
                of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            do {
                let uploadInfo = try await context.account.network.uploadAttachmentFile(
                    filename: sanitized, filetype: file.filetype, size: size,
                    width: 0, height: 0, token: token)
                try await context.account.network.uploadToMinIO(
                    url: uploadInfo.url, fileURL: file.url, contentType: file.filetype)
                let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                var att = Mezon_Api_MessageAttachment()
                att.filename = file.filename
                att.url = cdnURL
                att.filetype = file.filetype
                att.size = Int32(size)
                session.fileAttachments.append(att)
                try? FileManager.default.removeItem(at: file.url)
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "AttachmentUploadCoordinator.uploadFiles",
                    "filename": file.filename,
                ])
            }
        }
    }

    @MainActor
    private func uploadOneImage(
        _ item: ImageUploadItem,
        context: AccountContext,
        token: String
    ) async -> Mezon_Api_MessageAttachment? {
        guard let fileURL = item.fileURL else { return nil }

        let image = item.image
        let originalFilename = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let filetype = SendMessageInputViewController.mimeType(for: ext)
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let sanitized = originalFilename.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let isVideo = filetype.hasPrefix("video/")

        do {
            var att = Mezon_Api_MessageAttachment()
            att.filename = originalFilename
            att.filetype = filetype
            att.width = Int32(width)
            att.height = Int32(height)

            if isVideo {
                guard let size = await Self.fileSize(of: fileURL) else { return nil }
                let uploadInfo = try await context.account.network.uploadAttachmentFile(
                    filename: sanitized, filetype: filetype, size: size,
                    width: width, height: height, token: token)
                try await context.account.network.uploadToMinIO(
                    url: uploadInfo.url, fileURL: fileURL, contentType: filetype)
                att.url = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                att.size = Int32(size)
                att.thumbnail = await uploadVideoThumbnail(
                    image, originalFilename: sanitized, context: context, token: token)
            } else {
                let isGif = filetype == "image/gif" || ext == "gif"
                guard let payload = await Self.imageUploadPayload(
                    image: image, fileURL: fileURL, filetype: filetype,
                    filename: sanitized, isGif: isGif) else { return nil }
                let uploadInfo = try await context.account.network.uploadAttachmentFile(
                    filename: payload.filename, filetype: payload.filetype, size: payload.data.count,
                    width: width, height: height, token: token)
                try await context.account.network.uploadToMinIO(
                    url: uploadInfo.url, data: payload.data, contentType: payload.filetype)
                let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                ImageCache.shared.setImage(image, data: payload.data, forKey: cdnURL)
                att.filename = payload.filename
                att.filetype = payload.filetype
                att.url = cdnURL
                att.size = Int32(payload.data.count)
            }

            try? FileManager.default.removeItem(at: fileURL)
            return att
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "AttachmentUploadCoordinator.uploadOneImage",
                "filename": originalFilename,
            ])
            return nil
        }
    }

    @MainActor
    private func uploadVideoThumbnail(
        _ thumbnail: UIImage,
        originalFilename: String,
        context: AccountContext,
        token: String
    ) async -> String {
        guard let thumbData = await Self.encodeJPEG(thumbnail, quality: 0.7) else { return "" }

        let baseName = (originalFilename as NSString).deletingPathExtension
        let thumbFilename = "\(baseName.isEmpty ? "video" : baseName)_thumb.jpg"
        let width = Int(thumbnail.size.width)
        let height = Int(thumbnail.size.height)

        do {
            let uploadInfo = try await context.account.network.uploadAttachmentFile(
                filename: thumbFilename, filetype: "image/jpeg", size: thumbData.count,
                width: width, height: height, token: token)
            try await context.account.network.uploadToMinIO(
                url: uploadInfo.url, data: thumbData, contentType: "image/jpeg")
            let thumbCdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
            ImageCache.shared.setImage(thumbnail, data: thumbData, forKey: thumbCdnURL)
            return thumbCdnURL
        } catch {
            return ""
        }
    }

    // MARK: - Background I/O

    private static let imageCompressionQuality: CGFloat = 0.9

    private struct ImageUploadPayload {
        let data: Data
        let filetype: String
        let filename: String
    }

    private nonisolated static func imageUploadPayload(
        image: UIImage, fileURL: URL, filetype: String, filename: String, isGif: Bool
    ) async -> ImageUploadPayload? {
        await Task.detached(priority: .utility) {
            if !isGif, let jpeg = image.jpegData(compressionQuality: imageCompressionQuality) {
                let base = (filename as NSString).deletingPathExtension
                let name = "\(base.isEmpty ? "image" : base).jpg"
                return ImageUploadPayload(data: jpeg, filetype: "image/jpeg", filename: name)
            }
            guard let raw = try? Data(contentsOf: fileURL) else { return nil }
            return ImageUploadPayload(data: raw, filetype: filetype, filename: filename)
        }.value
    }

    private nonisolated static func fileSize(of url: URL) async -> Int? {
        await Task.detached(priority: .utility) {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        }.value?.intValue
    }

    private nonisolated static func encodeJPEG(_ image: UIImage, quality: CGFloat) async -> Data? {
        await Task.detached(priority: .utility) { image.jpegData(compressionQuality: quality) }.value
    }

    // MARK: - Helpers

    @MainActor
    private func nudge(_ session: ImageUploadSession, context: AccountContext) {
        let serverKey = "\(session.serverMessageId)"
        let localId = session.params.localId
        context.account.postbox.write { tx in
            if session.serverMessageId != 0, let r = tx.getMessageById(serverKey) {
                tx.addMessages([r])
            } else if let r = tx.getMessageById(localId) {
                tx.addMessages([r])
            }
        }
    }

    @MainActor
    private func clearDocumentPlaceholders(_ session: ImageUploadSession) {
        guard !session.params.files.isEmpty else { return }
        ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: session.params.localId)
        if session.serverMessageId != 0 {
            ParsedAttachment.pendingDocumentPlaceholders.removeValue(forKey: "\(session.serverMessageId)")
        }
    }
}
