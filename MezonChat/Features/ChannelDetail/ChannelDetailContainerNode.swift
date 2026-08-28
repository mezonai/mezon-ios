import AsyncDisplayKit
import UIKit

@MainActor
final class ChannelDetailContainerNode: ASDisplayNode {

    private enum AssetTab: Int {
        case members, media, files, pins, canvas
    }

    private let context: AccountContext
    private let clanId: Int64
    private var channel: Mezon_Api_ChannelDescription
    private let onClose: () -> Void
    private let onSettingsTapped: () -> Void
    private let onSearchTapped: () -> Void
    private let onThreadsTapped: () -> Void
    private let onMuteTapped: () -> Void
    private let onGroupOptionsTapped: () -> Void

    private let backButtonNode = ASButtonNode()
    private let moreButtonNode = ASButtonNode()
    private let headerTrailingSpacerNode = ASDisplayNode()
    private let titleNode = ASTextNode2()
    private let channelIconNode = ASImageNode()
    private let groupAvatarNode = ASNetworkImageNode()

    private let actionButtonsNode: ChannelDetailActionButtonsNode

    private let visibleTabs: [AssetTab]
    private var tabTitleNodes: [ASTextNode2] = []
    private var tabUnderlineNodes: [ASDisplayNode] = []
    private let tabsScrollNode = ASScrollNode()

    private let membersListNode: MemberListNode
    private let mediaGalleryNode: MediaGalleryNode
    private let fileListNode: FileListNode
    private let pinnedMessagesNode: PinnedMessagesNode
    private let canvasNode: CanvasNode

    private var activeTabIndex: Int = 0

    init(
        context: AccountContext, clanId: Int64, channel: Mezon_Api_ChannelDescription,
        onClose: @escaping () -> Void, onSettingsTapped: @escaping () -> Void,
        onSearchTapped: @escaping () -> Void, onThreadsTapped: @escaping () -> Void,
        onMuteTapped: @escaping () -> Void, onGroupOptionsTapped: @escaping () -> Void
    ) {
        self.context = context
        self.clanId = clanId
        self.channel = channel
        self.onClose = onClose
        self.onSettingsTapped = onSettingsTapped
        self.onSearchTapped = onSearchTapped
        self.onThreadsTapped = onThreadsTapped
        self.onMuteTapped = onMuteTapped
        self.onGroupOptionsTapped = onGroupOptionsTapped

        let myId = context.currentUser.flatMap { Int64($0.id) }
        self.visibleTabs = Self.visibleTabsList(channel: channel, currentUserId: myId)

        self.actionButtonsNode = ChannelDetailActionButtonsNode(
            channel: channel, context: context)
        self.membersListNode = MemberListNode(
            context: context, clanId: clanId, channelId: channel.channelID,
            channelDescription: channel)
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

        tabsScrollNode.scrollableDirections = [.left, .right]
        tabsScrollNode.automaticallyManagesContentSize = true
        tabsScrollNode.automaticallyManagesSubnodes = true

        setupHeader()
        buildTabs()
        actionButtonsNode.onSettingsTapped = { [weak self] in
            self?.settingsPressed()
        }
        actionButtonsNode.onSearchTapped = { [weak self] in
            self?.onSearchTapped()
        }
        actionButtonsNode.onThreadsTapped = { [weak self] in
            self?.onThreadsTapped()
        }
        actionButtonsNode.onMuteTapped = { [weak self] in
            self?.onMuteTapped()
        }

        loadDataForTab(at: 0)
    }

    override func didLoad() {
        super.didLoad()
        tabsScrollNode.view.showsHorizontalScrollIndicator = false
    }

    private static func visibleTabsList(
        channel: Mezon_Api_ChannelDescription, currentUserId: Int64?
    ) -> [AssetTab] {
        let dm = MezonConstants.ChannelType.dm.rawValue
        let group = MezonConstants.ChannelType.group.rawValue
        let isDMOrGroup = channel.type == dm || channel.type == group
        let isSelfDM = channel.type == dm && channel.userIds.first == currentUserId
        let isOneToOneDM =
            channel.type == dm && !isSelfDM && channel.userIds.count <= 2

        if isSelfDM {
            return [.media, .files, .pins]
        }
        if isOneToOneDM {
            return [.media, .files, .pins]
        }
        if !isDMOrGroup {
            return [.members, .media, .files, .pins, .canvas]
        }
        return [.members, .media, .files, .pins]
    }

    private func title(for tab: AssetTab) -> String {
        switch tab {
        case .members: return L(L10n.ChannelDetail.members)
        case .media: return L(L10n.ChannelDetail.media)
        case .files: return L(L10n.ChannelDetail.files)
        case .pins: return L(L10n.ChannelDetail.pins)
        case .canvas: return L(L10n.ChannelDetail.canvas)
        }
    }

    private func setupHeader() {
        backButtonNode.setImage(
            UIImage(systemName: "chevron.left")?.withTintColor(
                UIColor.theme.textStrong, renderingMode: .alwaysOriginal), for: .normal)
        backButtonNode.addTarget(
            self, action: #selector(backPressed), forControlEvents: .touchUpInside)
        backButtonNode.style.preferredSize = CGSize(width: 44.sf, height: 44.sf)
        backButtonNode.contentHorizontalAlignment = .middle
        backButtonNode.contentVerticalAlignment = .center

        moreButtonNode.setImage(
            UIImage(systemName: "ellipsis")?.withTintColor(
                UIColor.theme.textStrong, renderingMode: .alwaysOriginal), for: .normal)
        moreButtonNode.addTarget(
            self, action: #selector(groupOptionsPressed), forControlEvents: .touchUpInside)
        moreButtonNode.style.preferredSize = CGSize(width: 52.sf, height: 44.sf)
        moreButtonNode.contentHorizontalAlignment = .middle
        moreButtonNode.contentVerticalAlignment = .center

        configureChannelHeaderVisuals()
        titleNode.maximumNumberOfLines = 1
        titleNode.truncationMode = .byTruncatingTail
        titleNode.style.flexShrink = 1

        groupAvatarNode.cornerRadius = 14.sf
        groupAvatarNode.clipsToBounds = true
        groupAvatarNode.contentMode = .scaleAspectFill

        headerTrailingSpacerNode.style.preferredSize = CGSize(width: 52.sf, height: 44.sf)
        headerTrailingSpacerNode.isUserInteractionEnabled = false
        headerTrailingSpacerNode.backgroundColor = .clear
    }

    private func configureChannelHeaderVisuals() {
        let title = channel.channelLabel
        let isDmOrGroup = channel.type == MezonConstants.ChannelType.dm.rawValue
            || channel.type == MezonConstants.ChannelType.group.rawValue

        if isDmOrGroup {
            channelIconNode.isHidden = true
        } else {
            let iconName = channel.channelListIconAssetName()
            channelIconNode.image = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate)
            channelIconNode.tintColor = UIColor.theme.textStrong
            channelIconNode.isHidden = false
        }

        if let avatarURL = resolvedGroupDMAvatarURL() {
            groupAvatarNode.url = avatarURL
            groupAvatarNode.isHidden = false
        } else {
            groupAvatarNode.url = nil
            groupAvatarNode.isHidden = true
        }

        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .bold),
                .foregroundColor: UIColor.theme.textStrong,
            ]
        )
    }

    private func resolvedGroupDMAvatarURL() -> URL? {
        guard isGroupDirectMessage else { return nil }
        let raw = channel.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains("avatar-group.png") else { return nil }

        let absolute: String
        if let url = URL(string: raw), url.scheme != nil {
            absolute = raw
        } else if raw.hasPrefix("//") {
            absolute = "https:\(raw)"
        } else {
            let base = MezonConfig.baseImgURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            absolute = raw.hasPrefix("/") ? "\(base)\(raw)" : "\(base)/\(raw)"
        }

        let proxied = ImgproxyURL.avatarProxyURL(from: absolute, width: 180, height: 180)
        return URL(string: proxied)
    }

    func applyUpdatedChannel(_ updated: Mezon_Api_ChannelDescription) {
        guard updated.channelID == channel.channelID else { return }
        channel = updated
        configureChannelHeaderVisuals()
        actionButtonsNode.applyUpdatedChannel(updated)
        setNeedsLayout()
    }

    func updateMuteButtonState() {
        actionButtonsNode.updateMuteButtonState()
    }

    private func buildTabs() {
        tabTitleNodes = []
        tabUnderlineNodes = []
        for (index, tab) in visibleTabs.enumerated() {
            let textNode = ASTextNode2()
            textNode.isUserInteractionEnabled = true
            textNode.view.tag = index
            textNode.view.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(tabPressed(_:))))

            let underline = ASDisplayNode()
            underline.style.height = ASDimension(unit: .points, value: 2)
            underline.cornerRadius = 1

            tabTitleNodes.append(textNode)
            tabUnderlineNodes.append(underline)
            updateTabAppearance(index: index, title: title(for: tab))
        }
    }

    private func updateTabAppearance(index: Int, title: String) {
        guard index < tabTitleNodes.count, index < tabUnderlineNodes.count else { return }
        let isActive = index == activeTabIndex
        let t = UIColor.theme
        let activeColor = t.bgViolet
        let inactiveColor = t.text
        tabTitleNodes[index].attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: isActive ? .semibold : .medium),
                .foregroundColor: isActive ? activeColor : inactiveColor,
            ]
        )
        tabUnderlineNodes[index].backgroundColor = isActive ? activeColor : .clear
    }

    @objc private func tabPressed(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, index >= 0, index < visibleTabs.count else { return }
        activeTabIndex = index
        loadDataForTab(at: index)
        for i in 0..<visibleTabs.count {
            updateTabAppearance(index: i, title: title(for: visibleTabs[i]))
        }
        self.setNeedsLayout()
    }

    private func loadDataForTab(at index: Int) {
        guard index >= 0, index < visibleTabs.count else { return }
        switch visibleTabs[index] {
        case .members: membersListNode.loadTabDataIfNeeded()
        case .media: mediaGalleryNode.loadTabDataIfNeeded()
        case .files: fileListNode.loadTabDataIfNeeded()
        case .pins: pinnedMessagesNode.loadTabDataIfNeeded()
        case .canvas: canvasNode.loadTabDataIfNeeded()
        }
    }

    @objc private func backPressed() { onClose() }
    @objc private func settingsPressed() { onSettingsTapped() }
    @objc private func groupOptionsPressed() { onGroupOptionsTapped() }

    private var isGroupDirectMessage: Bool {
        clanId == 0 && channel.type == MezonConstants.ChannelType.group.rawValue
    }

    private func activeContentNode() -> ASDisplayNode {
        guard activeTabIndex < visibleTabs.count else { return membersListNode }
        switch visibleTabs[activeTabIndex] {
        case .members: return membersListNode
        case .media: return mediaGalleryNode
        case .files: return fileListNode
        case .pins: return pinnedMessagesNode
        case .canvas: return canvasNode
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        channelIconNode.style.preferredSize = CGSize(width: 16.sf, height: 16.sf)
        let showsGroupAvatar = resolvedGroupDMAvatarURL() != nil
        groupAvatarNode.style.preferredSize = CGSize(width: 28.sf, height: 28.sf)
        let headerContentChildren: [ASLayoutElement] = showsGroupAvatar
            ? [groupAvatarNode, titleNode]
            : [channelIconNode, titleNode]
        let headerContent = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 8.sw,
            justifyContent: .start,
            alignItems: .center,
            children: headerContentChildren
        )
        let headerHorizontalControlsWidth = 44.sf + 52.sf
        let headerTitlePadding: CGFloat = 20.sw + (showsGroupAvatar ? 36.sf : 0)
        let maxHeaderContentWidth = max(
            0,
            constrainedSize.max.width - 32.sw - headerHorizontalControlsWidth - headerTitlePadding
        )
        titleNode.style.maxWidth = ASDimension(unit: .points, value: maxHeaderContentWidth)
        headerContent.style.flexShrink = 1

        let titleCentered = ASCenterLayoutSpec(
            centeringOptions: .XY,
            child: headerContent
        )
        titleCentered.style.flexGrow = 1
        titleCentered.style.flexShrink = 1

        let topBar = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 0,
            justifyContent: .start,
            alignItems: .center,
            children: [backButtonNode, titleCentered, isGroupDirectMessage ? moreButtonNode : headerTrailingSpacerNode]
        )
        topBar.style.height = ASDimensionMake(56.sf)
        topBar.style.alignSelf = .stretch

        var tabColumns: [ASLayoutElement] = []
        for i in 0..<visibleTabs.count {
            let col = ASStackLayoutSpec(
                direction: .vertical,
                spacing: 5.sf,
                justifyContent: .start,
                alignItems: .stretch,
                children: [tabTitleNodes[i], tabUnderlineNodes[i]]
            )
            let padded = ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 0, left: 10.sw, bottom: 0, right: 10.sw),
                child: col
            )
            tabColumns.append(padded)
        }

        let tabsRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 0,
            justifyContent: .start,
            alignItems: .start,
            children: tabColumns
        )

        tabsScrollNode.layoutSpecBlock = { _, _ in tabsRow }
        tabsScrollNode.style.minHeight = ASDimension(unit: .points, value: 30.sf)

        let tabsHeader = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 20.sf, left: 0, bottom: 0, right: 0),
            child: tabsScrollNode
        )
        tabsHeader.style.alignSelf = .stretch

        var headerChildren: [ASLayoutElement] = [topBar]
        headerChildren.append(actionButtonsNode)
        headerChildren.append(tabsHeader)

        let headerSection = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: headerChildren
        )
        headerSection.style.alignSelf = .stretch

        let activeTabNode = activeContentNode()
        activeTabNode.style.flexGrow = 1
        activeTabNode.style.flexShrink = 1

        let mainStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
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
        configureChannelHeaderVisuals()
        backButtonNode.setImage(
            UIImage(systemName: "chevron.left")?.withTintColor(
                t.textStrong, renderingMode: .alwaysOriginal), for: .normal)
        moreButtonNode.setImage(
            UIImage(systemName: "ellipsis")?.withTintColor(
                t.textStrong, renderingMode: .alwaysOriginal), for: .normal)
        for i in 0..<visibleTabs.count {
            updateTabAppearance(index: i, title: title(for: visibleTabs[i]))
        }
        actionButtonsNode.applyTheme()
        pinnedMessagesNode.applyTheme()
    }
}
