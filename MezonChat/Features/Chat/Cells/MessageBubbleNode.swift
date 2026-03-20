import UIKit
import AsyncDisplayKit

final class MessageBubbleNode: ASCellNode {

    private let avatarContainerNode = ASDisplayNode()
    private let avatarImageNode = TransformImageNode()
    private let avatarPlaceholderNode = ASTextNode2()

    private let nameNode = ASTextNode2()
    private let timeNode = ASTextNode2()

    private var replyNode: MessageReplyNode?
    private var deletedReplyNode: MessageDeletedReplyNode?
    private var textContentNode: MessageTextContentNode?
    private var mediaContentNode: MessageMediaContentNode?
    private var reactionsNode: MessageReactionsNode?

    // MARK: - State

    private let display: ChatMessageDisplay
    private let isCombine: Bool
    private let hasContent: Bool
    private let hasMedia: Bool
    private let hasReactions: Bool
    private let hasReply: Bool
    private let hasDeletedReply: Bool

    private static let avatarSize: CGFloat = 40
    private static let contentLeading: CGFloat = 40 + 12.sw

    init(display: ChatMessageDisplay, interaction: ChatInteraction) {
        self.display = display
        self.isCombine = display.isCombine
        self.hasReply = display.replyRef != nil
        self.hasDeletedReply = display.isDeletedReply

        let parsed = display.parsedContent
        if display.checkOneLinkImage {
            self.hasContent = false
        } else {
            self.hasContent = !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let mediaAttachments = display.attachments.filter { $0.isMedia }
        self.hasMedia = !mediaAttachments.isEmpty
        self.hasReactions = !display.reactions.isEmpty

        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        let t = UIColor.theme

        // Avatar — container manages placeholder + image directly
        avatarContainerNode.backgroundColor = .colorAvatarDefault
        avatarContainerNode.cornerRadius = Self.avatarSize / 2
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.addSubnode(avatarPlaceholderNode)
        avatarContainerNode.addSubnode(avatarImageNode)

        avatarPlaceholderNode.attributedText = NSAttributedString(
            string: String(display.senderDisplayName.prefix(1)).uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )

        nameNode.attributedText = NSAttributedString(
            string: display.senderDisplayName,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .bold),
                .foregroundColor: t.textRoleLink,
            ]
        )
        nameNode.maximumNumberOfLines = 1

        timeNode.attributedText = NSAttributedString(
            string: Self.formatDate(display.message.createdAt),
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: t.textDisabled,
            ]
        )

        if let ref = display.replyRef {
            let rn = MessageReplyNode()
            rn.configure(ref: ref)
            replyNode = rn
        } else if display.isDeletedReply {
            deletedReplyNode = MessageDeletedReplyNode()
        }

        if hasContent {
            let tcn = MessageTextContentNode()
            tcn.configure(parsedContent: parsed)
            tcn.onMentionTapped = { interaction.onMentionTapped($0) }
            tcn.onHashtagTapped = { interaction.onHashtagTapped($0) }
            tcn.onLinkTapped = { UIApplication.shared.open($0) }
            textContentNode = tcn
        }

        if hasMedia {
            let mcn = MessageMediaContentNode()
            mcn.configure(media: mediaAttachments)
            mcn.onImageTapped = { [weak self] index in
                self?.handleImageTap(index: index, media: mediaAttachments, interaction: interaction)
            }
            mediaContentNode = mcn
        }

        if hasReactions {
            let rn = MessageReactionsNode()
            rn.configure(reactions: display.reactions)
            reactionsNode = rn
        }

        if !isCombine {
            loadAvatar()
        }
    }

    private func loadAvatar() {
        if let urlString = display.avatarURL, !urlString.isEmpty {
            avatarPlaceholderNode.isHidden = true
            let size = Self.avatarSize
            let args = TransformImageArguments(
                corners: ImageCorners(radius: size / 2),
                imageSize: CGSize(width: size, height: size),
                boundingSize: CGSize(width: size, height: size),
                intrinsicInsets: .zero
            )
            avatarImageNode.setSignal(remoteImageSignal(url: urlString, resizeMode: .fill), attemptSynchronously: false)
            let avatarLayout = avatarImageNode.asyncLayout()
            let apply = avatarLayout(args)
            apply()
        } else {
            avatarPlaceholderNode.isHidden = false
        }
    }

    private func handleImageTap(index: Int, media: [ParsedAttachment], interaction: ChatInteraction) {
        let galleryItems: [GalleryItemInfo] = media.enumerated().map { (_, att) in
            GalleryItemInfo(
                url: att.url,
                image: nil,
                senderName: display.senderDisplayName,
                senderAvatarURL: display.avatarURL,
                timestamp: display.message.createdAt,
                isVideo: att.isVideo
            )
        }
        let gallery = GalleryController(items: galleryItems, initialIndex: index)
        if let vc = findViewController() {
            vc.present(gallery, animated: true)
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = view
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }

    override func layout() {
        super.layout()
        let sz = avatarContainerNode.bounds.size
        avatarImageNode.frame = CGRect(origin: .zero, size: sz)
        let phSize = avatarPlaceholderNode.calculateSizeThatFits(sz)
        avatarPlaceholderNode.frame = CGRect(
            x: (sz.width - phSize.width) / 2,
            y: (sz.height - phSize.height) / 2,
            width: phSize.width,
            height: phSize.height
        )
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let contentLeadingTotal: CGFloat = 6.sw + Self.avatarSize + 6.sw
        let trailingInset: CGFloat = 12.sw
        let contentWidth = max(constrainedSize.max.width - contentLeadingTotal - trailingInset, 1)

        var contentChildren: [ASLayoutElement] = []

        if !isCombine {
            timeNode.style.flexShrink = 0
            nameNode.style.flexShrink = 1
            let nameTimeRow = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 4.sw,
                justifyContent: .start,
                alignItems: .end,
                children: [nameNode, timeNode]
            )
            contentChildren.append(nameTimeRow)
        }

        if let textContentNode = textContentNode {
            textContentNode.style.width = ASDimensionMake(contentWidth)
            contentChildren.append(textContentNode)
        }

        if let mediaContentNode = mediaContentNode {
            mediaContentNode.style.maxWidth = ASDimensionMake(contentWidth)
            contentChildren.append(mediaContentNode)
        }

        if let reactionsNode = reactionsNode {
            reactionsNode.style.maxWidth = ASDimensionMake(contentWidth)
            contentChildren.append(reactionsNode)
        }

        let contentColumn = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 4.sh,
            justifyContent: .start,
            alignItems: .start,
            children: contentChildren
        )

        var replySpec: ASLayoutElement?
        if let replyNode = replyNode {
            let replyInsets = UIEdgeInsets(top: 0, left: 6.sw, bottom: 2.sh, right: 12.sw)
            replySpec = ASInsetLayoutSpec(insets: replyInsets, child: replyNode)
        } else if let deletedReplyNode = deletedReplyNode {
            let replyInsets = UIEdgeInsets(top: 0, left: 6.sw, bottom: 2.sh, right: 12.sw)
            replySpec = ASInsetLayoutSpec(insets: replyInsets, child: deletedReplyNode)
        }

        if isCombine {
            let combineLeading: CGFloat = 6.sw + Self.avatarSize + 10.sw
            let contentInsets = UIEdgeInsets(top: 0, left: combineLeading, bottom: 0, right: 12.sw)
            let contentSpec = ASInsetLayoutSpec(insets: contentInsets, child: contentColumn)

            var verticalChildren: [ASLayoutElement] = []
            if let replySpec = replySpec { verticalChildren.append(replySpec) }
            verticalChildren.append(contentSpec)

            let verticalStack = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .start,
                alignItems: .stretch,
                children: verticalChildren
            )

            let outerInsets = UIEdgeInsets(top: 2.sh, left: 0, bottom: 12.sh, right: 0)
            return ASInsetLayoutSpec(insets: outerInsets, child: verticalStack)
        }

        let avatarSz = Self.avatarSize
        avatarContainerNode.style.preferredSize = CGSize(width: avatarSz, height: avatarSz)

        contentColumn.style.flexShrink = 1
        contentColumn.style.flexGrow = 1

        let mainRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10.sw,
            justifyContent: .start,
            alignItems: .start,
            children: [avatarContainerNode, contentColumn]
        )

        let mainRowInsets = UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 12.sw)
        let mainRowSpec = ASInsetLayoutSpec(insets: mainRowInsets, child: mainRow)

        var verticalChildren: [ASLayoutElement] = []
        if let replySpec = replySpec { verticalChildren.append(replySpec) }
        verticalChildren.append(mainRowSpec)

        let verticalStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: verticalChildren
        )

        let insets = UIEdgeInsets(top: 10.sh, left: 0, bottom: 12.sh, right: 0)
        return ASInsetLayoutSpec(insets: insets, child: verticalStack)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy, HH:mm"
        return f
    }()

    private static func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let timeStr = timeFormatter.string(from: date)
        if cal.isDateInToday(date) {
            return String(format: L(L10n.ChannelMessages.todayAt), timeStr)
        }
        if cal.isDateInYesterday(date) {
            return String(format: L(L10n.ChannelMessages.yesterdayAt), timeStr)
        }
        return fullFormatter.string(from: date)
    }
}
