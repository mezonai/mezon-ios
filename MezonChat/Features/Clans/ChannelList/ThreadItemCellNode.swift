import UIKit
import AsyncDisplayKit

final class ThreadItemCellNode: ASCellNode {

    private let connectorNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()
    private let isLast: Bool

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool, isLast: Bool) {
        self.isLast = isLast
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        clipsToBounds = false

        let t = UIColor.theme
        let unread = channel.countMessUnread
        let isUnread =
            unread > 0
            || (channel.hasLastSentMessage
                && channel.lastSeenMessage.timestampSeconds
                    < channel.lastSentMessage.timestampSeconds)

        let connectorName = isLast ? "Channel/ShortCorner" : "Channel/LongCorner"
        connectorNode.image = UIImage(named: connectorName)
        connectorNode.tintColor = t.channelNormal.withAlphaComponent(0.6)
        connectorNode.contentMode = .scaleAspectFit

        let nameColor =
            isSelected ? t.channelUnread : (isUnread ? t.channelUnread : t.channelNormal)
        let nameWeight: UIFont.Weight = isUnread ? .semibold : .regular
        nameNode.attributedText = NSAttributedString(
            string: channel.channelLabel,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: nameWeight),
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
            badgeNode.backgroundColor = .systemRed
            badgeNode.cornerRadius = 10.swh
            badgeNode.clipsToBounds = true
            badgeNode.isHidden = false
        } else {
            badgeNode.isHidden = true
        }

        backgroundColor = isSelected ? t.colorActiveClan : .clear
        if isSelected {
            cornerRadius = 16.swh
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        connectorNode.style.preferredSize = CGSize(
            width: isLast ? 12.swh : 14.swh, height: isLast ? 14.swh : 26.swh)
        badgeNode.style.minWidth = ASDimensionMake(20.swh)
        badgeNode.style.height = ASDimensionMake(20.swh)

        nameNode.style.flexShrink = 1
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        let topInset: CGFloat = isLast ? -4.sh : -18.sh
        let leftInset: CGFloat = isLast ? 2.sw : 0
        let connectorInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: topInset, left: leftInset, bottom: 0, right: 0),
            child: connectorNode)

        var children: [ASLayoutElement] = [connectorInset, nameNode]
        if !badgeNode.isHidden {
            children.append(contentsOf: [spacer, badgeNode])
        }

        let row = ASStackLayoutSpec(
            direction: .horizontal, spacing: 8.sw, justifyContent: .start, alignItems: .start,
            children: children)

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4.sh, left: 14.sw, bottom: 4.sh, right: 12.sw),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(30.sh)
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw), child: inset)
    }
}
