import UIKit
import LiveKitWebRTC

final class StreamingRoomViewController: ViewController {

    let streamChannelId: Int64

    private let context: AccountContext
    private let channel: Mezon_Api_ChannelDescription
    private let parentChannelName: String?
    private let existingPiPOverlay: StreamingPiPOverlay?
    private var isMinimizingToPiP = false
    private var presenceObserver: NSObjectProtocol?

    private let videoView = PeerCallVideoRenderView()
    private let backgroundImageView = UIImageView()
    private let streamBannerView = UIImageView()
    private let placeholderView = UIImageView()
    private let statusLabel = UILabel()
    private let membersContainer = UIView()
    private let membersOverflowLabel = UILabel()
    private let headerRow = UIStackView()
    private let footerRow = UIStackView()
    private let minimizeButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let chatButton = UIButton(type: .custom)
    private let leaveButton = UIButton(type: .custom)

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

    deinit {
        if let presenceObserver {
            NotificationCenter.default.removeObserver(presenceObserver)
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

        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 12
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(minimizeButton)
        headerRow.addArrangedSubview(titleLabel)

        styleCircleButton(chatButton, systemImage: "bubble.left.and.bubble.right.fill", pointSize: 18)
        chatButton.addTarget(self, action: #selector(chatTapped), for: .touchUpInside)

        leaveButton.translatesAutoresizingMaskIntoConstraints = false
        leaveButton.backgroundColor = UIColor.systemRed
        leaveButton.layer.cornerRadius = 25
        leaveButton.clipsToBounds = true
        leaveButton.setImage(UIImage(systemName: "phone.down.fill"), for: .normal)
        leaveButton.tintColor = .white
        leaveButton.addTarget(self, action: #selector(leaveTapped), for: .touchUpInside)

        footerRow.axis = .horizontal
        footerRow.alignment = .center
        footerRow.distribution = .equalSpacing
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footerRow.addArrangedSubview(chatButton)
        footerRow.addArrangedSubview(leaveButton)

        view.addSubview(backgroundImageView)
        view.addSubview(streamBannerView)
        view.addSubview(videoView)
        view.addSubview(placeholderView)
        view.addSubview(statusLabel)
        view.addSubview(membersContainer)
        view.addSubview(membersOverflowLabel)
        view.addSubview(headerRow)
        view.addSubview(footerRow)

        NSLayoutConstraint.activate([
            minimizeButton.widthAnchor.constraint(equalToConstant: 44),
            minimizeButton.heightAnchor.constraint(equalToConstant: 44),
            chatButton.widthAnchor.constraint(equalToConstant: 50),
            chatButton.heightAnchor.constraint(equalToConstant: 50),
            leaveButton.widthAnchor.constraint(equalToConstant: 50),
            leaveButton.heightAnchor.constraint(equalToConstant: 50),

            headerRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            headerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            videoView.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 12),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: membersContainer.topAnchor, constant: -16),

            backgroundImageView.topAnchor.constraint(equalTo: videoView.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: videoView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),

            streamBannerView.topAnchor.constraint(equalTo: videoView.topAnchor),
            streamBannerView.leadingAnchor.constraint(equalTo: videoView.leadingAnchor),
            streamBannerView.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
            streamBannerView.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),

            placeholderView.centerXAnchor.constraint(equalTo: videoView.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: videoView.centerYAnchor),
            placeholderView.widthAnchor.constraint(equalToConstant: 96),
            placeholderView.heightAnchor.constraint(equalToConstant: 96),

            statusLabel.topAnchor.constraint(equalTo: placeholderView.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            membersContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            membersContainer.bottomAnchor.constraint(equalTo: footerRow.topAnchor, constant: -20),
            membersContainer.heightAnchor.constraint(equalToConstant: Self.memberAvatarSize + 4),

            membersOverflowLabel.leadingAnchor.constraint(equalTo: membersContainer.trailingAnchor, constant: 8),
            membersOverflowLabel.centerYAnchor.constraint(equalTo: membersContainer.centerYAnchor),

            footerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            footerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            footerRow.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        bindSession()
        loadStreamBackgroundIfNeeded()
        refreshPlaybackUI()
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

        if let pip = existingPiPOverlay {
            pip.prepareForFullScreenRestore()
        }
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

        videoView.isHidden = !hasVideo
        backgroundImageView.isHidden = hasVideo || !isActive
        streamBannerView.isHidden = hasVideo || !isActive || hasStreamChannelAvatar
        placeholderView.isHidden = isActive || hasVideo
        statusLabel.isHidden = isActive || hasVideo

        if isActive && !hasVideo {
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

    private var hasStreamChannelAvatar: Bool {
        !channel.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadStreamBackgroundIfNeeded() {
        guard hasStreamChannelAvatar else {
            backgroundImageView.image = nil
            return
        }
        let raw = channel.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        let width = max(Int(view.bounds.width * UIScreen.main.scale), 720)
        let proxy = ImgproxyURL.create(from: raw, width: width, height: width)
        ImageCache.shared.loadAvatar(urlString: proxy) { [weak self] image in
            self?.backgroundImageView.image = image
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
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.setImage(UIImage(systemName: systemImage, withConfiguration: config), for: .normal)
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
        if let userId = context.currentUser?.id, let uid = Int64(userId) {
            context.engine.clanData.applyStreamLeaved(
                clanId: resolvedClanId,
                channelId: channel.channelID,
                userId: uid
            )
        }
        StreamingPiPOverlay.shared.dismiss(disconnectSession: true)
        navigationController?.popViewController(animated: true)
    }
}
