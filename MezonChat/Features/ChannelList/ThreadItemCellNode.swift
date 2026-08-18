import AsyncDisplayKit
import UIKit

final class ThreadItemCellNode: ASCellNode {

    private let connectorNode = ASImageNode()
    private let eventIconNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()
    private let badgeBackground = ASDisplayNode()
    private let selectionNode = ASDisplayNode()
    var onLongPress: (() -> Void)?
    private let isLast: Bool
    private var eventStatus: Int32?
    let channelId: Int64

    init(
        channel: Mezon_Api_ChannelDescription,
        isSelected: Bool,
        isLast: Bool,
        eventStatus: Int32? = nil
    ) {
        self.isLast = isLast
        self.eventStatus = ChannelEventIcon.normalizedStatus(eventStatus)
        self.channelId = channel.channelID
        super.init()
        automaticallyManagesSubnodes = true
        neverShowPlaceholders = true
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

        eventIconNode.image = ChannelEventIcon.image(for: eventStatus)
        eventIconNode.contentMode = .scaleAspectFit
        eventIconNode.isHidden = eventIconNode.image == nil

        let nameColor =
            isUnread ? t.channelUnread : t.channelNormal
        let nameWeight: UIFont.Weight = isUnread ? .semibold : .medium
        nameNode.attributedText = NSAttributedString(
            string: channel.channelLabel,
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

        backgroundColor = .clear
        let theme = ThemeManager.shared.current
        let isLight =
            theme == .light
            || (theme == .system && UIScreen.main.traitCollection.userInterfaceStyle != .dark)
        selectionNode.backgroundColor =
            isSelected ? (isLight ? t.secondaryWeight : t.secondaryLight) : .clear
        if isSelected {
            selectionNode.cornerRadius = 16.swh
        }
        selectionNode.isHidden = !isSelected

        isUserInteractionEnabled = true
    }

    func applyEventStatus(_ status: Int32?) {
        let normalized = ChannelEventIcon.normalizedStatus(status)
        guard eventStatus != normalized else { return }
        eventStatus = normalized
        eventIconNode.image = ChannelEventIcon.image(for: normalized)
        eventIconNode.isHidden = eventIconNode.image == nil
        setNeedsLayout()
    }

    func applyListSelectionState(selected: Bool) {
        let t = UIColor.theme
        selectionNode.isHidden = !selected
        let theme = ThemeManager.shared.current
        let isLight =
            theme == .light
            || (theme == .system && UIScreen.main.traitCollection.userInterfaceStyle != .dark)
        selectionNode.backgroundColor =
            selected ? (isLight ? t.secondaryWeight : t.secondaryLight) : .clear
        if selected {
            selectionNode.cornerRadius = 16.swh
        }
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
        eventIconNode.style.preferredSize = CGSize(width: 16.swh, height: 16.swh)
        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1

        let topInset: CGFloat = isLast ? -4.sh : -30.sh
        let leftInset: CGFloat = isLast ? 1.sw : 0
        let connectorInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: topInset, left: leftInset, bottom: 0, right: 0),
            child: connectorNode)

        var contentChildren: [ASLayoutElement] = []
        if !eventIconNode.isHidden {
            contentChildren.append(eventIconNode)
        }
        contentChildren.append(nameNode)
        if !badgeNode.isHidden {
            contentChildren.append(contentsOf: [spacer, badge])
        }

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
