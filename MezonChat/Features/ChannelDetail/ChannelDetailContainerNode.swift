import AsyncDisplayKit
import UIKit

@MainActor
final class ChannelDetailContainerNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channel: Mezon_Api_ChannelDescription
    private let onClose: () -> Void
    private let onSettingsTapped: () -> Void

    private let backButtonNode = ASButtonNode()
    private let titleNode = ASTextNode2()
    private let channelIconNode = ASImageNode()

    private let actionButtonsNode: ChannelDetailActionButtonsNode

    private var tabNodes: [ASTextNode2] = []
    private lazy var tabLabels = [
        L(L10n.ChannelDetail.members),
        L(L10n.ChannelDetail.media),
        L(L10n.ChannelDetail.files),
        L(L10n.ChannelDetail.pins),
        L(L10n.ChannelDetail.canvas),
    ]
    private let tabBarNode = ASScrollNode()
    private let tabIndicatorNode = ASDisplayNode()

    private let membersListNode: MemberListNode
    private let mediaGalleryNode: MediaGalleryNode
    private let fileListNode: FileListNode
    private let pinnedMessagesNode: PinnedMessagesNode
    private let canvasNode: CanvasNode

    private var activeTabIndex: Int = 0

    init(
        context: AccountContext, clanId: Int64, channel: Mezon_Api_ChannelDescription,
        onClose: @escaping () -> Void, onSettingsTapped: @escaping () -> Void
    ) {
        self.context = context
        self.clanId = clanId
        self.channel = channel
        self.onClose = onClose
        self.onSettingsTapped = onSettingsTapped

        self.actionButtonsNode = ChannelDetailActionButtonsNode()
        self.membersListNode = MemberListNode(
            context: context, clanId: clanId, channelId: channel.channelID,
            channelType: channel.type, isPrivate: channel.channelPrivate != 0)
        self.mediaGalleryNode = MediaGalleryNode(
            context: context, clanId: clanId, channelId: channel.channelID,
            channelType: channel.type)
        self.fileListNode = FileListNode(
            context: context, clanId: clanId, channelId: channel.channelID,
            channelType: channel.type)
        self.pinnedMessagesNode = PinnedMessagesNode(
            context: context, clanId: clanId, channelId: channel.channelID,
            channelType: channel.type)
        self.canvasNode = CanvasNode(
            context: context, clanId: clanId, channelId: channel.channelID,
            channelType: channel.type)

        super.init()
        self.automaticallyManagesSubnodes = true

        setupHeader()
        setupTabs()
        actionButtonsNode.onSettingsTapped = { [weak self] in
            self?.settingsPressed()
        }
        updateTabIndicator(animated: false)
    }

    private func setupHeader() {
        backButtonNode.setImage(
            UIImage(systemName: "chevron.left")?.withTintColor(
                UIColor.theme.textStrong, renderingMode: .alwaysOriginal), for: .normal)
        backButtonNode.addTarget(
            self, action: #selector(backPressed), forControlEvents: .touchUpInside)

        let title = channel.channelLabel
        let isThread = channel.type == 7

        let iconName: String
        if isThread {
            iconName =
                channel.channelPrivate != 0
                ? "Channel/channelThreadPrivate" : "Channel/channelThread"
        } else {
            iconName = "Channel/channel"
        }

        channelIconNode.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
        channelIconNode.tintColor = UIColor.theme.textStrong

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )
    }

    private func setupTabs() {
        tabNodes = tabLabels.enumerated().map { index, label in
            let node = ASTextNode2()
            node.isUserInteractionEnabled = true
            node.view.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(tabPressed(_:))))
            node.view.tag = index
            updateTabNode(node, isActive: index == activeTabIndex)
            return node
        }
        tabIndicatorNode.backgroundColor = UIColor.theme.textLink
        tabIndicatorNode.cornerRadius = 1.5.sf
        self.addSubnode(tabIndicatorNode)
    }

    private func updateTabNode(_ node: ASTextNode2, isActive: Bool) {
        let index = node.view.tag
        node.attributedText = NSAttributedString(
            string: tabLabels[index],
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: isActive ? .semibold : .medium),
                .foregroundColor: isActive ? UIColor.theme.textLink : UIColor.theme.textDisabled,
            ]
        )
    }

    @objc private func tabPressed(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        activeTabIndex = index
        for (i, node) in tabNodes.enumerated() {
            updateTabNode(node, isActive: i == activeTabIndex)
        }
        updateTabIndicator(animated: true)
        self.setNeedsLayout()
    }

    private func updateTabIndicator(animated: Bool) {
        self.setNeedsLayout()
        if animated {
            UIView.animate(withDuration: 0.25) {
                self.view.layoutIfNeeded()
            }
        }
    }

    override func layout() {
        super.layout()

        guard activeTabIndex < tabNodes.count else { return }
        let activeTab = tabNodes[activeTabIndex]
        let tabFrame = activeTab.frame
        let indicatorHeight: CGFloat = 3.sf
        let indicatorY = tabFrame.maxY + 4.sf

        tabIndicatorNode.frame = CGRect(
            x: tabFrame.origin.x,
            y: indicatorY,
            width: tabFrame.size.width,
            height: indicatorHeight
        )
    }

    @objc private func backPressed() { onClose() }
    @objc private func settingsPressed() { onSettingsTapped() }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        channelIconNode.style.preferredSize = CGSize(width: 16.sf, height: 16.sf)
        let headerContent = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8.sw,
            justifyContent: .start,
            alignItems: .center,
            children: [channelIconNode, titleNode]
        )
        headerContent.style.flexShrink = 1

        let centerSpec = ASCenterLayoutSpec(
            centeringOptions: .XY,
            child: headerContent
        )

        let leftSpec = ASRelativeLayoutSpec(
            horizontalPosition: .start,
            verticalPosition: .center,
            sizingOption: [],
            child: backButtonNode
        )

        let topBar = ASOverlayLayoutSpec(
            child: centerSpec,
            overlay: leftSpec
        )
        topBar.style.height = ASDimensionMake(56.sf)
        topBar.style.alignSelf = .stretch

        let tabsStack = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 24.sw,
            justifyContent: .start,
            alignItems: .center,
            children: tabNodes
        )

        let tabsWithIndicator = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8.sf,
            justifyContent: .start,
            alignItems: .start,
            children: [tabsStack]
        )

        let headerSection = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 20,
            justifyContent: .start,
            alignItems: .stretch,
            children: [topBar, actionButtonsNode, tabsWithIndicator]
        )
        headerSection.style.alignSelf = .stretch

        let activeTabNode: ASDisplayNode
        switch activeTabIndex {
        case 0: activeTabNode = membersListNode
        case 1: activeTabNode = mediaGalleryNode
        case 2: activeTabNode = fileListNode
        case 3: activeTabNode = pinnedMessagesNode
        case 4: activeTabNode = canvasNode
        default: activeTabNode = membersListNode
        }
        activeTabNode.style.flexGrow = 1
        activeTabNode.style.flexShrink = 1

        let mainStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 16,
            justifyContent: .start,
            alignItems: .stretch,
            children: [headerSection, activeTabNode]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 60.sf, left: 16.sw, bottom: 0, right: 16.sw), child: mainStack
        )
    }

    func applyTheme() {
        let t = UIColor.theme
        self.backgroundColor = t.primary
        titleNode.attributedText = NSAttributedString(
            string: channel.channelLabel,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .bold),
                .foregroundColor: t.textStrong,
            ]
        )
    }
}
