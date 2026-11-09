import AsyncDisplayKit
import UIKit

final class ThreadItemCellNode: ASCellNode {

    private let connectorNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()
    private let badgeBackground = ASDisplayNode()
    private let buzzBadge = BuzzBadgeNode()
    private let selectionNode = ASDisplayNode()
    var onLongPress: (() -> Void)?
    private let isLast: Bool
    private let channelLabel: String
    private let isUnread: Bool

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool, isLast: Bool, hasBuzz: Bool = false) {
        let unread = channel.countMessUnread
        self.isLast = isLast
        self.channelLabel = channel.channelLabel
        self.isUnread = unread > 0
            || (channel.hasLastSentMessage
                && channel.lastSeenMessage.timestampSeconds < channel.lastSentMessage.timestampSeconds)
        super.init()
        automaticallyManagesSubnodes = true
        neverShowPlaceholders = true
        selectionStyle = .none
        clipsToBounds = false
        buzzBadge.isHidden = !hasBuzz
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail

        let connectorName = isLast ? "Channel/ShortCorner" : "Channel/LongCorner"
        connectorNode.image = UIImage(named: connectorName)?.withRenderingMode(.alwaysTemplate)
        connectorNode.contentMode = .scaleAspectFit

        if unread > 0 {
            let text = unread > 99 ? "99+" : "\(unread)"
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            badgeNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10.sf, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: para,
                ])
            badgeBackground.backgroundColor = UIColor.theme.desktop.semantic.mentionBadge
            badgeBackground.clipsToBounds = true
            badgeBackground.isHidden = false
            badgeNode.isHidden = false
        } else {
            badgeBackground.isHidden = true
            badgeNode.isHidden = true
        }

        backgroundColor = .clear
        selectionNode.cornerRadius = 16.swh
        applyListSelectionState(selected: isSelected)
        isUserInteractionEnabled = true
    }

    func applyListSelectionState(selected: Bool) {
        let theme = UIColor.theme
        let isHighlighted = selected || isUnread
        let nameColor = isHighlighted ? theme.desktop[.textSecondary] : theme.textThemePrimary
        let nameWeight: UIFont.Weight = isHighlighted ? .semibold : .medium
        nameNode.attributedText = NSAttributedString(
            string: channelLabel,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: nameWeight),
                .foregroundColor: nameColor,
            ])
        connectorNode.tintColor = theme.textDisabled
        selectionNode.isHidden = !selected
        selectionNode.backgroundColor = selected ? theme.desktop[.bgActiveMemberChannel] : .clear
        setNeedsLayout()
    }

    override func didLoad() {
        super.didLoad()
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        view.addGestureRecognizer(lp)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onLongPress?()
        }
    }

    override func layout() {
        super.layout()
        badgeBackground.cornerRadius = badgeBackground.bounds.height / 2
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        connectorNode.style.preferredSize = CGSize(
            width: isLast ? 13.swh : 14.swh, height: isLast ? 18.swh : 34.swh)
        let badgeInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2.swh, left: 6.swh, bottom: 2.swh, right: 6.swh),
            child: badgeNode)
        let badge = ASBackgroundLayoutSpec(child: badgeInset, background: badgeBackground)
        badge.style.minSize = CGSize(width: 20.swh, height: 20.swh)

        nameNode.style.flexShrink = 1
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        let topInset: CGFloat = isLast ? -4.sh : -30.sh
        let leftInset: CGFloat = isLast ? 1.sw : 0
        let connectorInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: topInset, left: leftInset, bottom: 0, right: 0),
            child: connectorNode)

        var contentChildren: [ASLayoutElement] = [nameNode]
        if !badgeNode.isHidden || !buzzBadge.isHidden { contentChildren.append(spacer) }
        if !buzzBadge.isHidden { contentChildren.append(buzzBadge) }
        if !badgeNode.isHidden { contentChildren.append(badge) }

        let contentStack = ASStackLayoutSpec(
            direction: .horizontal, spacing: 8.sw, justifyContent: .start, alignItems: .center,
            children: contentChildren)
        contentStack.style.flexGrow = 1

        let contentWithBackground = ASBackgroundLayoutSpec(
            child: ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 8.sh, left: 8.sw, bottom: 6.sh, right: 12.sw),
                child: contentStack),
            background: selectionNode
        )
        contentWithBackground.style.flexGrow = 1

        let row = ASStackLayoutSpec(
            direction: .horizontal, spacing: 0, justifyContent: .start, alignItems: .center,
            children: [connectorInset, contentWithBackground])

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 14.sw, bottom: 0, right: 0),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(30.sh)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw), child: inset)
    }
}
