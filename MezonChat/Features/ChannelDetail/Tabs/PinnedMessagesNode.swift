import AsyncDisplayKit
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

    private let tableNode: ASTableNode

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
    }

    func loadTabDataIfNeeded() {
        guard !pinsLoadStarted else { return }
        pinsLoadStarted = true
        fetchPins()
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.primary
        tableNode.backgroundColor = .clear
        tableNode.view.backgroundColor = .clear
    }

    private func fetchPins() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = await context.getToken() ?? ""
                let targetClanId =
                    (channelType == MezonConstants.ChannelType.dm.rawValue
                        || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId

                let res = try await context.account.network.listPinMessages(
                    clanId: targetClanId,
                    channelId: channelId,
                    token: token
                )
                self.pinnedMessages = res.pinMessagesList
                self.pinsFetchCompleted = true
                await self.tableNode.reloadData()
            } catch {
                self.pinsFetchCompleted = true
                await self.tableNode.reloadData()
            }
        }
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
            let targetClanId =
                (channelType == MezonConstants.ChannelType.dm.rawValue
                    || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId
            do {
                try await context.account.network.deletePinMessage(
                    clanId: targetClanId,
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

@MainActor
extension PinnedMessagesNode: ASTableDataSource, ASTableDelegate {
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
        let row = PinRowContent.make(from: pin)
        let avatarURL = resolvedAvatarURLString(for: pin)
        return { [weak self] in
            PinnedMessageCellNode(
                displayName: displayName,
                row: row,
                avatarURLString: avatarURL,
                onUnpin: { self?.requestUnpin(pin) }
            )
        }
    }

    func tableNode(_ tableNode: ASTableNode, didSelectRowAt indexPath: IndexPath) {
        tableNode.deselectRow(at: indexPath, animated: true)
        guard pinsFetchCompleted, !pinnedMessages.isEmpty, indexPath.row < pinnedMessages.count else {
            return
        }
        jumpToPinnedMessage(pinnedMessages[indexPath.row])
    }
}

private struct PinRowContent {
    let caption: String
    let media: ParsedAttachment?
    let fileIconName: String?

    static func make(from pin: Mezon_Api_PinMessage) -> PinRowContent {
        let data = Data(pin.content.utf8)
        let parsed = MessageContentParser.parse(data: data, mentionsData: Data())
        let trimmed = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmbed = !parsed.embeds.isEmpty
        if !pin.attachment.isEmpty, let att = try? Mezon_Api_ChannelAttachment(serializedBytes: pin.attachment) {
            var urlStr = att.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if urlStr.isEmpty {
                for e in parsed.embeds {
                    if let u = e.imageURL, !u.isEmpty { urlStr = u; break }
                    if let u = e.thumbnailURL, !u.isEmpty { urlStr = u; break }
                }
            }
            let w = att.width == 0 ? nil : Int(att.width)
            let h = att.height == 0 ? nil : Int(att.height)
            let pa = ParsedAttachment(
                url: urlStr,
                filename: att.filename,
                filetype: att.filetype,
                width: w,
                height: h,
                durationSeconds: nil,
                localImage: nil,
                isUploading: false
            )
            if pa.isMedia, !urlStr.isEmpty {
                let cap: String
                if !trimmed.isEmpty { cap = trimmed }
                else {
                    let fn = att.filename.trimmingCharacters(in: .whitespacesAndNewlines)
                    cap = fn.isEmpty ? " " : fn
                }
                return PinRowContent(caption: cap, media: pa, fileIconName: nil)
            }
            let cap: String
            if !trimmed.isEmpty { cap = trimmed }
            else {
                let fn = att.filename.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fn.isEmpty { cap = fn } else { cap = L(L10n.ChannelDetail.pinAttachmentPreview) }
            }
            return PinRowContent(caption: cap, media: nil, fileIconName: Self.sfSymbol(for: att.filetype, parsed: pa))
        }
        if !trimmed.isEmpty { return PinRowContent(caption: trimmed, media: nil, fileIconName: nil) }
        if hasEmbed { return PinRowContent(caption: L(L10n.ChannelDetail.pinEmbedPreview), media: nil, fileIconName: nil) }
        if !pin.attachment.isEmpty { return PinRowContent(caption: L(L10n.ChannelDetail.pinAttachmentPreview), media: nil, fileIconName: "doc.fill") }
        if let d = pin.content.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
            let t = json["t"] as? String
        {
            let tTrim = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tTrim.isEmpty { return PinRowContent(caption: tTrim, media: nil, fileIconName: nil) }
        }
        let raw = pin.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let cap = raw.isEmpty ? " " : raw
        return PinRowContent(caption: cap, media: nil, fileIconName: nil)
    }

    private static func sfSymbol(for filetype: String, parsed: ParsedAttachment) -> String {
        let ft = filetype.lowercased()
        if ft.hasPrefix("image/") { return "photo" }
        if ft.hasPrefix("video/") { return "play.rectangle.fill" }
        if parsed.isImage { return "photo" }
        if parsed.isVideo { return "play.rectangle.fill" }
        if ft.contains("pdf") { return "doc.richtext.fill" }
        if ft.contains("audio") || ft.contains("mpeg") || ft.contains("mp3") || ft.contains("wav") { return "music.note" }
        if ft.contains("zip") || ft.contains("rar") || ft.contains("tar") || ft.contains("gz") { return "archivebox.fill" }
        if ft.contains("text") || ft.contains("json") || ft.contains("xml") { return "doc.plaintext.fill" }
        if ft.contains("sheet") || ft.contains("excel") || ft.contains("spreadsheet") { return "tablecells.fill" }
        return "doc.fill"
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
    private let mediaThumbNode: TransformImageNode?
    private let playOnVideoNode: ASImageNode?
    private let fileIconNode = ASImageNode()
    private let unpinButton = ASButtonNode()
    private let rowContent: PinRowContent
    private let onUnpin: () -> Void

    init(
        displayName: String, row: PinRowContent, avatarURLString: String, onUnpin: @escaping () -> Void
    ) {
        self.rowContent = row
        self.onUnpin = onUnpin
        if let m = row.media {
            let tn = TransformImageNode()
            tn.contentAnimations = [.firstUpdate]
            tn.style.preferredSize = CGSize(width: 56, height: 56)
            tn.cornerRadius = 8.sf
            tn.clipsToBounds = true
            self.mediaThumbNode = tn
            if m.isVideo {
                let p = ASImageNode()
                let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
                p.image = UIImage(systemName: "play.fill", withConfiguration: cfg)?.withTintColor(
                    .white, renderingMode: .alwaysOriginal)
                p.contentMode = .center
                self.playOnVideoNode = p
            } else {
                self.playOnVideoNode = nil
            }
        } else {
            self.mediaThumbNode = nil
            self.playOnVideoNode = nil
        }
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

        contentNode.attributedText = NSAttributedString(
            string: row.caption,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                .foregroundColor: t.text,
            ]
        )
        contentNode.maximumNumberOfLines = 3
        contentNode.truncationMode = .byTruncatingTail

        fileIconNode.style.preferredSize = CGSize(width: 32, height: 32)
        fileIconNode.contentMode = .scaleAspectFit
        if mediaThumbNode != nil {
            fileIconNode.isHidden = true
        } else if let sym = row.fileIconName, let img = UIImage(systemName: sym)?.withTintColor(t.text, renderingMode: .alwaysOriginal) {
            fileIconNode.image = img
            fileIconNode.isHidden = false
        } else {
            fileIconNode.isHidden = true
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
    }

    override func didLoad() {
        super.didLoad()
        guard let m = rowContent.media, let node = mediaThumbNode else { return }
        if m.isVideo {
            node.setSignal(
                videoThumbnailSignal(url: m.url, resizeMode: .fill), attemptSynchronously: false
            )
        } else {
            let w = 400
            let h = 400
            let proxy = ImgproxyURL.attachmentURL(
                from: m.url, width: w, height: h, resizeType: "fit"
            )
            node.setSignal(
                remoteAttachmentImageSignal(proxyURL: proxy, originalURL: m.url, resizeMode: .fit),
                attemptSynchronously: false
            )
        }
    }

    @objc fileprivate func unpinPressed() { onUnpin() }

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
        let avatarSize = 40.sf
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

        let textStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 4,
            justifyContent: .start,
            alignItems: .stretch,
            children: [nameNode, contentNode]
        )
        textStack.style.flexShrink = 1
        textStack.style.flexGrow = 1

        var rowChildren: [ASLayoutElement] = [avatarStack, textStack]
        if let mt = mediaThumbNode {
            let thumbInCard: ASLayoutElement
            if let play = playOnVideoNode {
                let playCentered = ASCenterLayoutSpec(
                    centeringOptions: .XY,
                    sizingOptions: .minimumXY,
                    child: play
                )
                playCentered.style.preferredSize = CGSize(width: 56, height: 56)
                thumbInCard = ASOverlayLayoutSpec(child: mt, overlay: playCentered)
            } else {
                thumbInCard = ASInsetLayoutSpec(insets: .zero, child: mt)
            }
            let right = ASInsetLayoutSpec(insets: .zero, child: thumbInCard)
            right.style.alignSelf = .center
            rowChildren.append(
                ASInsetLayoutSpec(
                    insets: UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0),
                    child: right
                )
            )
        } else if rowContent.fileIconName != nil {
            let rightInner = ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: .minimumXY,
                child: fileIconNode
            )
            rightInner.style.alignSelf = .center
            rowChildren.append(
                ASInsetLayoutSpec(
                    insets: UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0),
                    child: rightInner
                )
            )
        }
        let unpinWrap = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0),
            child: unpinButton
        )
        unpinWrap.style.alignSelf = .center
        rowChildren.append(unpinWrap)

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .start,
            alignItems: .center,
            children: rowChildren
        )

        let cardContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
            child: row
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
