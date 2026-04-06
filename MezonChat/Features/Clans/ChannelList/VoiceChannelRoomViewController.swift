import UIKit
import AVFoundation
import AVKit
import AsyncDisplayKit
import LiveKit

private enum VoiceParticipantTileKind {
    case mainVideo
    case screenShare
}

private struct VoiceParticipantTileDescriptor {
    let rowKey: String
    let participant: Participant
    let kind: VoiceParticipantTileKind
}

final class VoiceChannelRoomViewController: ViewController {

    private let context: AccountContext
    private let channel: Mezon_Api_ChannelDescription
    private let parentChannelName: String?

    private var liveKitBridge: VoiceChannelLiveKitBridge?
    private var connectTask: Task<Void, Never>?
    private var didStartVoiceConnection = false
    private var micButton: UIButton!
    private var camButton: UIButton!
    private var didAnnounceMeetJoin = false
    private var didAnnounceMeetLeave = false
    private var audioRouteObserver: NSObjectProtocol?

    private var participantRows: [String: VoiceParticipantRowView] = [:]
    fileprivate var screenSharePiPHostRetain: ScreenShareExpandedViewController?

    private let connectingOverlay = UIView()
    private let connectingSpinner = UIActivityIndicatorView(style: .large)
    private let connectingLabel = UILabel()

    private let headerBar = UIView()
    private let headerLeft = UIStackView()
    private let headerRight = UIStackView()
    private let collapseButton = UIButton(type: .custom)
    private let channelTitleLabel = UILabel()
    private let cameraSwitchButton = UIButton(type: .custom)
    private let speakerButton = UIButton(type: .custom)
    private let moreButton = UIButton(type: .custom)

    private let contentScroll = UIScrollView()
    private let participantArea = UIView()
    private let participantsStack = UIStackView()

    private let bottomPill = UIView()
    private let bottomControlsStack = UIStackView()

    init(context: AccountContext, channel: Mezon_Api_ChannelDescription, parentChannelName: String? = nil) {
        self.context = context
        self.channel = channel
        self.parentChannelName = parentChannelName
        super.init(navigationBarPresentationData: nil)
        hidesBottomBarWhenPushed = true
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = UIColor.theme.black
        self.displayNode = node
        self.displayNodeDidLoad()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.black

        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerLeft.axis = .horizontal
        headerLeft.alignment = .center
        headerLeft.spacing = 20
        headerLeft.translatesAutoresizingMaskIntoConstraints = false

        styleHeaderCircleButton(collapseButton, systemImage: "chevron.down", pointSize: 16)
        collapseButton.tintColor = UIColor.theme.white
        collapseButton.addTarget(self, action: #selector(popTapped), for: .touchUpInside)

        channelTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        channelTitleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        channelTitleLabel.textColor = UIColor.theme.textStrong
        channelTitleLabel.lineBreakMode = .byTruncatingTail
        channelTitleLabel.numberOfLines = 1
        let name = channel.channelLabel.isEmpty
            ? NSLocalizedString("voiceChannel.defaultName", tableName: nil, bundle: .main, value: "Voice", comment: "")
            : channel.channelLabel
        channelTitleLabel.text = name
        channelTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerLeft.addArrangedSubview(collapseButton)
        headerLeft.addArrangedSubview(channelTitleLabel)

        headerRight.axis = .horizontal
        headerRight.alignment = .center
        headerRight.spacing = 10
        headerRight.translatesAutoresizingMaskIntoConstraints = false

        styleHeaderCircleButton(cameraSwitchButton, systemImage: "arrow.triangle.2.circlepath.camera", pointSize: 16)
        cameraSwitchButton.tintColor = UIColor.theme.white
        cameraSwitchButton.addTarget(self, action: #selector(switchCameraTapped), for: .touchUpInside)
        styleHeaderCircleButton(speakerButton, systemImage: "speaker.wave.2.fill", pointSize: 16)
        speakerButton.tintColor = UIColor.theme.white
        speakerButton.addTarget(self, action: #selector(speakerTapped), for: .touchUpInside)
        let speakerLongPress = UILongPressGestureRecognizer(target: self, action: #selector(speakerLongPressed(_:)))
        speakerLongPress.minimumPressDuration = 0.45
        speakerButton.addGestureRecognizer(speakerLongPress)
        styleHeaderCircleButton(moreButton, systemImage: "ellipsis", pointSize: 18)
        moreButton.tintColor = UIColor.theme.white

        headerRight.addArrangedSubview(cameraSwitchButton)
        headerRight.addArrangedSubview(speakerButton)
        headerRight.addArrangedSubview(moreButton)

        headerBar.addSubview(headerLeft)
        headerBar.addSubview(headerRight)

        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.alwaysBounceVertical = true
        contentScroll.showsVerticalScrollIndicator = false

        participantArea.translatesAutoresizingMaskIntoConstraints = false

        participantsStack.translatesAutoresizingMaskIntoConstraints = false
        participantsStack.axis = .vertical
        participantsStack.spacing = 12
        participantsStack.alignment = .fill

        contentScroll.addSubview(participantArea)
        participantArea.addSubview(participantsStack)

        bottomPill.translatesAutoresizingMaskIntoConstraints = false
        bottomPill.backgroundColor = UIColor.theme.secondary
        bottomPill.layer.cornerRadius = 40

        bottomControlsStack.axis = .horizontal
        bottomControlsStack.spacing = 10
        bottomControlsStack.alignment = .center
        bottomControlsStack.distribution = .equalSpacing
        bottomControlsStack.translatesAutoresizingMaskIntoConstraints = false
        bottomControlsStack.isLayoutMarginsRelativeArrangement = true
        bottomControlsStack.layoutMargins = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

        let cam = makeControlBarIconButton(systemName: "video.slash.fill", action: #selector(cameraBarTapped))
        camButton = cam
        let mic = makeControlBarIconButton(systemName: "mic.slash.fill", action: #selector(micTapped))
        micButton = mic
        let chat = makeControlBarIconButton(systemName: "bubble.left.and.bubble.right.fill", action: #selector(openChatTapped))
        let hand = makeControlBarIconButton(systemName: "hand.raised.fill")
        let leave = makeEndCallButton()
        [cam, mic, chat, hand, leave].forEach { bottomControlsStack.addArrangedSubview($0) }

        bottomPill.addSubview(bottomControlsStack)

        connectingOverlay.translatesAutoresizingMaskIntoConstraints = false
        connectingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        connectingOverlay.isHidden = true
        connectingSpinner.translatesAutoresizingMaskIntoConstraints = false
        connectingSpinner.hidesWhenStopped = true
        connectingLabel.translatesAutoresizingMaskIntoConstraints = false
        connectingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        connectingLabel.textColor = UIColor.theme.textStrong
        connectingLabel.textAlignment = .center
        connectingLabel.numberOfLines = 0
        connectingLabel.text = NSLocalizedString(
            "voiceChannel.connecting", tableName: nil, bundle: .main, value: "Connecting to voice…", comment: "")
        connectingOverlay.addSubview(connectingSpinner)
        connectingOverlay.addSubview(connectingLabel)

        view.addSubview(headerBar)
        view.addSubview(contentScroll)
        view.addSubview(bottomPill)
        view.addSubview(connectingOverlay)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            headerBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            headerLeft.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            headerLeft.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            headerLeft.topAnchor.constraint(equalTo: headerBar.topAnchor),
            headerLeft.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerLeft.trailingAnchor.constraint(lessThanOrEqualTo: headerRight.leadingAnchor, constant: -12),

            headerRight.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerRight.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            collapseButton.widthAnchor.constraint(equalToConstant: 40),
            collapseButton.heightAnchor.constraint(equalToConstant: 40),
            cameraSwitchButton.widthAnchor.constraint(equalToConstant: 40),
            cameraSwitchButton.heightAnchor.constraint(equalToConstant: 40),
            speakerButton.widthAnchor.constraint(equalToConstant: 40),
            speakerButton.heightAnchor.constraint(equalToConstant: 40),
            moreButton.widthAnchor.constraint(equalToConstant: 40),
            moreButton.heightAnchor.constraint(equalToConstant: 40),

            contentScroll.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 8),
            contentScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: bottomPill.topAnchor, constant: -24),

            participantArea.topAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.topAnchor, constant: 16),
            participantArea.leadingAnchor.constraint(equalTo: contentScroll.frameLayoutGuide.leadingAnchor),
            participantArea.trailingAnchor.constraint(equalTo: contentScroll.frameLayoutGuide.trailingAnchor),
            participantArea.bottomAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.bottomAnchor, constant: -24),
            participantArea.widthAnchor.constraint(equalTo: contentScroll.frameLayoutGuide.widthAnchor),

            participantsStack.topAnchor.constraint(equalTo: participantArea.topAnchor),
            participantsStack.leadingAnchor.constraint(equalTo: participantArea.leadingAnchor, constant: 16),
            participantsStack.trailingAnchor.constraint(equalTo: participantArea.trailingAnchor, constant: -16),
            participantsStack.bottomAnchor.constraint(equalTo: participantArea.bottomAnchor),

            bottomPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),

            bottomControlsStack.topAnchor.constraint(equalTo: bottomPill.topAnchor, constant: 6),
            bottomControlsStack.leadingAnchor.constraint(equalTo: bottomPill.leadingAnchor, constant: 10),
            bottomControlsStack.trailingAnchor.constraint(equalTo: bottomPill.trailingAnchor, constant: -10),
            bottomControlsStack.bottomAnchor.constraint(equalTo: bottomPill.bottomAnchor, constant: -6),

            connectingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            connectingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            connectingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            connectingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            connectingSpinner.centerXAnchor.constraint(equalTo: connectingOverlay.centerXAnchor),
            connectingSpinner.centerYAnchor.constraint(equalTo: connectingOverlay.centerYAnchor, constant: -24),

            connectingLabel.leadingAnchor.constraint(equalTo: connectingOverlay.leadingAnchor, constant: 24),
            connectingLabel.trailingAnchor.constraint(equalTo: connectingOverlay.trailingAnchor, constant: -24),
            connectingLabel.topAnchor.constraint(equalTo: connectingSpinner.bottomAnchor, constant: 16),
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: ThemeManager.didChangeNotification, object: nil)

        audioRouteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            self?.refreshSpeakerRouteUI()
        }
    }

    private func styleHeaderCircleButton(_ button: UIButton, systemImage: String, pointSize: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.theme.secondary
        button.layer.cornerRadius = 20
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.theme.border.cgColor
        let img = UIImage(systemName: systemImage, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium))
        button.setImage(img?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
    }

    private func makeControlBarIconButton(systemName: String, action: Selector? = nil) -> UIButton {
        let b = UIButton(type: .custom)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = UIColor.theme.tertiary
        b.layer.cornerRadius = 25
        b.layer.borderWidth = 0.5
        b.layer.borderColor = UIColor.theme.textDisabled.withAlphaComponent(0.6).cgColor
        let img = UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        b.setImage(img?.withRenderingMode(.alwaysTemplate), for: .normal)
        b.tintColor = UIColor.theme.textStrong
        b.widthAnchor.constraint(equalToConstant: 50).isActive = true
        b.heightAnchor.constraint(equalToConstant: 50).isActive = true
        if let action {
            b.addTarget(self, action: action, for: .touchUpInside)
        }
        return b
    }

    private func makeEndCallButton() -> UIButton {
        let b = UIButton(type: .custom)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = UIColor(red: 0.89, green: 0.18, blue: 0.18, alpha: 1)
        b.layer.cornerRadius = 25
        let img = UIImage(systemName: "phone.down.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        b.setImage(img?.withRenderingMode(.alwaysTemplate), for: .normal)
        b.tintColor = .white
        b.widthAnchor.constraint(equalToConstant: 50).isActive = true
        b.heightAnchor.constraint(equalToConstant: 50).isActive = true
        b.addTarget(self, action: #selector(popTapped), for: .touchUpInside)
        return b
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
        if let audioRouteObserver {
            NotificationCenter.default.removeObserver(audioRouteObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStartVoiceConnection else { return }
        didStartVoiceConnection = true
        connectTask = Task { @MainActor in
            await self.runVoiceConnectionPipeline()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            tearDownScreenSharePresentationAndPiP()
            connectTask?.cancel()
            connectTask = nil
            sendMeetLeaveIfNeeded()
            let bridge = liveKitBridge
            liveKitBridge = nil
            bridge?.clearCallbacks()
            Task {
                await bridge?.disconnect()
            }
        }
    }

    @objc private func applyTheme() {
        view.backgroundColor = UIColor.theme.black
        displayNode.backgroundColor = UIColor.theme.black
        channelTitleLabel.textColor = UIColor.theme.textStrong
        collapseButton.backgroundColor = UIColor.theme.secondary
        collapseButton.layer.borderColor = UIColor.theme.border.cgColor
        cameraSwitchButton.backgroundColor = UIColor.theme.secondary
        cameraSwitchButton.layer.borderColor = UIColor.theme.border.cgColor
        speakerButton.backgroundColor = UIColor.theme.secondary
        speakerButton.layer.borderColor = UIColor.theme.border.cgColor
        moreButton.backgroundColor = UIColor.theme.secondary
        moreButton.layer.borderColor = UIColor.theme.border.cgColor
        bottomPill.backgroundColor = UIColor.theme.secondary
        connectingLabel.textColor = UIColor.theme.textStrong
        participantRows.values.forEach { $0.applyTheme() }
        refreshSpeakerRouteUI()
        refreshCamButtonIcon()
    }

    @objc private func popTapped() {
        tearDownScreenSharePresentationAndPiP()
        connectTask?.cancel()
        connectTask = nil
        sendMeetLeaveIfNeeded()
        let bridge = liveKitBridge
        liveKitBridge = nil
        bridge?.clearCallbacks()
        Task { @MainActor in
            await bridge?.disconnect()
            self.navigationController?.popViewController(animated: true)
        }
    }

    @objc private func micTapped() {
        guard let bridge = liveKitBridge else { return }
        Task { @MainActor in
            let currentlyOn = bridge.isMicrophoneEnabled()
            if !currentlyOn {
                let ok = await VoiceChannelMicPermission.requestIfNeeded()
                if !ok {
                    self.presentMicrophoneSettingsAlert()
                    return
                }
            }
            do {
                try await bridge.setMicrophoneEnabled(!currentlyOn)
                self.refreshMicButtonIcon()
                self.refreshCamButtonIcon()
                self.refreshParticipantRowsFromLiveKit()
            } catch {
                AppLogger.network.error("[VoiceChannel] toggle mic: \(error)")
                self.presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: error.localizedDescription)
            }
        }
    }

    @objc private func openChatTapped() {
        let chatVC = ChatViewController(
            clanId: channel.clanID,
            channel: channel,
            context: context,
            parentName: parentChannelName
        )
        navigationController?.pushViewController(chatVC, animated: true)
    }

    private func runVoiceConnectionPipeline() async {
        setConnectingOverlayVisible(true)
        await context.waitForSessionReady()
        guard !Task.isCancelled else {
            setConnectingOverlayVisible(false)
            return
        }
        guard let sessionToken = await context.getToken() else {
            setConnectingOverlayVisible(false)
            presentVoiceAlert(
                title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                message: NSLocalizedString("voiceChannel.errorNoSession", tableName: nil, bundle: .main, value: "You are not signed in.", comment: ""))
            return
        }

        let roomName = "\(channel.channelID)"
        let meetURL = MezonConfig.meetWebSocketURLString

        do {
            let jwt = try await context.account.network.generateMeetToken(
                channelId: channel.channelID,
                roomName: roomName,
                token: sessionToken
            )
            guard !jwt.isEmpty else {
                setConnectingOverlayVisible(false)
                presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: NSLocalizedString("voiceChannel.errorNoToken", tableName: nil, bundle: .main, value: "Could not get a room token.", comment: ""))
                return
            }
            guard !Task.isCancelled else {
                setConnectingOverlayVisible(false)
                return
            }

            let bridge = VoiceChannelLiveKitBridge()
            bridge.onConnectFailed = { [weak self] error in
                self?.setConnectingOverlayVisible(false)
                self?.liveKitBridge = nil
                self?.presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: error.localizedDescription)
            }
            bridge.onDisconnected = { [weak self] error in
                self?.handleLiveKitDisconnected(error: error)
            }
            bridge.onRoomParticipantsChanged = { [weak self] in
                self?.refreshParticipantRowsFromLiveKit()
            }
            liveKitBridge = bridge

            try await bridge.connect(url: meetURL, token: jwt)
            guard !Task.isCancelled else {
                await bridge.disconnect()
                liveKitBridge = nil
                setConnectingOverlayVisible(false)
                return
            }

            let micOk = await VoiceChannelMicPermission.requestIfNeeded()
            if micOk {
                do {
                    try await bridge.setMicrophoneEnabled(true)
                } catch {
                    AppLogger.network.error("[VoiceChannel] publish mic: \(error)")
                }
            }
            refreshMicButtonIcon()
            AudioManager.shared.isSpeakerOutputPreferred = false
            refreshSpeakerRouteUI()
            refreshCamButtonIcon()
            announceMeetJoinIfNeeded()
            refreshParticipantRowsFromLiveKit()
            setConnectingOverlayVisible(false)
        } catch {
            setConnectingOverlayVisible(false)
            if !Task.isCancelled {
                AppLogger.network.error("[VoiceChannel] connect pipeline: \(error)")
                presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: error.localizedDescription)
            }
            liveKitBridge = nil
        }
    }

    private func setConnectingOverlayVisible(_ visible: Bool) {
        connectingOverlay.isHidden = !visible
        if visible {
            connectingSpinner.startAnimating()
            view.bringSubviewToFront(connectingOverlay)
        } else {
            connectingSpinner.stopAnimating()
        }
    }

    private func refreshMicButtonIcon() {
        guard let bridge = liveKitBridge else {
            setMicButtonIcon(muted: true)
            return
        }
        setMicButtonIcon(muted: !bridge.isMicrophoneEnabled())
    }

    private func setMicButtonIcon(muted: Bool) {
        let name = muted ? "mic.slash.fill" : "mic.fill"
        let img = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        micButton.setImage(img?.withRenderingMode(.alwaysTemplate), for: .normal)
    }

    private func meetStateDisplayName() -> String {
        if let d = context.currentUser?.displayName, !d.isEmpty { return d }
        if let n = context.currentUser?.username, !n.isEmpty { return n }
        return "Mezon"
    }

    private func announceMeetJoinIfNeeded() {
        guard !didAnnounceMeetJoin else { return }
        didAnnounceMeetJoin = true
        if let uid = Int64(context.currentUser?.id ?? "") {
            context.engine.clanData.applyVoiceJoined(clanId: channel.clanID, channelId: channel.channelID, userId: uid)
        }
        context.account.socket.sendVoiceParticipantMeetState(
            clanId: channel.clanID,
            channelId: channel.channelID,
            roomName: "\(channel.channelID)",
            displayName: meetStateDisplayName(),
            join: true
        )
    }

    private func sendMeetLeaveIfNeeded() {
        guard !didAnnounceMeetLeave else { return }
        guard didAnnounceMeetJoin else { return }
        didAnnounceMeetLeave = true
        if let uid = Int64(context.currentUser?.id ?? "") {
            context.engine.clanData.applyVoiceLeaved(clanId: channel.clanID, channelId: channel.channelID, userId: uid)
        }
        context.account.socket.sendVoiceParticipantMeetState(
            clanId: channel.clanID,
            channelId: channel.channelID,
            roomName: "\(channel.channelID)",
            displayName: meetStateDisplayName(),
            join: false
        )
    }

    private func refreshParticipantRowsFromLiveKit() {
        guard let bridge = liveKitBridge, let room = bridge.room else { return }
        let ordered = orderedParticipants(room: room)
        let descriptors = voiceTileDescriptors(participants: ordered)
        var orderedKeys: [String] = []
        for d in descriptors {
            orderedKeys.append(d.rowKey)
            if participantRows[d.rowKey] == nil {
                participantRows[d.rowKey] = VoiceParticipantRowView(identityKey: d.rowKey, tileKind: d.kind)
            }
            guard let row = participantRows[d.rowKey] else { continue }
            let p = d.participant
            let isLocal = p is LocalParticipant
            let baseKey = participantRowKey(p)
            let display = resolveDisplayName(participant: p, isLocal: isLocal)
            let avatarURL = resolveAvatarURL(identityKey: baseKey)
            let videoTrack: VideoTrack?
            let mirrorVideo: Bool
            let speaking: Bool
            switch d.kind {
            case .screenShare:
                videoTrack = p.firstScreenShareVideoTrack
                mirrorVideo = false
                speaking = false
            case .mainVideo:
                videoTrack = p.firstCameraVideoTrack
                mirrorVideo = isLocal
                speaking = p.isSpeaking
            }
            row.configure(
                displayName: display,
                micOn: p.isMicrophoneEnabled(),
                speaking: speaking,
                avatarURL: avatarURL,
                videoTrack: videoTrack,
                mirrorVideo: mirrorVideo
            )
            row.applyTheme()
            switch d.kind {
            case .screenShare:
                row.onExpandScreenShare = { [weak self] in
                    guard let self, let track = p.firstScreenShareVideoTrack else { return }
                    self.presentScreenShareExpanded(track: track, displayName: display)
                }
            case .mainVideo:
                row.onExpandScreenShare = nil
            }
        }
        let nextKeys = Set(orderedKeys)
        let stale = participantRows.keys.filter { !nextKeys.contains($0) }
        for k in stale {
            participantRows[k]?.prepareForRemoval()
            participantRows[k]?.removeFromSuperview()
            participantRows.removeValue(forKey: k)
        }
        for v in participantsStack.arrangedSubviews {
            participantsStack.removeArrangedSubview(v)
        }
        for key in orderedKeys {
            guard let row = participantRows[key] else { continue }
            participantsStack.addArrangedSubview(row)
        }
    }

    /// RN-style: one **screen share** tile when publishing screen, plus a separate **camera / avatar** tile (never shows screen in the main tile).
    private func voiceTileDescriptors(participants: [Participant]) -> [VoiceParticipantTileDescriptor] {
        var out: [VoiceParticipantTileDescriptor] = []
        for p in participants {
            let base = participantRowKey(p)
            if base.isEmpty { continue }
            if p.firstScreenShareVideoTrack != nil {
                out.append(VoiceParticipantTileDescriptor(rowKey: "\(base)|screen", participant: p, kind: .screenShare))
            }
            out.append(VoiceParticipantTileDescriptor(rowKey: "\(base)|main", participant: p, kind: .mainVideo))
        }
        return out
    }

    private func participantRowKey(_ p: Participant) -> String {
        if let id = p.identity?.stringValue, !id.isEmpty { return id }
        if let sid = p.sid { return String(describing: sid) }
        return ""
    }

    private func orderedParticipants(room: Room) -> [Participant] {
        var out: [Participant] = [room.localParticipant]
        let sortedRemotes = room.remoteParticipants.values.sorted { a, b in
            if a.isSpeaking != b.isSpeaking { return a.isSpeaking && !b.isSpeaking }
            let na = a.name ?? a.identity?.stringValue ?? ""
            let nb = b.name ?? b.identity?.stringValue ?? ""
            return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending
        }
        out.append(contentsOf: sortedRemotes)
        return out
    }

    private func resolveDisplayName(participant: Participant, isLocal: Bool) -> String {
        if isLocal {
            if let d = context.currentUser?.displayName, !d.isEmpty { return d }
            if let n = context.currentUser?.username, !n.isEmpty { return n }
            return NSLocalizedString("voiceChannel.placeholderYou", tableName: nil, bundle: .main, value: "You", comment: "")
        }
        if let n = participant.name, !n.isEmpty { return n }
        let idKey = participant.identity?.stringValue ?? ""
        return displayNameForClanMember(userIdKey: idKey)
    }

    private func displayNameForClanMember(userIdKey: String) -> String {
        guard let uid = Int64(userIdKey) else { return userIdKey.isEmpty ? "…" : userIdKey }
        guard let list = context.engine.clanData.getClanUsers(clanId: channel.clanID) else { return "\(uid)" }
        for cu in list.clanUsers where cu.user.id == uid {
            if !cu.clanNick.isEmpty { return cu.clanNick }
            if !cu.user.displayName.isEmpty { return cu.user.displayName }
            if !cu.user.username.isEmpty { return cu.user.username }
        }
        return userIdKey
    }

    private func resolveAvatarURL(identityKey: String) -> String? {
        guard let uid = Int64(identityKey) else { return nil }
        if let my = Int64(context.currentUser?.id ?? ""), my == uid,
           let url = context.currentUser?.avatarURL?.absoluteString, !url.isEmpty {
            return url
        }
        guard let list = context.engine.clanData.getClanUsers(clanId: channel.clanID) else { return nil }
        for cu in list.clanUsers where cu.user.id == uid {
            if !cu.clanAvatar.isEmpty { return cu.clanAvatar }
            if !cu.user.avatarURL.isEmpty { return cu.user.avatarURL }
        }
        return nil
    }

    private func refreshSpeakerRouteUI() {
        let bluetooth = Self.audioRouteUsesBluetooth(AVAudioSession.sharedInstance())
        let symbol: String
        if bluetooth {
            symbol = "headphones"
        } else if AudioManager.shared.isSpeakerOutputPreferred {
            symbol = "speaker.wave.2.fill"
        } else {
            symbol = "iphone.radiowaves.left.and.right"
        }
        let img = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        speakerButton.setImage(img?.withRenderingMode(.alwaysTemplate), for: .normal)
    }

    private static func audioRouteUsesBluetooth(_ session: AVAudioSession) -> Bool {
        session.currentRoute.outputs.contains { out in
            switch out.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return true
            default:
                return false
            }
        }
    }

    @objc private func speakerTapped() {
        AudioManager.shared.isSpeakerOutputPreferred.toggle()
        refreshSpeakerRouteUI()
    }

    @objc private func speakerLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let title = NSLocalizedString("voiceChannel.audioRouteTitle", tableName: nil, bundle: .main, value: "Audio output", comment: "")
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("voiceChannel.audioOutputSpeaker", tableName: nil, bundle: .main, value: "Speaker", comment: ""),
            style: .default
        ) { _ in
            AudioManager.shared.isSpeakerOutputPreferred = true
            self.refreshSpeakerRouteUI()
        })
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("voiceChannel.audioOutputEarpiece", tableName: nil, bundle: .main, value: "Earpiece", comment: ""),
            style: .default
        ) { _ in
            AudioManager.shared.isSpeakerOutputPreferred = false
            self.refreshSpeakerRouteUI()
        })
        if Self.audioRouteUsesBluetooth(AVAudioSession.sharedInstance()) {
            let btTitle = NSLocalizedString("voiceChannel.audioOutputBluetooth", tableName: nil, bundle: .main, value: "Bluetooth (connected)", comment: "")
            sheet.addAction(UIAlertAction(title: btTitle, style: .default) { _ in
                AudioManager.shared.isSpeakerOutputPreferred = false
                self.refreshSpeakerRouteUI()
            })
        }
        sheet.addAction(UIAlertAction(
            title: NSLocalizedString("voiceChannel.cancel", tableName: nil, bundle: .main, value: "Cancel", comment: ""),
            style: .cancel
        ))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = speakerButton
            pop.sourceRect = speakerButton.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func cameraBarTapped() {
        guard let bridge = liveKitBridge else { return }
        Task { @MainActor in
            let currentlyOn = bridge.isCameraEnabled()
            if !currentlyOn {
                let ok = await VoiceChannelCameraPermission.requestIfNeeded()
                if !ok {
                    self.presentCameraSettingsAlert()
                    return
                }
            }
            do {
                try await bridge.setCameraEnabled(!currentlyOn)
                self.refreshCamButtonIcon()
                self.refreshParticipantRowsFromLiveKit()
            } catch {
                AppLogger.network.error("[VoiceChannel] toggle camera: \(error)")
                self.presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: error.localizedDescription)
            }
        }
    }

    @objc private func switchCameraTapped() {
        guard let bridge = liveKitBridge, bridge.isCameraEnabled() else { return }
        Task { @MainActor in
            do {
                try await bridge.switchCameraPosition()
            } catch {
                AppLogger.network.error("[VoiceChannel] switch camera: \(error)")
            }
        }
    }

    private func refreshCamButtonIcon() {
        guard let bridge = liveKitBridge else {
            setCamButtonIcon(cameraOn: false)
            return
        }
        setCamButtonIcon(cameraOn: bridge.isCameraEnabled())
    }

    private func setCamButtonIcon(cameraOn: Bool) {
        let name = cameraOn ? "video.fill" : "video.slash.fill"
        let img = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        camButton.setImage(img?.withRenderingMode(.alwaysTemplate), for: .normal)
    }

    private func handleLiveKitDisconnected(error: LiveKitError?) {
        guard liveKitBridge != nil else { return }

        tearDownScreenSharePresentationAndPiP()

        AppLogger.network.error("[VoiceChannel] disconnected: \(String(describing: error))")

        if error?.type == .roomDeleted {
            context.engine.clanData.applyVoiceEnded(clanId: channel.clanID, channelId: channel.channelID)
        }

        connectTask?.cancel()
        connectTask = nil

        let bridge = liveKitBridge
        liveKitBridge = nil
        bridge?.clearCallbacks()

        setConnectingOverlayVisible(false)
        sendMeetLeaveIfNeeded()

        guard navigationController?.topViewController === self else { return }

        if let lk = error {
            switch lk.type {
            case .participantRemoved, .duplicateIdentity, .roomDeleted:
                let message = Self.disconnectMessage(for: lk.type)
                presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.disconnectTitle", tableName: nil, bundle: .main, value: "Voice call ended", comment: ""),
                    message: message
                ) { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            case .cancelled:
                navigationController?.popViewController(animated: true)
            default:
                presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: lk.localizedDescription
                ) { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private static func disconnectMessage(for type: LiveKitErrorType) -> String {
        switch type {
        case .participantRemoved:
            return NSLocalizedString(
                "voiceChannel.disconnectRemoved", tableName: nil, bundle: .main,
                value: "You were removed from the voice channel.", comment: "")
        case .duplicateIdentity:
            return NSLocalizedString(
                "voiceChannel.disconnectDuplicate", tableName: nil, bundle: .main,
                value: "This account joined the call from another device.", comment: "")
        case .roomDeleted:
            return NSLocalizedString(
                "voiceChannel.disconnectRoomDeleted", tableName: nil, bundle: .main,
                value: "The voice room was closed.", comment: "")
        default:
            return NSLocalizedString(
                "voiceChannel.disconnectDefault", tableName: nil, bundle: .main,
                value: "The connection to the voice room was lost.", comment: "")
        }
    }

    private func presentVoiceAlert(title: String, message: String, onDismiss: (() -> Void)? = nil) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: NSLocalizedString("voiceChannel.ok", tableName: nil, bundle: .main, value: "OK", comment: ""), style: .default) { _ in
            onDismiss?()
        })
        present(ac, animated: true)
    }

    private func presentMicrophoneSettingsAlert() {
        let title = NSLocalizedString("voiceChannel.micPermissionTitle", tableName: nil, bundle: .main, value: "Microphone", comment: "")
        let message = NSLocalizedString(
            "voiceChannel.micPermissionBody", tableName: nil, bundle: .main,
            value: "Allow microphone access in Settings to speak in voice channels.", comment: "")
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: NSLocalizedString("voiceChannel.cancel", tableName: nil, bundle: .main, value: "Cancel", comment: ""), style: .cancel))
        ac.addAction(UIAlertAction(title: NSLocalizedString("voiceChannel.openSettings", tableName: nil, bundle: .main, value: "Settings", comment: ""), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(ac, animated: true)
    }

    private func presentCameraSettingsAlert() {
        let title = NSLocalizedString("voiceChannel.cameraPermissionTitle", tableName: nil, bundle: .main, value: "Camera", comment: "")
        let message = NSLocalizedString(
            "voiceChannel.cameraPermissionBody", tableName: nil, bundle: .main,
            value: "Allow camera access in Settings to share video in voice channels.", comment: "")
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: NSLocalizedString("voiceChannel.cancel", tableName: nil, bundle: .main, value: "Cancel", comment: ""), style: .cancel))
        ac.addAction(UIAlertAction(title: NSLocalizedString("voiceChannel.openSettings", tableName: nil, bundle: .main, value: "Settings", comment: ""), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(ac, animated: true)
    }

    private func presentScreenShareExpanded(track: VideoTrack, displayName: String) {
        tearDownScreenSharePresentationAndPiP()
        let vc = ScreenShareExpandedViewController(track: track, displayName: displayName)
        vc.pipHost = self
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func tearDownScreenSharePresentationAndPiP() {
        if let expanded = presentedViewController as? ScreenShareExpandedViewController {
            expanded.tearDownForVoiceRoomLeaving()
            dismiss(animated: false)
        }
        if let retained = screenSharePiPHostRetain {
            retained.tearDownForVoiceRoomLeaving()
            screenSharePiPHostRetain = nil
        }
    }

    fileprivate func retainScreenSharePiPHost(_ vc: ScreenShareExpandedViewController) {
        if let old = screenSharePiPHostRetain, old !== vc {
            old.tearDownForVoiceRoomLeaving()
        }
        screenSharePiPHostRetain = vc
    }

    fileprivate func releaseScreenSharePiPHost(_ vc: ScreenShareExpandedViewController) {
        guard screenSharePiPHostRetain === vc else { return }
        screenSharePiPHostRetain = nil
    }
}

private final class ScreenShareExpandedViewController: AVPictureInPictureVideoCallViewController, AVPictureInPictureControllerDelegate {

    weak var pipHost: VoiceChannelRoomViewController?

    private let shareTrack: VideoTrack
    private let personName: String
    private let videoView = VideoView()
    private var pipController: AVPictureInPictureController?
    private var didAutoDismissForPiP = false
    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let pipButton = UIButton(type: .system)

    init(track: VideoTrack, displayName: String) {
        self.shareTrack = track
        self.personName = displayName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        preferredContentSize = CGSize(width: 1920, height: 1080)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.renderMode = .sampleBuffer
        videoView.layoutMode = .fill
        videoView.mirrorMode = .off
        videoView.isPinchToZoomEnabled = false

        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.layer.cornerRadius = 12
        topBar.clipsToBounds = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.text = personName
        titleLabel.lineBreakMode = .byTruncatingTail

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let closeCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: closeCfg), for: .normal)
        closeButton.tintColor = .white
        closeButton.addAction(UIAction { [weak self] _ in self?.closeTapped() }, for: .touchUpInside)
        closeButton.accessibilityLabel = NSLocalizedString("voiceChannel.close", tableName: nil, bundle: .main, value: "Close", comment: "")

        pipButton.translatesAutoresizingMaskIntoConstraints = false
        let pipCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        pipButton.setImage(UIImage(systemName: "pip", withConfiguration: pipCfg), for: .normal)
        pipButton.tintColor = .white
        pipButton.addAction(UIAction { [weak self] _ in self?.pipTapped() }, for: .touchUpInside)
        pipButton.accessibilityLabel = NSLocalizedString("voiceChannel.screenSharePiP", tableName: nil, bundle: .main, value: "Picture in Picture", comment: "")

        let pipSupported = AVPictureInPictureController.isPictureInPictureSupported()
        pipButton.isEnabled = pipSupported
        pipButton.alpha = pipSupported ? 1 : 0.35

        view.addSubview(videoView)
        view.addSubview(topBar)
        topBar.contentView.addSubview(closeButton)
        topBar.contentView.addSubview(titleLabel)
        topBar.contentView.addSubview(pipButton)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: view.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            closeButton.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: topBar.contentView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            pipButton.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -12),
            pipButton.centerYAnchor.constraint(equalTo: topBar.contentView.centerYAnchor),
            pipButton.widthAnchor.constraint(equalToConstant: 40),
            pipButton.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: pipButton.leadingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.contentView.centerYAnchor),
        ])

        view.bringSubviewToFront(topBar)
        videoView.track = shareTrack
    }

    deinit {
        videoView.track = nil
        pipController?.delegate = nil
        pipController = nil
    }

    fileprivate func tearDownForVoiceRoomLeaving() {
        pipController?.stopPictureInPicture()
        videoView.track = nil
        pipController?.delegate = nil
        pipController = nil
    }

    private func closeTapped() {
        pipController?.stopPictureInPicture()
        pipHost?.releaseScreenSharePiPHost(self)
        dismiss(animated: true)
    }

    private func pipTapped() {
        guard pipButton.isEnabled else {
            presentPiPUnavailableAlert()
            return
        }
        if pipController == nil {
            let source = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: videoView,
                contentViewController: self
            )
            let pip = AVPictureInPictureController(contentSource: source)
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = false
            pipController = pip
        }
        pipController?.startPictureInPicture()
    }

    private func presentPiPUnavailableAlert() {
        let title = NSLocalizedString("voiceChannel.screenSharePiP", tableName: nil, bundle: .main, value: "Picture in Picture", comment: "")
        let message = NSLocalizedString(
            "voiceChannel.screenSharePiPUnavailable", tableName: nil, bundle: .main,
            value: "Picture in Picture isn’t available for this screen share on this device.", comment: "")
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: NSLocalizedString("voiceChannel.ok", tableName: nil, bundle: .main, value: "OK", comment: ""), style: .default))
        present(ac, animated: true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        AppLogger.network.error("[VoiceChannel] PiP failed: \(error)")
        let ac = UIAlertController(
            title: NSLocalizedString("voiceChannel.screenSharePiP", tableName: nil, bundle: .main, value: "Picture in Picture", comment: ""),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        ac.addAction(UIAlertAction(title: NSLocalizedString("voiceChannel.ok", tableName: nil, bundle: .main, value: "OK", comment: ""), style: .default))
        present(ac, animated: true)
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard !didAutoDismissForPiP else { return }
        didAutoDismissForPiP = true
        pipHost?.retainScreenSharePiPHost(self)
        dismiss(animated: true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        videoView.track = nil
        pipController?.delegate = nil
        pipController = nil
        pipHost?.releaseScreenSharePiPHost(self)
    }
}

private final class VoiceParticipantRowView: UIView {

    let identityKey: String
    var onExpandScreenShare: (() -> Void)?
    private let tileKind: VoiceParticipantTileKind
    private let card = UIView()
    private let videoTile = UIView()
    private let videoView = VideoView()
    private let avatarView = UIImageView()
    private let expandButton = UIButton(type: .system)
    private let footerStack = UIStackView()
    private let footerIconView = UIImageView()
    private let nameLabel = UILabel()
    private var lastAvatarURL: String?

    init(identityKey: String, tileKind: VoiceParticipantTileKind) {
        self.identityKey = identityKey
        self.tileKind = tileKind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 10
        card.clipsToBounds = true

        videoTile.translatesAutoresizingMaskIntoConstraints = false
        videoTile.clipsToBounds = true
        videoTile.layer.cornerRadius = 8
        videoTile.backgroundColor = .clear

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.layoutMode = .fill
        videoView.isPinchToZoomEnabled = false

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 36

        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.isHidden = tileKind != .screenShare
        let expandCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: expandCfg), for: .normal)
        expandButton.tintColor = .white
        expandButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        expandButton.layer.cornerRadius = 6
        expandButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        expandButton.isUserInteractionEnabled = tileKind == .screenShare
        expandButton.addAction(UIAction { [weak self] _ in
            self?.onExpandScreenShare?()
        }, for: .touchUpInside)
        expandButton.accessibilityLabel = NSLocalizedString(
            "voiceChannel.screenShareExpand", tableName: nil, bundle: .main, value: "Full screen", comment: "")

        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.axis = .horizontal
        footerStack.alignment = .center
        footerStack.spacing = 10
        footerStack.isLayoutMarginsRelativeArrangement = true
        footerStack.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)

        footerIconView.translatesAutoresizingMaskIntoConstraints = false
        footerIconView.contentMode = .scaleAspectFit
        footerIconView.setContentHuggingPriority(.required, for: .horizontal)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.numberOfLines = 1

        addSubview(card)
        card.addSubview(videoTile)
        videoTile.addSubview(videoView)
        videoTile.addSubview(avatarView)
        if tileKind == .screenShare {
            videoTile.addSubview(expandButton)
        }
        card.addSubview(footerStack)
        footerStack.addArrangedSubview(footerIconView)
        footerStack.addArrangedSubview(nameLabel)

        var constraints: [NSLayoutConstraint] = [
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            videoTile.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            videoTile.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            videoTile.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            videoTile.heightAnchor.constraint(equalTo: videoTile.widthAnchor, multiplier: 9.0 / 16.0),

            videoView.topAnchor.constraint(equalTo: videoTile.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: videoTile.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: videoTile.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: videoTile.bottomAnchor),

            avatarView.centerXAnchor.constraint(equalTo: videoTile.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: videoTile.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 72),
            avatarView.heightAnchor.constraint(equalToConstant: 72),

            footerStack.topAnchor.constraint(equalTo: videoTile.bottomAnchor),
            footerStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            footerStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            footerStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            footerIconView.widthAnchor.constraint(equalToConstant: 22),
            footerIconView.heightAnchor.constraint(equalToConstant: 22),
        ]
        if tileKind == .screenShare {
            constraints.append(contentsOf: [
                expandButton.topAnchor.constraint(equalTo: videoTile.topAnchor, constant: 8),
                expandButton.trailingAnchor.constraint(equalTo: videoTile.trailingAnchor, constant: -8),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        videoView.track = nil
    }

    /// Detach LiveKit renderer before the row leaves the hierarchy (avoids holding decoders).
    func prepareForRemoval() {
        videoView.track = nil
    }

    func applyTheme() {
        card.backgroundColor = UIColor.theme.secondary
        videoTile.backgroundColor = UIColor.theme.tertiary
        nameLabel.textColor = UIColor.theme.textStrong
        avatarView.backgroundColor = UIColor.theme.tertiary
    }

    func configure(
        displayName: String,
        micOn: Bool,
        speaking: Bool,
        avatarURL: String?,
        videoTrack: VideoTrack?,
        mirrorVideo: Bool
    ) {
        nameLabel.text = displayName
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        switch tileKind {
        case .mainVideo:
            let micName = micOn ? "mic.fill" : "mic.slash.fill"
            footerIconView.image = UIImage(systemName: micName, withConfiguration: iconCfg)
        case .screenShare:
            footerIconView.image = UIImage(systemName: "rectangle.on.rectangle", withConfiguration: iconCfg)
        }
        footerIconView.tintColor = UIColor.theme.textStrong

        if let track = videoTrack {
            avatarView.isHidden = true
            videoView.isHidden = false
            videoView.mirrorMode = mirrorVideo ? .auto : .off
            if videoView.track !== track {
                videoView.track = track
            }
        } else {
            videoView.track = nil
            videoView.isHidden = true
            avatarView.isHidden = false
        }

        if speaking {
            card.layer.borderWidth = 2
            card.layer.borderColor = UIColor.theme.textLink.cgColor
        } else {
            card.layer.borderWidth = 1
            card.layer.borderColor = UIColor.theme.borderDim.cgColor
        }
        if avatarURL != lastAvatarURL {
            lastAvatarURL = avatarURL
            avatarView.image = nil
            if let raw = avatarURL, !raw.isEmpty {
                let side = Int(72 * UIScreen.main.scale)
                let proxy = ImgproxyURL.create(from: raw, width: side, height: side)
                ImageCache.shared.loadAvatar(urlString: proxy) { [weak self] img in
                    self?.avatarView.image = img
                }
            }
        }
    }
}
