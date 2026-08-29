import AsyncDisplayKit
import Foundation
import SwiftProtobuf
import UIKit

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
    private var pinRowDisplayItems: [PinRowDisplayItem] = []

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
        tableNode.leadingScreensForBatching = 0

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePinsNeedRefresh(_:)),
            name: .mezonChannelPinsNeedRefresh,
            object: nil
        )
    }

    @available(iOS 13.0, *)
    func loadTabDataIfNeeded() {
        if !pinsLoadStarted {
            pinsLoadStarted = true
            fetchPins()
            return
        }
        guard pinsFetchCompleted else { return }
        tableNode.reloadData()
        setNeedsLayout()
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: .mezonChannelPinsNeedRefresh, object: nil)
    }

    @objc private func handlePinsNeedRefresh(_ notification: Notification) {
        if #available(iOS 13.0, *) {
            let eventChannel = Self.notificationInt64(notification.userInfo?["channelId"]) ?? 0
            guard eventChannel == channelId else { return }
            refetchPinsFromNetwork()
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.primary
        tableNode.backgroundColor = .clear
        tableNode.view.backgroundColor = .clear
    }

    @available(iOS 13.0, *)
    private func fetchPins() {
        refetchPinsFromNetwork()
    }

    @available(iOS 13.0, *)
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
                self.rebuildPinRowDisplayItems()
                await self.tableNode.reloadData()
                self.setNeedsLayout()
                self.enrichPinAttachmentsFromChannelIfNeeded(expectedDataGeneration: dataGen)
            } catch {
                self.pinsFetchCompleted = true
                self.rebuildPinRowDisplayItems()
                await self.tableNode.reloadData()
                self.setNeedsLayout()
            }
        }
    }

    @available(iOS 13.0, *)
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
            self.rebuildPinRowDisplayItems()
            await self.tableNode.reloadData()
            self.setNeedsLayout()
        }
    }

    private static func notificationInt64(_ value: Any?) -> Int64? {
        if let v = value as? Int64 { return v }
        if let v = value as? Int { return Int64(v) }
        if let v = value as? NSNumber { return v.int64Value }
        if let v = value as? String { return Int64(v) }
        return nil
    }

    @available(iOS 13.0, *)
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

    @available(iOS 13.0, *)
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
                self.rebuildPinRowDisplayItems()
                await self.tableNode.reloadData()
                self.setNeedsLayout()
            } catch {
                Toast.error(L(L10n.ChannelDetail.unpinError))
            }
        }
    }

    @available(iOS 13.0, *)
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

    private func resolvedSenderUsername(for pin: Mezon_Api_PinMessage) -> String {
        let idStr = String(pin.senderID)
        var resolved = ""
        context.account.postbox.read { tx in
            if let p = tx.getProfile(userId: idStr) {
                if !p.username.isEmpty {
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

    private func rebuildPinRowDisplayItems() {
        pinRowDisplayItems = pinnedMessages.map { pin in
            let extras = attachmentEnrichmentByMessageId[pin.messageID] ?? []
            return PinRowDisplayItem(
                pin: pin,
                displayName: resolvedSenderDisplayName(for: pin),
                username: resolvedSenderUsername(for: pin),
                row: PinRowContent.make(from: pin, context: context, attachmentExtras: extras),
                avatarURL: resolvedAvatarURLString(for: pin)
            )
        }
    }

}

private struct PinRowDisplayItem {
    let pin: Mezon_Api_PinMessage
    let displayName: String
    let username: String
    let row: PinRowContent
    let avatarURL: String
}

extension PinnedMessagesNode: ASTableDataSource {
    func tableNode(_ tableNode: ASTableNode, numberOfRowsInSection section: Int) -> Int {
        let count: Int
        if pinsLoadStarted, !pinsFetchCompleted {
            count = 1
        } else if !pinsFetchCompleted {
            count = 0
        } else if pinnedMessages.isEmpty {
            count = 1
        } else {
            count = pinnedMessages.count
        }
        return count
    }

    func tableNode(_ tableNode: ASTableNode, nodeBlockForRowAt indexPath: IndexPath) -> ASCellNodeBlock {
        if pinsLoadStarted, !pinsFetchCompleted {
            return { PinsLoadingCellNode() }
        }
        if pinnedMessages.isEmpty {
            return { EmptyPinsCellNode() }
        }
        let item = pinRowDisplayItems[indexPath.row]
        return { [weak self] in
            PinnedMessageCellNode(
                username: item.username,
                displayName: item.displayName,
                pin: item.pin,
                row: item.row,
                avatarURLString: item.avatarURL,
                onUnpin: { if #available(iOS 13.0, *) { self?.requestUnpin(item.pin) } }
            )
        }
    }
}

extension PinnedMessagesNode: ASTableDelegate {
    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
        guard pinsFetchCompleted, !pinnedMessages.isEmpty, indexPath.row < pinnedMessages.count else {
            return
        }
        if #available(iOS 13.0, *) {
            jumpToPinnedMessage(pinnedMessages[indexPath.row])
        }
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

    static func collatedURLCountBeforeExtras(for pin: Mezon_Api_PinMessage, context: AccountContext) -> Int {
        collatedAttachments(for: pin, context: context, attachmentExtras: []).count
    }

    static func make(from pin: Mezon_Api_PinMessage, context: AccountContext, attachmentExtras: [ParsedAttachment] = []) -> PinRowContent {
        let data = pin.content.data(using: .utf8) ?? Data()
        let parsed = MessageContentParser.parse(data: data, mentionsData: Data())
        let trimmed = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmbed = !parsed.embeds.isEmpty
        let isShareContact = isShareContactEmbed(parsed.embeds)
            || rawContentContainsShareContact(pin.content)

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
            if isShareContact {
                return "[\(L(L10n.ChannelDetail.pinContactPreview))]"
            }
            if hasEmbed, mediaAttachments.isEmpty, audioAttachments.isEmpty, fileAttachments.isEmpty {
                return L(L10n.ChannelDetail.pinEmbedPreview)
            }
            if !pin.attachment.isEmpty, combined.isEmpty {
                return L(L10n.ChannelDetail.pinAttachmentPreview)
            }
            let raw = pin.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            if let d = raw.data(using: .utf8),
               let jo = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            {
                let tStr = (jo["t"] as? String ?? jo["text"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return tStr.isEmpty ? nil : tStr
            }
            return raw
        }()

        return PinRowContent(
            caption: caption,
            messageIdKey: "\(pin.messageID)",
            mediaAttachments: mediaAttachments,
            audioAttachments: audioAttachments,
            fileAttachments: fileAttachments
        )
    }

    private static func isShareContactEmbed(_ embeds: [ParsedEmbed]) -> Bool {
        embeds.contains { embed in
            embed.fields.contains { field in
                let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = field.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if name == "key", isShareContactValue(value) { return true }
                return isShareContactValue(value)
            }
        }
    }

    private static func rawContentContainsShareContact(_ raw: String) -> Bool {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return embedPayloadContainsShareContact(json["embed"])
            || embedPayloadContainsShareContact(json["embeds"])
    }

    private static func embedPayloadContainsShareContact(_ payload: Any?) -> Bool {
        if let embeds = payload as? [[String: Any]] {
            return embeds.contains(where: embedDictionaryContainsShareContact)
        }
        if let embed = payload as? [String: Any] {
            return embedDictionaryContainsShareContact(embed)
        }
        if let embeds = payload as? [Any] {
            return embeds.contains { item in
                guard let embed = item as? [String: Any] else { return false }
                return embedDictionaryContainsShareContact(embed)
            }
        }
        return false
    }

    private static func embedDictionaryContainsShareContact(_ embed: [String: Any]) -> Bool {
        if let fields = embed["fields"] as? [[String: Any]] {
            return fieldsContainShareContact(fields)
        }
        if let fields = embed["fields"] as? [Any] {
            return fields.contains { item in
                guard let field = item as? [String: Any] else { return false }
                return fieldContainsShareContact(field)
            }
        }
        return false
    }

    private static func fieldsContainShareContact(_ fields: [[String: Any]]) -> Bool {
        fields.contains(where: fieldContainsShareContact)
    }

    private static func fieldContainsShareContact(_ field: [String: Any]) -> Bool {
        let name = ((field["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = ((field["value"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name == "key", isShareContactValue(value) { return true }
        return isShareContactValue(value)
    }

    private static func isShareContactValue(_ value: String) -> Bool {
        value == MezonConstants.shareContactKey || value == "share_contact_key"
    }

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
    private let spinnerHost = ASDisplayNode(viewBlock: {
        let v = UIActivityIndicatorView.mezonMedium()
        v.color = UIColor.theme.textStrong
        v.startAnimating()
        return v
    })

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none
        spinnerHost.style.preferredSize = CGSize(width: 44, height: 44)
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

private final class PinnedMessageCellNode: ASCellNode, ASNetworkImageNodeDelegate {
    private let row: PinRowContent
    private let displayNameForGallery: String
    private let pinForGallery: Mezon_Api_PinMessage
    private let avatarURLForGallery: String
    private let onUnpin: () -> Void
    private let includeCaption: Bool
    private let avatarUsernameForFallback: String
    private let displayName: String

    private let cardNode = ASDisplayNode()
    private let textAvatarNode = TextAvatarNode(username: "", size: 40.sf, fontSize: 16.sf)
    private let avatarNode = ASNetworkImageNode()
    private let nameNode = ASTextNode2()
    private let contentNode = ASTextNode2()
    private let unpinButton = ASButtonNode()
    private var mediaContentNode: MessageMediaContentNode?
    private var audioAttachmentNode: MessageAudioAttachmentNode?
    private var fileAttachmentNode: MessageFileAttachmentNode?
    private var didConfigureMainThreadUI = false
    private var lastAttachMaxWidth: CGFloat = 300

    init(
        username: String,
        displayName: String,
        pin: Mezon_Api_PinMessage,
        row: PinRowContent,
        avatarURLString: String,
        onUnpin: @escaping () -> Void
    ) {
        self.row = row
        self.displayNameForGallery = displayName
        self.pinForGallery = pin
        self.avatarURLForGallery = avatarURLString
        self.onUnpin = onUnpin
        self.avatarUsernameForFallback = username
        self.displayName = displayName
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

        avatarNode.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
        avatarNode.cornerRadius = avatarSize / 2
        avatarNode.clipsToBounds = true
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.delegate = self

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
            UIImage.mezonSystemImage("xmark.circle.fill")?.mezonTinted(
                t.text.withAlphaComponent(0.75), renderingMode: .alwaysOriginal),
            for: .normal)
        unpinButton.style.preferredSize = CGSize(width: 44, height: 44)
        unpinButton.contentHorizontalAlignment = .middle
        unpinButton.contentVerticalAlignment = .center
        unpinButton.addTarget(
            self, action: #selector(unpinPressed), forControlEvents: .touchUpInside)

        if !row.mediaAttachments.isEmpty {
            let mcn = MessageMediaContentNode()
            mcn.prepareForMeasurement(media: row.mediaAttachments)
            mediaContentNode = mcn
        }
        if !row.audioAttachments.isEmpty {
            let an = MessageAudioAttachmentNode()
            an.configure(audio: row.audioAttachments, messageId: row.messageIdKey)
            audioAttachmentNode = an
        }
        if !row.fileAttachments.isEmpty {
            fileAttachmentNode = MessageFileAttachmentNode()
        }
    }

    override func didLoad() {
        super.didLoad()
        configureMainThreadUIIfNeeded()
    }

    private func configureMainThreadUIIfNeeded() {
        guard !didConfigureMainThreadUI else { return }
        didConfigureMainThreadUI = true

        if let url = Self.displayURL(from: avatarURLForGallery) {
            avatarNode.url = url
            avatarNode.isHidden = false
            textAvatarNode.showSkeleton()
        } else {
            avatarNode.url = nil
            avatarNode.isHidden = true
            textAvatarNode.configure(username: avatarUsernameForFallback, fontSize: 16.sf)
        }

        if !row.mediaAttachments.isEmpty {
            let media = row.mediaAttachments
            if let mcn = mediaContentNode {
                mcn.configure(media: media)
                mcn.onImageTapped = { [weak self] index in
                    self?.presentMediaGallery(index: index, media: media)
                }
                if lastAttachMaxWidth > 0 {
                    _ = mcn.measureSize(maxWidth: lastAttachMaxWidth)
                }
            }
        }
        if let fan = fileAttachmentNode, !row.fileAttachments.isEmpty {
            fan.configure(files: row.fileAttachments)
            fan.onFileTapped = { urlString in
                guard let fileURL = URL(string: urlString),
                    let scheme = fileURL.scheme?.lowercased(),
                    scheme == "https" || scheme == "http"
                else { return }
                UIApplication.shared.open(fileURL)
            }
        }

        setNeedsLayout()
        invalidateCalculatedLayout()
    }

    @objc fileprivate func unpinPressed() { onUnpin() }

    private func presentMediaGallery(index: Int, media: [ParsedAttachment]) {
        let items: [GalleryItemInfo] = media.enumerated().map { (itemIndex, att) in
            if att.isVideo {
                return GalleryItemInfo(
                    url: att.url,
                    sourceURL: att.url,
                    image: itemIndex == index ? att.localImage : nil,
                    placeholderURL: nil,
                    senderName: displayNameForGallery,
                    senderId: String(pinForGallery.senderID),
                    senderAvatarURL: avatarURLForGallery,
                    timestamp: Self.galleryTimestamp(for: pinForGallery),
                    isVideo: true
                )
            }
            return GalleryItemInfo.imageItem(
                sourceURL: att.url,
                image: itemIndex == index ? att.localImage : nil,
                pixelSize: GalleryItemInfo.pixelSize(width: att.width, height: att.height),
                senderName: displayNameForGallery,
                senderId: String(pinForGallery.senderID),
                senderAvatarURL: avatarURLForGallery,
                timestamp: Self.galleryTimestamp(for: pinForGallery)
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

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didLoad image: UIImage) {
        guard imageNode === avatarNode else { return }
        let username = avatarUsernameForFallback
        runOnMainThread { [weak self] in
            guard let self, imageNode === self.avatarNode else { return }
            if image.size.width < 0.5 || image.size.height < 0.5 {
                self.textAvatarNode.configure(username: username, fontSize: 16.sf)
            } else {
                self.textAvatarNode.showImageMode()
            }
        }
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didFailWithError error: Error) {
        guard imageNode === avatarNode else { return }
        let username = avatarUsernameForFallback
        runOnMainThread { [weak self] in
            guard let self, imageNode === self.avatarNode else { return }
            self.textAvatarNode.configure(username: username, fontSize: 16.sf)
        }
    }

    private func runOnMainThread(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let maxCardW = constrainedSize.max.width
        let cardHPadding: CGFloat = 12.sf * 2
        let innerW = max(1, maxCardW - cardHPadding)
        let avatarW = 40.sf
        let avatarGap: CGFloat = 12.sf
        let attachLeading = avatarW + avatarGap
        let attachMaxW = max(1, innerW - attachLeading)
        lastAttachMaxWidth = attachMaxW

        var attachmentElements: [ASLayoutElement] = []
        if let mcn = mediaContentNode, !row.mediaAttachments.isEmpty {
            let sz = mcn.measureSize(maxWidth: attachMaxW)
            mcn.style.preferredSize = CGSize(width: max(sz.width, 1), height: max(sz.height, 1))
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
        if let fan = fileAttachmentNode, !row.fileAttachments.isEmpty {
            let sz =
                didConfigureMainThreadUI
                ? fan.measureSize(maxWidth: attachMaxW)
                : MessageFileAttachmentNode.estimatedMeasureSize(
                    files: row.fileAttachments, maxWidth: attachMaxW)
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

        let avatarStack = ASOverlayLayoutSpec(
            child: textAvatarNode,
            overlay: ASInsetLayoutSpec(insets: .zero, child: avatarNode)
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
