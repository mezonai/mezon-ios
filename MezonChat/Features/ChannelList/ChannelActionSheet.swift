import UIKit
import AsyncDisplayKit

enum ChannelAction: CaseIterable {
    case markAsRead
    case markFavorite
    case unmarkFavorite
    case copyLink
    case mute
    case unmute
    case notificationSettings
    case threads
    case editChannel
    case deleteChannel
    case leaveThread

    var title: String {
        switch self {
        case .markAsRead: return L(L10n.ChannelAction.markAsRead)
        case .markFavorite: return L(L10n.ChannelAction.markFavorite)
        case .unmarkFavorite: return L(L10n.ChannelAction.unmarkFavorite)
        case .copyLink: return L(L10n.ChannelAction.copyLink)
        case .mute: return L(L10n.ChannelAction.mute)
        case .unmute: return L(L10n.ChannelAction.unmute)
        case .notificationSettings: return L(L10n.ChannelAction.notificationSettings)
        case .threads: return L(L10n.Channel.thread)
        case .editChannel: return L(L10n.ChannelAction.editChannel)
        case .deleteChannel: return L(L10n.Channel.delete)
        case .leaveThread: return L(L10n.ChannelAction.leaveThread)
        }
    }

    var icon: String? {
        switch self {
        case .markAsRead: return "ChannelSetting/MarkAsRead"
        case .markFavorite, .unmarkFavorite: return "ChannelSetting/Favorite"
        case .copyLink: return "ClanSetting/Invite"
        case .mute: return "ChannelSetting/MuteChannel"
        case .unmute: return "ChannelSetting/UmuteChannelIcon"
        case .notificationSettings: return "ChannelSetting/NotificationSettings"
        case .threads: return "Channel/channelThread"
        case .editChannel: return "Profile/SettingIcon"
        case .deleteChannel: return "ChannelSetting/DeleteIcon"
        case .leaveThread: return "ChannelSetting/DeleteIcon" 
        }
    }

    var isDestructive: Bool {
        self == .deleteChannel || self == .leaveThread
    }
}

final class ChannelActionSheetController: ViewController {
    private let channelId: Int64
    private let channelName: String
    private let clanName: String
    private let clanAvatarURL: String
    private let isFavorite: Bool
    private let isMuted: Bool
    private let isThread: Bool
    private let channelType: Int32
    private let canManageChannel: Bool
    private let isGeneralChannel: Bool
    private let onAction: (ChannelAction) -> Void

    init(
        channelId: Int64,
        channelName: String,
        clanName: String,
        clanAvatarURL: String,
        isFavorite: Bool = false,
        isMuted: Bool = false,
        isThread: Bool = false,
        channelType: Int32,
        canManageChannel: Bool = false,
        isGeneralChannel: Bool = false,
        onAction: @escaping (ChannelAction) -> Void
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.clanName = clanName
        self.clanAvatarURL = clanAvatarURL
        self.isFavorite = isFavorite
        self.isMuted = isMuted
        self.isThread = isThread
        self.channelType = channelType
        self.canManageChannel = canManageChannel
        self.isGeneralChannel = isGeneralChannel
        self.onAction = onAction
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    private var actionSheetNode: ChannelActionSheetNode {
        return displayNode as! ChannelActionSheetNode
    }

    override func loadDisplayNode() {
        displayNode = ChannelActionSheetNode(
            channelId: channelId,
            channelName: channelName,
            clanName: clanName,
            clanAvatarURL: clanAvatarURL,
            isFavorite: isFavorite,
            isMuted: isMuted,
            isThread: isThread,
            channelType: channelType,
            canManageChannel: canManageChannel,
            isGeneralChannel: isGeneralChannel,
            onAction: { [weak self] action in
                guard let self else { return }
                switch action {
                case .copyLink:
                    self.onAction(action)
                    self.dismiss()
                default:
                    self.dismissThenCallAction(action)
                }
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )
        self.displayNodeDidLoad()
    }

    private func dismissThenCallAction(_ action: ChannelAction) {
        let callback = self.onAction
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

private final class ChannelActionSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {
    private let dimNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let scrollNode = ASScrollNode()

    private let channelId: Int64
    private let channelName: String
    private let clanName: String
    private let clanAvatarURL: String
    private let isFavorite: Bool
    private var isMuted: Bool
    private let isThread: Bool
    private let channelType: Int32
    private let canManageChannel: Bool
    private let isGeneralChannel: Bool
    private let onAction: (ChannelAction) -> Void
    private let onDismiss: () -> Void

    private var panGesture: UIPanGestureRecognizer!
    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private var didBuildContent = false

    init(
        channelId: Int64,
        channelName: String,
        clanName: String,
        clanAvatarURL: String,
        isFavorite: Bool,
        isMuted: Bool,
        isThread: Bool,
        channelType: Int32,
        canManageChannel: Bool,
        isGeneralChannel: Bool,
        onAction: @escaping (ChannelAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.clanName = clanName
        self.clanAvatarURL = clanAvatarURL
        self.isFavorite = isFavorite
        self.isMuted = isMuted
        self.isThread = isThread
        self.channelType = channelType
        self.canManageChannel = canManageChannel
        self.isGeneralChannel = isGeneralChannel
        self.onAction = onAction
        self.onDismiss = onDismiss
        super.init()

        dimNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        dimNode.alpha = 0
        addSubnode(dimNode)

        containerNode.backgroundColor = UIColor.theme.primary
        containerNode.cornerRadius = 24.swh
        addSubnode(containerNode)

        handleNode.backgroundColor = UIColor.theme.textDisabled.withAlphaComponent(0.3)
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleNotificationSettingUpdated(_:)), name: Notification.Name("NotificationSettingDidUpdate"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleNotificationSettingUpdated(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let updatedChannelId = userInfo["channelId"] as? Int64,
              updatedChannelId == self.channelId,
              let record = userInfo["record"] as? NotificationSettingRecord else { return }
        
        let timeMute = record.timeMuteSeconds
        let newIsMuted = timeMute != 0
        
        if self.isMuted != newIsMuted {
            self.isMuted = newIsMuted
            
            self.scrollNode.view.subviews.forEach { $0.removeFromSuperview() }
            self.didBuildContent = false
            if let layout = self.validLayout {
                self.updateLayout(layout: layout, transition: .immediate)
            }
        }
    }

    @objc private func handleDimTap() { onDismiss() }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        dimNode.frame = CGRect(origin: .zero, size: layout.size)

        let contentW = layout.size.width
        let safeBottom = layout.intrinsicInsets.bottom

        let groups = getGroups()
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
        let scrollH = containerHeight - scrollY - safeBottom
        scrollNode.frame = CGRect(x: 0, y: scrollY, width: contentW, height: scrollH)
        scrollNode.view.contentSize = CGSize(width: contentW, height: groupsH + 16.sh)

        if !didBuildContent {
            didBuildContent = true
            buildContent(width: contentW, safeBottom: safeBottom)
        }
    }

    private func buildContent(width: CGFloat, safeBottom: CGFloat) {
        let header = buildHeader(width: width)
        header.frame = CGRect(x: 16.sw, y: 24.sh, width: width - 32.sw, height: 56.swh)
        containerNode.view.addSubview(header)

        let groups = getGroups()

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

    private func getGroups() -> [[ChannelAction]] {
        var groups: [[ChannelAction]] = []
        
        let type = MezonConstants.ChannelType(rawValue: channelType)
        let shouldHideMarkAsRead = (type == .mezonVoice || type == .streaming)
        let shouldHideThreads = (type == .app || type == .mezonVoice || type == .streaming || isThread)
        
        if !shouldHideMarkAsRead {
            groups.append([.markAsRead])
        }
        
        var secondGroup: [ChannelAction] = []
        if !isThread {
            secondGroup.append(isFavorite ? .unmarkFavorite : .markFavorite)
        }
        secondGroup.append(.copyLink)
        groups.append(secondGroup)
        
        groups.append([isMuted ? .unmute : .mute, .notificationSettings])
        
        if !shouldHideThreads {
            groups.append([.threads])
        }
        
        if canManageChannel {
            if isGeneralChannel {
                groups.append([.editChannel])
            } else {
                groups.append([.editChannel, .deleteChannel])
            }
        } else if isThread {
            groups.append([.leaveThread])
        }
        return groups
    }

    private func buildHeader(width: CGFloat) -> UIView {
        let v = UIView()
        let avatarSize: CGFloat = 56.swh
        let avatar = UIView(frame: CGRect(x: 0, y: 0, width: avatarSize, height: avatarSize))
        avatar.backgroundColor = colorFor(name: clanName)
        avatar.layer.cornerRadius = 12.swh
        avatar.clipsToBounds = true
        v.addSubview(avatar)

        let initial = UILabel(frame: avatar.bounds)
        initial.text = initials(for: clanName)
        initial.font = .systemFont(ofSize: 18.sf, weight: .bold)
        initial.textColor = .white
        initial.textAlignment = .center
        avatar.addSubview(initial)

        let avatarImageView = UIImageView(frame: avatar.bounds)
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatar.addSubview(avatarImageView)

        if !clanAvatarURL.isEmpty {
            ImageCache.shared.loadImage(urlString: ImgproxyURL.create(from: clanAvatarURL, width: 150, height: 150)) { [weak avatarImageView, weak initial] image in
                if let image = image {
                    avatarImageView?.image = image
                    initial?.isHidden = true
                }
            }
        }

        let nameLabel = UILabel(frame: CGRect(x: avatarSize + 12.sw, y: (avatarSize - 24.sh) / 2, width: width - 32.sw - avatarSize - 12.sw, height: 24.sh))
        nameLabel.text = channelName
        nameLabel.font = .systemFont(ofSize: 18.sf, weight: .bold)
        nameLabel.textColor = UIColor.theme.textStrong
        v.addSubview(nameLabel)

        return v
    }

    private func buildGroup(actions: [ChannelAction], width: CGFloat) -> UIView {
        let v = UIView()
        v.backgroundColor = .mezonBorder
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
                sep.backgroundColor = .mezonTertiary
                stack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            }
        }
        return v
    }

    private func buildActionRow(action: ChannelAction) -> UIView {
        let v = UIButton(type: .system)
        v.backgroundColor = .clear

        let icon = UIImageView()
        if let iconName = action.icon {
            guard let base = UIImage(named: iconName) else { return v }
            if action.isDestructive {
                icon.image = base.withRenderingMode(.alwaysTemplate)
                icon.tintColor = .mezonError
            } else {
                icon.image = base.withRenderingMode(.alwaysOriginal)
                icon.tintColor = nil
            }
        }
        icon.contentMode = .scaleAspectFit
        v.addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16.sw),
            icon.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24.swh),
            icon.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        let l = UILabel()
        
        var actionTitle = action.title
        if isThread {
            if action == .editChannel {
                actionTitle = L(L10n.ChannelAction.editThread)
            } else if action == .deleteChannel {
                actionTitle = L(L10n.ChannelAction.deleteThread)
            } else if action == .mute {
                actionTitle = L(L10n.ChannelAction.muteThread)
            } else if action == .unmute {
                actionTitle = L(L10n.ChannelAction.unmuteThread)
            }
        }
        l.text = actionTitle
        
        l.font = .systemFont(ofSize: 14.sf, weight: .medium)
        l.textColor = action.isDestructive ? .mezonError : UIColor.theme.textStrong
        v.addSubview(l)
        l.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12.sw),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            l.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16.sw),
        ])

        v.heightAnchor.constraint(equalToConstant: 56.sh).isActive = true
        let wrapper = ChannelActionButton(type: .custom)
        wrapper.actionHandler = { [weak self] in self?.onAction(action) }
        wrapper.addTarget(wrapper, action: #selector(ChannelActionButton.performAction), for: .touchUpInside)
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
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
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
        case .began: break
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
        default: break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gesture = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let vel = gesture.velocity(in: view)
        return vel.y > 0 && scrollNode.view.contentOffset.y <= 0
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        if words.count > 1 {
            return words.compactMap { $0.first }.map { String($0).uppercased() }.joined()
        } else {
            return String(name.prefix(1)).uppercased()
        }
    }

    private func colorFor(name: String) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.36, green: 0.36, blue: 0.82, alpha: 1),
            UIColor(red: 0.23, green: 0.56, blue: 0.42, alpha: 1),
            UIColor(red: 0.72, green: 0.26, blue: 0.26, alpha: 1),
            UIColor(red: 0.75, green: 0.52, blue: 0.18, alpha: 1),
            UIColor(red: 0.32, green: 0.52, blue: 0.78, alpha: 1),
            UIColor(red: 0.55, green: 0.28, blue: 0.68, alpha: 1),
        ]
        let hash = abs(name.hashValue)
        return colors[hash % colors.count]
    }
}

private final class ChannelActionButton: UIButton {
    var actionHandler: (() -> Void)?
    @objc func performAction() { actionHandler?() }
}
