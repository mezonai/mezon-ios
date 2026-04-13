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
    private let isVoiceActive: Bool

    init(channel: Mezon_Api_ChannelDescription, isSelected: Bool, isVoiceActive: Bool = false) {
        self.channel = channel
        self.cellSelected = isSelected
        self.isVoiceActive = isVoiceActive
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        clipsToBounds = true
        setupContent()
    }

    private static let voiceTypes: Set<Int32> = [
        MezonConstants.ChannelType.mezonVoice.rawValue,
        MezonConstants.ChannelType.streaming.rawValue,
        MezonConstants.ChannelType.app.rawValue,
    ]

    private func setupContent() {
        let t = UIColor.theme
        let chType = ChannelType(rawValue: channel.type) ?? .unknown
        let isVoiceType = Self.voiceTypes.contains(channel.type)
        let isUnread = !isVoiceType && (
            channel.countMessUnread > 0
            || (channel.hasLastSentMessage
                && channel.lastSeenMessage.timestampSeconds
                    < channel.lastSentMessage.timestampSeconds))
        let unread = isVoiceType ? 0 : channel.countMessUnread

        let voiceActiveGreen = UIColor(red: 22/255, green: 163/255, blue: 74/255, alpha: 1)
        let iconColor: UIColor
        if isVoiceActive {
            iconColor = voiceActiveGreen
        } else if isUnread {
            iconColor = t.channelUnread
        } else {
            iconColor = t.channelNormal
        }
        if chType.isSystemImage {
            var iconName = chType.icon
            if chType == .voice && isVoiceActive {
                iconName = "Channel/channelVoiceActive"
            }
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
        unreadDot.isHidden = !(isUnread && !cellSelected)

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

        let paddedContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw),
            child: contentWithBackground)

        if !unreadDot.isHidden {
            unreadDot.style.layoutPosition = CGPoint(x: -3.swh, y: 15.sh)
            let absDot = ASAbsoluteLayoutSpec(children: [unreadDot])
            return ASOverlayLayoutSpec(child: paddedContent, overlay: absDot)
        } else {
            return paddedContent
        }
    }
}

struct VoiceMemberDisplay {
    let name: String
    let avatarURL: String?
}

private func makeVoiceAvatarNodes(member m: VoiceMemberDisplay, size s: CGFloat) -> (wrapper: ASDisplayNode, img: ASNetworkImageNode, initLabel: ASTextNode2) {
    let wrapper = ASDisplayNode()
    wrapper.style.preferredSize = CGSize(width: s, height: s)
    wrapper.cornerRadius = s / 2
    wrapper.clipsToBounds = true
    wrapper.backgroundColor = UIColor.theme.colorAvatarDefault

    let imgNode = ASNetworkImageNode()
    imgNode.style.preferredSize = CGSize(width: s, height: s)
    imgNode.cornerRadius = s / 2
    imgNode.clipsToBounds = true
    imgNode.contentMode = .scaleAspectFill

    let initNode = ASTextNode2()
    initNode.maximumNumberOfLines = 1

    if let av = m.avatarURL, !av.isEmpty {
        let px = Int(s * UIScreen.main.scale)
        let proxy = ImgproxyURL.create(from: av, width: px, height: px)
        imgNode.url = URL(string: proxy)
        initNode.isHidden = true
    } else {
        imgNode.isHidden = true
        let initial = String(m.name.prefix(1)).uppercased()
        let fontSize: CGFloat = s < 20 ? 8 : 10
        initNode.attributedText = NSAttributedString(
            string: initial,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ])
    }

    wrapper.addSubnode(imgNode)
    wrapper.addSubnode(initNode)
    return (wrapper, imgNode, initNode)
}

final class VoiceMemberExpandedCellNode: ASCellNode {

    private static let avatarSize: CGFloat = 22

    private let avatarWrapper: ASDisplayNode
    private let avatarImg: ASNetworkImageNode
    private let avatarInit: ASTextNode2
    private let nameNode = ASTextNode2()

    init(member: VoiceMemberDisplay) {
        let nodes = makeVoiceAvatarNodes(member: member, size: Self.avatarSize)
        avatarWrapper = nodes.wrapper
        avatarImg = nodes.img
        avatarInit = nodes.initLabel
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: member.name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .regular),
                .foregroundColor: UIColor.theme.channelNormal,
            ])
    }

    override func layout() {
        super.layout()
        let s = Self.avatarSize
        avatarImg.frame = CGRect(origin: .zero, size: CGSize(width: s, height: s))
        avatarInit.frame = CGRect(origin: .zero, size: CGSize(width: s, height: s))
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        nameNode.style.flexShrink = 1
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarWrapper, nameNode]
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 4, left: 40, bottom: 4, right: 12),
            child: row
        )
    }
}

final class VoiceChannelMembersCollapsedCellNode: ASCellNode {

    private static let avatarSize: CGFloat = 18
    private static let maxVisible = 5

    private var avatarNodes: [ASDisplayNode] = []
    private var overflowNode: ASTextNode2?
    private var overflowBg: ASDisplayNode?

    init(members: [VoiceMemberDisplay], totalCount: Int) {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        let visible = Array(members.prefix(Self.maxVisible))
        for m in visible {
            let nodes = makeVoiceAvatarNodes(member: m, size: Self.avatarSize)
            avatarNodes.append(nodes.wrapper)
        }

        if totalCount > Self.maxVisible {
            let text = "+\(totalCount - Self.maxVisible)"
            let font = UIFont.systemFont(ofSize: 9, weight: .bold)
            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            let badgeWidth = max(Self.avatarSize, ceil(textWidth) + 8)

            let bg = ASDisplayNode()
            bg.style.preferredSize = CGSize(width: badgeWidth, height: Self.avatarSize)
            bg.cornerRadius = Self.avatarSize / 2
            bg.clipsToBounds = true
            bg.backgroundColor = UIColor.theme.primary
            bg.borderWidth = 1
            bg.borderColor = UIColor.theme.textDisabled.cgColor
            overflowBg = bg

            let node = ASTextNode2()
            node.maximumNumberOfLines = 1
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.minimumLineHeight = Self.avatarSize
            para.maximumLineHeight = Self.avatarSize
            node.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.theme.channelNormal,
                    .paragraphStyle: para,
                    .baselineOffset: (Self.avatarSize - font.lineHeight) / 2,
                ])
            node.style.preferredSize = CGSize(width: badgeWidth, height: Self.avatarSize)
            overflowNode = node
        }
    }

    override func layout() {
        super.layout()
        let s = Self.avatarSize
        for wrapper in avatarNodes {
            for sub in wrapper.subnodes ?? [] {
                sub.frame = CGRect(origin: .zero, size: CGSize(width: s, height: s))
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let s = Self.avatarSize
        var children: [ASLayoutElement] = avatarNodes
        if let overflow = overflowNode, let bg = overflowBg {
            children.append(ASBackgroundLayoutSpec(child: overflow, background: bg))
        }
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: -4,
            justifyContent: .start,
            alignItems: .center,
            children: children
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2, left: 38, bottom: 4, right: 12),
            child: row
        )
    }
}
