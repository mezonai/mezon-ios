import UIKit
import WebRTC

@available(iOS 13.0, *)
final class StreamingRoomViewController: ViewController {

    let streamChannelId: Int64

    private let context: AccountContext
    private var channel: Mezon_Api_ChannelDescription
    private let parentChannelName: String?
    private let existingPiPOverlay: StreamingPiPOverlay?
    private var isMinimizingToPiP = false
    private var presenceObserver: NSObjectProtocol?
    private var channelDescriptionObserver: NSObjectProtocol?
    private var cachedAvatarURL: String?
    private var backgroundLoadToken = 0
    private var isLoadingBackground = false
    private var didFetchRemoteChannel = false

    private let videoView = PeerCallVideoRenderView()
    private let backgroundImageView = UIImageView()
    private let streamBannerView = UIImageView()
    private let placeholderView = UIImageView()
    private let statusLabel = UILabel()
    private let membersContainer = UIView()
    private let membersOverflowLabel = UILabel()
    private let headerBar = UIView()
    private let bottomChrome = UIView()
    private let headerRow = UIStackView()
    private let footerRow = UIStackView()
    private let minimizeButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let chatButton = UIButton(type: .custom)
    private let leaveButton = UIButton(type: .custom)
    private var bottomChromeBottomConstraint: NSLayoutConstraint?
    private var membersBottomConstraint: NSLayoutConstraint?

    private static let streamBannerSize: CGFloat = 240
    private static let bottomChromeHeight: CGFloat = 50
    private static let membersBottomOffset: CGFloat = 88

    private static let memberAvatarSize: CGFloat = 40
    private static let memberOverlap: CGFloat = 10
    private static let maxVisibleMembers = 5

    init(
        context: AccountContext,
        channel: Mezon_Api_ChannelDescription,
        parentChannelName: String?,
        existingPiPOverlay: StreamingPiPOverlay? = nil
    ) {
        self.context = context
        self.channel = channel
        self.parentChannelName = parentChannelName
        self.existingPiPOverlay = existingPiPOverlay
        self.streamChannelId = channel.channelID
        super.init(navigationBarPresentationData: nil)
        hidesBottomBarWhenPushed = true
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = UIColor.theme.primary
        self.displayNode = node
        self.displayNodeDidLoad()
    }

    deinit {
        if let presenceObserver {
            NotificationCenter.default.removeObserver(presenceObserver)
        }
        if let channelDescriptionObserver {
            NotificationCenter.default.removeObserver(channelDescriptionObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary

        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundImageView.contentMode = .scaleAspectFit
        backgroundImageView.clipsToBounds = true
        backgroundImageView.isHidden = true

        streamBannerView.translatesAutoresizingMaskIntoConstraints = false
        streamBannerView.contentMode = .scaleAspectFit
        streamBannerView.clipsToBounds = true
        streamBannerView.isHidden = true
        streamBannerView.tintColor = UIColor.theme.textStrong
        streamBannerView.image = UIImage(named: "Channel/channelStream")?.withRenderingMode(.alwaysTemplate)

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.contentMode = .scaleAspectFit
        placeholderView.tintColor = UIColor.theme.textStrong
        placeholderView.image = UIImage(named: "Channel/channelStream")?.withRenderingMode(.alwaysTemplate)

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.isMirrored = true
        videoView.isHidden = true

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = UIColor.theme.textDisabled
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.text = NSLocalizedString(
            "streamingRoom.noDisplay",
            tableName: nil,
            bundle: .main,
            value: "Stream is not available",
            comment: "")

        membersContainer.translatesAutoresizingMaskIntoConstraints = false

        membersOverflowLabel.translatesAutoresizingMaskIntoConstraints = false
        membersOverflowLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        membersOverflowLabel.textColor = UIColor.theme.textStrong
        membersOverflowLabel.isHidden = true

        styleCircleButton(minimizeButton, systemImage: "chevron.down", pointSize: 18)
        minimizeButton.addTarget(self, action: #selector(minimizeTapped), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.text = channel.channelLabel
        titleLabel.numberOfLines = 2

        headerBar.translatesAutoresizingMaskIntoConstraints = false
        bottomChrome.translatesAutoresizingMaskIntoConstraints = false

        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 12
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(minimizeButton)
        headerRow.addArrangedSubview(titleLabel)
        headerBar.addSubview(headerRow)

        styleCircleButton(chatButton, systemImage: "bubble.left.and.bubble.right.fill", pointSize: 18)
        chatButton.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)

        leaveButton.translatesAutoresizingMaskIntoConstraints = false
        leaveButton.backgroundColor = UIColor.systemRed
        leaveButton.layer.cornerRadius = 25
        leaveButton.clipsToBounds = true
        leaveButton.setImage(UIImage.mezonSystemImage("phone.down.fill"), for: .normal)
        leaveButton.tintColor = .white
        leaveButton.addTarget(self, action: #selector(leaveTapped), for: .touchUpInside)

        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.distribution = .equalSpacing
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footerRow.addArrangedSubview(chatButton)
        footerRow.addArrangedSubview(leaveButton)
        bottomChrome.addSubview(footerRow)

        view.addSubview(videoView)
        view.addSubview(backgroundImageView)
        view.addSubview(streamBannerView)
        view.addSubview(placeholderView)
        view.addSubview(statusLabel)
        view.addSubview(membersContainer)
        view.addSubview(membersOverflowLabel)
        view.addSubview(headerBar)
        view.addSubview(bottomChrome)

        NSLayoutConstraint.activate([
            minimizeButton.widthAnchor.constraint(equalToConstant: 44),
            minimizeButton.heightAnchor.constraint(equalToConstant: 44),
            chatButton.widthAnchor.constraint(equalToConstant: 50),
            chatButton.heightAnchor.constraint(equalToConstant: 50),
            leaveButton.widthAnchor.constraint(equalToConstant: 50),
            leaveButton.heightAnchor.constraint(equalToConstant: 50),

            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            streamBannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            streamBannerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            streamBannerView.widthAnchor.constraint(equalToConstant: Self.streamBannerSize),
            streamBannerView.heightAnchor.constraint(equalToConstant: Self.streamBannerSize),

            placeholderView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholderView.widthAnchor.constraint(equalToConstant: Self.streamBannerSize),
            placeholderView.heightAnchor.constraint(equalToConstant: Self.streamBannerSize),

            statusLabel.topAnchor.constraint(equalTo: placeholderView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            headerRow.topAnchor.constraint(equalTo: headerBar.topAnchor),
            headerRow.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            headerRow.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -12),
            headerRow.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),

            bottomChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomChrome.heightAnchor.constraint(equalToConstant: Self.bottomChromeHeight),

            footerRow.topAnchor.constraint(equalTo: bottomChrome.topAnchor),
            footerRow.leadingAnchor.constraint(equalTo: bottomChrome.leadingAnchor, constant: 24),
            footerRow.trailingAnchor.constraint(equalTo: bottomChrome.trailingAnchor, constant: -24),
            footerRow.bottomAnchor.constraint(equalTo: bottomChrome.bottomAnchor),

            membersContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            membersContainer.heightAnchor.constraint(equalToConstant: Self.memberAvatarSize + 4),

            membersOverflowLabel.leadingAnchor.constraint(equalTo: membersContainer.trailingAnchor, constant: 8),
            membersOverflowLabel.centerYAnchor.constraint(equalTo: membersContainer.centerYAnchor),
        ])

        bottomChromeBottomConstraint = bottomChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        bottomChromeBottomConstraint?.isActive = true

        membersBottomConstraint = membersContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.membersBottomOffset)
        membersBottomConstraint?.isActive = true

        view.bringSubviewToFront(headerBar)
        view.bringSubviewToFront(membersContainer)
        view.bringSubviewToFront(membersOverflowLabel)
        view.bringSubviewToFront(bottomChrome)

        bindSession()
        if #available(iOS 13.0, *) {
            loadStreamBackgroundIfNeeded()
        }
        if #available(iOS 13.0, *) {
            refreshPlaybackUI()
        }
        refreshMembersRow()

        presenceObserver = NotificationCenter.default.addObserver(
            forName: .mezonVoicePresenceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let updatedClanId = (notification.userInfo?["clanId"] as? NSNumber)?.int64Value ?? 0
            guard updatedClanId == self.resolvedClanId else { return }
            self.refreshMembersRow()
        }

        channelDescriptionObserver = NotificationCenter.default.addObserver(
            forName: .mezonChannelDescriptionDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let updatedChannelId = (notification.userInfo?["channelId"] as? NSNumber)?.int64Value ?? 0
            guard updatedChannelId == self.channel.channelID else { return }
            let updatedClanId = (notification.userInfo?["clanId"] as? NSNumber)?.int64Value ?? 0
            if updatedClanId != 0, updatedClanId != self.resolvedClanId { return }
            if let updated = self.context.account.postbox.resolvedChannelDescription(
                clanId: self.resolvedClanId,
                channelId: updatedChannelId
            ) {
                self.channel = updated
                self.cachedAvatarURL = nil
            }
            if #available(iOS 13.0, *) {
                self.loadStreamBackgroundIfNeeded()
            }
            if #available(iOS 13.0, *) {
                self.refreshPlaybackUI()
            }
        }

        if let pip = existingPiPOverlay {
            pip.prepareForFullScreenRestore()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bottomInset = view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom
        bottomChromeBottomConstraint?.constant = -(bottomInset + 24)
        membersBottomConstraint?.constant = -(bottomInset + Self.membersBottomOffset)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMinimizingToPiP { return }
        if isMovingFromParent || isBeingDismissed {
            StreamingWebRTCSession.shared.onStreamingStateChanged = nil
            StreamingWebRTCSession.shared.onRemoteVideoTrackChanged = nil
        }
    }

    private var resolvedClanId: Int64 {
        channel.clanID != 0 ? channel.clanID : context.currentClanId
    }

    private func bindSession() {
        StreamingWebRTCSession.shared.onStreamingStateChanged = { [weak self] in
            self?.refreshPlaybackUI()
        }
        StreamingWebRTCSession.shared.onRemoteVideoTrackChanged = { [weak self] track in
            self?.videoView.attach(track: track)
            self?.refreshPlaybackUI()
        }
        videoView.attach(track: StreamingWebRTCSession.shared.remoteVideoTrack)
    }

    private func refreshPlaybackUI() {
        let session = StreamingWebRTCSession.shared
        let hasVideo = session.isRemoteVideoStream
        let isActive = session.isStreaming
        let avatarURL = resolvedStreamChannelAvatarURL()
        let showBackground = isActive && !hasVideo && (backgroundImageView.image != nil || !avatarURL.isEmpty)

        videoView.isHidden = !hasVideo
        backgroundImageView.isHidden = !showBackground
        streamBannerView.isHidden = true
        placeholderView.isHidden = true
        statusLabel.isHidden = isActive || hasVideo

        if !hasVideo && backgroundImageView.image == nil && !isLoadingBackground {
            loadStreamBackgroundIfNeeded()
        }

        if !isActive {
            statusLabel.text = NSLocalizedString(
                "streamingRoom.noDisplay",
                tableName: nil,
                bundle: .main,
                value: "Stream is not available",
                comment: "")
        }
    }

    private func resolvedStreamChannelAvatarURL() -> String {
        if let cachedAvatarURL { return cachedAvatarURL }
        let resolved = StreamingChannelBackground.resolveAvatarURL(channel: channel, context: context)
        cachedAvatarURL = resolved
        return resolved
    }

    @available(iOS 13.0, *)
    private func fetchRemoteChannelAvatarIfNeeded() {
        guard !didFetchRemoteChannel else { return }
        guard resolvedStreamChannelAvatarURL().isEmpty else { return }
        didFetchRemoteChannel = true
        let clanId = resolvedClanId
        let channelId = channel.channelID
        Task { @MainActor [weak self] in
            guard let self, clanId != 0, let token = await self.context.getToken() else { return }
            do {
                let channels = try await self.context.engine.channels.listChannelDescs(clanId: clanId, token: token)
                guard let found = channels.first(where: { $0.channelID == channelId }) else { return }
                self.channel = found
                self.cachedAvatarURL = nil
                self.loadStreamBackgroundIfNeeded()
                self.refreshPlaybackUI()
            } catch {}
        }
    }

    private func loadStreamBackgroundIfNeeded() {
        let raw = resolvedStreamChannelAvatarURL()
        guard !raw.isEmpty else {
            fetchRemoteChannelAvatarIfNeeded()
            return
        }
        guard !isLoadingBackground else { return }
        isLoadingBackground = true
        backgroundLoadToken += 1
        let token = backgroundLoadToken
        let scale = UIScreen.main.scale
        let width = max(Int(view.bounds.width * scale), 720)
        let height = max(Int(view.bounds.height * scale), 720)
        StreamingChannelBackground.loadImage(raw: raw, width: width, height: height) { [weak self] image in
            guard let self, token == self.backgroundLoadToken else { return }
            self.isLoadingBackground = false
            self.backgroundImageView.image = image
            self.refreshPlaybackUI()
        }
    }

    private func streamMemberUserIds() -> [String] {
        guard let list = context.engine.clanData.getStreamUsers(clanId: resolvedClanId) else { return [] }
        var userIds: [String] = []
        for entry in list.voiceChannelUsers where entry.channelID == channel.channelID {
            for uid in entry.userIds where !uid.isEmpty && Int64(uid) != nil && !userIds.contains(uid) {
                userIds.append(uid)
            }
        }
        return userIds
    }

    private func resolveStreamMember(_ uid: String) -> VoiceMemberDisplay? {
        guard let uidInt = Int64(uid) else { return nil }
        let profile = context.account.postbox.read { $0.getProfile(userId: uid) }
        let member = context.account.postbox.read {
            $0.getClanMembers(clanId: self.resolvedClanId)
        }.first(where: { $0.userId == uidInt })

        let name: String
        let username: String
        if let m = member {
            if !m.clanNick.isEmpty {
                name = m.clanNick
            } else if !m.displayName.isEmpty {
                name = m.displayName
            } else if !m.username.isEmpty {
                name = m.username
            } else {
                return nil
            }
            username = m.username
        } else if let profile {
            name = (profile.displayName?.isEmpty == false ? profile.displayName : nil) ?? profile.username
            username = profile.username
        } else {
            return nil
        }

        let avatar: String?
        if let m = member {
            avatar = m.resolvedAvatarURL(fallbackProfileAvatar: profile?.avatarUrl)
                .flatMap { raw -> String? in
                    let absolute = ImgproxyURL.absoluteResourceURL(from: raw)
                    return absolute.isEmpty ? nil : absolute
                }
        } else {
            avatar = profile?.avatarUrl.flatMap { raw -> String? in
                guard !raw.isEmpty else { return nil }
                let absolute = ImgproxyURL.absoluteResourceURL(from: raw)
                return absolute.isEmpty ? nil : absolute
            }
        }

        return VoiceMemberDisplay(name: name, username: username, avatarURL: avatar)
    }

    private func refreshMembersRow() {
        membersContainer.subviews.forEach { $0.removeFromSuperview() }

        let members = streamMemberUserIds().compactMap { resolveStreamMember($0) }
        membersOverflowLabel.isHidden = true

        guard !members.isEmpty else {
            membersContainer.isHidden = true
            return
        }

        membersContainer.isHidden = false
        let avatarSize = Self.memberAvatarSize
        let overlap = Self.memberOverlap
        let visible = Array(members.prefix(Self.maxVisibleMembers))
        let overflowCount = members.count - visible.count

        for (index, member) in visible.enumerated() {
            let container = TextAvatarView(username: member.username, size: avatarSize, fontSize: 16)
            container.translatesAutoresizingMaskIntoConstraints = false
            container.layer.borderWidth = 2
            container.layer.borderColor = UIColor.theme.secondary.cgColor

            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = avatarSize / 2

            if let av = member.avatarURL, !av.isEmpty {
                let px = Int(avatarSize * UIScreen.main.scale)
                let proxy = ImgproxyURL.create(from: av, width: px, height: px)
                container.showSkeleton()
                let fallbackUsername = member.username
                ImageCache.shared.loadAvatar(urlString: proxy) { [weak container] img in
                    imageView.image = img
                    if img != nil {
                        container?.showImageMode()
                    } else {
                        container?.configure(username: fallbackUsername, fontSize: 16)
                    }
                }
            }

            container.addSubview(imageView)
            membersContainer.addSubview(container)

            let xOffset = CGFloat(index) * (avatarSize - overlap)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: membersContainer.leadingAnchor, constant: xOffset),
                container.centerYAnchor.constraint(equalTo: membersContainer.centerYAnchor),
                container.widthAnchor.constraint(equalToConstant: avatarSize),
                container.heightAnchor.constraint(equalToConstant: avatarSize),
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        let totalItems = visible.count + (overflowCount > 0 ? 1 : 0)
        let totalWidth = avatarSize + CGFloat(max(totalItems - 1, 0)) * (avatarSize - overlap)
        membersContainer.constraints.filter { $0.firstAttribute == .width }.forEach { membersContainer.removeConstraint($0) }
        membersContainer.widthAnchor.constraint(equalToConstant: totalWidth).isActive = true

        if overflowCount > 0 {
            membersOverflowLabel.isHidden = false
            membersOverflowLabel.text = "+\(overflowCount)"
        }
    }

    private func styleCircleButton(_ button: UIButton, systemImage: String, pointSize: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.theme.tertiary
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
        button.tintColor = UIColor.theme.textStrong
        let config = MezonSymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.setImage(UIImage.mezonSystemImage(systemImage, withConfiguration: config), for: .normal)
    }

    @objc private func minimizeTapped() {
        StreamingWebRTCSession.shared.onStreamingStateChanged = nil
        StreamingWebRTCSession.shared.onRemoteVideoTrackChanged = nil
        isMinimizingToPiP = true
        StreamingPiPOverlay.shared.show(
            context: context,
            channel: channel,
            parentChannelName: parentChannelName
        )
        navigationController?.popViewController(animated: true)
    }

    @objc private func chatTapped() {
        guard let nav = navigationController else { return }
        if let chatVC = nav.viewControllers.last(where: { ($0 as? ChatViewController)?.channel.channelID == channel.channelID }) {
            nav.popToViewController(chatVC, animated: true)
            return
        }
        let chatVC = ChatViewController(
            clanId: channel.clanID != 0 ? channel.clanID : context.currentClanId,
            channel: channel,
            context: context,
            parentName: parentChannelName
        )
        nav.pushViewController(chatVC, animated: true)
    }

    @objc private func leaveTapped() {
        Self.endStream(
            context: context,
            clanId: resolvedClanId,
            channelId: channel.channelID,
            navigationController: navigationController
        )
    }

    static func endStream(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64,
        navigationController: UINavigationController?
    ) {
        if let userIdStr = context.currentUser?.id, let userId = Int64(userIdStr) {
            context.engine.clanData.applyStreamLeaved(clanId: clanId, channelId: channelId, userId: userId)
        }
        StreamingWebRTCSession.shared.onStreamingStateChanged = nil
        StreamingWebRTCSession.shared.onRemoteVideoTrackChanged = nil
        StreamingWebRTCSession.shared.leave()
        if StreamingPiPOverlay.shared.isActive {
            StreamingPiPOverlay.shared.dismiss(disconnectSession: false)
        }
        guard let nav = navigationController ?? findNavigationControllerForStreamExit() else { return }
        if nav.topViewController is StreamingRoomViewController {
            nav.popViewController(animated: true)
            return
        }
        let filtered = nav.viewControllers.filter { vc in
            guard let streamVC = vc as? StreamingRoomViewController else { return true }
            return streamVC.streamChannelId != channelId
        }
        if filtered.count != nav.viewControllers.count {
            nav.setViewControllers(filtered, animated: true)
        }
    }

    private static func findNavigationControllerForStreamExit() -> UINavigationController? {
        for window in mezonApplicationWindows() where !window.isHidden {
            if let nav = findNavigationController(in: window.rootViewController) {
                return nav
            }
        }
        return nil
    }

    private static func findNavigationController(in viewController: UIViewController?) -> UINavigationController? {
        guard let viewController else { return nil }
        if let nav = viewController as? UINavigationController { return nav }
        for child in viewController.children {
            if let nav = findNavigationController(in: child) { return nav }
        }
        if let presented = viewController.presentedViewController {
            if let nav = findNavigationController(in: presented) { return nav }
        }
        return nil
    }

    static func prepareJoiningStream(
        targetChannelId: Int64,
        clanId: Int64,
        context: AccountContext,
        navigationController: UINavigationController
    ) {
        guard let userIdStr = context.currentUser?.id, let userId = Int64(userIdStr) else { return }

        var channelsToLeave = Set<Int64>()
        if let activeId = StreamingWebRTCSession.shared.activeStreamChannelId, activeId != targetChannelId {
            channelsToLeave.insert(activeId)
        }
        let pip = StreamingPiPOverlay.shared
        if let pipChannelId = pip.channel?.channelID, pipChannelId != targetChannelId {
            channelsToLeave.insert(pipChannelId)
        }
        for vc in navigationController.viewControllers {
            guard let streamVC = vc as? StreamingRoomViewController, streamVC.streamChannelId != targetChannelId else { continue }
            channelsToLeave.insert(streamVC.streamChannelId)
        }
        for channelId in channelsToLeave {
            context.engine.clanData.applyStreamLeaved(clanId: clanId, channelId: channelId, userId: userId)
        }

        if pip.isActive, pip.channel?.channelID != targetChannelId {
            pip.dismiss(disconnectSession: true)
        } else if StreamingWebRTCSession.shared.activeStreamChannelId != nil,
                  StreamingWebRTCSession.shared.activeStreamChannelId != targetChannelId {
            StreamingWebRTCSession.shared.disconnect()
        }

        let filtered = navigationController.viewControllers.filter { vc in
            guard let streamVC = vc as? StreamingRoomViewController else { return true }
            return streamVC.streamChannelId == targetChannelId
        }
        if filtered.count != navigationController.viewControllers.count {
            navigationController.setViewControllers(filtered, animated: false)
        }
    }
}
