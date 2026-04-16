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
        let previewText = PinMessagePreview.text(for: pin)
        let avatarURL = resolvedAvatarURLString(for: pin)
        return {
            PinnedMessageCellNode(
                displayName: displayName, previewText: previewText, avatarURLString: avatarURL)
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

private enum PinMessagePreview {
    static func text(for pin: Mezon_Api_PinMessage) -> String {
        let data = Data(pin.content.utf8)
        let parsed = MessageContentParser.parse(data: data, mentionsData: Data())
        let trimmed = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !parsed.embeds.isEmpty { return L(L10n.ChannelDetail.pinEmbedPreview) }
        if !pin.attachment.isEmpty { return L(L10n.ChannelDetail.pinAttachmentPreview) }
        if let d = pin.content.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
            let t = json["t"] as? String
        {
            let tTrim = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tTrim.isEmpty { return tTrim }
        }
        let raw = pin.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? " " : raw
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

    init(displayName: String, previewText: String, avatarURLString: String) {
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
            string: previewText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                .foregroundColor: t.text,
            ]
        )
        contentNode.maximumNumberOfLines = 3
        contentNode.truncationMode = .byTruncatingTail
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

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarStack, textStack]
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
