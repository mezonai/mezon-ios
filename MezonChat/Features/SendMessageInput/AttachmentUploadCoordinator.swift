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
    let skipOptimisticPending: Bool
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
    let showsUploadPercent: Bool
    var state: ImageUploadItemState = .uploading
    var reservedAttachment: Mezon_Api_MessageAttachment?
    var presignKey: String = ""
    fileprivate var pendingUploads: [PendingMinIOUpload] = []

    init(image: UIImage, fileURL: URL?, showsUploadPercent: Bool = false) {
        self.image = image
        self.fileURL = fileURL
        self.showsUploadPercent = showsUploadPercent
    }
}

fileprivate struct MultipartPlan {
    let fileURL: URL
    let partURLs: [String]
    let uploadId: String
    let filename: String
    let fileSize: Int
    let contentType: String
}

fileprivate struct PendingMinIOUpload {
    enum Body {
        case data(Data)
        case file(URL)
        case multipart(MultipartPlan)
    }

    let minioURL: String
    let contentType: String
    let body: Body
    let progressKey: String
    let cacheImage: (image: UIImage, data: Data, cdnURL: String)?
}

fileprivate final class FileUploadTrack {
    let file: PickedFileInfo
    let presignKey: String
    var attachment: Mezon_Api_MessageAttachment
    var pending: PendingMinIOUpload
    var state: ImageUploadItemState = .uploading

    init(file: PickedFileInfo, presignKey: String, attachment: Mezon_Api_MessageAttachment, pending: PendingMinIOUpload) {
        self.file = file
        self.presignKey = presignKey
        self.attachment = attachment
        self.pending = pending
    }
}

final class ImageUploadSession {
    let params: ImageSendParams
    let outgoingBase: Data
    var items: [ImageUploadItem]
    fileprivate var fileTracks: [FileUploadTrack] = []
    var serverMessageId: Int64 = 0
    var serverCreateTimeSeconds: UInt32 = 0
    var aborted = false
    var finished = false
    var isSending = false
    var presignFinishedKeys: [String] = []
    var lastSyncedPresignCount = 0
    var isPresignSyncInFlight = false
    var usesPresignSync = true

    init(params: ImageSendParams) {
        self.params = params
        self.outgoingBase = PresignFinishContent.presignSyncOriginContent(params.outgoingContentData)
        self.items = params.images.enumerated().map { idx, img in
            let url = params.fileURLs[idx]
            return ImageUploadItem(
                image: img,
                fileURL: url,
                showsUploadPercent: ImageUploadSession.shouldShowUploadPercent(for: url))
        }
    }

    private static func shouldShowUploadPercent(for fileURL: URL?) -> Bool {
        guard let fileURL else { return false }
        let ext = fileURL.pathExtension.lowercased()
        guard SendMessageInputViewController.mimeType(for: ext).hasPrefix("video/") else { return false }
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.intValue ?? 0
        return size >= AttachmentUploader.minMultipartFileSize
    }
}

final class AttachmentUploadCoordinator {

    static let shared = AttachmentUploadCoordinator()
    private init() {}

    private static let maxConcurrentUploads = 4
    private static let presignEditBatchSize = 4
    private static let presignSendFirstMinCount = 4
    private static let progressNotificationBucketCount = 20
    private static let presignFinishSyncDelayNanos: UInt64 = 500_000_000
    private static let multipartMaxParallelParts = 3
    private static let autoRetryReserveDelayNanos: UInt64 = 1_000_000_000

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

    func hasActiveProgressKey(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        for session in sessionsByKey.values {
            if session.items.contains(where: { $0.fileURL?.path == key }) { return true }
            if session.fileTracks.contains(where: { $0.file.url.path == key }) { return true }
            if session.params.files.contains(where: { $0.url.path == key }) { return true }
        }
        return false
    }

    func pruneSessions(keepingMessageIds keep: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        sessionsByKey = sessionsByKey.filter { keep.contains($0.key) }
    }

    // MARK: - Overlay for rendering

    func fileOverlay(for messageId: String) -> [ParsedAttachment]? {
        guard let session = session(forKey: messageId) else { return nil }
        guard !session.fileTracks.isEmpty else { return nil }
        return session.fileTracks.map { track -> ParsedAttachment in
            let progressKey = track.file.url.path
            switch track.state {
            case let .uploaded(att):
                return ParsedAttachment(
                    url: att.url,
                    filename: att.filename,
                    filetype: att.filetype,
                    width: att.width != 0 ? Int(att.width) : nil,
                    height: att.height != 0 ? Int(att.height) : nil,
                    durationSeconds: nil,
                    isUploading: false,
                    uploadFailed: false
                )
            case .uploading:
                return ParsedAttachment(
                    url: track.attachment.url,
                    filename: track.attachment.filename,
                    filetype: track.attachment.filetype,
                    width: track.attachment.width != 0 ? Int(track.attachment.width) : nil,
                    height: track.attachment.height != 0 ? Int(track.attachment.height) : nil,
                    durationSeconds: nil,
                    isUploading: true,
                    uploadFailed: false,
                    uploadProgress: AttachmentUploadProgressStore.shared.progress(forKey: progressKey),
                    uploadProgressKey: progressKey,
                    uploadShowsPercent: Int(track.attachment.size) >= AttachmentUploader.minMultipartFileSize
                )
            case .failed:
                return ParsedAttachment(
                    url: track.attachment.url,
                    filename: track.attachment.filename,
                    filetype: track.attachment.filetype,
                    width: nil,
                    height: nil,
                    durationSeconds: nil,
                    isUploading: false,
                    uploadFailed: true
                )
            }
        }
    }

    func imageOverlay(for messageId: String) -> [ParsedAttachment]? {
        guard let session = session(forKey: messageId) else { return nil }
        guard !session.items.isEmpty else { return nil }
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
                    thumbnail: att.thumbnail,
                    localImage: item.image,
                    isUploading: false,
                    uploadFailed: false
                )
            case .uploading:
                return ParsedAttachment(
                    url: item.reservedAttachment?.url ?? "",
                    filename: item.reservedAttachment?.filename ?? "uploading.jpg",
                    filetype: item.reservedAttachment?.filetype ?? "image/jpeg",
                    width: Int(item.image.size.width),
                    height: Int(item.image.size.height),
                    durationSeconds: item.reservedAttachment.flatMap { att in
                        att.duration != 0 ? Int(att.duration) : nil
                    },
                    thumbnail: item.reservedAttachment?.thumbnail ?? "",
                    localImage: item.image,
                    isUploading: true,
                    uploadFailed: false,
                    uploadProgress: item.fileURL.map {
                        AttachmentUploadProgressStore.shared.progress(forKey: $0.path)
                    } ?? 0,
                    uploadProgressKey: item.fileURL?.path ?? "",
                    uploadShowsPercent: item.showsUploadPercent
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
        prepare: ((String) async throws -> Void)? = nil
    ) {
        let session = ImageUploadSession(params: params)
        register(session, key: params.localId)

        if !params.skipOptimisticPending, let sender = context.currentUser {
            let presignContent = PresignFinishContent.contentStringForSend(
                base: session.outgoingBase,
                presignKeys: []
            ).data(using: .utf8) ?? PresignFinishContent.injectEmptyPresignFinish(into: session.outgoingBase)
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
                contentData: presignContent
            )
            context.account.postbox.write { tx in tx.addMessages([record]) }
        }

        session.isSending = true
        Task { @MainActor in
            await self.runWithBackgroundTask {
                await self.runUploads(session, context: context, prepare: prepare)
            }
        }
    }

    @MainActor
    func retry(context: AccountContext, messageId: String, itemIndex: Int) {
        guard let session = session(forKey: messageId) else { return }
        if session.aborted || session.serverMessageId == 0 {
            _ = resendFailedSession(context: context, messageId: messageId)
            return
        }
        guard itemIndex >= 0, itemIndex < session.items.count else { return }
        guard session.items[itemIndex].state.isFailed else { return }
        guard session.items[itemIndex].reservedAttachment != nil else { return }

        session.items[itemIndex].state = .uploading
        session.finished = false
        Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))

        Task { @MainActor in
            await self.runWithBackgroundTask {
                let item = session.items[itemIndex]
                let success = await self.executeImageUpload(item, context: context)
                session.items[itemIndex].state = success ? .uploaded(item.reservedAttachment!) : .failed
                if success { self.markPresignFinished(session, key: item.presignKey) }
                Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))
                if success, let token = await context.getToken() {
                    await self.maybeSyncPresignFinish(session, context: context, token: token, forceFlush: true)
                }
                await self.finalizeIfComplete(session, context: context)
            }
        }
    }

    // MARK: - Orchestration

    @MainActor
    private func runWithBackgroundTask(_ body: @MainActor () async -> Void) async {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MezonAttachmentUpload") {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        defer {
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
        await body()
    }

    @MainActor
    private func runUploads(
        _ session: ImageUploadSession,
        context: AccountContext,
        prepare: ((String) async throws -> Void)?
    ) async {
        defer { session.isSending = false }
        guard let token = await prepareSendToken(context: context) else {
            for item in session.items where item.state.isUploading { item.state = .failed }
            finalizeAllFailed(session, context: context)
            return
        }

        await reserveAttachments(session, context: context, token: token)

        guard allAttachmentsReserved(session) else {
            finalizeAllFailed(session, context: context)
            return
        }

        let attachments = allReservedAttachments(session)

        do {
            try await prepare?(token)
        } catch {
            finalizeAllFailed(session, context: context)
            return
        }

        let canSend = !attachments.isEmpty || session.params.hasText
        if !canSend {
            finalizeAllFailed(session, context: context)
            return
        }

        let sendFirst = attachments.count >= Self.presignSendFirstMinCount
        if sendFirst {
            print("[MezonPresign] send-first mode count=\(attachments.count) localId=\(session.params.localId)")
            guard let sendToken = await context.getToken() else {
                finalizeAllFailed(session, context: context)
                return
            }
            await sendMessage(session, context: context, token: sendToken, attachments: attachments)

            guard !session.aborted else {
                return
            }

            guard let uploadToken = await context.getToken() else { return }
            await executeFileUploads(session, context: context, token: uploadToken)
            await executeImageUploads(session, context: context, token: uploadToken)
            await retryFailedUploads(session, context: context)
            await flushAllPresignFinish(session, context: context)
            if session.lastSyncedPresignCount < session.presignFinishedKeys.count {
                await retryFailedUploads(session, context: context)
                await flushAllPresignFinish(session, context: context)
            }
            await finalizeIfComplete(session, context: context)
            return
        }

        print("[MezonPresign] upload-first mode count=\(attachments.count) localId=\(session.params.localId)")
        session.usesPresignSync = false
        guard let uploadToken = await context.getToken() else {
            finalizeAllFailed(session, context: context)
            return
        }
        await executeFileUploads(session, context: context, token: uploadToken)
        await executeImageUploads(session, context: context, token: uploadToken)
        await retryFailedUploads(session, context: context)

        let uploaded = uploadedAttachments(session)
        print("[MezonPresign] uploads finished uploaded=\(uploaded.count)/\(attachments.count) localId=\(session.params.localId)")
        guard !uploaded.isEmpty || session.params.hasText else {
            finalizeAllFailed(session, context: context)
            return
        }
        guard let postUploadToken = await context.getToken() else {
            finalizeAllFailed(session, context: context)
            return
        }
        await sendMessage(session, context: context, token: postUploadToken, attachments: uploaded, includePresignFinish: false)
        guard !session.aborted else { return }
        print("[MezonPresign] message sent after uploads messageId=\(session.serverMessageId) localId=\(session.params.localId)")
        await finalizeIfComplete(session, context: context)
    }

    @MainActor
    private func prepareSendToken(context: AccountContext) async -> String? {
        _ = await context.account.socket.waitForConnected(timeoutNanoseconds: 3_000_000_000)
        return await context.getToken()
    }

    @MainActor
    private func allAttachmentsReserved(_ session: ImageUploadSession) -> Bool {
        let imagesReady = session.items.allSatisfy { $0.reservedAttachment != nil }
        let filesReady = session.fileTracks.count == session.params.files.count
        return imagesReady && filesReady
    }

    @MainActor
    private func reserveAttachments(
        _ session: ImageUploadSession,
        context: AccountContext,
        token: String
    ) async {
        await reserveFiles(session, context: context, token: token)
        await reserveImages(session, context: context, token: token)
        for _ in 0..<2 {
            let missingImageIndices = session.items.enumerated().compactMap { index, item -> Int? in
                item.reservedAttachment == nil ? index : nil
            }
            guard !missingImageIndices.isEmpty else { break }
            guard let retryToken = await context.getToken() else { break }
            for index in missingImageIndices {
                session.items[index].state = .uploading
                if !(await reserveOneImage(session.items[index], context: context, token: retryToken)) {
                    session.items[index].state = .failed
                }
            }
        }
    }

    @MainActor
    private func retryFailedUploads(
        _ session: ImageUploadSession,
        context: AccountContext
    ) async {
        let failedItems = session.items.indices.filter { session.items[$0].state.isFailed }
        let failedTracks = session.fileTracks.indices.filter { session.fileTracks[$0].state.isFailed }
        guard !failedItems.isEmpty || !failedTracks.isEmpty else { return }

        let reReserve = session.serverMessageId == 0

        if reReserve {
            for index in failedItems { session.items[index].state = .uploading }
            for index in failedTracks { session.fileTracks[index].state = .uploading }
            Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))
            try? await Task.sleep(nanoseconds: Self.autoRetryReserveDelayNanos)
        }

        guard let token = await context.getToken() else {
            if reReserve {
                for index in failedItems { session.items[index].state = .failed }
                for index in failedTracks { session.fileTracks[index].state = .failed }
                Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))
            }
            return
        }

        for index in failedItems {
            let item = session.items[index]
            item.state = .uploading
            if reReserve {
                _ = await reserveOneImage(item, context: context, token: token)
            }
            let ok: Bool
            if item.reservedAttachment != nil {
                ok = await executeImageUpload(item, context: context)
            } else {
                ok = false
            }
            session.items[index].state = ok ? .uploaded(item.reservedAttachment!) : .failed
            if ok { markPresignFinished(session, key: item.presignKey) }
            Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))
        }
        for index in failedTracks {
            let track = session.fileTracks[index]
            track.state = .uploading
            let ok = await executePendingUpload(track.pending, context: context)
            track.state = ok ? .uploaded(track.attachment) : .failed
            if ok {
                markPresignFinished(session, key: track.presignKey)
                try? FileManager.default.removeItem(at: track.file.url)
            }
            Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))
        }
    }

    @MainActor
    private func finalizeIfComplete(_ session: ImageUploadSession, context: AccountContext) async {
        guard !session.aborted else { return }
        let allResolved = session.items.allSatisfy { !$0.state.isUploading }
            && session.fileTracks.allSatisfy { !$0.state.isUploading }
        guard allResolved else { return }
        finalizeSuccessIfNeeded(session, context: context)
    }

    @MainActor
    private func sendMessage(
        _ session: ImageUploadSession,
        context: AccountContext,
        token: String,
        attachments: [Mezon_Api_MessageAttachment],
        includePresignFinish: Bool = true
    ) async {
        let p = session.params
        let contentStr: String
        let contentData: Data
        if includePresignFinish {
            contentStr = PresignFinishContent.contentStringForSend(base: session.outgoingBase, presignKeys: [])
            contentData = contentStr.data(using: .utf8) ?? PresignFinishContent.injectEmptyPresignFinish(into: session.outgoingBase)
        } else {
            contentData = session.outgoingBase
            contentStr = String(data: session.outgoingBase, encoding: .utf8) ?? "{}"
        }
        do {
            let ack = try await context.account.network.sendChannelMessage(
                clanId: p.clanId,
                channelId: p.channelId,
                mode: p.mode,
                isPublic: p.isPublic,
                content: contentStr,
                mentions: p.mentionList,
                attachments: attachments,
                references: p.references,
                anonymous: false,
                mentionEveryone: false,
                avatar: p.avatar,
                topicId: p.topicId,
                token: token
            )
            session.serverMessageId = ack.messageID
            session.serverCreateTimeSeconds = ack.createTimeSeconds
            guard ack.messageID != 0 else {
                session.aborted = true
                context.account.postbox.write { tx in tx.markMessageFailed(id: p.localId) }
                return
            }
            register(session, key: "\(ack.messageID)")
            if p.clanId == 0, p.topicId == 0 {
                DMListPreviewCache.updateLastSentMessage(
                    context: context,
                    channelId: p.channelId,
                    ack: ack,
                    content: contentStr,
                    hasAttachments: !attachments.isEmpty
                )
            }
            context.account.postbox.write { tx in
                let pending = tx.getMessageById(p.localId)
                let attachmentsJSON: Data = {
                    guard !attachments.isEmpty else { return pending?.attachmentsJSON ?? Data() }
                    var list = Mezon_Api_MessageAttachmentList()
                    list.attachments = attachments
                    return (try? list.serializedData()) ?? pending?.attachmentsJSON ?? Data()
                }()
                let createdAt: Date = ack.createTimeSeconds > 0
                    ? Date(timeIntervalSince1970: TimeInterval(ack.createTimeSeconds))
                    : (pending?.createdAt ?? Date())
                let editedAt: Date? = ack.updateTimeSeconds > ack.createTimeSeconds && ack.updateTimeSeconds > 0
                    ? Date(timeIntervalSince1970: TimeInterval(ack.updateTimeSeconds))
                    : nil
                let fallbackSenderId = context.currentUser?.id ?? ""
                let merged = MessageRecord(
                    id: "\(ack.messageID)",
                    channelId: pending?.channelId ?? p.channelIdStr,
                    clanId: pending?.clanId ?? (p.clanId == 0 ? nil : "\(p.clanId)"),
                    senderId: pending?.senderId ?? fallbackSenderId,
                    content: contentData,
                    createdAt: createdAt,
                    editedAt: editedAt,
                    isDeleted: pending?.isDeleted ?? false,
                    code: ack.code,
                    senderDisplayName: pending?.senderDisplayName ?? p.pendingSenderDisplayName,
                    senderAvatarURL: pending?.senderAvatarURL ?? p.pendingSenderAvatarURL,
                    sendingState: .sent,
                    attachmentsJSON: attachmentsJSON,
                    reactionsJSON: pending?.reactionsJSON ?? Data(),
                    referencesData: pending?.referencesData ?? p.pendingReferencesData,
                    mentionsJSON: pending?.mentionsJSON ?? p.mentionsPayload
                )
                tx.replaceMessage(pendingId: p.localId, with: merged)
            }
            ClanOnboardingChannelCache.markSendMessageOnboardingProgressIfNeeded(
                context: context,
                postbox: context.account.postbox,
                clanId: p.clanId,
                channelId: p.channelId,
                messageId: ack.messageID,
                messageCode: ack.code,
                anonymous: false
            )
            nudge(session, context: context)
        } catch {
            session.aborted = true
            SentryLogger.capture(error, extras: [
                "where": "AttachmentUploadCoordinator.sendMessage",
                "channelId": p.channelId,
                "clanId": p.clanId,
            ])
            context.account.postbox.write { tx in tx.markMessageFailed(id: p.localId) }
        }
    }

    @MainActor
    private func finalizeSuccessIfNeeded(
        _ session: ImageUploadSession,
        context: AccountContext
    ) {
        let anyFailed = session.items.contains { $0.state.isFailed }
            || session.fileTracks.contains { $0.state.isFailed }
        if !anyFailed, session.serverMessageId != 0 {
            let messageId = "\(session.serverMessageId)"
            clearDocumentPlaceholders(session)
            remove(session)
            Self.postUploadSlotStateChanged(messageId: messageId)
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

    @MainActor
    private func resolveCreateTimeSeconds(
        _ session: ImageUploadSession,
        context: AccountContext
    ) -> UInt32 {
        guard session.serverMessageId != 0 else { return session.serverCreateTimeSeconds }
        let serverKey = "\(session.serverMessageId)"
        let stored = context.account.postbox.read { tx in
            tx.getMessageById(serverKey)?.createdAt
        }
        if let stored {
            let seconds = UInt32(stored.timeIntervalSince1970)
            if seconds > 0 { return seconds }
        }
        return session.serverCreateTimeSeconds
    }

    @MainActor
    private func writeMessageContent(
        _ session: ImageUploadSession,
        context: AccountContext,
        contentData: Data
    ) {
        let serverKey = "\(session.serverMessageId)"
        let localId = session.params.localId
        context.account.postbox.write { tx in
            guard let old = tx.getMessageById(serverKey) ?? tx.getMessageById(localId) else { return }
            let updated = MessageRecord(
                id: old.id,
                channelId: old.channelId,
                clanId: old.clanId,
                senderId: old.senderId,
                content: contentData,
                createdAt: old.createdAt,
                editedAt: nil,
                isDeleted: old.isDeleted,
                code: old.code,
                senderDisplayName: old.senderDisplayName,
                senderAvatarURL: old.senderAvatarURL,
                sendingState: old.sendingState,
                attachmentsJSON: old.attachmentsJSON,
                reactionsJSON: old.reactionsJSON,
                referencesData: old.referencesData,
                mentionsJSON: old.mentionsJSON
            )
            tx.addMessages([updated])
        }
    }

    @MainActor
    private func markPresignFinished(_ session: ImageUploadSession, key: String) {
        guard !key.isEmpty, !session.presignFinishedKeys.contains(key) else { return }
        session.presignFinishedKeys.append(key)
    }

    @MainActor
    private func maybeSyncPresignFinish(
        _ session: ImageUploadSession,
        context: AccountContext,
        token: String,
        forceFlush: Bool = false
    ) async {
        guard session.usesPresignSync else { return }
        guard !session.aborted, session.serverMessageId != 0 else { return }
        guard !session.presignFinishedKeys.isEmpty else { return }
        let pendingNew = session.presignFinishedKeys.count - session.lastSyncedPresignCount
        guard forceFlush || pendingNew >= Self.presignEditBatchSize else { return }
        if session.isPresignSyncInFlight {
            guard forceFlush else { return }
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if !session.isPresignSyncInFlight { break }
            }
            guard !session.isPresignSyncInFlight else { return }
        }
        session.isPresignSyncInFlight = true
        defer { session.isPresignSyncInFlight = false }
        await updatePresignFinishContent(session, context: context, token: token, isFinal: forceFlush)
    }

    @MainActor
    private func flushAllPresignFinish(
        _ session: ImageUploadSession,
        context: AccountContext
    ) async {
        for attempt in 0..<8 {
            guard !session.aborted, session.serverMessageId != 0 else { return }
            guard session.lastSyncedPresignCount < session.presignFinishedKeys.count else { return }
            guard let token = await context.getToken() else { return }
            await maybeSyncPresignFinish(session, context: context, token: token, forceFlush: true)
            if session.lastSyncedPresignCount >= session.presignFinishedKeys.count { return }
            let delayMs = UInt64(150_000_000 * UInt64(attempt + 1))
            try? await Task.sleep(nanoseconds: delayMs)
        }
    }

    @MainActor
    func resendFailedSession(context: AccountContext, messageId: String) -> Bool {
        guard let session = session(forKey: messageId) else { return false }
        guard session.aborted || session.serverMessageId == 0 else { return false }
        guard !session.isSending else { return false }
        session.isSending = true
        session.aborted = false
        session.finished = false
        session.serverMessageId = 0
        session.serverCreateTimeSeconds = 0
        session.presignFinishedKeys.removeAll()
        session.lastSyncedPresignCount = 0
        session.fileTracks.removeAll()
        for item in session.items {
            item.state = .uploading
            item.reservedAttachment = nil
            item.presignKey = ""
            item.pendingUploads = []
        }
        context.account.postbox.write { tx in
            if let record = tx.getMessageById(messageId) {
                tx.registerResendDuplicateGuard(senderId: record.senderId, content: record.content)
            }
            tx.markMessagePending(id: messageId)
        }
        Task { @MainActor in
            await self.runWithBackgroundTask {
                await self.runUploads(session, context: context, prepare: nil)
            }
        }
        return true
    }

    @MainActor
    private func mentionsForPresignSync(
        _ session: ImageUploadSession,
        context: AccountContext
    ) -> [Mezon_Api_MessageMention] {
        let p = session.params
        let serverKey = "\(session.serverMessageId)"
        if let record = context.account.postbox.read({ tx in
            tx.getMessageById(serverKey) ?? tx.getMessageById(p.localId)
        }),
           !record.mentionsJSON.isEmpty,
           let list = try? Mezon_Api_MessageMentionList(serializedBytes: record.mentionsJSON) {
            return list.mentions
        }
        return p.mentionList
    }

    @MainActor
    private func updatePresignFinishContent(
        _ session: ImageUploadSession,
        context: AccountContext,
        token: String,
        isFinal: Bool = false
    ) async {
        let p = session.params
        let keysSnapshot = session.presignFinishedKeys
        let localContentStr = PresignFinishContent.contentStringForSend(
            base: session.outgoingBase,
            presignKeys: keysSnapshot
        )
        guard !localContentStr.isEmpty else { return }
        let createTimeSeconds = resolveCreateTimeSeconds(session, context: context)
        let contentStr = PresignFinishContent.withCreateTimeSeconds(
            localContentStr,
            createTimeSeconds: createTimeSeconds
        )
        let localContentData = localContentStr.data(using: .utf8) ?? Data()
        try? await Task.sleep(nanoseconds: Self.presignFinishSyncDelayNanos)
        guard !session.aborted, session.serverMessageId != 0 else { return }
        let maxAttempts = isFinal ? 4 : 1
        for attempt in 1...maxAttempts {
            let activeToken: String
            if attempt == 1 {
                activeToken = token
            } else if let refreshed = await context.getToken() {
                activeToken = refreshed
            } else {
                activeToken = token
            }
            do {
                _ = try await context.account.network.updateChannelMessage(
                    clanId: p.clanId,
                    channelId: p.topicId != 0 ? p.topicId : p.channelId,
                    mode: p.mode,
                    isPublic: p.isPublic,
                    messageId: session.serverMessageId,
                    content: contentStr,
                    mentions: mentionsForPresignSync(session, context: context),
                    hideEditted: true,
                    topicId: p.topicId != 0 ? p.topicId : nil,
                    isUpdateMsgTopic: p.topicId != 0,
                    createTimeSeconds: createTimeSeconds != 0 ? createTimeSeconds : nil,
                    token: activeToken
                )
                writeMessageContent(session, context: context, contentData: localContentData)
                session.lastSyncedPresignCount = keysSnapshot.count
                nudge(session, context: context)
                return
            } catch {
                if attempt == maxAttempts {
                    SentryLogger.capture(error, extras: [
                        "where": "AttachmentUploadCoordinator.updatePresignFinishContent",
                        "messageId": session.serverMessageId,
                        "isFinal": isFinal,
                        "keyCount": keysSnapshot.count,
                    ])
                } else {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 200_000_000)
                }
            }
        }
    }

    // MARK: - Reserve URLs

    private func allReservedAttachments(_ session: ImageUploadSession) -> [Mezon_Api_MessageAttachment] {
        var result = session.items.compactMap { $0.reservedAttachment }
        result.append(contentsOf: session.fileTracks.map(\.attachment))
        return result
    }

    private func uploadedAttachments(_ session: ImageUploadSession) -> [Mezon_Api_MessageAttachment] {
        var result = session.items.compactMap { $0.state.uploadedAttachment }
        result.append(contentsOf: session.fileTracks.compactMap { $0.state.uploadedAttachment })
        return result
    }

    private func readyAttachments(_ session: ImageUploadSession) -> [Mezon_Api_MessageAttachment] {
        var result = session.items.compactMap { item -> Mezon_Api_MessageAttachment? in
            if let att = item.state.uploadedAttachment { return att }
            return item.reservedAttachment
        }
        result.append(contentsOf: session.fileTracks.compactMap { track -> Mezon_Api_MessageAttachment? in
            if let att = track.state.uploadedAttachment { return att }
            return track.attachment
        })
        return result
    }

    @MainActor
    private func reserveFiles(_ session: ImageUploadSession, context: AccountContext, token: String) async {
        for file in session.params.files {
            guard FileManager.default.fileExists(atPath: file.url.path),
                  let size = await Self.fileSize(of: file.url) else {
                AttachmentUploadProgressStore.shared.clear(forKey: file.url.path)
                SentryLogger.capture(
                    NSError(domain: "AttachmentUpload", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Picked file missing before upload"]),
                    extras: [
                        "where": "AttachmentUploadCoordinator.reserveFiles.missingFile",
                        "filename": file.filename,
                        "path": file.url.path,
                    ])
                continue
            }
            let sanitized = file.filename.replacingOccurrences(
                of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            do {
                let (cdnURL, pending) = try await reserveFileBody(
                    fileURL: file.url, filename: sanitized, filetype: file.filetype, size: size,
                    width: 0, height: 0, context: context, token: token)
                let presignKey = PresignFinishContent.presignKey(from: cdnURL)
                var att = Mezon_Api_MessageAttachment()
                att.filename = file.filename
                att.url = cdnURL
                att.filetype = file.filetype
                att.size = Int32(size)
                session.fileTracks.append(FileUploadTrack(
                    file: file, presignKey: presignKey, attachment: att, pending: pending))
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "AttachmentUploadCoordinator.reserveFiles",
                    "filename": file.filename,
                ])
            }
        }
    }

    @MainActor
    private func reserveImages(_ session: ImageUploadSession, context: AccountContext, token: String) async {
        var nextIndex = 0
        await withTaskGroup(of: (Int, Bool).self) { group in
            func addNext() {
                guard nextIndex < session.items.count else { return }
                let index = nextIndex
                nextIndex += 1
                group.addTask { @MainActor in
                    let ok = await self.reserveOneImage(session.items[index], context: context, token: token)
                    return (index, ok)
                }
            }

            for _ in 0..<Self.maxConcurrentUploads { addNext() }

            for await (index, ok) in group {
                if !ok { session.items[index].state = .failed }
                addNext()
            }
        }
    }

    @MainActor
    private func reserveOneImage(
        _ item: ImageUploadItem,
        context: AccountContext,
        token: String
    ) async -> Bool {
        guard let fileURL = item.fileURL else { return false }

        let image = item.image
        let originalFilename = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let filetype = SendMessageInputViewController.mimeType(for: ext)
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let sanitized = originalFilename.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        let isVideo = filetype.hasPrefix("video/")
        let progressKey = fileURL.path
        print("[MezonUpload] reserveOneImage file=\(originalFilename) ext=\(ext) filetype=\(filetype) isVideo=\(isVideo)")

        do {
            var att = Mezon_Api_MessageAttachment()
            att.filename = originalFilename
            att.filetype = filetype
            att.width = Int32(width)
            att.height = Int32(height)
            var pendingUploads: [PendingMinIOUpload] = []

            if isVideo {
                guard let size = await Self.fileSize(of: fileURL) else {
                    print("[MezonUpload] video fileSize=nil file=\(originalFilename)")
                    return false
                }
                print("[MezonUpload] video size=\(size)B (~\(size / 1024 / 1024)MB) thresholdMB=\(AttachmentUploader.minMultipartFileSize / 1024 / 1024) willMultipart=\(size >= AttachmentUploader.minMultipartFileSize)")
                let (cdnURL, filePending) = try await reserveFileBody(
                    fileURL: fileURL, filename: sanitized, filetype: filetype, size: size,
                    width: width, height: height, context: context, token: token)
                att.url = cdnURL
                att.size = Int32(size)

                if let thumb = await reserveVideoThumbnail(image, originalFilename: sanitized, context: context, token: token) {
                    att.thumbnail = thumb.cdnURL
                    pendingUploads.append(thumb.pending)
                }

                pendingUploads.append(filePending)
            } else {
                let isGif = filetype == "image/gif" || ext == "gif"
                guard let payload = await Self.imageUploadPayload(
                    image: image, fileURL: fileURL, filetype: filetype,
                    filename: sanitized, isGif: isGif) else { return false }
                let uploadInfo = try await context.account.network.uploadAttachmentFile(
                    filename: payload.filename, filetype: payload.filetype, size: payload.data.count,
                    width: width, height: height, token: token)
                let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                att.filename = payload.filename
                att.filetype = payload.filetype
                att.url = cdnURL
                att.size = Int32(payload.data.count)
                pendingUploads.append(PendingMinIOUpload(
                    minioURL: uploadInfo.url,
                    contentType: payload.filetype,
                    body: .data(payload.data),
                    progressKey: progressKey,
                    cacheImage: (image, payload.data, cdnURL)))
            }

            item.reservedAttachment = att
            item.presignKey = PresignFinishContent.presignKey(from: att.url)
            item.pendingUploads = pendingUploads
            return true
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "AttachmentUploadCoordinator.reserveOneImage",
                "filename": originalFilename,
            ])
            return false
        }
    }

    @MainActor
    private func reserveFileBody(
        fileURL: URL,
        filename: String,
        filetype: String,
        size: Int,
        width: Int,
        height: Int,
        context: AccountContext,
        token: String
    ) async throws -> (cdnURL: String, pending: PendingMinIOUpload) {
        let progressKey = fileURL.path
        print("[MezonUpload] reserveFileBody file=\(filename) size=\(size)B (~\(size / 1024 / 1024)MB) thresholdMB=\(AttachmentUploader.minMultipartFileSize / 1024 / 1024) multipart=\(size >= AttachmentUploader.minMultipartFileSize)")
        if size >= AttachmentUploader.minMultipartFileSize {
            do {
                let partCount = max(1, Int((Double(size) / Double(AttachmentUploader.partSize)).rounded(.up)))
                let start = try await context.account.network.multipartUploadAttachmentFileStart(
                    filename: filename, filetype: filetype, size: size,
                    width: width, height: height, partCount: partCount, token: token)
                print("[MezonUpload] multipartStart partCount=\(partCount) urls=\(start.urls.count) uploadId=\(start.uploadID.isEmpty ? "EMPTY" : "ok") serverFilename=\(start.filename)")
                let serverFilename = start.filename.isEmpty ? filename : start.filename
                let cdnURL = "\(MezonConfig.baseImgURL)/\(serverFilename)"
                if start.urls.count > 1, !start.uploadID.isEmpty {
                    let plan = MultipartPlan(
                        fileURL: fileURL, partURLs: start.urls, uploadId: start.uploadID,
                        filename: serverFilename, fileSize: size, contentType: filetype)
                    return (cdnURL, PendingMinIOUpload(
                        minioURL: "", contentType: filetype, body: .multipart(plan),
                        progressKey: progressKey, cacheImage: nil))
                }
                if let first = start.urls.first, !first.isEmpty {
                    return (cdnURL, PendingMinIOUpload(
                        minioURL: first, contentType: filetype, body: .file(fileURL),
                        progressKey: progressKey, cacheImage: nil))
                }
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "AttachmentUploadCoordinator.reserveFileBody.multipartStart",
                    "filename": filename,
                    "size": size,
                ])
            }
        }
        let info = try await context.account.network.uploadAttachmentFile(
            filename: filename, filetype: filetype, size: size,
            width: width, height: height, token: token)
        return ("\(MezonConfig.baseImgURL)/\(info.filename)", PendingMinIOUpload(
            minioURL: info.url, contentType: filetype, body: .file(fileURL),
            progressKey: progressKey, cacheImage: nil))
    }

    @MainActor
    private func reserveVideoThumbnail(
        _ thumbnail: UIImage,
        originalFilename: String,
        context: AccountContext,
        token: String
    ) async -> (cdnURL: String, pending: PendingMinIOUpload)? {
        guard let thumbData = await Self.encodeJPEG(thumbnail, quality: 0.7) else { return nil }

        let baseName = (originalFilename as NSString).deletingPathExtension
        let thumbFilename = "\(baseName.isEmpty ? "video" : baseName)_thumb.jpg"
        let width = Int(thumbnail.size.width)
        let height = Int(thumbnail.size.height)

        do {
            let uploadInfo = try await context.account.network.uploadAttachmentFile(
                filename: thumbFilename, filetype: "image/jpeg", size: thumbData.count,
                width: width, height: height, token: token)
            let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
            let pending = PendingMinIOUpload(
                minioURL: uploadInfo.url,
                contentType: "image/jpeg",
                body: .data(thumbData),
                progressKey: "",
                cacheImage: (thumbnail, thumbData, cdnURL))
            return (cdnURL, pending)
        } catch {
            return nil
        }
    }

    // MARK: - Execute uploads

    @MainActor
    private func executeFileUploads(_ session: ImageUploadSession, context: AccountContext, token: String) async {
        for track in session.fileTracks where track.state.isUploading {
            let ok = await executePendingUpload(track.pending, context: context)
            track.state = ok ? .uploaded(track.attachment) : .failed
            if ok {
                markPresignFinished(session, key: track.presignKey)
                try? FileManager.default.removeItem(at: track.file.url)
            } else {
            }
            Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))
            let pendingNew = session.presignFinishedKeys.count - session.lastSyncedPresignCount
            if pendingNew >= Self.presignEditBatchSize {
                await maybeSyncPresignFinish(session, context: context, token: token)
            }
        }
    }

    @MainActor
    private func executeImageUploads(_ session: ImageUploadSession, context: AccountContext, token: String) async {
        var nextIndex = 0
        await withTaskGroup(of: (Int, Bool).self) { group in
            func addNext() {
                guard nextIndex < session.items.count else { return }
                let index = nextIndex
                nextIndex += 1
                let item = session.items[index]
                guard item.reservedAttachment != nil, item.state.isUploading else { return }
                group.addTask { @MainActor in
                    let ok = await self.executeImageUpload(item, context: context)
                    return (index, ok)
                }
            }

            for _ in 0..<Self.maxConcurrentUploads { addNext() }

            for await (index, ok) in group {
                let item = session.items[index]
                session.items[index].state = ok
                    ? .uploaded(item.reservedAttachment!)
                    : .failed
                if ok {
                    markPresignFinished(session, key: item.presignKey)
                } else {
                }
                Self.postUploadSlotStateChanged(messageId: Self.sessionMessageId(session))
                let pendingNew = session.presignFinishedKeys.count - session.lastSyncedPresignCount
                if pendingNew >= Self.presignEditBatchSize {
                    await maybeSyncPresignFinish(session, context: context, token: token)
                }
                addNext()
            }
        }
    }

    @MainActor
    private func executeImageUpload(_ item: ImageUploadItem, context: AccountContext) async -> Bool {
        guard item.reservedAttachment != nil else { return false }
        for pending in item.pendingUploads {
            guard await executePendingUpload(pending, context: context) else { return false }
        }
        if let fileURL = item.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        return true
    }

    @MainActor
    private func executePendingUpload(
        _ pending: PendingMinIOUpload,
        context: AccountContext
    ) async -> Bool {
        for attempt in 0..<2 {
            if await performPendingUpload(pending, context: context) { return true }
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        return false
    }

    @MainActor
    private func performPendingUpload(
        _ pending: PendingMinIOUpload,
        context: AccountContext
    ) async -> Bool {
        let progressKey = pending.progressKey
        if !progressKey.isEmpty {
            AttachmentUploadProgressStore.shared.setProgress(0, forKey: progressKey)
            Self.postUploadProgress(key: progressKey, progress: 0, previousBucket: -1)
        }
        do {
            switch pending.body {
            case let .data(data):
                _ = try await MinIOStreamingUploader.shared.putData(
                    url: pending.minioURL, data: data, contentType: pending.contentType
                ) { fraction in
                    guard !progressKey.isEmpty else { return }
                    let clamped = min(max(fraction, 0), 0.99)
                    let previous = AttachmentUploadProgressStore.shared.progress(forKey: progressKey)
                    AttachmentUploadProgressStore.shared.setProgress(clamped, forKey: progressKey)
                    Self.postUploadProgress(
                        key: progressKey,
                        progress: clamped,
                        previousBucket: Self.progressBucket(for: previous))
                }
                if !progressKey.isEmpty {
                    AttachmentUploadProgressStore.shared.setProgress(1, forKey: progressKey)
                }
            case let .file(fileURL):
                _ = try await MinIOStreamingUploader.shared.put(
                    url: pending.minioURL, fileURL: fileURL, contentType: pending.contentType
                ) { fraction in
                    guard !progressKey.isEmpty else { return }
                    let clamped = min(max(fraction, 0), 0.99)
                    let previous = AttachmentUploadProgressStore.shared.progress(forKey: progressKey)
                    AttachmentUploadProgressStore.shared.setProgress(clamped, forKey: progressKey)
                    Self.postUploadProgress(
                        key: progressKey,
                        progress: clamped,
                        previousBucket: Self.progressBucket(for: previous))
                }
                if !progressKey.isEmpty {
                    AttachmentUploadProgressStore.shared.setProgress(1, forKey: progressKey)
                }
            case let .multipart(plan):
                try await performMultipartUpload(plan, context: context, progressKey: progressKey)
                if !progressKey.isEmpty {
                    AttachmentUploadProgressStore.shared.setProgress(1, forKey: progressKey)
                }
            }
            if let cache = pending.cacheImage {
                ImageCache.shared.persistData(cache.data, forKey: cache.cdnURL)
            }
            if !progressKey.isEmpty {
                AttachmentUploadProgressStore.shared.clear(forKey: progressKey)
            }
            return true
        } catch {
            if !progressKey.isEmpty {
                AttachmentUploadProgressStore.shared.clear(forKey: progressKey)
            }
            SentryLogger.capture(error, extras: [
                "where": "AttachmentUploadCoordinator.executePendingUpload",
            ])
            return false
        }
    }

    @MainActor
    private func performMultipartUpload(
        _ plan: MultipartPlan,
        context: AccountContext,
        progressKey: String
    ) async throws {
        let network = context.account.network
        let partCount = plan.partURLs.count
        let total = max(plan.fileSize, 1)
        var collected: [(partNumber: Int, eTag: String)] = []
        collected.reserveCapacity(partCount)
        var uploadedBytes = 0

        try await withThrowingTaskGroup(of: (Int, String, Int).self) { group in
            var nextIndex = 0
            func submit() {
                guard nextIndex < partCount else { return }
                let index = nextIndex
                nextIndex += 1
                let offset = index * AttachmentUploader.partSize
                let end = (index == partCount - 1) ? plan.fileSize : offset + AttachmentUploader.partSize
                let length = max(0, end - offset)
                let url = plan.partURLs[index]
                let ct = plan.contentType
                let furl = plan.fileURL
                group.addTask {
                    let chunk = try Self.readChunk(fileURL: furl, offset: offset, length: length)
                    let etag = try await network.uploadPartToMinIO(url: url, data: chunk, contentType: ct)
                    return (index + 1, etag, length)
                }
            }

            for _ in 0..<min(Self.multipartMaxParallelParts, partCount) { submit() }

            while let (partNumber, etag, length) = try await group.next() {
                collected.append((partNumber, etag))
                uploadedBytes += length
                if !progressKey.isEmpty {
                    let clamped = min(max(Double(uploadedBytes) / Double(total), 0), 0.99)
                    let previous = AttachmentUploadProgressStore.shared.progress(forKey: progressKey)
                    AttachmentUploadProgressStore.shared.setProgress(clamped, forKey: progressKey)
                    Self.postUploadProgress(
                        key: progressKey,
                        progress: clamped,
                        previousBucket: Self.progressBucket(for: previous))
                }
                submit()
            }
        }

        collected.sort { $0.partNumber < $1.partNumber }
        guard let finishToken = await context.getToken() else {
            throw MezonError.httpError(statusCode: 0, message: "No token for multipart finish")
        }
        _ = try await network.multipartUploadAttachmentFileFinish(
            uploadId: plan.uploadId, parts: collected, filename: plan.filename, token: finishToken)
    }

    private static func readChunk(fileURL: URL, offset: Int, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        if offset > 0 {
            try handle.seek(toOffset: UInt64(offset))
        }
        return handle.readData(ofLength: length)
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

    private static func progressBucket(for value: Double) -> Int {
        Int(min(max(value, 0), 1) * Double(progressNotificationBucketCount))
    }

    private static func postUploadProgress(key: String, progress: Double, previousBucket: Int) {
        let clamped = min(max(progress, 0), 1)
        let newBucket = progressBucket(for: clamped)
        guard newBucket != previousBucket || clamped >= 1 else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .mezonAttachmentUploadProgress,
                object: nil,
                userInfo: ["key": key, "progress": clamped])
        }
    }

    private static func sessionMessageId(_ session: ImageUploadSession) -> String {
        session.serverMessageId != 0 ? "\(session.serverMessageId)" : session.params.localId
    }

    private static func postUploadSlotStateChanged(messageId: String) {
        guard !messageId.isEmpty else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .mezonAttachmentUploadSlotStateChanged,
                object: nil,
                userInfo: ["messageId": messageId])
        }
    }

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
