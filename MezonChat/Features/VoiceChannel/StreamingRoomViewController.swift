import UIKit
import AVKit

final class StreamingRoomViewController: ViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {

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
    private var requestedBackgroundURL: String?
    private var didFetchRemoteChannel = false

    private let playbackView = StreamingPlaybackView(frame: .zero)
    private let videoScrollView = UIScrollView()
    private let videoContainer = UIView()
    private var lastVideoViewportSize: CGSize = .zero
    private var controlsVisible = true
    private var isFullscreen = false
    private var orientationBeforeFullscreen: UIInterfaceOrientation = .portrait
    private var orientationsBeforeFullscreen: ViewControllerSupportedOrientations?
    private let fullscreenButton = UIButton(type: .custom)
    private let backgroundImageView = UIImageView()
    private let streamBannerView = UIImageView()
    private let placeholderView = UIImageView()
    private let statusLabel = UILabel()
    private let membersContainer = UIView()
    private let membersOverflowLabel = UILabel()
    private var visibleViewerIDs: [Int64] = []
    private var viewerAvatarViews: [Int64: StreamingViewerAvatarView] = [:]
    private var membersWidthConstraint: NSLayoutConstraint?
    private var membersRefreshWorkItem: DispatchWorkItem?
    private var displayedViewerCount: Int?
    private let headerBar = UIView()
    private let bottomChrome = UIView()
    private let headerRow = UIStackView()
    private let footerRow = UIStackView()
    private let minimizeButton = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let viewerCountLabel = UILabel()
    private let liveBadgeLabel = UILabel()
    private let speakerButton = UIButton(type: .custom)
    private let speakerRouteIcon = UIImageView()
    private let qualityButton = UIButton(type: .custom)
    private let outputPicker = AVRoutePickerView()
    private let bufferingIndicator = UIActivityIndicatorView(style: .large)
    private var showsViewers = true
    private let chatButton = UIButton(type: .custom)
    private let leaveButton = UIButton(type: .custom)
    private var bottomChromeBottomConstraint: NSLayoutConstraint?
    private var footerPortraitConstraints: [NSLayoutConstraint] = []
    private var footerLandscapeConstraints: [NSLayoutConstraint] = []
    private var footerSizeConstraints: [(width: NSLayoutConstraint, height: NSLayoutConstraint)] = []
    private var compactFooter: Bool?
    private var footerControls: [UIView] { [speakerButton, outputPicker, qualityButton, chatButton, leaveButton] }

    private static let streamBannerSize: CGFloat = 240
    private static let bottomChromeHeight: CGFloat = 50
    private static let footerPortraitSizes = [
        CGSize(width: 44, height: 44), CGSize(width: 40, height: 44),
        CGSize(width: 40, height: 44), CGSize(width: 50, height: 50), CGSize(width: 50, height: 50)
    ]

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
        attemptNavigation = { [weak self] _ in
            guard let self else { return true }
            if self.isFullscreen {
                self.setFullscreen(false)
                return false
            }
            if self.videoScrollView.zoomScale > 1.05 {
                self.videoScrollView.setZoomScale(1, animated: true)
                return false
            }
            return true
        }
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let node = ASDisplayNode()
        node.backgroundColor = .black
        self.displayNode = node
        self.displayNodeDidLoad()
    }

    deinit {
        membersRefreshWorkItem?.cancel()
        if let presenceObserver {
            NotificationCenter.default.removeObserver(presenceObserver)
        }
        if let channelDescriptionObserver {
            NotificationCenter.default.removeObserver(channelDescriptionObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundImageView.contentMode = .scaleAspectFit
        backgroundImageView.clipsToBounds = true
        backgroundImageView.image = StreamingChannelBackground.defaultPosterImage
        backgroundImageView.isHidden = false

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

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.text = NSLocalizedString(
            "streamingRoom.noDisplay",
            tableName: nil,
            bundle: .main,
            value: "Stream is not available",
            comment: "")

        membersContainer.translatesAutoresizingMaskIntoConstraints = false
        membersWidthConstraint = membersContainer.widthAnchor.constraint(equalToConstant: 0)
        membersWidthConstraint?.isActive = true

        membersOverflowLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        membersOverflowLabel.textAlignment = .center
        membersOverflowLabel.adjustsFontSizeToFitWidth = true
        membersOverflowLabel.minimumScaleFactor = 0.6
        membersOverflowLabel.backgroundColor = UIColor(white: 0.12, alpha: 1)
        membersOverflowLabel.layer.cornerRadius = Self.memberAvatarSize / 2
        membersOverflowLabel.clipsToBounds = true
        membersOverflowLabel.layer.borderWidth = 2
        membersOverflowLabel.layer.borderColor = UIColor.black.cgColor
        membersOverflowLabel.isAccessibilityElement = true
        membersContainer.addSubview(membersOverflowLabel)
        membersOverflowLabel.textColor = .white
        membersOverflowLabel.isHidden = true

        styleCircleButton(minimizeButton, systemImage: "chevron.down", pointSize: 18)
        minimizeButton.addTarget(self, action: #selector(minimizeTapped), for: .touchUpInside)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.text = channel.channelLabel
        titleLabel.numberOfLines = 2

        headerBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        bottomChrome.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        bottomChrome.translatesAutoresizingMaskIntoConstraints = false

        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 12
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(minimizeButton)
        headerRow.addArrangedSubview(titleLabel)
        liveBadgeLabel.text = "LIVE"
        liveBadgeLabel.textColor = .white
        liveBadgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        liveBadgeLabel.textAlignment = .center
        liveBadgeLabel.backgroundColor = .systemRed
        liveBadgeLabel.layer.cornerRadius = 3
        liveBadgeLabel.clipsToBounds = true
        liveBadgeLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        liveBadgeLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true
        headerRow.addArrangedSubview(liveBadgeLabel)
        viewerCountLabel.font = .systemFont(ofSize: 14, weight: .medium)
        viewerCountLabel.textColor = .white
        viewerCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        headerRow.addArrangedSubview(viewerCountLabel)
        styleCircleButton(fullscreenButton, systemImage: "arrow.up.left.and.arrow.down.right", pointSize: 16)
        fullscreenButton.accessibilityLabel = L("streamingRoom.enterFullscreen")
        fullscreenButton.addTarget(self, action: #selector(fullscreenTapped), for: .touchUpInside)
        headerRow.addArrangedSubview(fullscreenButton)
        viewerCountLabel.isUserInteractionEnabled = true
        viewerCountLabel.accessibilityTraits.insert(.button)
        viewerCountLabel.accessibilityHint = NSLocalizedString(
            "streamingRoom.toggleViewers", tableName: nil, bundle: .main, value: "Show or hide viewers", comment: "")
        viewerCountLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleViewers)))
        headerBar.addSubview(headerRow)

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
        styleCircleButton(speakerButton, systemImage: "speaker.wave.2.fill", pointSize: 18)
        speakerButton.setImage(nil, for: .normal)
        speakerRouteIcon.translatesAutoresizingMaskIntoConstraints = false
        speakerRouteIcon.contentMode = .scaleAspectFit
        speakerRouteIcon.tintColor = .white
        speakerRouteIcon.isUserInteractionEnabled = false
        speakerButton.addSubview(speakerRouteIcon)
        speakerButton.addTarget(self, action: #selector(speakerTapped), for: .touchUpInside)
        styleCircleButton(qualityButton, systemImage: "slider.horizontal.3", pointSize: 18)
        qualityButton.addTarget(self, action: #selector(qualityTapped), for: .touchUpInside)
        outputPicker.translatesAutoresizingMaskIntoConstraints = false
        outputPicker.tintColor = .white
        outputPicker.activeTintColor = .systemGreen
        outputPicker.prioritizesVideoDevices = false
        outputPicker.accessibilityLabel = NSLocalizedString(
            "voiceChannel.audioRouteTitle", tableName: nil, bundle: .main, value: "Audio output", comment: "")
        bufferingIndicator.translatesAutoresizingMaskIntoConstraints = false
        bufferingIndicator.color = .white
        bufferingIndicator.hidesWhenStopped = true
        footerRow.addArrangedSubview(speakerButton)
        footerRow.addArrangedSubview(outputPicker)
        footerRow.addArrangedSubview(qualityButton)
        footerRow.addArrangedSubview(chatButton)
        footerRow.addArrangedSubview(leaveButton)
        bottomChrome.addSubview(footerRow)
        for (index, control) in footerControls.enumerated() {
            let size = Self.footerPortraitSizes[index]
            let width = control.widthAnchor.constraint(equalToConstant: size.width)
            let height = control.heightAnchor.constraint(equalToConstant: size.height)
            footerSizeConstraints.append((width, height))
            NSLayoutConstraint.activate([width, height])
        }
        footerPortraitConstraints = [
            footerRow.leadingAnchor.constraint(equalTo: bottomChrome.leadingAnchor, constant: 24),
            footerRow.trailingAnchor.constraint(equalTo: bottomChrome.trailingAnchor, constant: -24)
        ]
        footerLandscapeConstraints = [
            footerRow.centerXAnchor.constraint(equalTo: bottomChrome.centerXAnchor),
            footerRow.widthAnchor.constraint(equalToConstant: CGFloat(footerControls.count) * 48 + CGFloat(footerControls.count - 2) * 14 + 24),
            footerRow.leadingAnchor.constraint(greaterThanOrEqualTo: bottomChrome.leadingAnchor, constant: 12),
            footerRow.trailingAnchor.constraint(lessThanOrEqualTo: bottomChrome.trailingAnchor, constant: -12)
        ]
        NSLayoutConstraint.activate(footerPortraitConstraints)

        videoScrollView.translatesAutoresizingMaskIntoConstraints = false
        videoScrollView.delegate = self
        videoScrollView.minimumZoomScale = 1
        videoScrollView.maximumZoomScale = 4
        videoScrollView.bouncesZoom = false
        videoScrollView.showsHorizontalScrollIndicator = false
        videoScrollView.showsVerticalScrollIndicator = false
        videoScrollView.contentInsetAdjustmentBehavior = .never
        videoScrollView.isAccessibilityElement = true
        videoScrollView.accessibilityLabel = L("streamingRoom.video")
        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.clipsToBounds = true
        view.addSubview(videoScrollView)
        videoScrollView.addSubview(videoContainer)
        playbackView.translatesAutoresizingMaskIntoConstraints = false
        videoContainer.addSubview(playbackView)
        NSLayoutConstraint.activate([
            videoScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            videoScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            videoScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            videoScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            videoContainer.topAnchor.constraint(equalTo: videoScrollView.contentLayoutGuide.topAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: videoScrollView.contentLayoutGuide.bottomAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: videoScrollView.contentLayoutGuide.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: videoScrollView.contentLayoutGuide.trailingAnchor),
            videoContainer.widthAnchor.constraint(equalTo: videoScrollView.frameLayoutGuide.widthAnchor),
            videoContainer.heightAnchor.constraint(equalTo: videoScrollView.frameLayoutGuide.heightAnchor),
            playbackView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            playbackView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
            playbackView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            playbackView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
        ])
        videoContainer.addSubview(backgroundImageView)
        view.addSubview(streamBannerView)
        view.addSubview(placeholderView)
        view.addSubview(statusLabel)
        view.addSubview(membersContainer)
        view.addSubview(headerBar)
        view.addSubview(bottomChrome)
        view.addSubview(bufferingIndicator)

        NSLayoutConstraint.activate([
            speakerRouteIcon.centerXAnchor.constraint(equalTo: speakerButton.centerXAnchor),
            speakerRouteIcon.centerYAnchor.constraint(equalTo: speakerButton.centerYAnchor),
            speakerRouteIcon.widthAnchor.constraint(equalToConstant: 18),
            speakerRouteIcon.heightAnchor.constraint(equalToConstant: 15),
            membersContainer.bottomAnchor.constraint(equalTo: bottomChrome.topAnchor, constant: -20),
            bufferingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bufferingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            minimizeButton.widthAnchor.constraint(equalToConstant: 44),
            minimizeButton.heightAnchor.constraint(equalToConstant: 44),
            fullscreenButton.widthAnchor.constraint(equalToConstant: 44),
            fullscreenButton.heightAnchor.constraint(equalToConstant: 44),

            backgroundImageView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),

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
            headerBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            headerBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            headerRow.topAnchor.constraint(equalTo: headerBar.topAnchor),
            headerRow.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            headerRow.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -12),
            headerRow.bottomAnchor.constraint(equalTo: headerBar.bottomAnchor),

            bottomChrome.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bottomChrome.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bottomChrome.heightAnchor.constraint(equalToConstant: Self.bottomChromeHeight),

            footerRow.topAnchor.constraint(equalTo: bottomChrome.topAnchor),
            footerRow.bottomAnchor.constraint(equalTo: bottomChrome.bottomAnchor),

            membersContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            membersContainer.heightAnchor.constraint(equalToConstant: Self.memberAvatarSize + 4),

        ])

        bottomChromeBottomConstraint = bottomChrome.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24)
        bottomChromeBottomConstraint?.isActive = true

        view.bringSubviewToFront(headerBar)
        view.bringSubviewToFront(membersContainer)
        view.bringSubviewToFront(bottomChrome)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomVideo(_:)))
        doubleTap.numberOfTapsRequired = 2
        videoScrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        singleTap.delegate = self
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
        setControlsVisible(true, animated: false)

        existingPiPOverlay?.prepareForFullScreenRestore()
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
            self.scheduleMembersRefresh()
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
            self.loadStreamBackgroundIfNeeded()
            self.refreshPlaybackUI()
        }

    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let pip = StreamingPiPOverlay.shared
        if pip.isActive, pip.channel?.channelID == streamChannelId {
            pip.prepareForFullScreenRestore()
        }
        isMinimizingToPiP = false
        bindSession()
        refreshPlaybackUI()
        refreshMembersRow()
        setControlsVisible(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bottomInset = view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom
        let landscape = view.bounds.width > view.bounds.height
        updateBottomChromeBackground()
        updateFooterLayout(compact: landscape)
        bottomChromeBottomConstraint?.constant = -(bottomInset + (landscape ? 12 : 24))
        if lastVideoViewportSize != videoScrollView.bounds.size {
            lastVideoViewportSize = videoScrollView.bounds.size
            videoScrollView.setZoomScale(1, animated: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed { resetViewingMode() }
        if isMinimizingToPiP { return }
        if isMovingFromParent || isBeingDismissed {
            if StreamingWebRTCSession.shared.activeStreamChannelId == streamChannelId {
                showPiP()
            } else {
                StreamingWebRTCSession.shared.onStreamingStateChanged = nil
                playbackView.update(session: nil)
            }
        }
    }

    private var resolvedClanId: Int64 {
        channel.clanID != 0 ? channel.clanID : context.currentClanId
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var shouldAutorotate: Bool { true }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { videoContainer }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return false }
        return ![headerBar, footerRow, membersContainer].contains {
            touchedView === $0 || touchedView.isDescendant(of: $0)
        }
    }

    @objc private func zoomVideo(_ gesture: UITapGestureRecognizer) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        if videoScrollView.zoomScale > 1.05 {
            videoScrollView.setZoomScale(1, animated: animated)
        } else {
            let point = gesture.location(in: videoContainer)
            let size = CGSize(width: videoScrollView.bounds.width / 2.5, height: videoScrollView.bounds.height / 2.5)
            videoScrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                           width: size.width, height: size.height), animated: animated)
        }
    }

    @objc private func toggleControls() { setControlsVisible(!controlsVisible) }

    private func setControlsVisible(_ visible: Bool, animated: Bool = true) {
        controlsVisible = visible
        let chrome = [headerBar, bottomChrome, membersContainer]
        chrome.forEach {
            $0.isUserInteractionEnabled = visible
            $0.accessibilityElementsHidden = !visible
        }
        UIView.animate(withDuration: animated && !UIAccessibility.isReduceMotionEnabled ? 0.2 : 0,
                       delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            chrome.forEach { $0.alpha = visible ? 1 : 0 }
        }
        prefersOnScreenNavigationHidden = isFullscreen && !visible
        setStatusBarStyle(isFullscreen && !visible ? .Hide : .White, animated: animated)
        updateViewingAccessibilityActions()
    }

    private func updateViewingAccessibilityActions() {
        videoScrollView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: L(controlsVisible ? "streamingRoom.hideControls" : "streamingRoom.showControls")) { [weak self] _ in
                self?.toggleControls()
                return true
            },
            UIAccessibilityCustomAction(name: L(isFullscreen ? "streamingRoom.exitFullscreen" : "streamingRoom.enterFullscreen")) { [weak self] _ in
                guard let self else { return false }
                self.setFullscreen(!self.isFullscreen)
                return true
            },
            UIAccessibilityCustomAction(name: L("streamingRoom.resetZoom")) { [weak self] _ in
                self?.videoScrollView.setZoomScale(1, animated: false)
                return true
            }
        ]
    }

    @objc private func fullscreenTapped() { setFullscreen(!isFullscreen) }

    private func updateFooterLayout(compact: Bool) {
        guard compactFooter != compact else { return }
        compactFooter = compact
        NSLayoutConstraint.deactivate(compact ? footerPortraitConstraints : footerLandscapeConstraints)
        footerRow.distribution = compact ? .fill : .equalSpacing
        footerRow.spacing = compact ? 14 : 0
        footerRow.setCustomSpacing(compact ? 24 : UIStackView.spacingUseDefault, after: chatButton)
        for (index, control) in footerControls.enumerated() {
            let size = compact ? CGSize(width: 48, height: 48) : Self.footerPortraitSizes[index]
            footerSizeConstraints[index].width.constant = size.width
            footerSizeConstraints[index].height.constant = size.height
            control.layer.cornerRadius = compact ? 24 : (control === leaveButton ? 25 : (control === outputPicker ? 0 : 22))
        }
        outputPicker.backgroundColor = compact ? UIColor.black.withAlphaComponent(0.45) : nil
        outputPicker.clipsToBounds = compact
        NSLayoutConstraint.activate(compact ? footerLandscapeConstraints : footerPortraitConstraints)
    }

    private func updateBottomChromeBackground() {
        let landscape = view.bounds.width > view.bounds.height
        bottomChrome.backgroundColor = isFullscreen || landscape ? .clear : UIColor.black.withAlphaComponent(0.55)
    }

    private func setFullscreen(_ enabled: Bool) {
        guard isFullscreen != enabled else { return }
        if enabled {
            orientationBeforeFullscreen = view.window?.windowScene?.interfaceOrientation ?? .portrait
            orientationsBeforeFullscreen = supportedOrientations
            supportedOrientations = ViewControllerSupportedOrientations(regularSize: .landscape, compactSize: .landscape)
        } else if let previous = orientationsBeforeFullscreen {
            supportedOrientations = previous
            orientationsBeforeFullscreen = nil
        }
        isFullscreen = enabled
        updateBottomChromeBackground()
        videoScrollView.setZoomScale(1, animated: false)
        fullscreenButton.setImage(UIImage(systemName: enabled ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
        fullscreenButton.accessibilityLabel = L(enabled ? "streamingRoom.exitFullscreen" : "streamingRoom.enterFullscreen")
        setControlsVisible(!enabled)
        requestVideoOrientation(enabled: enabled)
    }

    private func requestVideoOrientation(enabled: Bool) {
        let orientation: UIInterfaceOrientationMask
        switch orientationBeforeFullscreen {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        default: orientation = .portrait
        }
        view.window?.layoutIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFullscreen == enabled, let window = self.view.window else { return }
            if #available(iOS 16.0, *) {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                window.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: enabled ? .landscape : orientation))
            } else {
                UIDevice.current.setValue(enabled ? UIInterfaceOrientation.landscapeRight.rawValue : self.orientationBeforeFullscreen.rawValue,
                                          forKey: "orientation")
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }

    private func resetViewingMode() {
        setFullscreen(false)
        videoScrollView.setZoomScale(1, animated: false)
        setControlsVisible(true, animated: false)
    }

    override func accessibilityPerformEscape() -> Bool {
        if isFullscreen { setFullscreen(false) }
        else { minimizeTapped() }
        return true
    }

    private func bindSession() {
        StreamingWebRTCSession.shared.onStreamingStateChanged = { [weak self] in
            guard let self else { return }
            self.refreshPlaybackUI()
            guard StreamingWebRTCSession.shared.activeStreamChannelId == nil else { return }
            // Let an in-progress channel switch finish removing its old controller first.
            DispatchQueue.main.async { [weak self] in
                guard let self, let nav = self.navigationController,
                      StreamingWebRTCSession.shared.activeStreamChannelId == nil else { return }
                Self.endStream(context: self.context, clanId: self.resolvedClanId,
                               channelId: self.streamChannelId, navigationController: nav)
            }
        }
    }

    private func refreshPlaybackUI() {
        let session = StreamingWebRTCSession.shared
        playbackView.update(session: session)
        let isActive = session.isStreaming
        backgroundImageView.isHidden = session.hasVideoFrames
        streamBannerView.isHidden = true
        placeholderView.isHidden = true
        statusLabel.isHidden = isActive || session.isBuffering
        if session.isBuffering { bufferingIndicator.startAnimating() }
        else { bufferingIndicator.stopAnimating() }
        refreshAudioOutputButton()
        qualityButton.accessibilityLabel = NSLocalizedString(
            "streamingRoom.quality", tableName: nil, bundle: .main, value: "Quality", comment: "") + ": " + session.quality.title
        statusLabel.text = session.activeStreamChannelId == streamChannelId
            ? NSLocalizedString("streamingRoom.connecting", tableName: nil, bundle: .main, value: "Connecting…", comment: "")
            : NSLocalizedString("streamingRoom.noDisplay", tableName: nil, bundle: .main, value: "Stream is not available", comment: "")

        loadStreamBackgroundIfNeeded()
    }

    private func resolvedStreamChannelAvatarURL() -> String {
        if let cachedAvatarURL { return cachedAvatarURL }
        let resolved = StreamingChannelBackground.resolveAvatarURL(channel: channel, context: context)
        cachedAvatarURL = resolved
        return resolved
    }

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
        guard requestedBackgroundURL != raw else { return }
        requestedBackgroundURL = raw
        backgroundLoadToken &+= 1
        let token = backgroundLoadToken
        backgroundImageView.image = StreamingChannelBackground.defaultPosterImage
        guard !raw.isEmpty else {
            fetchRemoteChannelAvatarIfNeeded()
            return
        }
        let scale = UIScreen.main.scale
        let width = max(Int(view.bounds.width * scale), 720)
        let height = max(Int(view.bounds.height * scale), 720)
        StreamingChannelBackground.loadImage(raw: raw, width: width, height: height) { [weak self] image in
            guard let self, token == self.backgroundLoadToken else { return }
            self.backgroundImageView.image = image ?? StreamingChannelBackground.defaultPosterImage
            self.refreshPlaybackUI()
        }
    }

    private func resolveStreamMember(
        _ entry: Mezon_Api_StreamingChannelUser, clanMember member: ClanMemberRecord?
    ) -> VoiceMemberDisplay {
        let uid = String(entry.userID)
        let profile = context.account.postbox.read { $0.getProfile(userId: uid) }
        let fallbackName = entry.participant.isEmpty ? uid : entry.participant
        let name: String
        if let m = member {
            if !m.clanNick.isEmpty {
                name = m.clanNick
            } else if !m.displayName.isEmpty {
                name = m.displayName
            } else if !m.username.isEmpty {
                name = m.username
            } else {
                name = fallbackName
            }
        } else if let profile {
            name = (profile.displayName?.isEmpty == false ? profile.displayName : nil) ?? profile.username
        } else {
            name = fallbackName
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

        return VoiceMemberDisplay(name: name, avatarURL: avatar)
    }

    private func scheduleMembersRefresh() {
        // Coalesce bursts without postponing updates indefinitely during a busy stream.
        guard membersRefreshWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.membersRefreshWorkItem = nil
            self?.refreshMembersRow()
        }
        membersRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func refreshMembersRow() {
        membersRefreshWorkItem?.cancel()
        membersRefreshWorkItem = nil
        let entries = context.engine.clanData.streamMembers(clanId: resolvedClanId, channelId: streamChannelId)
        let viewerCount = context.engine.clanData.streamViewerCount(clanId: resolvedClanId, channelId: streamChannelId)
        let viewers = entries.dropFirst()
        let joinedIDs = Set(viewers.map(\.userID))
        // Preserve the visible order when snapshots arrive in a different server order.
        var nextIDs = visibleViewerIDs.filter { joinedIDs.contains($0) }
        for viewer in viewers where nextIDs.count < Self.maxVisibleMembers {
            if !nextIDs.contains(viewer.userID) { nextIDs.append(viewer.userID) }
        }
        let visibleIDs = Set(nextIDs)
        var requestedIDs = visibleIDs
        if let publisher = entries.first { requestedIDs.insert(publisher.userID) }
        // Read clan members once and resolve profiles only for the publisher and visible avatars.
        let clanMembers = context.account.postbox.read { $0.getClanMembers(clanId: self.resolvedClanId) }
        var membersByID: [Int64: ClanMemberRecord] = [:]
        for member in clanMembers where requestedIDs.contains(member.userId) {
            membersByID[member.userId] = member
        }
        if let publisher = entries.first {
            let display = resolveStreamMember(publisher, clanMember: membersByID[publisher.userID])
            let title = display.name + "\n" + channel.channelLabel
            if titleLabel.text != title { titleLabel.text = title }
        } else if titleLabel.text != channel.channelLabel { titleLabel.text = channel.channelLabel }
        liveBadgeLabel.isHidden = entries.isEmpty
        if displayedViewerCount != viewerCount {
            displayedViewerCount = viewerCount
            let count = NSMutableAttributedString(attachment: {
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: "eye")?.withTintColor(.white)
                attachment.bounds = CGRect(x: 0, y: -2, width: 16, height: 12)
                return attachment
            }())
            count.append(NSAttributedString(string: " \(viewerCount)"))
            viewerCountLabel.attributedText = count
            viewerCountLabel.accessibilityLabel = String(format: NSLocalizedString(
                "streamingRoom.viewerCount", tableName: nil, bundle: .main, value: "%d viewers", comment: ""), viewerCount)
        }

        for id in visibleViewerIDs where !visibleIDs.contains(id) {
            viewerAvatarViews.removeValue(forKey: id)?.removeFromSuperview()
        }
        let size = Self.memberAvatarSize
        let step = size - Self.memberOverlap
        for entry in viewers where visibleIDs.contains(entry.userID) {
            let avatar: StreamingViewerAvatarView
            if let existing = viewerAvatarViews[entry.userID] { avatar = existing }
            else {
                avatar = StreamingViewerAvatarView(size: size)
                viewerAvatarViews[entry.userID] = avatar
                membersContainer.addSubview(avatar)
            }
            avatar.update(member: resolveStreamMember(entry, clanMember: membersByID[entry.userID]))
        }
        for (index, id) in nextIDs.enumerated() {
            guard let avatar = viewerAvatarViews[id] else { continue }
            avatar.frame = CGRect(x: CGFloat(index) * step, y: 2, width: size, height: size)
            membersContainer.bringSubviewToFront(avatar)
        }
        visibleViewerIDs = nextIDs
        let overflow = max(0, viewerCount - nextIDs.count)
        var width = nextIDs.isEmpty ? 0 : size + CGFloat(nextIDs.count - 1) * step
        membersOverflowLabel.isHidden = overflow == 0
        if overflow > 0 {
            let text = "+" + NumberFormatter.localizedString(from: NSNumber(value: overflow), number: .decimal)
            if membersOverflowLabel.text != text { membersOverflowLabel.text = text }
            membersOverflowLabel.accessibilityLabel = String(format: NSLocalizedString(
                "streamingRoom.moreViewers", tableName: nil, bundle: .main,
                value: "%d more viewers", comment: ""), overflow)
            let badgeWidth = max(size, min(88, membersOverflowLabel.intrinsicContentSize.width + 16))
            membersOverflowLabel.frame = CGRect(x: CGFloat(nextIDs.count) * step, y: 2, width: badgeWidth, height: size)
            membersContainer.bringSubviewToFront(membersOverflowLabel)
            width = membersOverflowLabel.frame.maxX
        }
        if membersWidthConstraint?.constant != width { membersWidthConstraint?.constant = width }
        membersContainer.isHidden = !showsViewers || nextIDs.isEmpty
    }

    private func refreshAudioOutputButton() {
        let audio = AVAudioSession.sharedInstance()
        let port = audio.currentRoute.outputs.first
        let speaker = StreamingWebRTCSession.shared.isSpeakerOutput
        let image: UIImage?
        let name: String
        switch port?.portType {
        case .builtInSpeaker:
            image = UIImage(named: "externalSpeaker")?.withRenderingMode(.alwaysTemplate)
            name = NSLocalizedString("streamingRoom.speaker", tableName: nil, bundle: .main,
                                     value: "Speaker", comment: "")
        case .builtInReceiver:
            image = UIImage(named: "internalSpeaker")?.withRenderingMode(.alwaysTemplate)
            name = NSLocalizedString("streamingRoom.receiver", tableName: nil, bundle: .main,
                                     value: "Receiver", comment: "")
        case .headphones, .headsetMic, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            image = UIImage(systemName: "headphones", withConfiguration:
                UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))?.withRenderingMode(.alwaysTemplate)
            name = port?.portName ?? ""
        default:
            image = port == nil
                ? UIImage(named: "internalSpeaker")?.withRenderingMode(.alwaysTemplate)
                : UIImage(systemName: "airplayaudio", withConfiguration:
                    UIImage.SymbolConfiguration(pointSize: 12, weight: .medium))?.withRenderingMode(.alwaysTemplate)
            name = port?.portName ?? NSLocalizedString(
                "voiceChannel.audioRouteTitle", tableName: nil, bundle: .main, value: "Audio output", comment: "")
        }
        speakerRouteIcon.image = image
        speakerButton.backgroundColor = speaker ? UIColor.white.withAlphaComponent(0.18) : UIColor.black.withAlphaComponent(0.45)
        speakerButton.isSelected = speaker
        speakerButton.accessibilityLabel = NSLocalizedString(
            "voiceChannel.audioRouteTitle", tableName: nil, bundle: .main, value: "Audio output", comment: "")
        speakerButton.accessibilityValue = name
        speakerButton.accessibilityHint = NSLocalizedString(
            speaker ? "streamingRoom.switchToReceiver" : "streamingRoom.switchToSpeaker",
            tableName: nil, bundle: .main, value: speaker ? "Switch to receiver" : "Switch to speaker", comment: "")
    }

    @objc private func speakerTapped() {
        StreamingWebRTCSession.shared.toggleSpeakerOutput()
    }

    @objc private func qualityTapped() {
        guard presentedViewController == nil else { return }
        let session = StreamingWebRTCSession.shared
        let sheet = StreamingQualitySheetController(
            selectedQuality: session.quality,
            defaultQuality: session.defaultQuality,
            onSelect: { quality in
                if session.quality != quality { session.setQuality(quality) }
            },
            onSaveDefault: { session.setDefaultQuality(session.quality) }
        )
        present(sheet, animated: false)
    }

    @objc private func toggleViewers() {
        showsViewers.toggle()
        refreshMembersRow()
    }

    private func styleCircleButton(_ button: UIButton, systemImage: String, pointSize: CGFloat) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 22
        button.clipsToBounds = true
        button.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        button.setImage(UIImage(systemName: systemImage, withConfiguration: config), for: .normal)
    }

    private func showPiP() {
        resetViewingMode()
        StreamingWebRTCSession.shared.onStreamingStateChanged = nil
        playbackView.update(session: nil)
        isMinimizingToPiP = true
        StreamingPiPOverlay.shared.show(
            context: context,
            channel: channel,
            parentChannelName: parentChannelName
        )
    }

    @objc private func minimizeTapped() {
        showPiP()
        navigationController?.popViewController(animated: true)
    }

    @objc private func chatTapped() {
        guard let nav = navigationController else { return }
        showPiP()
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
        nav.setViewControllers(nav.viewControllers.filter { $0 !== self } + [chatVC], animated: true)
    }

    @objc private func leaveTapped() {
        resetViewingMode()
        Self.endStream(
            context: context,
            clanId: resolvedClanId,
            channelId: channel.channelID,
            navigationController: navigationController
        )
    }

    @MainActor
    static func endStream(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64,
        navigationController: UINavigationController?
    ) {
        let session = StreamingWebRTCSession.shared
        if session.activeStreamChannelId == channelId {
            session.onStreamingStateChanged = nil
            session.leave()
        } else if session.activeStreamChannelId == nil {
            session.onStreamingStateChanged = nil
        }
        if StreamingPiPOverlay.shared.isActive, StreamingPiPOverlay.shared.channel?.channelID == channelId {
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

    @MainActor
    private static func findNavigationControllerForStreamExit() -> UINavigationController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for window in scene.windows where !window.isHidden {
            if let nav = findNavigationController(in: window.rootViewController) {
                return nav
            }
        }
        return nil
    }

    @MainActor
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

    @MainActor
    static func prepareJoiningStream(
        targetChannelId: Int64,
        clanId: Int64,
        context: AccountContext,
        navigationController: UINavigationController
    ) {
        let pip = StreamingPiPOverlay.shared
        if pip.isActive, pip.channel?.channelID != targetChannelId {
            pip.dismiss(disconnectSession: false)
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

private final class StreamingViewerAvatarView: UIView {
    private let placeholder: TextAvatarView
    private let imageView = UIImageView()
    private var displayedName: String?
    private var requestedURL: String?

    init(size: CGFloat) {
        placeholder = TextAvatarView(size: size)
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        layer.cornerRadius = size / 2
        clipsToBounds = true
        placeholder.frame = bounds
        placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(placeholder)
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        layer.borderWidth = 2
        layer.borderColor = UIColor.black.cgColor
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(member: VoiceMemberDisplay) {
        if displayedName != member.name {
            displayedName = member.name
            placeholder.configure(username: member.name)
            accessibilityLabel = member.name
        }
        let url = member.avatarURL.flatMap { $0.isEmpty ? nil : ImgproxyURL.iconURL(from: $0, width: 100, height: 100) }
        guard requestedURL != url else { return }
        requestedURL = url
        imageView.image = nil
        guard let url else { return }
        // Keep initials visible while loading; unchanged users keep their existing image.
        ImageCache.shared.loadAvatar(urlString: url) { [weak self] image in
            guard let self, self.requestedURL == url else { return }
            self.imageView.image = image
        }
    }
}

private final class StreamingQualitySheetController: UIViewController, UIGestureRecognizerDelegate {
    private static let accent = UIColor(red: 0.62, green: 0.54, blue: 1, alpha: 1)

    private let selectedQuality: StreamingQuality
    private let defaultQuality: StreamingQuality
    private let onSelect: (StreamingQuality) -> Void
    private let onSaveDefault: () -> Void
    private let dimControl = UIControl()
    private let panel = UIView()
    private let header = UIView()
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var panelHeight: NSLayoutConstraint?
    private var didAnimateIn = false
    private var isClosing = false

    init(
        selectedQuality: StreamingQuality,
        defaultQuality: StreamingQuality,
        onSelect: @escaping (StreamingQuality) -> Void,
        onSaveDefault: @escaping () -> Void
    ) {
        self.selectedQuality = selectedQuality
        self.defaultQuality = defaultQuality
        self.onSelect = onSelect
        self.onSaveDefault = onSaveDefault
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        dimControl.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        dimControl.alpha = 0
        dimControl.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        panel.backgroundColor = UIColor(white: 0.105, alpha: 1)
        panel.layer.cornerRadius = 24
        panel.layer.cornerCurve = .continuous
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        panel.layer.borderWidth = 1
        panel.clipsToBounds = true
        panel.alpha = 0
        for child in [dimControl, panel] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }

        let handle = UIView()
        handle.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        handle.layer.cornerRadius = 2
        handle.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(handle)
        header.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(header)
        titleLabel.text = NSLocalizedString(
            "streamingRoom.quality", tableName: nil, bundle: .main, value: "Quality", comment: "")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.accessibilityTraits.insert(.header)
        let subtitle = UILabel()
        subtitle.text = NSLocalizedString(
            "streamingRoom.qualityDescription", tableName: nil, bundle: .main,
            value: "Choose your playback quality", comment: "")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.5)
        subtitle.numberOfLines = 0
        let heading = UIStackView(arrangedSubviews: [titleLabel, subtitle])
        heading.axis = .vertical
        heading.spacing = 4
        heading.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(heading)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)), for: .normal)
        close.tintColor = UIColor.white.withAlphaComponent(0.7)
        close.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        close.layer.cornerRadius = 18
        close.accessibilityLabel = NSLocalizedString(
            "common.close", tableName: nil, bundle: .main, value: "Close", comment: "")
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(close)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        header.addGestureRecognizer(pan)
        let handlePan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        handlePan.delegate = self
        handle.isUserInteractionEnabled = true
        handle.addGestureRecognizer(handlePan)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        panel.addSubview(scrollView)
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        let options = UIStackView()
        options.axis = .vertical
        options.spacing = 4
        for (index, quality) in StreamingQuality.allCases.enumerated() {
            let row = StreamingQualityOptionRow(
                quality: quality, selected: quality == selectedQuality, accent: Self.accent)
            row.tag = index
            row.addTarget(self, action: #selector(qualitySelected(_:)), for: .touchUpInside)
            options.addArrangedSubview(row)
        }
        contentStack.addArrangedSubview(options)
        contentStack.addArrangedSubview(makeDefaultRow())

        let preferredWidth = panel.widthAnchor.constraint(equalTo: view.widthAnchor)
        preferredWidth.priority = .defaultHigh
        let height = panel.heightAnchor.constraint(equalToConstant: 420)
        height.priority = .defaultHigh
        panelHeight = height
        NSLayoutConstraint.activate([
            dimControl.topAnchor.constraint(equalTo: view.topAnchor),
            dimControl.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            preferredWidth,
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            panel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            height,
            handle.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            handle.centerXAnchor.constraint(equalTo: panel.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 4),
            header.topAnchor.constraint(equalTo: panel.topAnchor, constant: 28),
            header.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
            header.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            heading.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            heading.topAnchor.constraint(equalTo: header.topAnchor),
            heading.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -12),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            close.topAnchor.constraint(equalTo: header.topAnchor),
            close.widthAnchor.constraint(equalToConstant: 36),
            close.heightAnchor.constraint(equalToConstant: 36),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = max(0, panel.bounds.width - 40)
        guard width > 0 else { return }
        let contentHeight = contentStack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let headingHeight = header.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        let preferredHeight = 28 + max(52, headingHeight) + 12 + contentHeight + 18 + view.safeAreaInsets.bottom
        if abs((panelHeight?.constant ?? 0) - preferredHeight) > 0.5 {
            panelHeight?.constant = preferredHeight
            view.layoutIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        view.layoutIfNeeded()
        panel.transform = CGAffineTransform(translationX: 0, y: panel.bounds.height)
        panel.alpha = 1
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.panel.transform = .identity
            self.dimControl.alpha = 1
        } completion: { _ in
            UIAccessibility.post(notification: .screenChanged, argument: self.titleLabel)
        }
    }

    private func makeDefaultRow() -> UIControl {
        let isDefault = selectedQuality == defaultQuality
        let row = UIControl()
        row.backgroundColor = UIColor.white.withAlphaComponent(0.04)
        row.layer.cornerRadius = 14
        row.isEnabled = !isDefault
        row.addTarget(self, action: #selector(saveDefaultTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = NSLocalizedString(
            isDefault ? "streamingRoom.defaultQuality" : "streamingRoom.useAsDefault", tableName: nil, bundle: .main,
            value: isDefault ? "Default quality" : "Use as default", comment: "")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        let detail = UILabel()
        detail.text = String(format: NSLocalizedString(
            "streamingRoom.defaultQualityDetail", tableName: nil, bundle: .main,
            value: "%@ for new streams", comment: ""), selectedQuality.title)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = UIColor.white.withAlphaComponent(0.45)
        detail.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [title, detail])
        labels.axis = .vertical
        labels.spacing = 3
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: isDefault ? "checkmark.circle.fill" : "arrow.down.to.line"))
        icon.tintColor = isDefault ? Self.accent : UIColor.white.withAlphaComponent(0.6)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(labels)
        row.addSubview(icon)
        row.isAccessibilityElement = true
        row.accessibilityLabel = [title.text, detail.text].compactMap { $0 }.joined(separator: ", ")
        row.accessibilityTraits = isDefault ? [.staticText] : [.button]
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
            labels.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            labels.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            labels.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: icon.leadingAnchor, constant: -12),
            icon.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
        ])
        return row
    }

    @objc private func qualitySelected(_ sender: UIControl) {
        guard StreamingQuality.allCases.indices.contains(sender.tag) else { return }
        let quality = StreamingQuality.allCases[sender.tag]
        dismissSheet { self.onSelect(quality) }
    }

    @objc private func saveDefaultTapped() { dismissSheet(after: onSaveDefault) }
    @objc private func closeTapped() { dismissSheet() }

    private func dismissSheet(after completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.panel.transform = CGAffineTransform(translationX: 0, y: self.panel.bounds.height)
            self.dimControl.alpha = 0
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isClosing else { return }
        let offset = max(0, gesture.translation(in: view).y)
        switch gesture.state {
        case .changed:
            panel.transform = CGAffineTransform(translationX: 0, y: offset)
            dimControl.alpha = 1 - min(1, offset / max(panel.bounds.height, 1)) * 0.6
        case .ended:
            if offset > 100 || gesture.velocity(in: view).y > 800 { dismissSheet() }
            else { restorePosition() }
        case .cancelled, .failed:
            restorePosition()
        default: break
        }
    }

    private func restorePosition() {
        UIView.animate(withDuration: 0.2) {
            self.panel.transform = .identity
            self.dimControl.alpha = 1
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return !isClosing && velocity.y > abs(velocity.x)
    }

    override func accessibilityPerformEscape() -> Bool {
        dismissSheet()
        return true
    }
}

private final class StreamingQualityOptionRow: UIControl {
    init(quality: StreamingQuality, selected: Bool, accent: UIColor) {
        super.init(frame: .zero)
        layer.cornerRadius = 12
        layer.borderWidth = selected ? 1 : 0
        layer.borderColor = accent.withAlphaComponent(0.45).cgColor
        backgroundColor = selected ? accent.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.025)
        let badge = UILabel()
        switch quality {
        case .auto: badge.text = "A"
        case .high: badge.text = "HQ"
        case .mid: badge.text = "MQ"
        case .low: badge.text = "LQ"
        }
        badge.font = .systemFont(ofSize: 12, weight: .bold)
        badge.textAlignment = .center
        badge.textColor = selected ? accent : UIColor.white.withAlphaComponent(0.65)
        badge.backgroundColor = selected ? accent.withAlphaComponent(0.12) : UIColor.white.withAlphaComponent(0.05)
        badge.layer.cornerRadius = 9
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = quality.title
        title.font = .systemFont(ofSize: 16, weight: selected ? .semibold : .medium)
        title.textColor = .white
        let detail = UILabel()
        let key: String
        let fallback: String
        switch quality {
        case .auto: key = "qualityAutoDetail"; fallback = "Adapts to your connection"
        case .high: key = "qualityHighDetail"; fallback = "Best picture quality"
        case .mid: key = "qualityMidDetail"; fallback = "Balanced quality and data"
        case .low: key = "qualityLowDetail"; fallback = "Uses less data"
        }
        detail.text = NSLocalizedString("streamingRoom." + key, tableName: nil, bundle: .main, value: fallback, comment: "")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = UIColor.white.withAlphaComponent(0.45)
        detail.numberOfLines = 0
        let labels = UIStackView(arrangedSubviews: [title, detail])
        labels.axis = .vertical
        labels.spacing = 3
        labels.isUserInteractionEnabled = false
        labels.translatesAutoresizingMaskIntoConstraints = false
        let check = UIImageView(image: UIImage(systemName: selected ? "checkmark.circle.fill" : "circle"))
        check.tintColor = selected ? accent : UIColor.white.withAlphaComponent(0.18)
        check.contentMode = .scaleAspectFit
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        addSubview(labels)
        addSubview(check)
        isAccessibilityElement = true
        accessibilityLabel = quality.title
        accessibilityHint = detail.text
        accessibilityTraits = selected ? [.button, .selected] : [.button]
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 34),
            badge.heightAnchor.constraint(equalToConstant: 34),
            labels.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            labels.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            labels.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -12),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 22),
            check.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.65 : 1 }
    }
}
