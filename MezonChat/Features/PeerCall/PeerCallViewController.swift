import AVFoundation
import AsyncDisplayKit
import UIKit

@MainActor
final class PeerCallViewController: ViewController {

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

    private let remoteMutedBanner = UIStackView()
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
    private var userDidExplicitlyEnd = false
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
    private var durationTopBelowMutedBanner: NSLayoutConstraint?
    private var mutedBannerBelowAvatar: NSLayoutConstraint?
    private var mutedBannerAboveFooter: NSLayoutConstraint?

    private var ringViews: [UIView] = []
    private var ringDisplayLink: CADisplayLink?
    private var ringPhaseStart: CFTimeInterval = 0

    private var audioRouteObserver: NSObjectProtocol?
    private var closeHeaderWidthConstraint: NSLayoutConstraint?
    private var callKitMatchedIncomingObserver: NSObjectProtocol?
    private let skipIncomingRingingUI: Bool
    private var connectingSubtitleShownAt: Date?
    private var pendingConnectedChromeWorkItem: DispatchWorkItem?

    init(
        context: AccountContext,
        remoteUserName: String,
        remoteAvatarURL: String?,
        remoteUserId: Int64,
        channelId: Int64,
        isVideo: Bool
    ) {
        self.skipIncomingRingingUI = false
        self.accountContext = context
        self.entry = .outgoing(isVideo: isVideo, remoteUserName: remoteUserName, remoteAvatarURL: remoteAvatarURL, remoteUserId: remoteUserId, channelId: channelId)
        super.init(navigationBarPresentationData: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
        prefersOnScreenNavigationHidden = true
    }

    init(
        context: AccountContext,
        incoming payload: IncomingPeerCallPayload,
        remoteDisplayName: String,
        remoteAvatarURL: String?,
        skipIncomingRingingUI: Bool = false
    ) {
        self.skipIncomingRingingUI = skipIncomingRingingUI
        self.accountContext = context
        self.entry = .incoming(payload: payload, remoteDisplayName: remoteDisplayName, remoteAvatarURL: remoteAvatarURL)
        super.init(navigationBarPresentationData: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
        prefersOnScreenNavigationHidden = true
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if case .incoming(let payload, _, _) = entry {
            guard payload.channelId != 0, payload.callerId != 0 else {
                DispatchQueue.main.async { [weak self] in
                    self?.closeFromBadPayload()
                }
                return
            }
            if !skipIncomingRingingUI {
                callKitMatchedIncomingObserver = NotificationCenter.default.addObserver(
                    forName: .mezonCallKitMatchedExistingIncoming,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    self?.handleCallKitMatchedExistingIncoming(note)
                }
            }
        }

        gradientHost.translatesAutoresizingMaskIntoConstraints = false
        gradientHost.isUserInteractionEnabled = false
        gradientLayer.locations = [0, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0, y: 1)
        gradientHost.layer.addSublayer(gradientLayer)

        remoteBackdrop.translatesAutoresizingMaskIntoConstraints = false
        remoteBackdrop.isHidden = true
        remoteBackdrop.isUserInteractionEnabled = false

        remoteVideoView.translatesAutoresizingMaskIntoConstraints = false
        remoteVideoView.isHidden = false
        remoteVideoView.alpha = 0
        remoteVideoView.attach(track: nil)
        localVideoView.translatesAutoresizingMaskIntoConstraints = false
        localVideoView.layer.cornerRadius = 0
        localVideoView.layer.borderWidth = 1
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
        avatarImageView.layer.cornerRadius = 50

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .systemFont(ofSize: 16)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.textAlignment = .center
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        durationLabel.isHidden = true
        durationLabel.numberOfLines = 1
        durationLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        remoteMutedBanner.axis = .horizontal
        remoteMutedBanner.alignment = .center
        remoteMutedBanner.spacing = 8
        remoteMutedBanner.isLayoutMarginsRelativeArrangement = true
        remoteMutedBanner.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        remoteMutedBanner.translatesAutoresizingMaskIntoConstraints = false
        remoteMutedBanner.layer.cornerRadius = 20
        remoteMutedBanner.clipsToBounds = true
        remoteMutedBanner.isHidden = true
        remoteMutedBanner.setContentHuggingPriority(.required, for: .horizontal)
        remoteMutedBanner.setContentCompressionResistancePriority(.required, for: .vertical)

        remoteMutedIcon.image = UIImage(systemName: "mic.slash.fill")
        remoteMutedIcon.contentMode = .scaleAspectFit
        remoteMutedIcon.setContentHuggingPriority(.required, for: .horizontal)

        remoteMutedLabel.font = .systemFont(ofSize: 14)
        remoteMutedLabel.numberOfLines = 2
        remoteMutedLabel.textAlignment = .natural
        remoteMutedLabel.lineBreakMode = .byWordWrapping
        remoteMutedLabel.setContentHuggingPriority(.required, for: .horizontal)

        networkBanner.translatesAutoresizingMaskIntoConstraints = false
        networkBanner.textAlignment = .center
        networkBanner.font = .systemFont(ofSize: 13, weight: .medium)
        networkBanner.layer.cornerRadius = 8
        networkBanner.clipsToBounds = true
        networkBanner.isHidden = true

        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.backgroundColor = .clear
        footerContainer.isUserInteractionEnabled = true
        activeFooterStack.axis = .horizontal
        activeFooterStack.spacing = 30
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
        speakerCaption.font = .systemFont(ofSize: 12, weight: .semibold)

        configureFooterCircle(endButton, side: 54)
        endButton.setImage(UIImage(systemName: "phone.down.fill"), for: .normal)
        endButton.addTarget(self, action: #selector(endTapped), for: .touchUpInside)

        endCaption.font = .systemFont(ofSize: 12, weight: .semibold)
        endCaption.text = PeerCallLocalizedStrings.actionEnd

        configureFooterCircle(micButton, side: 54)
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        micCaption.font = .systemFont(ofSize: 12, weight: .semibold)
        micCaption.text = PeerCallLocalizedStrings.actionMic

        let sbW = speakerButton.widthAnchor.constraint(equalToConstant: 54)
        let sbH = speakerButton.heightAnchor.constraint(equalToConstant: 54)
        let ebW = endButton.widthAnchor.constraint(equalToConstant: 54)
        let ebH = endButton.heightAnchor.constraint(equalToConstant: 54)
        let mbW = micButton.widthAnchor.constraint(equalToConstant: 54)
        let mbH = micButton.heightAnchor.constraint(equalToConstant: 54)
        for c in [sbW, sbH, ebW, ebH, mbW, mbH] {
            c.priority = .defaultHigh
        }
        NSLayoutConstraint.activate([sbW, sbH, ebW, ebH, mbW, mbH])

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

        remoteMutedBanner.addArrangedSubview(remoteMutedIcon)
        remoteMutedBanner.addArrangedSubview(remoteMutedLabel)

        NSLayoutConstraint.activate([
            remoteMutedIcon.widthAnchor.constraint(equalToConstant: 22),
            remoteMutedIcon.heightAnchor.constraint(equalToConstant: 22),
        ])

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
            avatarImageView.widthAnchor.constraint(equalToConstant: 100),
            avatarImageView.heightAnchor.constraint(equalToConstant: 100),

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

            remoteMutedBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            remoteMutedBanner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            remoteMutedBanner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
            remoteMutedBanner.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),

            durationLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            localVideoView.widthAnchor.constraint(equalToConstant: 140),
            localVideoView.heightAnchor.constraint(equalToConstant: 165),
            localVideoView.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 10),
            localVideoView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerContainer.heightAnchor.constraint(equalToConstant: 152),

            activeFooterStack.centerXAnchor.constraint(equalTo: footerContainer.centerXAnchor),
            activeFooterStack.bottomAnchor.constraint(equalTo: footerContainer.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            activeFooterStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75),

            incomingFooterStack.centerXAnchor.constraint(equalTo: footerContainer.centerXAnchor),
            incomingFooterStack.bottomAnchor.constraint(equalTo: footerContainer.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            incomingFooterStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75),

            answerButton.widthAnchor.constraint(equalToConstant: 56),
            answerButton.heightAnchor.constraint(equalToConstant: 56),
            declineButton.widthAnchor.constraint(equalToConstant: 56),
            declineButton.heightAnchor.constraint(equalToConstant: 56),
        ])

        durationConstraintAvatar = durationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10)
        let dcVideo = durationLabel.bottomAnchor.constraint(equalTo: activeFooterStack.topAnchor, constant: -32)
        dcVideo.priority = .required
        durationConstraintVideo = dcVideo
        let topBelowMuted = durationLabel.topAnchor.constraint(equalTo: remoteMutedBanner.bottomAnchor, constant: 14)
        topBelowMuted.priority = .required
        durationTopBelowMutedBanner = topBelowMuted
        mutedBannerBelowAvatar = remoteMutedBanner.topAnchor.constraint(equalTo: avatarBlock.bottomAnchor, constant: 16)
        mutedBannerAboveFooter = remoteMutedBanner.bottomAnchor.constraint(equalTo: footerContainer.topAnchor, constant: -48)

        buildRingViews()
        loadRemoteAvatar()
        applyIdleChromeColors()
        updateHeaderVideoAppearance()
        updateFlipVisibility()
        updateRemoteMutedBanner()
        refreshRemoteCallLayout()

        switch entry {
        case .outgoing(_, let remoteUserName, _, _, _):
            titleLabel.text = remoteUserName.isEmpty ? PeerCallLocalizedStrings.titleDefaultOutgoing : remoteUserName
            subtitleLabel.text = PeerCallLocalizedStrings.statusRinging
            activeFooterStack.isHidden = false
            incomingFooterStack.isHidden = true
            setCloseHeaderChromeVisible(false)
            PeerCallSoundPlayer.shared.playDialToneLoop()
        case .incoming(_, let remoteDisplayName, _):
            titleLabel.text = remoteDisplayName.isEmpty ? PeerCallLocalizedStrings.titleDefaultIncoming : remoteDisplayName
            if skipIncomingRingingUI {
                subtitleLabel.text = PeerCallLocalizedStrings.statusConnecting
                connectingSubtitleShownAt = Date()
                activeFooterStack.isHidden = false
                incomingFooterStack.isHidden = true
                setCloseHeaderChromeVisible(true)
                PeerCallSoundPlayer.shared.stopAll()
            } else {
                subtitleLabel.text = PeerCallLocalizedStrings.statusIncoming
                activeFooterStack.isHidden = true
                incomingFooterStack.isHidden = false
                setCloseHeaderChromeVisible(false)
                PeerCallSoundPlayer.shared.playRingingLoop()
            }
        }

        updateFooterControlAppearance()
        updateFlipVisibility()
        startRingPulseIfNeeded()

        buildSessionAndCallbacks()
        refreshHeaderRightVisibility()

        applyThemeColors()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )

        switch entry {
        case .incoming:
            if !skipIncomingRingingUI {
                session?.scheduleIncomingRingTimeout()
            }
        case .outgoing:
            break
        }
    }

    deinit {
        ringDisplayLink?.invalidate()
        if let obs = audioRouteObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let o = callKitMatchedIncomingObserver {
            NotificationCenter.default.removeObserver(o)
        }
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
    }

    @objc private func handleThemeChange() {
        applyThemeColors()
        applyIdleChromeColors()
        updateFooterControlAppearance()
        updateHeaderVideoAppearance()
        updateFlipVisibility()
        if isCallConnected {
            applyConnectedAvatarBorderInstant()
        }
    }

    private func applyThemeColors() {
        let theme = UIColor.theme
        view.backgroundColor = theme.primary
        gradientLayer.colors = [theme.primary.cgColor, theme.primaryGradient.cgColor]
        remoteBackdrop.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        localVideoView.layer.borderColor = theme.border.cgColor
        avatarImageView.backgroundColor = theme.secondaryLight
        if avatarImageView.contentMode == .center {
            avatarImageView.tintColor = theme.iconSecondary
        }
        remoteMutedBanner.backgroundColor = theme.secondaryWeight.withAlphaComponent(0.85)
        remoteMutedIcon.tintColor = theme.iconPrimary
        remoteMutedLabel.textColor = theme.text
        networkBanner.backgroundColor = theme.secondaryWeight.withAlphaComponent(0.85)
        networkBanner.textColor = theme.text
        for ring in ringViews {
            ring.layer.borderColor = theme.border.cgColor
        }
        styleHeaderCircle(closeHeaderButton, symbol: "xmark")
        styleHeaderCircle(flipCameraButton, symbol: "camera.rotate.fill")
        styleHeaderCircle(headerVideoButton, symbol: localCameraOn ? "video.fill" : "video.slash.fill")
    }

    private static let peerCallSuccessAccent = UIColor(red: 76 / 255, green: 175 / 255, blue: 80 / 255, alpha: 1)

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = gradientHost.bounds
        if !remoteMutedBanner.isHidden {
            let w = max(100, view.bounds.width - 32 - remoteMutedBanner.layoutMargins.left - remoteMutedBanner.layoutMargins.right - remoteMutedBanner.spacing - 22)
            if abs(remoteMutedLabel.preferredMaxLayoutWidth - w) > 0.5 {
                remoteMutedLabel.preferredMaxLayoutWidth = w
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let session else {
            return
        }
        WebRTCCallManager.shared.attachSignalingSession(session)
        session.resyncRemoteAttachmentWithUI()
        switch entry {
        case .outgoing:
            session.beginOutgoingCall()
        case .incoming:
            if skipIncomingRingingUI {
                subtitleLabel.text = PeerCallLocalizedStrings.statusConnecting
                subtitleLabel.isHidden = false
                durationLabel.isHidden = true
                connectingSubtitleShownAt = connectingSubtitleShownAt ?? Date()
                session.answerIncomingCall()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pendingConnectedChromeWorkItem?.cancel()
        pendingConnectedChromeWorkItem = nil
        durationTimer?.invalidate()
        durationTimer = nil
        stopRingAnimations()
        guard isBeingDismissed || isMovingFromParent else { return }
        let shouldEnd = userDidExplicitlyEnd || (session?.didEstablishMediaConnection == true)
        guard shouldEnd else {
            return
        }
        PeerCallSoundPlayer.shared.stopAll()
        session?.hangUp()
        WebRTCCallManager.shared.abandonIncomingPresentation()
        CallKitManager.shared.requestEndActiveVoIPCallIfNeeded()
    }

    @objc private func closeHeaderTapped() {
        let alert = UIAlertController(
            title: PeerCallLocalizedStrings.alertEndCallTitle,
            message: PeerCallLocalizedStrings.alertEndCallMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: PeerCallLocalizedStrings.actionCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: PeerCallLocalizedStrings.actionOK, style: .destructive, handler: { [weak self] _ in
            guard let self else { return }
            if case .incoming = self.entry, !self.incomingFooterStack.isHidden {
                self.declineTapped()
                return
            }
            self.userDidExplicitlyEnd = true
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

    private func handleCallKitMatchedExistingIncoming(_ note: Notification) {
        guard case .incoming(let payload, _, _) = entry else { return }
        guard let nCh = note.userInfo?["channelId"] as? NSNumber,
              let nCaller = note.userInfo?["callerId"] as? NSNumber else { return }
        guard nCh.int64Value == payload.channelId && nCaller.int64Value == payload.callerId else { return }
        applyIncomingAnswerChromeOnly()
    }

    private func applyIncomingAnswerChromeOnly() {
        PeerCallSoundPlayer.shared.stopRinging()
        incomingFooterStack.isHidden = true
        activeFooterStack.isHidden = false
        setCloseHeaderChromeVisible(true)
        refreshHeaderRightVisibility()
        updateFlipVisibility()
        updateHeaderVideoAppearance()
        syncLocalPreviewMirror()
    }

    @objc private func answerTapped() {
        applyIncomingAnswerChromeOnly()
        session?.answerIncomingCall()
    }

    @objc private func declineTapped() {
        userDidExplicitlyEnd = true
        PeerCallSoundPlayer.shared.stopRinging()
        session?.declineIncoming()
        WebRTCCallManager.shared.abandonIncomingPresentation()
        CallKitManager.shared.invalidateStoredVoIPPayloadOnly()
        CallKitManager.shared.requestEndActiveVoIPCallIfNeeded()
    }

    @objc private func endTapped() {
        userDidExplicitlyEnd = true
        session?.hangUp()
    }

    @objc private func micTapped() {
        session?.toggleMicrophoneEnabled()
    }

    private func leaveCallScreen(animated: Bool) {
        if let nav = navigationController,
           nav.viewControllers.contains(where: { $0 === self }),
           nav.viewControllers.count > 1 {
            nav.popViewController(animated: animated)
            return
        }
        dismiss(animated: animated)
    }

    private func closeFromBadPayload() {
        WebRTCCallManager.shared.abandonIncomingPresentation()
        leaveCallScreen(animated: true)
    }

    private func applyConnectedCallChrome(connectedAt: Date) {
        pendingConnectedChromeWorkItem = nil
        guard !isCallConnected else { return }
        isCallConnected = true
        triggerConnectedHaptic()
        UIView.transition(with: subtitleLabel, duration: 0.22, options: .transitionCrossDissolve, animations: {
            self.subtitleLabel.isHidden = true
        })
        didStartDurationTimer = true
        durationLabel.alpha = 0
        durationLabel.isHidden = false
        durationLabel.text = "00:00"
        UIView.animate(withDuration: 0.32, delay: 0.08, options: [.curveEaseOut]) {
            self.durationLabel.alpha = 1
        }
        connectedDate = connectedAt
        durationTimer?.invalidate()
        let t = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] (_: Foundation.Timer) in
            guard let self else { return }
            let sec = max(0, Int(Date().timeIntervalSince(connectedAt)))
            let m = sec / 60
            let s = sec % 60
            self.durationLabel.text = String(format: "%02d:%02d", m, s)
        }
        durationTimer = t
        RunLoop.main.add(t, forMode: .common)
        applyConnectedAvatarBorder()
        playAvatarConnectBloom()
        stopRingAnimations()
        applyIdleChromeColors()
        updateRemoteMutedBanner()
        refreshRemoteCallLayout()
    }

    private func triggerConnectedHaptic() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
    }

    private func playAvatarConnectBloom() {
        guard avatarImageView.bounds.width > 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.playAvatarConnectBloom()
            }
            return
        }
        let bloom = CALayer()
        bloom.frame = avatarImageView.bounds
        bloom.cornerRadius = avatarImageView.layer.cornerRadius
        bloom.borderWidth = 3
        bloom.borderColor = Self.peerCallSuccessAccent.cgColor
        bloom.backgroundColor = UIColor.clear.cgColor
        avatarImageView.layer.addSublayer(bloom)

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 1.7
        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.85
        opacityAnim.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim]
        group.duration = 0.9
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        bloom.add(group, forKey: "connectBloom")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak bloom] in
            bloom?.removeFromSuperlayer()
        }
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

    private func resolveLocalUserIdForPeerCall() -> Int64? {
        if let s = accountContext.currentUser?.id, let v = Int64(s), v != 0 {
            return v
        }
        if let s = SessionStore.load()?.userId, let v = Int64(s), v != 0 {
            return v
        }
        return nil
    }

    private func buildSessionAndCallbacks() {
        guard let myId = resolveLocalUserIdForPeerCall() else {
            leaveCallScreen(animated: true)
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
            if let warm = WebRTCCallManager.shared.consumePreWarmedIncomingSession(
                channelId: payload.channelId, callerId: payload.callerId
            ) {
                session = warm
            } else {
                let offer = payload.resolvedCompressedOffer()
                let video = false
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
        }

        refreshHeaderRightVisibility()

        session?.onCallMediaConnectedAt = { [weak self] connectedAt in
            guard let self else { return }
            self.pendingConnectedChromeWorkItem?.cancel()
            let minConnectingVisibility: TimeInterval = self.skipIncomingRingingUI ? 0.45 : 0
            let anchor = self.connectingSubtitleShownAt ?? connectedAt
            let delay = max(0, minConnectingVisibility - Date().timeIntervalSince(anchor))
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.view.window != nil else { return }
                guard !self.userDidExplicitlyEnd else { return }
                self.applyConnectedCallChrome(connectedAt: connectedAt)
            }
            self.pendingConnectedChromeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        session?.onStatusLabel = { [weak self] text in
            guard let self else { return }
            if text == PeerCallLocalizedStrings.statusConnected {
                return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            self.subtitleLabel.text = text
            self.subtitleLabel.isHidden = false
            if trimmed == PeerCallLocalizedStrings.statusConnecting {
                self.connectingSubtitleShownAt = Date()
            }
        }

        session?.onEnded = { [weak self] in
            guard let self else { return }
            self.userDidExplicitlyEnd = true
            self.remoteVideoSurfaceShown = false
            self.pendingRemoteVideoRendererSync = false
            // Cold-launched-for-VoIP minimal flow: skip the modal dismiss
            // animation and tear the process down as soon as the quit signal
            // has had a moment to flush. The user explicitly asked for an
            // immediate kill on end-call to avoid stale-state bugs from
            // re-using a process whose only purpose was the VoIP push.
            if VoIPMinimalCallBootstrap.isMinimalChromeActive {
                CallKitManager.shared.endActiveCallAndExitProcessFastIfMinimalFlow()
                return
            }
            self.leaveCallScreen(animated: true)
        }

        session?.onRemoteVideoInboundActive = { [weak self] active in
            guard let self else { return }
            let was = self.remoteVideoInboundActive
            self.remoteVideoInboundActive = active
            if active, !was, self.remoteVideoActive {
                self.pendingRemoteVideoRendererSync = true
            }
            self.refreshRemoteCallLayout()
            self.applyIdleChromeColors()
            self.updateRemoteMutedBanner()
        }

        session?.onRemoteMedia = { [weak self] mic in
            guard let self else { return }
            self.remoteMicOn = mic
            self.refreshRemoteCallLayout()
            self.updateRemoteMutedBanner()
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
            if track != nil {
                self.pendingRemoteVideoRendererSync = true
            }
            self.refreshRemoteCallLayout()
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
        headerRightStack.isHidden = !incomingFooterStack.isHidden
    }

    private func setCloseHeaderChromeVisible(_: Bool) {
        closeHeaderButton.isHidden = true
        closeHeaderButton.isUserInteractionEnabled = false
        closeHeaderWidthConstraint?.constant = 0
    }

    private func loadRemoteAvatar() {
        let urlString = remoteAvatarURLString() ?? ""
        guard !urlString.isEmpty else {
            avatarImageView.image = UIImage(systemName: "person.fill")
            avatarImageView.tintColor = UIColor.theme.iconSecondary
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
        let dim = UIColor.theme.border
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
        if skipIncomingRingingUI { return }
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
        let layer = avatarImageView.layer
        let targetColor = Self.peerCallSuccessAccent.cgColor
        let widthAnim = CABasicAnimation(keyPath: "borderWidth")
        widthAnim.fromValue = layer.borderWidth
        widthAnim.toValue = 4
        widthAnim.duration = 0.4
        widthAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let colorAnim = CABasicAnimation(keyPath: "borderColor")
        colorAnim.fromValue = layer.borderColor ?? UIColor.clear.cgColor
        colorAnim.toValue = targetColor
        colorAnim.duration = 0.4
        layer.borderWidth = 4
        layer.borderColor = targetColor
        layer.add(widthAnim, forKey: "borderWidthAnim")
        layer.add(colorAnim, forKey: "borderColorAnim")
    }

    private func applyConnectedAvatarBorderInstant() {
        let layer = avatarImageView.layer
        layer.borderWidth = 4
        layer.borderColor = Self.peerCallSuccessAccent.cgColor
    }

    private func applyIdleChromeColors() {
        let theme = UIColor.theme
        titleLabel.textColor = theme.textStrong
        if !isCallConnected {
            subtitleLabel.textColor = theme.text.withAlphaComponent(0.7)
        }
        durationLabel.textColor = theme.textStrong
        speakerCaption.textColor = theme.text
        endCaption.textColor = theme.text
        micCaption.textColor = theme.text
    }

    private func updateDurationConstraints() {
        durationConstraintAvatar?.isActive = false
        durationConstraintVideo?.isActive = false
        durationTopBelowMutedBanner?.isActive = false
        durationConstraintVideo?.priority = .required
        if !isCallConnected || durationLabel.isHidden {
            return
        }
        if showRemoteVideoSurface {
            durationConstraintVideo?.isActive = true
            if !remoteMicOn {
                durationTopBelowMutedBanner?.isActive = true
                durationConstraintVideo?.priority = UILayoutPriority(750)
            }
        } else {
            durationConstraintAvatar?.isActive = true
        }
    }

    private func updateRemoteMutedBanner() {
        mutedBannerBelowAvatar?.isActive = false
        mutedBannerAboveFooter?.isActive = false
        let show = isCallConnected && !remoteMicOn
        remoteMutedBanner.isHidden = !show
        remoteMutedLabel.text = PeerCallLocalizedStrings.remoteMicOffBanner(name: remoteDisplayNameForBanner)
        if show {
            if showRemoteVideoSurface {
                mutedBannerAboveFooter?.isActive = true
            } else {
                mutedBannerBelowAvatar?.isActive = true
            }
        }
        updateDurationConstraints()
    }

    private func updateFooterControlAppearance() {
        let theme = UIColor.theme
        let dimFill = theme.secondaryWeight.withAlphaComponent(0.55)
        let activeBg = theme.textStrong
        let activeIcon = theme.primary
        let inactiveTint = theme.text
        let speakerRouteOn = session?.isSpeakerOn ?? false
        if speakerRouteOn {
            speakerButton.backgroundColor = activeBg
            speakerButton.tintColor = activeIcon
        } else {
            speakerButton.backgroundColor = dimFill
            speakerButton.tintColor = inactiveTint
        }
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
        let spkrTitle = PeerCallLocalizedStrings.actionSpeaker
        speakerCaption.text = spkrTitle
        speakerButton.accessibilityLabel = spkrTitle

        endButton.backgroundColor = Self.peerCallEndAccent
        endButton.tintColor = .white

        if localMicOn {
            micButton.backgroundColor = activeBg
            micButton.tintColor = activeIcon
        } else {
            micButton.backgroundColor = dimFill
            micButton.tintColor = inactiveTint
        }
        micButton.setImage(UIImage(systemName: localMicOn ? "mic.fill" : "mic.slash.fill"), for: .normal)
    }

    private static let peerCallEndAccent = UIColor(red: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1)

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
        let theme = UIColor.theme
        let dimFill = theme.secondaryWeight.withAlphaComponent(0.55)
        if localCameraOn {
            headerVideoButton.backgroundColor = theme.textStrong
            headerVideoButton.tintColor = theme.primary
        } else {
            headerVideoButton.backgroundColor = dimFill
            headerVideoButton.tintColor = theme.text
        }
        let img = localCameraOn ? UIImage(systemName: "video.fill") : UIImage(systemName: "video.slash.fill")
        headerVideoButton.setImage(img, for: .normal)
    }

    private func updateFlipVisibility() {
        let theme = UIColor.theme
        flipCameraButton.backgroundColor = theme.secondaryWeight
        flipCameraButton.tintColor = theme.text
        flipCameraButton.isHidden = !localCameraOn || !hasLocalVideoTrack || !incomingFooterStack.isHidden
    }

    private func syncLocalPreviewMirror() {
        localVideoView.isMirrored = session?.isUsingFrontCamera ?? true
    }

    private func styleHeaderCircle(_ b: UIButton, symbol: String) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = UIColor.theme.secondaryWeight
        b.tintColor = UIColor.theme.text
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
