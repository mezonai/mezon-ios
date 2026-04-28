import AsyncDisplayKit
import Foundation
import SwiftProtobuf
import UIKit

@MainActor
final class PinnedMessagesNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var pinnedMessages: [Mezon_Api_PinMessage] = []
    private var pinsFetchCompleted = false
    private var pinsLoadStarted = false
    private var pinsDataGeneration: UInt64 = 0
    private var attachmentEnrichmentByMessageId: [Int64: [ParsedAttachment]] = [:]

    private let tableNode: ASTableNode

    private var pinListApiClanId: Int64 {
        (channelType == MezonConstants.ChannelType.dm.rawValue
            || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId
    }

    init(context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType

        self.tableNode = ASTableNode()

        super.init()
        self.automaticallyManagesSubnodes = true

        applyTheme()

        tableNode.dataSource = self
        tableNode.delegate = self
        tableNode.view.separatorStyle = .none
        tableNode.view.showsVerticalScrollIndicator = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePinsNeedRefresh(_:)),
            name: .mezonChannelPinsNeedRefresh,
            object: nil
        )
    }

    func loadTabDataIfNeeded() {
        guard !pinsLoadStarted else { return }
        pinsLoadStarted = true
        fetchPins()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .mezonChannelPinsNeedRefresh, object: nil)
    }

    @objc private func handlePinsNeedRefresh(_ notification: Notification) {
        let eventChannel = Self.notificationInt64(notification.userInfo?["channelId"]) ?? 0
        guard eventChannel == channelId else { return }
        refetchPinsFromNetwork()
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.primary
        tableNode.backgroundColor = .clear
        tableNode.view.backgroundColor = .clear
    }

    private func fetchPins() {
        refetchPinsFromNetwork()
    }

    private func refetchPinsFromNetwork() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = await context.getToken() ?? ""
                let res = try await context.account.network.listPinMessages(
                    clanId: self.pinListApiClanId,
                    channelId: channelId,
                    token: token
                )
                self.pinsDataGeneration += 1
                let dataGen = self.pinsDataGeneration
                self.pinnedMessages = res.pinMessagesList
                self.attachmentEnrichmentByMessageId = [:]
                self.pinsFetchCompleted = true
                await self.tableNode.reloadData()
                self.enrichPinAttachmentsFromChannelIfNeeded(expectedDataGeneration: dataGen)
            } catch {
                self.pinsFetchCompleted = true
                await self.tableNode.reloadData()
            }
        }
    }

    private func enrichPinAttachmentsFromChannelIfNeeded(expectedDataGeneration: UInt64) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard expectedDataGeneration == self.pinsDataGeneration else { return }
            guard let token = await context.getToken() else { return }
            guard expectedDataGeneration == self.pinsDataGeneration else { return }
            var merged = self.attachmentEnrichmentByMessageId
            var didChange = false
            for pin in self.pinnedMessages {
                guard expectedDataGeneration == self.pinsDataGeneration else { return }
                guard pin.messageID != 0 else { continue }
                if merged[pin.messageID] != nil { continue }
                if PinRowContent.collatedURLCountBeforeExtras(for: pin, context: self.context) > 0 {
                    continue
                }
                guard !pin.attachment.isEmpty else { continue }
                do {
                    let resp = try await context.account.network.listChannelMessages(
                        clanId: pinListApiClanId,
                        channelId: channelId,
                        messageId: pin.messageID,
                        direction: 2,
                        limit: 25,
                        topicId: 0,
                        token: token
                    )
                    guard expectedDataGeneration == self.pinsDataGeneration else { return }
                    guard let msg = resp.messages.first(where: { $0.messageID == pin.messageID }) else { continue }
                    let parsed = PinAttachmentDecoder.parsedAttachments(from: msg.attachments)
                    guard !parsed.isEmpty else { continue }
                    merged[pin.messageID] = parsed
                    didChange = true
                } catch {
                }
            }
            guard expectedDataGeneration == self.pinsDataGeneration, didChange else { return }
            self.attachmentEnrichmentByMessageId = merged
            await self.tableNode.reloadData()
        }
    }

    private static func notificationInt64(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? NSNumber { return v.int64Value }
        if let v = value as? String { return Int64(v) }
        return nil
    }

    private func requestUnpin(_ pin: Mezon_Api_PinMessage) {
        guard let presenter = tableNode.view.findHostingViewController() else {
            unpinMessage(pin)
            return
        }
        MezonConfirm.present(
            from: presenter,
            title: L(L10n.ChannelDetail.unpinConfirmTitle),
            content: L(L10n.ChannelDetail.unpinConfirmBody),
            confirmTitle: L(L10n.ChannelDetail.unpinConfirmAction),
            isDanger: true,
            onConfirm: { [weak self] in
                self?.unpinMessage(pin)
            }
        )
    }

    private func unpinMessage(_ pin: Mezon_Api_PinMessage) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await context.getToken() else { return }
            do {
                try await context.account.network.deletePinMessage(
                    clanId: self.pinListApiClanId,
                    channelId: channelId,
                    pinId: pin.id,
                    messageId: pin.messageID,
                    token: token
                )
                if pin.id != 0 {
                    self.pinnedMessages.removeAll { $0.id == pin.id }
                } else {
                    self.pinnedMessages.removeAll { $0.messageID == pin.messageID }
                }
                await self.tableNode.reloadData()
            } catch {
                Toast.error(L(L10n.ChannelDetail.unpinError))
            }
        }
    }

    private func jumpToPinnedMessage(_ pin: Mezon_Api_PinMessage) {
        let messageId = "\(pin.messageID)"
        guard let nav = tableNode.view.findHostingViewController()?.navigationController else { return }

        for vc in nav.viewControllers.reversed() {
            guard let chat = vc as? ChatViewController else { continue }
            if chat.channel.channelID == pin.channelID && chat.clanId == clanId {
                nav.popToViewController(chat, animated: true)
                DispatchQueue.main.async {
                    chat.jumpToMessageFromChannelDetail(messageId: messageId)
                }
                return
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        tableNode.style.flexGrow = 1
        return ASWrapperLayoutSpec(layoutElement: tableNode)
    }

    private func resolvedSenderDisplayName(for pin: Mezon_Api_PinMessage) -> String {
        let idStr = String(pin.senderID)
        var resolved = ""
        context.account.postbox.read { tx in
            if let p = tx.getProfile(userId: idStr) {
                if let dn = p.displayName, !dn.isEmpty {
                    resolved = dn
                } else if !p.username.isEmpty {
                    resolved = p.username
                }
            }
        }
        if !resolved.isEmpty { return resolved }
        if !pin.username.isEmpty { return pin.username }
        return idStr
    }

    private func resolvedAvatarURLString(for pin: Mezon_Api_PinMessage) -> String {
        let idStr = String(pin.senderID)
        var fromProfile = ""
        context.account.postbox.read { tx in
            if let p = tx.getProfile(userId: idStr), let u = p.avatarUrl, !u.isEmpty {
                fromProfile = u
            }
        }
        if !fromProfile.isEmpty { return fromProfile }
        return pin.avatar.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension PinnedMessagesNode: @MainActor ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        if pinsLoadStarted, !pinsFetchCompleted { return 1 }
        guard pinsFetchCompleted else { return 0 }
        if pinnedMessages.isEmpty { return 1 }
        return pinnedMessages.count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if pinsLoadStarted, !pinsFetchCompleted {
            return { PinsLoadingCellNode() }
        }
        if pinnedMessages.isEmpty {
            return { EmptyPinsCellNode() }
        }
        let pin = pinnedMessages[indexPath.row]
        let displayName = resolvedSenderDisplayName(for: pin)
        let extras = attachmentEnrichmentByMessageId[pin.messageID] ?? []
        let row = PinRowContent.make(from: pin, context: context, attachmentExtras: extras)
        let avatarURL = resolvedAvatarURLString(for: pin)
        return { [weak self] in
            PinnedMessageCellNode(
                displayName: displayName,
                pin: pin,
                row: row,
                avatarURLString: avatarURL,
                onUnpin: { self?.requestUnpin(pin) }
            )
        }
    }
}

extension PinnedMessagesNode: @MainActor ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
        guard pinsFetchCompleted, !pinnedMessages.isEmpty, indexPath.row < pinnedMessages.count else {
            return
        }
        jumpToPinnedMessage(pinnedMessages[indexPath.row])
    }
}

private enum PinAttachmentDecoder {
    static func parsedAttachments(from data: Data, didUnwrapBase64: Bool = false) -> [ParsedAttachment] {
        guard !data.isEmpty else { return [] }

        if !didUnwrapBase64 {
            let ascii = data.reduce(true) { ok, b in ok && (b == 9 || b == 10 || b == 13 || b == 32 || (b >= 43 && b <= 122)) }
            if ascii, let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               s.count >= 16, let inner = Data(base64Encoded: s), inner.count >= 8, inner != data
            {
                let innerResult = parsedAttachments(from: inner, didUnwrapBase64: true)
                if !innerResult.isEmpty { return innerResult }
            }
        }

        if let list = try? Mezon_Api_ChannelAttachmentList(serializedBytes: data), !list.attachments.isEmpty {
            let mapped = list.attachments.map(Self.parsedFromChannel).filter {
                !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if !mapped.isEmpty { return mapped }
        }
        if let att = try? Mezon_Api_ChannelAttachment(serializedBytes: data) {
            let pa = Self.parsedFromChannel(att)
            if !pa.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return [pa]
            }
        }

        if let list = try? Mezon_Api_MessageAttachmentList(serializedBytes: data),
            !list.attachments.isEmpty
        {
            let parsed = list.attachments.compactMap(Self.parsedFromMessage)
            if !parsed.isEmpty { return parsed }
        }
        if let one = try? Mezon_Api_MessageAttachment(serializedBytes: data) {
            if let pa = Self.parsedFromMessage(one) {
                return [pa]
            }
        }

        let jsonBytes = Self.dataWithoutUtf8Bom(data)
        var jsonItems: [[String: Any]]?
        if let arr = try? JSONSerialization.jsonObject(with: jsonBytes) as? [[String: Any]] {
            jsonItems = arr
        } else if let dict = try? JSONSerialization.jsonObject(with: jsonBytes) as? [String: Any] {
            if let arr = dict["attachments"] as? [[String: Any]] {
                jsonItems = arr
            } else if let arr = dict["a"] as? [[String: Any]] {
                jsonItems = arr
            } else if Self.jsonDictLooksLikeAttachmentItem(dict) {
                jsonItems = [dict]
            }
        } else if let str = String(data: jsonBytes, encoding: .utf8),
            let strData = str.data(using: .utf8)
        {
            if let arr = try? JSONSerialization.jsonObject(with: strData) as? [[String: Any]] {
                jsonItems = arr
            } else if let dict = try? JSONSerialization.jsonObject(with: strData) as? [String: Any] {
                if let arr = dict["attachments"] as? [[String: Any]] {
                    jsonItems = arr
                } else if let arr = dict["a"] as? [[String: Any]] {
                    jsonItems = arr
                } else if Self.jsonDictLooksLikeAttachmentItem(dict) {
                    jsonItems = [dict]
                }
            }
        }

        if let json = jsonItems {
            return json.compactMap(Self.parsedFromJSONItem)
        }

        return []
    }

    private static func dataWithoutUtf8Bom(_ data: Data) -> Data {
        guard data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF else { return data }
        return data.subdata(in: 3..<data.count)
    }

    private static func jsonDictLooksLikeAttachmentItem(_ dict: [String: Any]) -> Bool {
        let u = (dict["url"] as? String ?? dict["uri"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let th = (dict["thumbnail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !u.isEmpty || !th.isEmpty
    }

    private static func parsedFromChannel(_ att: Mezon_Api_ChannelAttachment) -> ParsedAttachment {
        ParsedAttachment(
            url: att.url,
            filename: att.filename,
            filetype: att.filetype,
            width: att.width == 0 ? nil : Int(att.width),
            height: att.height == 0 ? nil : Int(att.height),
            durationSeconds: nil,
            localImage: nil,
            isUploading: false
        )
    }

    private static func parsedFromMessage(_ att: Mezon_Api_MessageAttachment) -> ParsedAttachment? {
        let urlPrimary = att.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let thumb = att.thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlStr = !urlPrimary.isEmpty ? urlPrimary : thumb
        guard !urlStr.isEmpty else { return nil }
        return ParsedAttachment(
            url: urlStr,
            filename: att.filename,
            filetype: att.filetype,
            width: att.width != 0 ? Int(att.width) : nil,
            height: att.height != 0 ? Int(att.height) : nil,
            durationSeconds: att.duration > 0 ? Int(att.duration) : nil,
            localImage: nil,
            isUploading: false
        )
    }

    private static func parsedFromJSONItem(_ item: [String: Any]) -> ParsedAttachment? {
        let urlDirect = (item["url"] as? String ?? item["uri"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let thumb = (item["thumbnail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlStr = !urlDirect.isEmpty ? urlDirect : thumb
        guard !urlStr.isEmpty else { return nil }
        let w = item["width"] as? Int ?? (item["width"] as? String).flatMap { Int($0) }
        let h = item["height"] as? Int ?? (item["height"] as? String).flatMap { Int($0) }
        let d: Int? = {
            if let n = item["duration"] as? Int { return n > 0 ? n : nil }
            if let n = item["duration"] as? Int64 { return n > 0 ? Int(n) : nil }
            if let s = item["duration"] as? String, let n = Int(s) { return n > 0 ? n : nil }
            return nil
        }()
        let ftRaw = item["filetype"] as? String ?? item["file_type"] as? String ?? ""
        return ParsedAttachment(
            url: urlStr,
            filename: item["filename"] as? String ?? "",
            filetype: ftRaw,
            width: w,
            height: h,
            durationSeconds: d,
            localImage: nil,
            isUploading: false
        )
    }
}

private struct PinRowContent {
    let caption: String?
    let messageIdKey: String
    let mediaAttachments: [ParsedAttachment]
    let audioAttachments: [ParsedAttachment]
    let fileAttachments: [ParsedAttachment]

    @MainActor
    static func collatedURLCountBeforeExtras(for pin: Mezon_Api_PinMessage, context: AccountContext) -> Int {
        collatedAttachments(for: pin, context: context, attachmentExtras: []).count
    }

    @MainActor
    static func make(from pin: Mezon_Api_PinMessage, context: AccountContext, attachmentExtras: [ParsedAttachment] = []) -> PinRowContent {
        let data = pin.content.data(using: .utf8) ?? Data()
        let parsed = MessageContentParser.parse(data: data, mentionsData: Data())
        let trimmed = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmbed = !parsed.embeds.isEmpty

        let decoded = collatedAttachments(for: pin, context: context, attachmentExtras: attachmentExtras)
        let enriched = decoded.map { attachmentWithEmbedMediaURLIfNeeded($0, embeds: parsed.embeds) }
        let withURL = enriched.filter { !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var combined = withURL
        if combined.first(where: { $0.isMedia }) == nil, let em = firstEmbedMediaAttachment(embeds: parsed.embeds) {
            combined.insert(em, at: 0)
        }

        let mediaAttachments = combined.filter { $0.isMedia }
        let audioAttachments = combined.filter {
            $0.isAudio && !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let fileAttachments = combined.filter {
            !$0.isMedia && !$0.isAudio
                && !$0.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let caption: String? = {
            if !trimmed.isEmpty { return trimmed }
            if hasEmbed, mediaAttachments.isEmpty, audioAttachments.isEmpty, fileAttachments.isEmpty {
                return L(L10n.ChannelDetail.pinEmbedPreview)
            }
            if !pin.attachment.isEmpty, combined.isEmpty {
                return L(L10n.ChannelDetail.pinAttachmentPreview)
            }
            if let d = pin.content.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                let t = json["t"] as? String
            {
                let tTrim = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tTrim.isEmpty { return tTrim }
            }
            let raw = pin.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? nil : raw
        }()

        return PinRowContent(
            caption: caption,
            messageIdKey: "\(pin.messageID)",
            mediaAttachments: mediaAttachments,
            audioAttachments: audioAttachments,
            fileAttachments: fileAttachments
        )
    }

    @MainActor
    private static func collatedAttachments(for pin: Mezon_Api_PinMessage, context: AccountContext, attachmentExtras: [ParsedAttachment]) -> [ParsedAttachment] {
        var out: [ParsedAttachment] = []
        var seen = Set<String>()
        let append: ([ParsedAttachment]) -> Void = { items in
            for a in items {
                let u = a.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !u.isEmpty, !seen.contains(u) else { continue }
                seen.insert(u)
                out.append(a)
            }
        }
        append(PinAttachmentDecoder.parsedAttachments(from: pin.attachment))
        if let cd = pin.content.data(using: .utf8),
            let jo = try? JSONSerialization.jsonObject(with: cd) as? [String: Any]
        {
            for key in ["attachments", "a", "at"] {
                if let arr = jo[key] as? [[String: Any]],
                    let nested = try? JSONSerialization.data(withJSONObject: arr)
                {
                    append(PinAttachmentDecoder.parsedAttachments(from: nested))
                }
            }
            if let one = jo["attachment"] as? [String: Any],
                let nested = try? JSONSerialization.data(withJSONObject: one)
            {
                append(PinAttachmentDecoder.parsedAttachments(from: nested))
            }
        }
        if pin.messageID != 0 {
            let fromPostbox: [ParsedAttachment] = context.account.postbox.read { tx in
                guard let rec = tx.getMessageById("\(pin.messageID)") else { return [] }
                return PinAttachmentDecoder.parsedAttachments(from: rec.attachmentsJSON)
            }
            append(fromPostbox)
        }
        append(attachmentExtras)
        return out
    }

    private static func attachmentWithEmbedMediaURLIfNeeded(_ pa: ParsedAttachment, embeds: [ParsedEmbed]) -> ParsedAttachment {
        let u = pa.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty { return pa }
        var fill = ""
        for e in embeds {
            if let x = e.imageURL, !x.isEmpty { fill = x; break }
            if let x = e.thumbnailURL, !x.isEmpty { fill = x; break }
        }
        guard !fill.isEmpty else { return pa }
        let ft = pa.filetype.trimmingCharacters(in: .whitespacesAndNewlines)
        let filetype = ft.isEmpty ? "image/jpeg" : ft
        return ParsedAttachment(
            url: fill,
            filename: pa.filename,
            filetype: filetype,
            width: pa.width,
            height: pa.height,
            durationSeconds: pa.durationSeconds,
            localImage: pa.localImage,
            isUploading: pa.isUploading
        )
    }

    private static func firstEmbedMediaAttachment(embeds: [ParsedEmbed]) -> ParsedAttachment? {
        for e in embeds {
            var u = (e.imageURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if u.isEmpty { u = (e.thumbnailURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !u.isEmpty else { continue }
            let pa = ParsedAttachment(
                url: u,
                filename: "",
                filetype: "image/jpeg",
                width: e.imageWidth,
                height: e.imageHeight,
                durationSeconds: nil,
                localImage: nil,
                isUploading: false
            )
            if pa.isMedia { return pa }
        }
        return nil
    }
}

private final class PinsLoadingCellNode: ASCellNode {
    private let spinnerHost = ASDisplayNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none
        spinnerHost.style.preferredSize = CGSize(width: 44, height: 44)
        spinnerHost.setViewBlock {
            let v = UIActivityIndicatorView(style: .medium)
            v.color = UIColor.theme.textStrong
            v.startAnimating()
            return v
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let centered = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: spinnerHost
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 24, left: 0, bottom: 24, right: 0),
            child: centered
        )
    }
}

private final class EmptyPinsCellNode: ASCellNode {
    private let labelNode = ASTextNode2()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none

        labelNode.attributedText = NSAttributedString(
            string: L(L10n.ChannelDetail.noPinsYet),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .medium),
                .foregroundColor: UIColor.theme.text.withAlphaComponent(0.65),
            ]
        )
        labelNode.maximumNumberOfLines = 0
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let centered = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: labelNode
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 32, left: 16, bottom: 32, right: 16),
            child: centered
        )
    }
}

private final class PinnedMessageCellNode: ASCellNode {
    private let cardNode = ASDisplayNode()
    private let avatarBgNode = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let avatarPlaceholderNode = ASTextNode2()
    private let nameNode = ASTextNode2()
    private let contentNode = ASTextNode2()
    private let unpinButton = ASButtonNode()
    private var mediaContentNode: MessageMediaContentNode?
    private var audioAttachmentNode: MessageAudioAttachmentNode?
    private var fileAttachmentNode: MessageFileAttachmentNode?
    private let displayNameForGallery: String
    private let pinForGallery: Mezon_Api_PinMessage
    private let avatarURLForGallery: String
    private let onUnpin: () -> Void
    private let includeCaption: Bool

    init(
        displayName: String,
        pin: Mezon_Api_PinMessage,
        row: PinRowContent,
        avatarURLString: String,
        onUnpin: @escaping () -> Void
    ) {
        self.displayNameForGallery = displayName
        self.pinForGallery = pin
        self.avatarURLForGallery = avatarURLString
        self.onUnpin = onUnpin
        let cap = row.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.includeCaption = !cap.isEmpty
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none

        let t = UIColor.theme
        let avatarSize: CGFloat = 40.sf

        cardNode.backgroundColor = t.secondary
        cardNode.cornerRadius = 10.sf
        cardNode.clipsToBounds = true

        avatarBgNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
        avatarBgNode.cornerRadius = avatarSize / 2
        avatarBgNode.clipsToBounds = true
        avatarBgNode.backgroundColor = .colorAvatarDefault

        avatarNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
        avatarNode.cornerRadius = avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill

        let initial = String(displayName.prefix(1)).uppercased()
        avatarPlaceholderNode.attributedText = NSAttributedString(
            string: initial,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )

        if let url = Self.displayURL(from: avatarURLString) {
            avatarNode.url = url
            avatarNode.isHidden = false
            avatarPlaceholderNode.isHidden = true
        } else {
            avatarNode.url = nil
            avatarNode.isHidden = true
            avatarPlaceholderNode.isHidden = false
        }

        nameNode.attributedText = NSAttributedString(
            string: displayName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail

        if includeCaption {
            contentNode.attributedText = NSAttributedString(
                string: row.caption ?? "",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                    .foregroundColor: t.text,
                ]
            )
            contentNode.maximumNumberOfLines = 3
            contentNode.truncationMode = .byTruncatingTail
        }

        unpinButton.setImage(
            UIImage(systemName: "xmark.circle.fill")?.withTintColor(
                t.text.withAlphaComponent(0.75), renderingMode: .alwaysOriginal),
            for: .normal)
        unpinButton.style.preferredSize = CGSize(width: 44, height: 44)
        unpinButton.contentHorizontalAlignment = .middle
        unpinButton.contentVerticalAlignment = .center
        unpinButton.addTarget(
            self, action: #selector(unpinPressed), forControlEvents: .touchUpInside)

        addSubnode(avatarBgNode)
        addSubnode(avatarNode)
        addSubnode(avatarPlaceholderNode)
        addSubnode(nameNode)
        if includeCaption {
            addSubnode(contentNode)
        }
        addSubnode(unpinButton)

        if !row.mediaAttachments.isEmpty {
            let mcn = MessageMediaContentNode()
            mcn.configure(media: row.mediaAttachments)
            let media = row.mediaAttachments
            mcn.onImageTapped = { [weak self] index in
                self?.presentMediaGallery(index: index, media: media)
            }
            mediaContentNode = mcn
            addSubnode(mcn)
        }
        if !row.audioAttachments.isEmpty {
            let an = MessageAudioAttachmentNode()
            an.configure(audio: row.audioAttachments, messageId: row.messageIdKey)
            audioAttachmentNode = an
            addSubnode(an)
        }
        if !row.fileAttachments.isEmpty {
            let fan = MessageFileAttachmentNode()
            fan.configure(files: row.fileAttachments)
            fan.onFileTapped = { urlString in
                guard let fileURL = URL(string: urlString),
                    let scheme = fileURL.scheme?.lowercased(),
                    scheme == "https" || scheme == "http"
                else { return }
                UIApplication.shared.open(fileURL)
            }
            fileAttachmentNode = fan
            addSubnode(fan)
        }
    }

    @objc fileprivate func unpinPressed() { onUnpin() }

    private func presentMediaGallery(index: Int, media: [ParsedAttachment]) {
        let items: [GalleryItemInfo] = media.enumerated().map { (_, att) in
            let placeholderURL: String? = att.isVideo
                ? nil
                : ImgproxyURL.attachmentURL(
                    from: att.url,
                    width: 400,
                    height: 400,
                    resizeType: "fit"
                )
            return GalleryItemInfo(
                url: att.url,
                image: nil,
                placeholderURL: placeholderURL,
                senderName: displayNameForGallery,
                senderAvatarURL: avatarURLForGallery,
                timestamp: Self.galleryTimestamp(for: pinForGallery),
                isVideo: att.isVideo
            )
        }
        let gallery = GalleryController(items: items, initialIndex: index)
        if let vc = findViewControllerForPresent() {
            vc.present(gallery, animated: true)
        }
    }

    private func findViewControllerForPresent() -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }

    private static func galleryTimestamp(for pin: Mezon_Api_PinMessage) -> Date {
        if pin.createTimeSeconds > 0 {
            return Date(timeIntervalSince1970: TimeInterval(pin.createTimeSeconds))
        }
        return Date()
    }

    private static func displayURL(from raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let proxied = ImgproxyURL.attachmentURL(from: s, width: 80, height: 80, resizeType: "fill")
        if let u = URL(string: proxied) { return u }
        if let enc = proxied.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let u = URL(string: enc)
        {
            return u
        }
        if let u = URL(string: s) { return u }
        return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap { URL(string: $0) }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let maxCardW = constrainedSize.max.width
        let cardHPadding: CGFloat = 12.sf * 2
        let innerW = max(1, maxCardW - cardHPadding)
        let avatarW = 40.sf
        let avatarGap: CGFloat = 12.sf
        let unpinW: CGFloat = 44
        let attachLeading = avatarW + avatarGap
        let attachMaxW = max(1, innerW - attachLeading)

        var attachmentElements: [ASLayoutElement] = []
        if let mcn = mediaContentNode {
            let sz = mcn.measureSize(maxWidth: attachMaxW)
            mcn.style.preferredSize = CGSize(width: sz.width, height: sz.height)
            attachmentElements.append(
                ASInsetLayoutSpec(
                    insets: UIEdgeInsets(top: 0, left: attachLeading, bottom: 0, right: 0),
                    child: mcn
                )
            )
        }
        if let an = audioAttachmentNode {
            let sz = an.measureSize(maxWidth: attachMaxW)
            an.style.preferredSize = CGSize(width: sz.width, height: sz.height)
            attachmentElements.append(
                ASInsetLayoutSpec(
                    insets: UIEdgeInsets(top: 0, left: attachLeading, bottom: 0, right: 0),
                    child: an
                )
            )
        }
        if let fan = fileAttachmentNode {
            let sz = fan.measureSize(maxWidth: attachMaxW)
            fan.style.preferredSize = CGSize(width: sz.width, height: sz.height)
            attachmentElements.append(
                ASInsetLayoutSpec(
                    insets: UIEdgeInsets(top: 0, left: attachLeading, bottom: 0, right: 0),
                    child: fan
                )
            )
        }

        var textChildren: [ASLayoutElement] = [nameNode]
        if includeCaption {
            textChildren.append(contentNode)
        }
        let textStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 4,
            justifyContent: .start,
            alignItems: .stretch,
            children: textChildren
        )
        textStack.style.flexShrink = 1
        textStack.style.flexGrow = 1

        let placeholderCentered = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: avatarPlaceholderNode
        )
        let imageFill = ASInsetLayoutSpec(insets: .zero, child: avatarNode)
        let avatarStack = ASOverlayLayoutSpec(
            child: avatarBgNode,
            overlay: ASOverlayLayoutSpec(
                child: placeholderCentered,
                overlay: imageFill
            )
        )

        let unpinWrap = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0),
            child: unpinButton
        )
        unpinWrap.style.alignSelf = .center

        let topRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarStack, textStack, unpinWrap]
        )

        var columnChildren: [ASLayoutElement] = [topRow]
        if !attachmentElements.isEmpty {
            let attachColumn = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 8,
                justifyContent: .start,
                alignItems: .stretch,
                children: attachmentElements
            )
            columnChildren.append(attachColumn)
        }

        let column = ASStackLayoutSpec(
            direction: .vertical,
            spacing: attachmentElements.isEmpty ? 0 : 8,
            justifyContent: .start,
            alignItems: .stretch,
            children: columnChildren
        )

        let cardContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
            child: column
        )
        let card = ASBackgroundLayoutSpec(child: cardContent, background: cardNode)

        let outer = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0),
            child: card
        )
        outer.style.alignSelf = .stretch
        return outer
    }
}

private extension UIView {
    func findHostingViewController() -> ViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? ViewController { return vc }
            responder = next
        }
        return nil
    }
}
