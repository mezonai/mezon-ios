import AsyncDisplayKit
import UIKit

final class ChannelItemCellNode: ASCellNode {

    private let iconNode = ASTextNode2()
    private let iconImgNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()
    private let badgeBackground = ASDisplayNode()
    private let unreadDot = ASDisplayNode()
    private let selectionNode = ASDisplayNode()
    var onLongPress: (() -> Void)?

    private let channel: Mezon_Api_ChannelDescription
    private let cellSelected: Bool

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool) {
        self.channel = channel
        self.cellSelected = isSelected
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        setupContent()
    }

    private func setupContent() {
        let t = UIColor.theme
        let chType = ChannelType(rawValue: channel.type) ?? .unknown
        let isUnread =
            channel.countMessUnread > 0
            || (channel.hasLastSentMessage
                && channel.lastSeenMessage.timestampSeconds
                    < channel.lastSentMessage.timestampSeconds)
        let unread = channel.countMessUnread

        let iconColor =
            isUnread ? t.channelUnread : t.channelNormal
        if chType.isSystemImage {
            var iconName = chType.icon
            if chType == .text && channel.channelPrivate == 1 {
                iconName = "Channel/channelPrivate"
            }
            if chType == .text && channel.ageRestricted == 1 {
                iconName = "Channel/channelWarning"
            }
            let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
            iconImgNode.image = image?.withRenderingMode(.alwaysTemplate)
            iconImgNode.tintColor = iconColor
            iconImgNode.isHidden = false
            iconNode.isHidden = true
        } else {
            iconNode.attributedText = NSAttributedString(
                string: chType.icon,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                    .foregroundColor: iconColor,
                ])
            iconNode.isHidden = false
            iconImgNode.isHidden = true
        }

        let nameStr = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        let nameColor =
            isUnread ? t.channelUnread : t.channelNormal
        let nameWeight: UIFont.Weight = isUnread ? .semibold : .medium
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: nameStr,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: nameWeight),
                .foregroundColor: nameColor,
            ])

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
            badgeBackground.backgroundColor = .systemRed
            badgeBackground.clipsToBounds = true
            badgeBackground.isHidden = false
            badgeNode.isHidden = false
        } else {
            badgeBackground.isHidden = true
            badgeNode.isHidden = true
        }

        unreadDot.backgroundColor = .white
        unreadDot.cornerRadius = 3.swh
        unreadDot.isHidden = !(unread > 0 && !cellSelected)

        selectionNode.isHidden = !cellSelected
        let theme = ThemeManager.shared.current
        let isLight =
            theme == .light
            || (theme == .system && UIScreen.main.traitCollection.userInterfaceStyle != .dark)
        selectionNode.backgroundColor =
            cellSelected ? (isLight ? t.secondaryWeight : t.secondaryLight) : .clear
        selectionNode.cornerRadius = 16.swh
        backgroundColor = .clear

        isUserInteractionEnabled = true
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
        iconNode.style.preferredSize = CGSize(width: 14.swh, height: 14.swh)
        iconImgNode.style.preferredSize = CGSize(width: 12.swh, height: 12.swh)
        let iconChild: ASLayoutElement = iconNode.isHidden ? iconImgNode : iconNode

        let badgeInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2.swh, left: 6.swh, bottom: 2.swh, right: 6.swh),
            child: badgeNode)
        let badge = ASBackgroundLayoutSpec(child: badgeInset, background: badgeBackground)
        badge.style.minSize = CGSize(width: 20.swh, height: 20.swh)

        unreadDot.style.preferredSize = CGSize(width: 6.swh, height: 6.swh)

        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1
        nameNode.style.flexShrink = 1
        nameNode.style.flexGrow = 0

        var children: [ASLayoutElement] = [iconChild, nameNode]
        if !badgeNode.isHidden {
            children.append(contentsOf: [spacer, badge])
        }

        let row = ASStackLayoutSpec(
            direction: .horizontal, spacing: 10.sw, justifyContent: .start, alignItems: .center,
            children: children)

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sh, left: 12.sw, bottom: 8.sh, right: 12.sw),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(36.sh)
        let contentWithBackground = ASBackgroundLayoutSpec(child: inset, background: selectionNode)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw),
            child: contentWithBackground)
    }
}
