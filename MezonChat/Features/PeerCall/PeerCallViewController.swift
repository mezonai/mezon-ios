import AVFoundation
import UIKit

@MainActor
final class PeerCallViewController: UIViewController {

    private enum Entry {
        case outgoing(isVideo: Bool, remoteUserName: String, remoteAvatarURL: String?, remoteUserId: Int64, channelId: Int64)
        case incoming(payload: IncomingPeerCallPayload, remoteDisplayName: String, remoteAvatarURL: String?)
    }

    private let accountContext: AccountContext
    private let entry: Entry

    private let gradientHost = UIView()
    private let gradientLayer = CAGradientLayer()

    private let headerBar = UIView()
    private let closeHeaderButton = UIButton(type: .custom)
    private let headerRightStack = UIStackView()
    private let flipCameraButton = UIButton(type: .custom)
    private let headerVideoButton = UIButton(type: .custom)

    private let remoteVideoView = PeerCallVideoRenderView()
    private let localVideoView = PeerCallVideoRenderView()
    private let remoteBackdrop = UIView()

    private let avatarBlock = UIView()
    private let ringContainer = UIView()
    private let avatarImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let durationLabel = UILabel()

    private let remoteMutedBanner = UIView()
    private let remoteMutedIcon = UIImageView()
    private let remoteMutedLabel = UILabel()

    private let networkBanner = UILabel()

    private let footerContainer = UIView()
    private let activeFooterStack = UIStackView()
    private let speakerColumn = UIStackView()
    private let endColumn = UIStackView()
    private let micColumn = UIStackView()
    private let speakerButton = UIButton(type: .custom)
    private let speakerCaption = UILabel()
    private let endButton = UIButton(type: .custom)
    private let endCaption = UILabel()
    private let micButton = UIButton(type: .custom)
    private let micCaption = UILabel()

    private let incomingFooterStack = UIStackView()
    private let answerButton = UIButton(type: .system)
    private let declineButton = UIButton(type: .system)

    private var session: PeerWebRTCCallSession?
    private var didStartDurationTimer = false
    private var connectedDate: Date?
    private var durationTimer: Foundation.Timer?

    private var isCallConnected = false
    private var remoteVideoActive = false
    private var remoteVideoInboundActive = false
    private var remoteVideoSurfaceShown = false
    private var pendingRemoteVideoRendererSync = false
    private var localCameraOn = false
    private var localMicOn = true
    private var remoteMicOn = true
    private var hasLocalVideoTrack = false

    private var durationConstraintAvatar: NSLayoutConstraint?
    private var durationConstraintVideo: NSLayoutConstraint?
    private var mutedBannerBelowAvatar: NSLayoutConstraint?
    private var mutedBannerAboveFooter: NSLayoutConstraint?

    private var ringViews: [UIView] = []
    private var ringDisplayLink: CADisplayLink?
    private var ringPhaseStart: CFTimeInterval = 0

    private var audioRouteObserver: NSObjectProtocol?
    private var closeHeaderWidthConstraint: NSLayoutConstraint?

    init(
        context: AccountContext,
        remoteUserName: String,
        remoteAvatarURL: String?,
        remoteUserId: Int64,
        channelId: Int64,
        isVideo: Bool
    ) {
        self.accountContext = context
        self.entry = .outgoing(isVideo: isVideo, remoteUserName: remoteUserName, remoteAvatarURL: remoteAvatarURL, remoteUserId: remoteUserId, channelId: channelId)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    init(
        context: AccountContext,
        incoming payload: IncomingPeerCallPayload,
        remoteDisplayName: String,
        remoteAvatarURL: String?
    ) {
        self.accountContext = context
        self.entry = .incoming(payload: payload, remoteDisplayName: remoteDisplayName, remoteAvatarURL: remoteAvatarURL)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if case .incoming(let payload, _, _) = entry, payload.resolvedCompressedOffer() == nil {
            DispatchQueue.main.async { [weak self] in
                self?.closeFromBadPayload()
            }
            return
        }

        view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)

        gradientHost.translatesAutoresizingMaskIntoConstraints = false
        gradientHost.isUserInteractionEnabled = false
        let g0 = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1).cgColor
        let g1 = UIColor(red: 0.11, green: 0.12, blue: 0.17, alpha: 1).cgColor
        gradientLayer.colors = [g0, g1]
        gradientLayer.locations = [0, 1]
        gradientLayer.startPoint = CGPoint(x: 1, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0, y: 0)
        gradientHost.layer.addSublayer(gradientLayer)

        remoteBackdrop.translatesAutoresizingMaskIntoConstraints = false
        remoteBackdrop.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        remoteBackdrop.isHidden = true

        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.isHidden = false
        remoteVideoView.alpha = 0
        remoteVideoView.attach(track: nil)
        localVideoView.translatesAutoresizingMaskIntoConstraints = false
        localVideoView.layer.cornerRadius = 8
        localVideoView.layer.borderWidth = 1
        localVideoView.layer.borderColor = UIColor.mezonBorder.cgColor
        localVideoView.clipsToBounds = true
        localVideoView.isHidden = true

        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.backgroundColor = .clear

        styleHeaderCircle(closeHeaderButton, symbol: "xmark")
        closeHeaderButton.addTarget(self, action: #selector(closeHeaderTapped), for: .touchUpInside)

        headerRightStack.axis = .horizontal
        headerRightStack.spacing = 10
        headerRightStack.alignment = .center
        headerRightStack.translatesAutoresizingMaskIntoConstraints = false

        styleHeaderCircle(flipCameraButton, symbol: "camera.rotate.fill")
        flipCameraButton.addTarget(self, action: #selector(flipCameraTapped), for: .touchUpInside)
        flipCameraButton.isHidden = true

        styleHeaderCircle(headerVideoButton, symbol: "video.slash.fill")
        headerVideoButton.addTarget(self, action: #selector(headerVideoTapped), for: .touchUpInside)

        headerRightStack.addArrangedSubview(flipCameraButton)
        headerRightStack.addArrangedSubview(headerVideoButton)

        avatarBlock.translatesAutoresizingMaskIntoConstraints = false
        ringContainer.translatesAutoresizingMaskIntoConstraints = false
        ringContainer.backgroundColor = .clear

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 54
        avatarImageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 16)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.68)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.textAlignment = .center
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .medium)
        durationLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        durationLabel.isHidden = true

        remoteMutedBanner.translatesAutoresizingMaskIntoConstraints = false
        remoteMutedBanner.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        remoteMutedBanner.layer.cornerRadius = 20
        remoteMutedBanner.clipsToBounds = true
        remoteMutedBanner.isHidden = true

        remoteMutedIcon.translatesAutoresizingMaskIntoConstraints = false
        remoteMutedIcon.image = UIImage(systemName: "mic.slash.fill")
        remoteMutedIcon.tintColor = .white

        remoteMutedLabel.translatesAutoresizingMaskIntoConstraints = false
        remoteMutedLabel.font = .systemFont(ofSize: 14)
        remoteMutedLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        remoteMutedLabel.numberOfLines = 2
        remoteMutedLabel.textAlignment = .center

        networkBanner.translatesAutoresizingMaskIntoConstraints = false
        networkBanner.textAlignment = .center
        networkBanner.font = .systemFont(ofSize: 13, weight: .medium)
        networkBanner.textColor = .white
        networkBanner.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        networkBanner.layer.cornerRadius = 8
        networkBanner.clipsToBounds = true
        networkBanner.isHidden = true

        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 0.97)
        footerContainer.isUserInteractionEnabled = true
        activeFooterStack.axis = .horizontal
        activeFooterStack.spacing = 40
        activeFooterStack.distribution = .equalSpacing
        activeFooterStack.alignment = .center
        activeFooterStack.translatesAutoresizingMaskIntoConstraints = false

        speakerColumn.axis = .vertical
        speakerColumn.alignment = .center
        speakerColumn.spacing = 10
        endColumn.axis = .vertical
        endColumn.alignment = .center
        endColumn.spacing = 10
        micColumn.axis = .vertical
        micColumn.alignment = .center
        micColumn.spacing = 10

        configureFooterCircle(speakerButton, side: 54)
        speakerButton.addTarget(self, action: #selector(speakerTapped), for: .touchUpInside)
        speakerCaption.font = .systemFont(ofSize: 12, weight: .medium)
        speakerCaption.textColor = UIColor.white.withAlphaComponent(0.85)

        configureFooterCircle(endButton, side: 54)
        endButton.setImage(UIImage(systemName: "phone.down.fill"), for: .normal)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            speakerButton.widthAnchor.constraint(equalToConstant: 54),
            speakerButton.heightAnchor.constraint(equalToConstant: 54),
            endButton.widthAnchor.constraint(equalToConstant: 54),
            endButton.heightAnchor.constraint(equalToConstant: 54),
            micButton.widthAnchor.constraint(equalToConstant: 54),
            micButton.heightAnchor.constraint(equalToConstant: 54),
        ])

        endCaption.font = .systemFont(ofSize: 12, weight: .medium)
        endCaption.textColor = UIColor.white.withAlphaComponent(0.85)
        endCaption.text = "End"

        configureFooterCircle(micButton, side: 54)
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micCaption.font = .systemFont(ofSize: 12, weight: .medium)
        micCaption.textColor = UIColor.white.withAlphaComponent(0.85)
        micCaption.text = "Mic"

        speakerColumn.addArrangedSubview(speakerButton)
        speakerColumn.addArrangedSubview(speakerCaption)
        endColumn.addArrangedSubview(endButton)
        endColumn.addArrangedSubview(endCaption)
        micColumn.addArrangedSubview(micButton)
        micColumn.addArrangedSubview(micCaption)

        activeFooterStack.addArrangedSubview(speakerColumn)
        activeFooterStack.addArrangedSubview(endColumn)
        activeFooterStack.addArrangedSubview(micColumn)

        incomingFooterStack.axis = .horizontal
        incomingFooterStack.spacing = 18
        incomingFooterStack.distribution = .equalSpacing
        incomingFooterStack.alignment = .center
        incomingFooterStack.translatesAutoresizingMaskIntoConstraints = false

        styleCircleButton(answerButton, tint: UIColor.theme.textSuccess, systemImage: "phone.fill", diameter: 56)
        styleCircleButton(declineButton, tint: UIColor.mezonError, systemImage: "phone.down.fill", diameter: 56)
        answerButton.addTarget(self, action: #selector(answerTapped), for: .touchUpInside)
        declineButton.addTarget(self, action: #selector(declineTapped), for: .touchUpInside)

        incomingFooterStack.addArrangedSubview(answerButton)
        incomingFooterStack.addArrangedSubview(declineButton)

        view.addSubview(gradientHost)
        view.addSubview(remoteBackdrop)
        view.addSubview(remoteVideoView)
        view.addSubview(avatarBlock)
        view.addSubview(remoteMutedBanner)
        view.addSubview(durationLabel)
        view.addSubview(networkBanner)
        view.addSubview(headerBar)
        view.addSubview(localVideoView)
        view.addSubview(footerContainer)

        headerBar.addSubview(closeHeaderButton)
        headerBar.addSubview(headerRightStack)

        avatarBlock.addSubview(ringContainer)
        avatarBlock.addSubview(avatarImageView)
        avatarBlock.addSubview(titleLabel)
        avatarBlock.addSubview(subtitleLabel)

        remoteMutedBanner.addSubview(remoteMutedIcon)
        remoteMutedBanner.addSubview(remoteMutedLabel)

        footerContainer.addSubview(activeFooterStack)
        footerContainer.addSubview(incomingFooterStack)

        view.sendSubviewToBack(gradientHost)

        closeHeaderWidthConstraint = closeHeaderButton.widthAnchor.constraint(equalToConstant: 48)

        NSLayoutConstraint.activate([
            gradientHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientHost.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientHost.topAnchor.constraint(equalTo: view.topAnchor),
            gradientHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            remoteBackdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            remoteBackdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            remoteBackdrop.topAnchor.constraint(equalTo: view.topAnchor),
            remoteBackdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            remoteVideoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            remoteVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            remoteVideoView.topAnchor.constraint(equalTo: view.topAnchor),
            remoteVideoView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            headerBar.heightAnchor.constraint(equalToConstant: 48),

            closeHeaderButton.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor),
            closeHeaderButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeHeaderWidthConstraint!,
            closeHeaderButton.heightAnchor.constraint(equalToConstant: 48),

            headerRightStack.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor),
            headerRightStack.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            flipCameraButton.widthAnchor.constraint(equalToConstant: 48),
            flipCameraButton.heightAnchor.constraint(equalToConstant: 48),
            headerVideoButton.widthAnchor.constraint(equalToConstant: 48),
            headerVideoButton.heightAnchor.constraint(equalToConstant: 48),

            avatarBlock.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarBlock.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            avatarBlock.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            avatarBlock.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),

            ringContainer.centerXAnchor.constraint(equalTo: avatarBlock.centerXAnchor),
            ringContainer.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            ringContainer.widthAnchor.constraint(equalToConstant: 200),
            ringContainer.heightAnchor.constraint(equalToConstant: 200),

            avatarImageView.topAnchor.constraint(equalTo: avatarBlock.topAnchor),
            avatarImageView.centerXAnchor.constraint(equalTo: avatarBlock.centerXAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 108),
            avatarImageView.heightAnchor.constraint(equalToConstant: 108),

            titleLabel.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: avatarBlock.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: avatarBlock.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: avatarBlock.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: avatarBlock.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: avatarBlock.bottomAnchor),

            networkBanner.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 8),
            networkBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            networkBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            remoteMutedBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            remoteMutedBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            remoteMutedIcon.leadingAnchor.constraint(equalTo: remoteMutedBanner.leadingAnchor, constant: 12),
            remoteMutedIcon.centerYAnchor.constraint(equalTo: remoteMutedBanner.centerYAnchor),
            remoteMutedIcon.widthAnchor.constraint(equalToConstant: 22),
            remoteMutedIcon.heightAnchor.constraint(equalToConstant: 22),

            remoteMutedLabel.leadingAnchor.constraint(equalTo: remoteMutedIcon.trailingAnchor, constant: 8),
            remoteMutedLabel.trailingAnchor.constraint(equalTo: remoteMutedBanner.trailingAnchor, constant: -12),
            remoteMutedLabel.topAnchor.constraint(equalTo: remoteMutedBanner.topAnchor, constant: 8),
            remoteMutedLabel.bottomAnchor.constraint(equalTo: remoteMutedBanner.bottomAnchor, constant: -8),

            durationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            localVideoView.widthAnchor.constraint(equalToConstant: 118),
            localVideoView.heightAnchor.constraint(equalToConstant: 210),
            localVideoView.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 10),
            localVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerContainer.heightAnchor.constraint(equalToConstant: 152),

            activeFooterStack.centerXAnchor.constraint(equalTo: footerContainer.centerXAnchor),
            activeFooterStack.bottomAnchor.constraint(equalTo: footerContainer.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            activeFooterStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.88),

            incomingFooterStack.centerXAnchor.constraint(equalTo: footerContainer.centerXAnchor),
            incomingFooterStack.bottomAnchor.constraint(equalTo: footerContainer.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            incomingFooterStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.88),

            answerButton.widthAnchor.constraint(equalToConstant: 56),
            answerButton.heightAnchor.constraint(equalToConstant: 56),
            declineButton.widthAnchor.constraint(equalToConstant: 56),
            declineButton.heightAnchor.constraint(equalToConstant: 56),
        ])

        durationConstraintAvatar = durationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10)
        durationConstraintVideo = durationLabel.bottomAnchor.constraint(equalTo: activeFooterStack.topAnchor, constant: -12)
        mutedBannerBelowAvatar = remoteMutedBanner.topAnchor.constraint(equalTo: avatarBlock.bottomAnchor, constant: 16)
        mutedBannerAboveFooter = remoteMutedBanner.bottomAnchor.constraint(equalTo: footerContainer.topAnchor, constant: -20)

        buildRingViews()
        loadRemoteAvatar()
        applyIdleChromeColors()
        updateHeaderVideoAppearance()
        updateFooterControlAppearance()
        updateFlipVisibility()
        updateRemoteMutedBanner()
        refreshRemoteCallLayout()

        switch entry {
        case .outgoing(_, let remoteUserName, _, _, _):
            titleLabel.text = remoteUserName.isEmpty ? "Call" : remoteUserName
            subtitleLabel.text = "Calling…"
            activeFooterStack.isHidden = false
            incomingFooterStack.isHidden = true
            setCloseHeaderChromeVisible(true)
            PeerCallSoundPlayer.shared.playDialToneLoop()
        case .incoming(_, let remoteDisplayName, _):
            titleLabel.text = remoteDisplayName.isEmpty ? "Incoming call" : remoteDisplayName
            subtitleLabel.text = "Incoming…"
            activeFooterStack.isHidden = true
            incomingFooterStack.isHidden = false
            setCloseHeaderChromeVisible(false)
            PeerCallSoundPlayer.shared.playRingingLoop()
        }

        startRingPulseIfNeeded()

        buildSessionAndCallbacks()
        refreshHeaderRightVisibility()

        switch entry {
        case .incoming:
            session?.scheduleIncomingRingTimeout()
        case .outgoing:
            break
        }
    }

    deinit {
        ringDisplayLink?.invalidate()
        if let obs = audioRouteObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = gradientHost.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let session else { return }
        WebRTCCallManager.shared.attachSignalingSession(session)
        session.resyncRemoteAttachmentWithUI()
        switch entry {
        case .outgoing:
            session.beginOutgoingCall()
        case .incoming:
            break
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        durationTimer?.invalidate()
        durationTimer = nil
        stopRingAnimations()
        if isBeingDismissed || isMovingFromParent {
            PeerCallSoundPlayer.shared.stopAll()
            session?.hangUp()
            WebRTCCallManager.shared.abandonIncomingPresentation()
            CallKitManager.shared.requestEndActiveVoIPCallIfNeeded()
        }
    }

    @objc private func closeHeaderTapped() {
        let alert = UIAlertController(title: "End Call", message: "Please confirm if you would like to end the call?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "OK", style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            if case .incoming = self.entry, !self.incomingFooterStack.isHidden {
                self.declineTapped()
                return
            }
            self.session?.hangUp()
        }))
        present(alert, animated: true)
    }

    @objc private func flipCameraTapped() {
        session?.switchCamera()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.syncLocalPreviewMirror()
        }
    }

    @objc private func headerVideoTapped() {
        session?.toggleCameraEnabled()
    }

    @objc private func speakerTapped() {
        session?.toggleSpeaker()
        updateFooterControlAppearance()
    }

    @objc private func answerTapped() {
        PeerCallSoundPlayer.shared.stopRinging()
        incomingFooterStack.isHidden = true
        activeFooterStack.isHidden = false
        setCloseHeaderChromeVisible(true)
        refreshHeaderRightVisibility()
        session?.answerIncomingCall()
        updateFlipVisibility()
        updateHeaderVideoAppearance()
        syncLocalPreviewMirror()
    }

    @objc private func declineTapped() {
        PeerCallSoundPlayer.shared.stopRinging()
        session?.declineIncoming()
        WebRTCCallManager.shared.abandonIncomingPresentation()
        CallKitManager.shared.invalidateStoredVoIPPayloadOnly()
    }

    @objc private func endTapped() {
        session?.hangUp()
    }

    @objc private func micTapped() {
        session?.toggleMicrophoneEnabled()
    }

    private func closeFromBadPayload() {
        WebRTCCallManager.shared.abandonIncomingPresentation()
        dismiss(animated: true)
    }

    private var isVideoSession: Bool {
        session?.isVideoCallSession ?? {
            switch entry {
            case .outgoing(let v, _, _, _, _): return v
            case .incoming(let payload, _, _):
                guard let offer = payload.resolvedCompressedOffer() else { return false }
                let meta = IncomingPeerCallPayloadParser.callerDisplayFromCompressedOffer(offer)
                return IncomingPeerCallPayloadParser.sdpContainsVideo(meta.sdpHint)
            }
        }()
    }

    private var showRemoteVideoSurface: Bool {
        guard isCallConnected else { return false }
        return remoteVideoActive && remoteVideoInboundActive
    }

    private func restackCallLayersWithRemoteVideoUnderChrome() {
        view.sendSubviewToBack(gradientHost)
        view.insertSubview(remoteBackdrop, aboveSubview: gradientHost)
        view.insertSubview(remoteVideoView, aboveSubview: remoteBackdrop)
        var anchor: UIView = remoteVideoView
        for overlay in [avatarBlock, remoteMutedBanner, durationLabel, networkBanner, localVideoView, headerBar, footerContainer] {
            view.insertSubview(overlay, aboveSubview: anchor)
            anchor = overlay
        }
    }

    private func refreshRemoteCallLayout() {
        let showVideo = showRemoteVideoSurface
        gradientHost.isHidden = showVideo
        remoteVideoView.isHidden = !showVideo
        remoteVideoView.alpha = showVideo ? 1 : 0
        avatarBlock.isHidden = showVideo
        titleLabel.isHidden = showVideo
        restackCallLayersWithRemoteVideoUnderChrome()
        if showVideo {
            if remoteVideoActive && (!remoteVideoSurfaceShown || pendingRemoteVideoRendererSync) {
                remoteVideoView.refreshAttachedRenderers()
                pendingRemoteVideoRendererSync = false
            }
        }
        remoteVideoSurfaceShown = showVideo
    }

    private var remoteDisplayNameForBanner: String {
        switch entry {
        case .outgoing(_, let name, _, _, _): return name
        case .incoming(_, let name, _): return name
        }
    }

    private func remoteAvatarURLString() -> String? {
        switch entry {
        case .outgoing(_, _, let url, _, _): return url
        case .incoming(_, _, let url): return url
        }
    }

    private func buildSessionAndCallbacks() {
        guard let myId = Int64(accountContext.currentUser?.id ?? "") else {
            dismiss(animated: true)
            return
        }

        let callerName = accountContext.currentUser?.username ?? ""
        let callerAvatar = accountContext.currentUser?.avatarURL?.absoluteString ?? ""

        switch entry {
        case .outgoing(let isVideo, _, _, let peerId, let channelId):
            session = PeerWebRTCCallSession(
                direction: .outgoing,
                myUserId: myId,
                peerUserId: peerId,
                channelId: channelId,
                callerDisplayNameForPush: callerName,
                callerAvatarURLStringForPush: callerAvatar,
                wantsVideo: isVideo,
                incomingStartsRinging: false,
                initialCompressedOffer: nil
            )
        case .incoming(let payload, _, _):
            guard let offer = payload.resolvedCompressedOffer() else { return }
            let meta = IncomingPeerCallPayloadParser.callerDisplayFromCompressedOffer(offer)
            let video = IncomingPeerCallPayloadParser.sdpContainsVideo(meta.sdpHint)
            session = PeerWebRTCCallSession(
                direction: .incoming,
                myUserId: myId,
                peerUserId: payload.callerId,
                channelId: payload.channelId,
                callerDisplayNameForPush: callerName,
                callerAvatarURLStringForPush: callerAvatar,
                wantsVideo: video,
                incomingStartsRinging: true,
                initialCompressedOffer: offer
            )
        }

        refreshHeaderRightVisibility()

        session?.onStatusLabel = { [weak self] text in
            guard let self else { return }
            if text == "Connected" {
                self.isCallConnected = true
                self.subtitleLabel.isHidden = true
                self.didStartDurationTimer = true
                self.durationLabel.isHidden = false
                let connectedAt = Date()
                self.connectedDate = connectedAt
                self.durationTimer?.invalidate()
                let t = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] (_: Foundation.Timer) in
                    guard let self else { return }
                    let sec = max(0, Int(Date().timeIntervalSince(connectedAt)))
                    let m = sec / 60
                    let s = sec % 60
                    self.durationLabel.text = String(format: "%02d:%02d", m, s)
                }
                self.durationTimer = t
                RunLoop.main.add(t, forMode: .common)
                self.applyConnectedAvatarBorder()
                self.stopRingAnimations()
                self.updateDurationConstraints()
                self.applyIdleChromeColors()
                self.updateRemoteMutedBanner()
                self.refreshRemoteCallLayout()
            } else {
                self.subtitleLabel.text = text
                self.subtitleLabel.isHidden = false
            }
        }

        session?.onEnded = { [weak self] in
            guard let self else { return }
            self.remoteVideoSurfaceShown = false
            self.pendingRemoteVideoRendererSync = false
            self.dismiss(animated: true)
        }

        session?.onRemoteVideoInboundActive = { [weak self] active in
            guard let self else { return }
            let was = self.remoteVideoInboundActive
            self.remoteVideoInboundActive = active
            if active, !was, self.remoteVideoActive {
                self.pendingRemoteVideoRendererSync = true
            }
            self.refreshRemoteCallLayout()
            self.updateDurationConstraints()
            self.applyIdleChromeColors()
            self.updateRemoteMutedBanner()
        }

        session?.onRemoteMedia = { [weak self] mic in
            guard let self else { return }
            self.remoteMicOn = mic
            self.refreshRemoteCallLayout()
            self.updateRemoteMutedBanner()
            self.updateDurationConstraints()
            self.applyIdleChromeColors()
        }

        session?.onLocalMedia = { [weak self] mic, cam in
            guard let self else { return }
            self.localMicOn = mic
            self.localCameraOn = cam
            self.localVideoView.isHidden = !cam
            self.updateFooterControlAppearance()
            self.updateHeaderVideoAppearance()
            self.updateFlipVisibility()
            self.syncLocalPreviewMirror()
        }

        session?.onNetworkBanner = { [weak self] text in
            guard let self else { return }
            if let text, !text.isEmpty {
                self.networkBanner.text = "  \(text)  "
                self.networkBanner.isHidden = false
            } else {
                self.networkBanner.isHidden = true
            }
        }

        session?.onRemoteVideoTrack = { [weak self] track in
            guard let self else { return }
            self.remoteVideoView.attach(track: track)
            self.remoteVideoActive = track != nil
            if track == nil {
                self.remoteVideoInboundActive = false
            }
            if track != nil, self.isVideoSession {
                self.pendingRemoteVideoRendererSync = true
            }
            self.refreshRemoteCallLayout()
            self.updateDurationConstraints()
            self.applyIdleChromeColors()
            self.updateRemoteMutedBanner()
            if track != nil {
                DispatchQueue.main.async { [weak self] in
                    self?.remoteVideoView.setNeedsLayout()
                    self?.remoteVideoView.layoutIfNeeded()
                }
            }
        }

        session?.onLocalVideoTrack = { [weak self] track in
            guard let self else { return }
            self.localVideoView.attach(track: track)
            self.localVideoView.isHidden = track == nil
            self.hasLocalVideoTrack = track != nil
            self.updateFlipVisibility()
            self.syncLocalPreviewMirror()
        }

        if audioRouteObserver == nil {
            audioRouteObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.updateFooterControlAppearance()
            }
        }
        updateFooterControlAppearance()
    }

    private func refreshHeaderRightVisibility() {
        headerRightStack.isHidden = !isVideoSession || !incomingFooterStack.isHidden
    }

    private func setCloseHeaderChromeVisible(_ visible: Bool) {
        closeHeaderButton.isHidden = !visible
        closeHeaderButton.isUserInteractionEnabled = visible
        closeHeaderWidthConstraint?.constant = visible ? 48 : 0
    }

    private func loadRemoteAvatar() {
        let urlString = remoteAvatarURLString() ?? ""
        guard !urlString.isEmpty else {
            avatarImageView.image = UIImage(systemName: "person.fill")
            avatarImageView.tintColor = UIColor.white.withAlphaComponent(0.4)
            avatarImageView.contentMode = .center
            return
        }
        ImageCache.shared.loadAvatar(urlString: urlString) { [weak self] image in
            guard let self else { return }
            if let image {
                self.avatarImageView.image = image
                self.avatarImageView.contentMode = .scaleAspectFill
                self.avatarImageView.tintColor = nil
            }
        }
    }

    private func buildRingViews() {
        let sizes: [CGFloat] = [50, 160, 180]
        let dim = UIColor.white.withAlphaComponent(0.22)
        for size in sizes {
            let ring = UIView()
            ring.translatesAutoresizingMaskIntoConstraints = false
            ring.isUserInteractionEnabled = false
            ring.layer.borderWidth = 2
            ring.layer.borderColor = dim.cgColor
            ring.layer.cornerRadius = size / 2
            ring.alpha = 0
            ringContainer.addSubview(ring)
            NSLayoutConstraint.activate([
                ring.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
                ring.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),
                ring.widthAnchor.constraint(equalToConstant: size),
                ring.heightAnchor.constraint(equalToConstant: size),
            ])
            ringViews.append(ring)
        }
    }

    private func startRingPulseIfNeeded() {
        stopRingDisplayLink()
        guard !isCallConnected, ringViews.count == 3 else { return }
        ringPhaseStart = CACurrentMediaTime()
        let dl = CADisplayLink(target: self, selector: #selector(ringPhaseTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        }
        dl.add(to: .main, forMode: .common)
        ringDisplayLink = dl
    }

    @objc private func ringPhaseTick() {
        guard !isCallConnected else {
            stopRingDisplayLink()
            return
        }
        let period = 3.5
        let phase = CGFloat((CACurrentMediaTime() - ringPhaseStart).truncatingRemainder(dividingBy: period) / period)
        let delays: [CGFloat] = [0, 0.25, 0.5]
        for (idx, ring) in ringViews.enumerated() {
            let delay = idx < delays.count ? delays[idx] : 0
            let dv = ringDelayedValue(phase: phase, delay: delay)
            let scale = 1 + 1.8 * dv
            ring.transform = CGAffineTransform(scaleX: scale, y: scale)
            ring.alpha = ringOpacity(delayedValue: dv)
        }
    }

    private func ringDelayedValue(phase: CGFloat, delay: CGFloat) -> CGFloat {
        if phase < delay { return 0 }
        if phase < delay + 0.4 {
            return (phase - delay) / 0.4
        }
        return 1
    }

    private func ringOpacity(delayedValue: CGFloat) -> CGFloat {
        if delayedValue <= 0 { return 0 }
        if delayedValue < 0.1 {
            return (delayedValue / 0.1) * 0.8
        }
        if delayedValue < 0.6 {
            let t = (delayedValue - 0.1) / 0.5
            return 0.8 + t * (0.3 - 0.8)
        }
        if delayedValue < 1 {
            let t = (delayedValue - 0.6) / 0.4
            return 0.3 + t * (-0.3)
        }
        return 0
    }

    private func stopRingDisplayLink() {
        ringDisplayLink?.invalidate()
        ringDisplayLink = nil
    }

    private func stopRingAnimations() {
        stopRingDisplayLink()
        for ring in ringViews {
            ring.transform = .identity
            ring.alpha = 0
        }
    }

    private func applyConnectedAvatarBorder() {
        avatarImageView.layer.borderWidth = 4
        avatarImageView.layer.borderColor = UIColor.theme.textSuccess.cgColor
    }

    private func applyIdleChromeColors() {
        let onRemoteVideo = showRemoteVideoSurface
        let fg = UIColor.white
        let fgMuted = UIColor.white.withAlphaComponent(0.68)
        let fgTimer = UIColor.white.withAlphaComponent(0.92)
        titleLabel.textColor = fg
        if !isCallConnected {
            subtitleLabel.textColor = fgMuted
        }
        durationLabel.textColor = onRemoteVideo ? fgMuted : fgTimer
        let footerCaption = UIColor.white.withAlphaComponent(0.85)
        speakerCaption.textColor = footerCaption
        endCaption.textColor = footerCaption
        micCaption.textColor = footerCaption
    }

    private func updateDurationConstraints() {
        durationConstraintAvatar?.isActive = false
        durationConstraintVideo?.isActive = false
        if !isCallConnected || durationLabel.isHidden {
            return
        }
        if showRemoteVideoSurface {
            durationConstraintVideo?.isActive = true
        } else {
            durationConstraintAvatar?.isActive = true
        }
    }

    private func updateRemoteMutedBanner() {
        mutedBannerBelowAvatar?.isActive = false
        mutedBannerAboveFooter?.isActive = false
        let show = isCallConnected && !remoteMicOn
        remoteMutedBanner.isHidden = !show
        remoteMutedLabel.text = "\(remoteDisplayNameForBanner) turned the microphone off"
        if show {
            if showRemoteVideoSurface {
                mutedBannerAboveFooter?.isActive = true
            } else {
                mutedBannerBelowAvatar?.isActive = true
            }
        }
    }

    private func updateFooterControlAppearance() {
        let speakerFill = UIColor(white: 0.26, alpha: 1)
        let speakerRouteOn = session?.isSpeakerOn ?? false
        speakerButton.backgroundColor = speakerRouteOn ? UIColor(white: 0.34, alpha: 1) : speakerFill
        speakerButton.tintColor = .white
        let av = AVAudioSession.sharedInstance()
        let spkName: String
        if let port = av.currentRoute.outputs.first?.portType {
            switch port {
            case .headphones, .headsetMic:
                spkName = "headphones"
            default:
                spkName = Self.peerCallFooterSpeakerSymbol(speakerRouteOn: speakerRouteOn, session: av)
            }
        } else {
            spkName = Self.peerCallFooterSpeakerSymbol(speakerRouteOn: speakerRouteOn, session: av)
        }
        speakerButton.setImage(UIImage(systemName: spkName), for: .normal)
        let spkrTitle = NSLocalizedString(
            "peerCall.audioRouteSpeaker", tableName: nil, bundle: .main, value: "Speaker", comment: "")
        let earTitle = NSLocalizedString(
            "peerCall.audioRouteEarpiece", tableName: nil, bundle: .main, value: "Earpiece", comment: "")
        speakerCaption.text = speakerRouteOn ? spkrTitle : earTitle
        speakerButton.accessibilityLabel = speakerRouteOn ? spkrTitle : earTitle

        endButton.backgroundColor = UIColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1)
        endButton.tintColor = .white

        if localMicOn {
            micButton.backgroundColor = .white
            micButton.tintColor = .black
        } else {
            micButton.backgroundColor = speakerFill
            micButton.tintColor = .white
        }
        micButton.setImage(UIImage(systemName: localMicOn ? "mic.fill" : "mic.slash.fill"), for: .normal)
    }

    private static func peerCallFooterSpeakerSymbol(speakerRouteOn: Bool, session: AVAudioSession) -> String {
        if Self.peerCallAudioRouteHasBluetooth(session), !speakerRouteOn {
            return "headphones"
        }
        if speakerRouteOn {
            return "speaker.wave.2.fill"
        }
        return "iphone.radiowaves.left.and.right"
    }

    private static func peerCallAudioRouteHasBluetooth(_ session: AVAudioSession) -> Bool {
        for output in session.currentRoute.outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return true
            default:
                break
            }
        }
        for input in session.availableInputs ?? [] {
            switch input.portType {
            case .bluetoothHFP, .bluetoothLE:
                return true
            default:
                break
            }
        }
        return false
    }

    private func updateHeaderVideoAppearance() {
        let pill = UIColor.white.withAlphaComponent(0.18)
        headerVideoButton.backgroundColor = pill
        headerVideoButton.tintColor = .white
        let img = localCameraOn ? UIImage(systemName: "video.fill") : UIImage(systemName: "video.slash.fill")
        headerVideoButton.setImage(img, for: .normal)
    }

    private func updateFlipVisibility() {
        let pill = UIColor.white.withAlphaComponent(0.18)
        flipCameraButton.backgroundColor = pill
        flipCameraButton.tintColor = .white
        flipCameraButton.isHidden = !isVideoSession || !localCameraOn || !hasLocalVideoTrack || incomingFooterStack.isHidden == false
    }

    private func syncLocalPreviewMirror() {
        localVideoView.isMirrored = session?.isUsingFrontCamera ?? true
    }

    private func styleHeaderCircle(_ b: UIButton, symbol: String) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        b.tintColor = .white
        b.layer.cornerRadius = 24
        b.clipsToBounds = true
        b.setImage(UIImage(systemName: symbol), for: .normal)
        b.imageView?.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    }

    private func configureFooterCircle(_ b: UIButton, side: CGFloat) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.layer.cornerRadius = side / 2
        b.clipsToBounds = true
        b.imageView?.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
    }

    private func styleCircleButton(_ b: UIButton, tint: UIColor, systemImage: String, diameter: CGFloat = 56) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = .clear
        b.tintColor = tint
        b.layer.cornerRadius = diameter / 2
        let img = UIImage(systemName: systemImage)
        b.setImage(img, for: .normal)
        b.imageView?.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
    }
}
