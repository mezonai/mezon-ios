import UIKit
import AsyncDisplayKit

enum DmAction: Hashable {
    case leaveOrDeleteGroup(isDelete: Bool)
    case closeDm
    case addFriend
    case removeFriend
    case blockUser
    case unblockUser
    case markAsRead
    case muteConversation
    case unmuteConversation

    var isDestructive: Bool {
        switch self {
        case .leaveOrDeleteGroup, .closeDm, .removeFriend, .blockUser:
            return true
        default:
            return false
        }
    }

    func title(isDeleteGroup: Bool = false) -> String {
        switch self {
        case .leaveOrDeleteGroup(let isDelete):
            return isDelete ? L(L10n.DmMenu.deleteGroup) : L(L10n.DmMenu.leaveGroup)
        case .closeDm: return L(L10n.DmMenu.closeDm)
        case .addFriend: return L(L10n.DmMenu.addFriend)
        case .removeFriend: return L(L10n.DmMenu.removeFriend)
        case .blockUser: return L(L10n.DmMenu.blockUser)
        case .unblockUser: return L(L10n.DmMenu.unblockUser)
        case .markAsRead: return L(L10n.ChannelAction.markAsRead)
        case .muteConversation: return L(L10n.DmMenu.muteConversation)
        case .unmuteConversation: return L(L10n.DmMenu.unmuteConversation)
        }
    }

    var iconName: String? {
        switch self {
        case .markAsRead: return "ChannelSetting/MarkAsRead"
        case .muteConversation: return "ChannelSetting/MuteChannel"
        case .unmuteConversation: return "ChannelSetting/UmuteChannelIcon"
        case .addFriend: return "Notifications/AddFriendIcon"
        case .removeFriend: return "ChannelSetting/DeleteIcon"
        case .blockUser: return "ChannelSetting/BanIcon"
        case .closeDm: return "Chat/MessageIcon"
        case .leaveOrDeleteGroup: return nil
        case .unblockUser: return nil
        }
    }
}

struct DmMenuContext {
    let channel: Mezon_Api_ChannelDescription
    let displayName: String
    let avatarURL: String
    let friend: Mezon_Api_Friend?
    let currentUserId: Int64
    let isMuted: Bool
    let groupMemberUserIds: [Int64]

    var isGroup: Bool {
        channel.type == MezonConstants.ChannelType.group.rawValue
    }

    var isChatWithMyself: Bool {
        guard channel.type == MezonConstants.ChannelType.dm.rawValue else { return false }
        guard let otherId = channel.userIds.first else { return false }
        return otherId == currentUserId
    }

    var peerUserId: Int64? {
        guard !isGroup else { return nil }
        return channel.userIds.first
    }

    var didIBlockUser: Bool {
        guard let friend, let peerId = peerUserId else { return false }
        return friend.state == EStateFriend.block.rawValue
            && friend.sourceID == currentUserId
            && friend.user.id == peerId
    }

    var isLastOneInGroup: Bool {
        groupMemberUserIds.count <= 1
    }

    func menuGroups() -> [[DmAction]] {
        var groups: [[DmAction]] = []

        if isGroup {
            groups.append([.leaveOrDeleteGroup(isDelete: isLastOneInGroup)])
        }

        var profileGroup: [DmAction] = []
        if !isGroup {
            profileGroup.append(.closeDm)
        }
        if shouldShowFriendAction {
            profileGroup.append(friend?.state == EStateFriend.friend.rawValue ? .removeFriend : .addFriend)
        }
        if shouldShowBlockAction {
            profileGroup.append(didIBlockUser ? .unblockUser : .blockUser)
        }
        if !profileGroup.isEmpty {
            groups.append(profileGroup)
        }

        if !isChatWithMyself {
            groups.append([.markAsRead])
        }

        if !isChatWithMyself {
            groups.append([isMuted ? .unmuteConversation : .muteConversation])
        }

        return groups
    }

    private var shouldShowFriendAction: Bool {
        guard !isGroup, !isChatWithMyself, let friend else { return !isGroup && !isChatWithMyself }
        switch friend.state {
        case EStateFriend.block.rawValue,
             EStateFriend.myPending.rawValue,
             EStateFriend.otherPending.rawValue:
            return false
        default:
            return true
        }
    }

    private var shouldShowBlockAction: Bool {
        guard !isGroup, !isChatWithMyself else { return false }
        if didIBlockUser { return true }
        return friend?.state == EStateFriend.friend.rawValue
    }

    static func isConversationMuted(record: NotificationSettingRecord?) -> Bool {
        guard let record else { return false }
        return record.timeMuteSeconds != 0
    }
}

private enum DmActionAssetCache {
    private static var originals: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func image(named name: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = originals[name] { return cached }
        guard let image = UIImage(named: name) else { return nil }
        originals[name] = image
        return image
    }
}

final class DmActionSheetController: ViewController {
    private let menuContext: DmMenuContext
    private let onAction: (DmAction) -> Void
    private var didRunEntranceAnimation = false

    init(menuContext: DmMenuContext, onAction: @escaping (DmAction) -> Void) {
        self.menuContext = menuContext
        self.onAction = onAction
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
        self.blocksBackgroundWhenInOverlay = true
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    private var actionSheetNode: DmActionSheetNode {
        displayNode as! DmActionSheetNode
    }

    override func loadDisplayNode() {
        displayNode = DmActionSheetNode(
            menuContext: menuContext,
            onAction: { [weak self] action in
                guard let self else { return }
                self.dismissThenCallAction(action)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        displayNodeDidLoad()
    }

    private func dismissThenCallAction(_ action: DmAction) {
        let callback = onAction
        actionSheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            DispatchQueue.main.async {
                callback(action)
            }
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        actionSheetNode.updateLayout(layout: layout, transition: transition)
        guard !didRunEntranceAnimation, layout.size.width > 1, layout.size.height > 1 else { return }
        didRunEntranceAnimation = true
        actionSheetNode.animateIn()
    }

    func animateIn() {
        actionSheetNode.animateIn()
    }

    private func dismiss() {
        actionSheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
        }
    }
}

private final class DmActionSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {
    private let dimNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let scrollNode = ASScrollNode()

    private let menuContext: DmMenuContext
    private var isMuted: Bool
    private let onAction: (DmAction) -> Void
    private let onDismiss: () -> Void

    private var panGesture: UIPanGestureRecognizer!
    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var didBuildContent = false

    init(
        menuContext: DmMenuContext,
        onAction: @escaping (DmAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.menuContext = menuContext
        self.isMuted = menuContext.isMuted
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init()

        dimNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimNode.alpha = 0
        addSubnode(dimNode)

        containerNode.backgroundColor = UIColor.theme.primary
        containerNode.cornerRadius = 24.swh
        addSubnode(containerNode)

        handleNode.backgroundColor = UIColor.theme.textDisabled
        handleNode.cornerRadius = 2.5
        containerNode.addSubnode(handleNode)

        scrollNode.automaticallyManagesSubnodes = false
        scrollNode.automaticallyManagesContentSize = false
        containerNode.addSubnode(scrollNode)
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDimTap))
        dimNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNotificationSettingUpdated(_:)),
            name: .mezonNotificationSettingDidUpdate,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleNotificationSettingUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let updatedChannelId = userInfo["channelId"] as? Int64,
              updatedChannelId == menuContext.channel.channelID,
              let record = userInfo["record"] as? NotificationSettingRecord else { return }

        let newIsMuted = record.timeMuteSeconds != 0
        guard isMuted != newIsMuted else { return }
        isMuted = newIsMuted
        rebuildContent()
    }

    private func rebuildContent() {
        scrollNode.view.subviews.forEach { $0.removeFromSuperview() }
        containerNode.view.subviews.filter { $0.tag == 9001 }.forEach { $0.removeFromSuperview() }
        didBuildContent = false
        if let layout = validLayout {
            updateLayout(layout: layout, transition: .immediate)
        }
    }

    @objc private func handleDimTap() { onDismiss() }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        dimNode.frame = CGRect(origin: .zero, size: layout.size)

        let contentW = layout.size.width
        let safeBottom = layout.intrinsicInsets.bottom

        let groups = menuContext.menuGroups()
        var groupsH: CGFloat = 0
        for group in groups {
            groupsH += CGFloat(group.count) * 48.sh + 12.sh
        }
        let totalContentH = 48.swh + 16.sh + 24.sh + groupsH + safeBottom
        let maxContainerH = layout.size.height * 0.9
        containerHeight = min(totalContentH + 40.sh, maxContainerH)

        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: contentW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (contentW - 40.sw) / 2, y: 8.sh, width: 40.sw, height: 5.sh))

        let scrollY: CGFloat = 8.sh + 5.sh + 16.sh + 48.swh + 24.sh
        let scrollH = max(0, containerHeight - scrollY - safeBottom)
        scrollNode.frame = CGRect(x: 0, y: scrollY, width: contentW, height: scrollH)
        scrollNode.view.contentSize = CGSize(width: contentW, height: groupsH + 16.sh)

        if !didBuildContent {
            didBuildContent = true
            buildContent(width: contentW, safeBottom: safeBottom)
        }
    }

    private func buildContent(width: CGFloat, safeBottom: CGFloat) {
        let header = buildHeader(width: width)
        header.tag = 9001
        header.frame = CGRect(x: 16.sw, y: 24.sh, width: width - 32.sw, height: 56.swh)
        containerNode.view.addSubview(header)

        let groups = menuContext.menuGroups()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12.sh
        stack.frame = CGRect(x: 16.sw, y: 0, width: width - 32.sw, height: 0)
        scrollNode.view.addSubview(stack)

        for group in groups {
            let groupView = buildGroup(actions: group, width: width - 32.sw)
            stack.addArrangedSubview(groupView)
        }

        stack.layoutIfNeeded()
        let stackH = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        stack.frame.size.height = stackH
        scrollNode.view.contentSize = CGSize(width: width, height: stackH + 20.sh)
    }

    private func buildHeader(width: CGFloat) -> UIView {
        let v = UIView()
        let avatarSize: CGFloat = 56.swh
        let avatar = TextAvatarView(username: menuContext.displayName, size: avatarSize, fontSize: 18.sf)
        avatar.frame = CGRect(x: 0, y: 0, width: avatarSize, height: avatarSize)
        avatar.layer.cornerRadius = menuContext.isGroup ? 12.swh : avatarSize / 2
        v.addSubview(avatar)

        let avatarImageView = UIImageView(frame: avatar.bounds)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatar.addSubview(avatarImageView)

        if menuContext.isGroup,
           menuContext.avatarURL.isEmpty || menuContext.avatarURL.contains("avatar-group.png") {
            avatar.showImageMode()
            avatar.backgroundColor = .groupDMDefaultAvatar
            let groupIcon = UIImageView(image: UIImage(systemName: "person.2.fill"))
            groupIcon.tintColor = .white
            groupIcon.contentMode = .scaleAspectFit
            groupIcon.frame = CGRect(x: (avatarSize - 24) / 2, y: (avatarSize - 24) / 2, width: 24, height: 24)
            avatar.addSubview(groupIcon)
        } else if !menuContext.avatarURL.isEmpty {
            avatar.showImageMode()
            ImageCache.shared.loadImage(
                urlString: ImgproxyURL.create(from: menuContext.avatarURL, width: 150, height: 150)
            ) { [weak avatarImageView, weak avatar] image in
                if let image {
                    avatarImageView?.image = image
                } else {
                    avatar?.showPlaceholder()
                }
            }
        }

        let textX = avatarSize + 12.sw
        let textW = max(0, width - 32.sw - textX)

        if menuContext.isGroup, menuContext.channel.memberCount > 0 {
            let nameLabel = UILabel(frame: CGRect(x: textX, y: 8.sh, width: textW, height: 22.sh))
            nameLabel.text = menuContext.displayName
            nameLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
            nameLabel.textColor = UIColor.theme.textStrong
            nameLabel.numberOfLines = 2
            v.addSubview(nameLabel)

            let memberLabel = UILabel(frame: CGRect(x: textX, y: 32.sh, width: textW, height: 18.sh))
            memberLabel.text = L(L10n.DmMenu.members, Int(menuContext.channel.memberCount))
            memberLabel.font = .systemFont(ofSize: 13.sf)
            memberLabel.textColor = UIColor.theme.textDisabled
            v.addSubview(memberLabel)
        } else {
            let nameLabel = UILabel(frame: CGRect(x: textX, y: (avatarSize - 24.sh) / 2, width: textW, height: 24.sh))
            nameLabel.text = menuContext.displayName
            nameLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
            nameLabel.textColor = UIColor.theme.textStrong
            nameLabel.numberOfLines = 2
            v.addSubview(nameLabel)
        }

        return v
    }

    private func buildGroup(actions: [DmAction], width: CGFloat) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.theme.secondary
        v.layer.cornerRadius = 12

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        v.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])

        for (idx, action) in actions.enumerated() {
            let row = buildActionRow(action: action)
            stack.addArrangedSubview(row)
            if idx < actions.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.border
                stack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            }
        }
        return v
    }

    private func buildActionRow(action: DmAction) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        if let iconName = action.iconName, let base = DmActionAssetCache.image(named: iconName) {
            if action.isDestructive {
                icon.image = base.withRenderingMode(.alwaysTemplate)
                icon.tintColor = .mezonError
            } else {
                icon.image = base.withRenderingMode(.alwaysOriginal)
            }
        } else if action == .unblockUser {
            icon.image = UIImage(systemName: "hand.raised.slash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf))
            icon.tintColor = UIColor.theme.textStrong
        } else if case .leaveOrDeleteGroup = action {
            icon.image = UIImage(systemName: "rectangle.portrait.and.arrow.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.sf))
            icon.tintColor = .mezonError
        }
        v.addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16.sw),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24.swh),
            icon.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        let label = UILabel()
        if case .leaveOrDeleteGroup(let isDelete) = action {
            label.text = action.title(isDeleteGroup: isDelete)
        } else {
            label.text = action.title()
        }
        label.font = .systemFont(ofSize: 14.sf, weight: .medium)
        label.textColor = action.isDestructive ? .mezonError : UIColor.theme.textStrong
        v.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12.sw),
            label.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16.sw),
        ])

        v.heightAnchor.constraint(equalToConstant: 56.sh).isActive = true
        let wrapper = DmActionButton(type: .custom)
        wrapper.actionHandler = { [weak self] in self?.onAction(action) }
        wrapper.addTarget(wrapper, action: #selector(DmActionButton.performAction), for: .touchUpInside)
        v.addSubview(wrapper)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrapper.topAnchor.constraint(equalTo: v.topAnchor),
            wrapper.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            wrapper.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        return v
    }

    func animateIn() {
        guard let layout = validLayout else { return }
        let toY = layout.size.height - containerHeight
        containerNode.frame.origin.y = layout.size.height
        dimNode.alpha = 0
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut) {
            self.containerNode.frame.origin.y = toY
            self.dimNode.alpha = 1
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else {
            completion()
            return
        }
        UIView.animate(withDuration: 0.2, animations: {
            self.containerNode.frame.origin.y = layout.size.height
            self.dimNode.alpha = 0
        }) { _ in
            completion()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                containerNode.frame.origin.y = (layout.size.height - containerHeight) + translation.y
                dimNode.alpha = 1 - (translation.y / containerHeight)
            }
        case .ended:
            if translation.y > 100 {
                onDismiss()
            } else {
                UIView.animate(withDuration: 0.3) {
                    self.containerNode.frame.origin.y = layout.size.height - self.containerHeight
                    self.dimNode.alpha = 1
                }
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let vel = gesture.velocity(in: view)
        return vel.y > 0 && scrollNode.view.contentOffset.y <= 0
    }
}

private final class DmActionButton: UIButton {
    var actionHandler: (() -> Void)?
    @objc func performAction() { actionHandler?() }
}
