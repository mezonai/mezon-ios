import UIKit
import AVFoundation
import AVKit
import WebRTC

protocol ScreenShareExpandedPiPHost: AnyObject {
    func noteScreenShareExpandedSessionEnded()
    func screenShareExpandedDidDismiss()
    func restoreOrientationLockAfterScreenShareDetailIfNeeded()
    func retainScreenSharePiPHost(_ vc: AnyObject)
    func releaseScreenSharePiPHost(_ vc: AnyObject)
    func dismissScreenShareExpandedIfSourceShareEnded()
}

@available(iOS 15.0, *)
final class ScreenShareExpandedViewController: AVPictureInPictureVideoCallViewController, AVPictureInPictureControllerDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    weak var pipHost: ScreenShareExpandedPiPHost?

    var onPttPress: (() -> Void)?
    var onPttRelease: (() -> Void)?
    var showsPttControl = false
    var onCameraToggle: (() -> Void)?
    var onMicToggle: (() -> Void)?
    var onOpenChat: (() -> Void)?
    var onRaiseHand: (() -> Void)?
    var onLeave: (() -> Void)?

    private let callControls = UIStackView()
    private let cameraButton = UIButton(type: .custom)
    private let microphoneButton = UIButton(type: .custom)
    private let chatButton = UIButton(type: .custom)
    private let handButton = UIButton(type: .custom)
    private let leaveButton = UIButton(type: .custom)
    private var controlsVisible = true
    private var isClosingDetail = false

    private let shareTrack: RTCVideoTrack
    private let personName: String
    private let videoView = RTCMTLVideoView()
    private var pipController: AVPictureInPictureController?
    private var didAutoDismissForPiP = false
    private var screenShareFocusPollTimer: Foundation.Timer?

    private let pttPill = UIControl()
    private let pttTint = UIView()
    private let pttIcon = UIImageView()
    private let pttIconSlot = UIView()
    private let pttProgress = UIActivityIndicatorView(style: .medium)
    private let pttLabel = UILabel()
    private var pttHoldTriggered = false
    private var pttControlEnabled = false
    private var pttFeedbackState: SfuPttFeedbackState = .idle
    private var pttReadyShown = false
    private var pttHintView: UIView?

    private var pipSourceView: UIView?
    private var pipBackgroundObserver: NSObjectProtocol?
    private var pipForegroundObserver: NSObjectProtocol?
    private var pipActiveObserver: NSObjectProtocol?

    private let scrollView = UIScrollView()
    private let videoContainer = UIView()

    private let dismissDetailButton = UIButton(type: .system)

    init(track: RTCVideoTrack, displayName: String) {
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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.isAccessibilityElement = true
        scrollView.accessibilityLabel = NSLocalizedString("voiceChannel.screenShare", tableName: nil, bundle: .main, value: "Screen share", comment: "")

        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.videoContentMode = .scaleAspectFit
        videoView.backgroundColor = .clear

        view.addSubview(scrollView)
        scrollView.addSubview(videoContainer)
        videoContainer.addSubview(videoView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            videoContainer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            videoContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            videoContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            videoContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            videoContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            videoContainer.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            videoView.topAnchor.constraint(equalTo: videoContainer.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: videoContainer.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: videoContainer.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: videoContainer.bottomAnchor),
        ])

        let dismissCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        dismissDetailButton.translatesAutoresizingMaskIntoConstraints = false
        dismissDetailButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: dismissCfg), for: .normal)
        dismissDetailButton.tintColor = .white
        dismissDetailButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        dismissDetailButton.layer.cornerRadius = 22
        dismissDetailButton.accessibilityLabel = NSLocalizedString("voiceChannel.closeScreenShare", tableName: nil, bundle: .main, value: "Close screen share", comment: "")
        dismissDetailButton.addTarget(self, action: #selector(closeScreenShareTapped), for: .touchUpInside)
        view.addSubview(dismissDetailButton)

        NSLayoutConstraint.activate([
            dismissDetailButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            dismissDetailButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            dismissDetailButton.widthAnchor.constraint(equalToConstant: 44),
            dismissDetailButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        singleTap.delegate = self
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)

        setupCallControls()
        setupPttControl()
        updateControlsAccessibilityAction()

        shareTrack.add(videoView)
        VideoTrackLastFrameStore.replayLastFrame(of: shareTrack, to: [videoView])
        setupScreenSharePiP()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return false }
        let overlays: [UIView] = [callControls, pttPill, dismissDetailButton]
        return !overlays.contains {
            touchedView === $0 || touchedView.isDescendant(of: $0)
        }
    }

    @objc private func toggleControls() {
        guard !pttHoldTriggered else { return }
        controlsVisible.toggle()
        if !controlsVisible {
            pttHintView?.removeFromSuperview()
            pttHintView = nil
        }
        let overlays: [UIView] = [callControls, pttPill, dismissDetailButton]
        overlays.forEach {
            $0.isUserInteractionEnabled = controlsVisible
            $0.accessibilityElementsHidden = !controlsVisible
        }
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                overlays.forEach { $0.alpha = self.controlsVisible ? 1 : 0 }
            }
        )
        updateControlsAccessibilityAction()
    }

    private func updateControlsAccessibilityAction() {
        let title = controlsVisible
            ? NSLocalizedString("voiceChannel.hideControls", tableName: nil, bundle: .main, value: "Hide controls", comment: "")
            : NSLocalizedString("voiceChannel.showControls", tableName: nil, bundle: .main, value: "Show controls", comment: "")
        scrollView.accessibilityCustomActions = [UIAccessibilityCustomAction(name: title) { [weak self] _ in
            guard let self, !self.pttHoldTriggered else { return false }
            self.toggleControls()
            return true
        }]
    }

    private func setupCallControls() {
        callControls.translatesAutoresizingMaskIntoConstraints = false
        callControls.axis = .horizontal
        callControls.spacing = 10
        callControls.alignment = .center
        callControls.isLayoutMarginsRelativeArrangement = true
        callControls.layoutMargins = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        callControls.backgroundColor = UIColor.theme.secondary
        callControls.layer.cornerRadius = 35

        let controls: [(UIButton, String, String, String, Selector)] = [
            (cameraButton, "video.slash.fill", "voiceChannel.cameraPermissionTitle", "Camera", #selector(cameraTapped)),
            (microphoneButton, "mic.slash.fill", "voiceChannel.micPermissionTitle", "Microphone", #selector(microphoneTapped)),
            (chatButton, "bubble.left.and.bubble.right.fill", "voiceChannel.openChat", "Open chat", #selector(chatTapped)),
            (handButton, "hand.raised.fill", "voiceChannel.raiseHand", "Raise hand", #selector(handTapped)),
            (leaveButton, "phone.down.fill", "voiceChannel.leaveCall", "Leave call", #selector(leaveTapped)),
        ]
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        for (button, symbol, key, label, action) in controls {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
            button.tintColor = UIColor.theme.textStrong
            button.backgroundColor = UIColor.theme.tertiary
            button.layer.cornerRadius = 25
            button.layer.borderWidth = 0.5
            button.layer.borderColor = UIColor.theme.textDisabled.withAlphaComponent(0.6).cgColor
            button.accessibilityLabel = NSLocalizedString(key, tableName: nil, bundle: .main, value: label, comment: "")
            button.addTarget(self, action: action, for: .touchUpInside)
            callControls.addArrangedSubview(button)
            let preferredWidth = button.widthAnchor.constraint(equalToConstant: 50)
            preferredWidth.priority = .defaultHigh
            let minimumWidth = button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
            minimumWidth.priority = UILayoutPriority(999)
            NSLayoutConstraint.activate([
                preferredWidth,
                minimumWidth,
                button.heightAnchor.constraint(equalTo: button.widthAnchor),
            ])
        }
        leaveButton.backgroundColor = UIColor(red: 0.89, green: 0.18, blue: 0.18, alpha: 1)
        leaveButton.tintColor = .white
        leaveButton.layer.borderWidth = 0
        view.addSubview(callControls)
        NSLayoutConstraint.activate([
            callControls.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            callControls.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            callControls.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            callControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    func updateCallControls(cameraOn: Bool, microphoneOn: Bool, handRaised: Bool, connected: Bool) {
        loadViewIfNeeded()
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        cameraButton.setImage(UIImage(systemName: cameraOn ? "video.fill" : "video.slash.fill", withConfiguration: config), for: .normal)
        microphoneButton.setImage(UIImage(systemName: microphoneOn ? "mic.fill" : "mic.slash.fill", withConfiguration: config), for: .normal)
        cameraButton.isSelected = cameraOn
        microphoneButton.isSelected = microphoneOn
        handButton.isSelected = handRaised
        handButton.tintColor = handRaised ? UIColor.theme.textLink : UIColor.theme.textStrong
        handButton.backgroundColor = handRaised ? UIColor.theme.textLink.withAlphaComponent(0.22) : UIColor.theme.tertiary
        handButton.accessibilityLabel = handRaised
            ? NSLocalizedString("voiceChannel.lowerHand", tableName: nil, bundle: .main, value: "Lower hand", comment: "")
            : NSLocalizedString("voiceChannel.raiseHand", tableName: nil, bundle: .main, value: "Raise hand", comment: "")
        for button in [cameraButton, microphoneButton, handButton] {
            button.isEnabled = connected
            button.alpha = connected ? 1 : 0.45
        }
        cameraButton.isHidden = showsPttControl
        microphoneButton.isHidden = showsPttControl
    }

    @objc private func cameraTapped() { onCameraToggle?() }
    @objc private func microphoneTapped() { onMicToggle?() }
    @objc private func handTapped() { onRaiseHand?() }
    @objc private func leaveTapped() {
        closeScreenShare(completion: onLeave)
    }

    @objc private func chatTapped() {
        closeScreenShare(completion: onOpenChat)
    }

    private func setupPttControl() {
        pttPill.translatesAutoresizingMaskIntoConstraints = false
        pttPill.backgroundColor = .clear
        pttPill.layer.cornerRadius = 29
        pttPill.clipsToBounds = true
        pttPill.isHidden = !showsPttControl
        pttPill.isEnabled = pttControlEnabled
        pttPill.isAccessibilityElement = true
        pttPill.accessibilityTraits = .button
        pttPill.addTarget(self, action: #selector(pttTouchDown), for: .touchDown)
        pttPill.addTarget(self, action: #selector(pttTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.isUserInteractionEnabled = false

        pttTint.translatesAutoresizingMaskIntoConstraints = false
        pttTint.backgroundColor = .clear
        pttTint.isUserInteractionEnabled = false

        pttIcon.translatesAutoresizingMaskIntoConstraints = false
        pttIcon.contentMode = .scaleAspectFit
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        pttIcon.image = UIImage(systemName: "mic.slash.fill", withConfiguration: iconCfg)?.withRenderingMode(.alwaysTemplate)
        pttIcon.tintColor = .white
        pttIcon.isUserInteractionEnabled = false

        pttLabel.translatesAutoresizingMaskIntoConstraints = false
        pttLabel.text = SfuPttFeedbackState.idle.localizedTitle
        pttLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        pttLabel.textColor = .white
        pttLabel.isUserInteractionEnabled = false

        pttIconSlot.translatesAutoresizingMaskIntoConstraints = false
        pttIconSlot.isUserInteractionEnabled = false
        pttProgress.translatesAutoresizingMaskIntoConstraints = false
        pttProgress.isUserInteractionEnabled = false
        pttProgress.hidesWhenStopped = true
        pttIconSlot.addSubview(pttIcon)
        pttIconSlot.addSubview(pttProgress)
        let content = UIStackView(arrangedSubviews: [pttIconSlot, pttLabel])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .horizontal
        content.spacing = 8
        content.alignment = .center
        content.isUserInteractionEnabled = false

        pttPill.addSubview(blur)
        pttPill.addSubview(pttTint)
        pttPill.addSubview(content)
        view.addSubview(pttPill)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: pttPill.topAnchor),
            blur.leadingAnchor.constraint(equalTo: pttPill.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: pttPill.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: pttPill.bottomAnchor),

            pttTint.topAnchor.constraint(equalTo: pttPill.topAnchor),
            pttTint.leadingAnchor.constraint(equalTo: pttPill.leadingAnchor),
            pttTint.trailingAnchor.constraint(equalTo: pttPill.trailingAnchor),
            pttTint.bottomAnchor.constraint(equalTo: pttPill.bottomAnchor),

            pttPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pttPill.bottomAnchor.constraint(equalTo: callControls.topAnchor, constant: -12),
            pttPill.heightAnchor.constraint(equalToConstant: 58),
            pttPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            pttIconSlot.widthAnchor.constraint(equalToConstant: 26),
            pttIconSlot.heightAnchor.constraint(equalToConstant: 26),
            pttIcon.topAnchor.constraint(equalTo: pttIconSlot.topAnchor),
            pttIcon.bottomAnchor.constraint(equalTo: pttIconSlot.bottomAnchor),
            pttIcon.leadingAnchor.constraint(equalTo: pttIconSlot.leadingAnchor),
            pttIcon.trailingAnchor.constraint(equalTo: pttIconSlot.trailingAnchor),
            pttProgress.centerXAnchor.constraint(equalTo: pttIconSlot.centerXAnchor),
            pttProgress.centerYAnchor.constraint(equalTo: pttIconSlot.centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: pttPill.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: pttPill.trailingAnchor, constant: -24),
            content.centerXAnchor.constraint(equalTo: pttPill.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: pttPill.centerYAnchor),
        ])
    }

    func setPttControlVisible(_ visible: Bool) {
        showsPttControl = visible
        pttPill.isHidden = !visible
        cameraButton.isHidden = visible
        microphoneButton.isHidden = visible
        if !visible {
            releasePttIfHeld()
        }
        refreshPttFeedback()
    }

    func setPttControlEnabled(_ enabled: Bool) {
        pttControlEnabled = enabled
        pttPill.isEnabled = enabled
        if !enabled { releasePttIfHeld() }
        refreshPttFeedback()
    }

    func setPttFeedbackState(_ state: SfuPttFeedbackState) {
        pttFeedbackState = state
        refreshPttFeedback()
    }

    @objc private func pttTouchDown() {
        guard showsPttControl, pttControlEnabled, !pttHoldTriggered else { return }
        pttHoldTriggered = true
        pttFeedbackState = .idle
        refreshPttFeedback()
        onPttPress?()
    }

    @objc private func pttTouchUp() {
        if pttHoldTriggered {
            pttHoldTriggered = false
            pttFeedbackState = .idle
            refreshPttFeedback()
            onPttRelease?()
        } else {
            showPttHoldHint()
        }
    }

    private func releasePttIfHeld() {
        guard pttHoldTriggered else { return }
        pttHoldTriggered = false
        pttFeedbackState = .idle
        refreshPttFeedback()
        onPttRelease?()
    }

    private func refreshPttFeedback() {
        let state = pttHoldTriggered && showsPttControl && pttControlEnabled ? pttFeedbackState : .idle
        let ready = state == .ready
        let loading = state == .waiting || state == .preparing
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let tint = loading ? UIColor.theme.textWarning : UIColor.white
        pttTint.backgroundColor = ready ? UIColor.theme.bgViolet.withAlphaComponent(0.9) : .clear
        pttPill.layer.borderWidth = loading ? 1 : 0
        pttPill.layer.borderColor = tint.cgColor
        pttIcon.image = UIImage(systemName: ready ? "mic.fill" : "mic.slash.fill", withConfiguration: iconCfg)?.withRenderingMode(.alwaysTemplate)
        pttIcon.tintColor = tint
        pttIcon.isHidden = loading
        pttProgress.color = tint
        if loading { pttProgress.startAnimating() }
        else { pttProgress.stopAnimating() }
        pttLabel.text = state.localizedTitle
        pttLabel.textColor = tint
        pttPill.accessibilityLabel = state.localizedTitle
        if ready {
            if !pttReadyShown {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                startPttPulse()
            }
        } else {
            stopPttPulse()
        }
        pttReadyShown = ready
    }

    private func startPttPulse() {
        pttIcon.layer.removeAnimation(forKey: "pttPulse")
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1
        pulse.toValue = 1.18
        pulse.duration = 0.52
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pttIcon.layer.add(pulse, forKey: "pttPulse")
    }

    private func stopPttPulse() {
        pttIcon.layer.removeAnimation(forKey: "pttPulse")
    }

    private func showPttHoldHint() {
        pttHintView?.removeFromSuperview()
        let hint = UIView()
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        hint.layer.cornerRadius = 16
        hint.isUserInteractionEnabled = false
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = NSLocalizedString("voiceChannel.pttHoldHint", tableName: nil, bundle: .main, value: "Please hold", comment: "")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        hint.addSubview(label)
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: hint.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: hint.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: hint.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: hint.trailingAnchor, constant: -16),
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: pttPill.topAnchor, constant: -12),
        ])
        pttHintView = hint
        hint.alpha = 0
        UIView.animate(withDuration: 0.18) {
            hint.alpha = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak hint] in
            guard let hint else { return }
            UIView.animate(withDuration: 0.25, animations: {
                hint.alpha = 0
            }, completion: { _ in
                hint.removeFromSuperview()
                if self?.pttHintView === hint {
                    self?.pttHintView = nil
                }
            })
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.bringSubviewToFront(callControls)
        view.bringSubviewToFront(pttPill)
        view.bringSubviewToFront(dismissDetailButton)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override var shouldAutorotate: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.layoutIfNeeded()
        VideoTrackLastFrameStore.replayLastFrame(of: shareTrack, to: [videoView])
        UIViewController.attemptRotationToDeviceOrientation()
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        screenShareFocusPollTimer?.invalidate()
        let timer = Foundation.Timer(timeInterval: 0.65, repeats: true) { [weak self] (_: Foundation.Timer) in
            self?.pipHost?.dismissScreenShareExpandedIfSourceShareEnded()
        }
        RunLoop.main.add(timer, forMode: .common)
        screenShareFocusPollTimer = timer
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        releasePttIfHeld()
        screenShareFocusPollTimer?.invalidate()
        screenShareFocusPollTimer = nil
        if isBeingDismissed, !didAutoDismissForPiP {
            pipHost?.noteScreenShareExpandedSessionEnded()
        }
        if isBeingDismissed || isMovingFromParent {
            pipHost?.screenShareExpandedDidDismiss()
        }
        if isBeingDismissed {
            pipHost?.restoreOrientationLockAfterScreenShareDetailIfNeeded()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            if self.scrollView.zoomScale > self.scrollView.minimumZoomScale {
                self.scrollView.setZoomScale(self.scrollView.minimumZoomScale, animated: false)
            }
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        videoContainer
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: videoContainer)
            let zoomRect = CGRect(
                x: point.x - 50,
                y: point.y - 50,
                width: 100,
                height: 100
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    deinit {
        screenShareFocusPollTimer?.invalidate()
        tearDownScreenSharePiP()
        shareTrack.remove(videoView)
    }

    // MARK: - PiP Setup

    private func setupScreenSharePiP() {
        tearDownScreenSharePiP()

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return
        }

        let sourceView = UIView()
        sourceView.translatesAutoresizingMaskIntoConstraints = false
        sourceView.isUserInteractionEnabled = false
        sourceView.alpha = 0.02
        view.addSubview(sourceView)
        NSLayoutConstraint.activate([
            sourceView.widthAnchor.constraint(equalToConstant: 2),
            sourceView.heightAnchor.constraint(equalToConstant: 2),
            sourceView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            sourceView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        ])
        pipSourceView = sourceView

        let contentVC = AVPictureInPictureVideoCallViewController()
        contentVC.preferredContentSize = CGSize(width: 1920, height: 1080)
        contentVC.view.backgroundColor = .black

        let pipVideoView = PeerCallVideoRenderView()
        pipVideoView.translatesAutoresizingMaskIntoConstraints = false
        pipVideoView.renderContentMode = .fit
        pipVideoView.attach(track: shareTrack)
        contentVC.view.addSubview(pipVideoView)
        NSLayoutConstraint.activate([
            pipVideoView.topAnchor.constraint(equalTo: contentVC.view.topAnchor),
            pipVideoView.leadingAnchor.constraint(equalTo: contentVC.view.leadingAnchor),
            pipVideoView.trailingAnchor.constraint(equalTo: contentVC.view.trailingAnchor),
            pipVideoView.bottomAnchor.constraint(equalTo: contentVC.view.bottomAnchor),
        ])

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentVC
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        pip.delegate = self
        pipController = pip

        pipBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tryStartScreenSharePiP()
        }

        pipForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopScreenSharePiPOnForeground()
        }

        pipActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopScreenSharePiPOnForeground()
        }
    }

    private func tryStartScreenSharePiP(retryCount: Int = 0) {
        guard let pip = pipController else { return }
        guard pip === self.pipController else { return }
        guard !pip.isPictureInPictureActive else { return }
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        } else if retryCount < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.tryStartScreenSharePiP(retryCount: retryCount + 1)
            }
        }
    }

    private func stopScreenSharePiPOnForeground() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let pip = self.pipController, pip.isPictureInPictureActive else { return }
            pip.stopPictureInPicture()
        }
    }

    private func tearDownScreenSharePiP() {
        if let obs = pipBackgroundObserver {
            NotificationCenter.default.removeObserver(obs)
            pipBackgroundObserver = nil
        }
        if let obs = pipForegroundObserver {
            NotificationCenter.default.removeObserver(obs)
            pipForegroundObserver = nil
        }
        if let obs = pipActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            pipActiveObserver = nil
        }
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        pipController?.delegate = nil
        pipController = nil
        pipSourceView?.removeFromSuperview()
        pipSourceView = nil
    }

    // MARK: - Tear Down

    func tearDownForVoiceRoomLeaving() {
        releasePttIfHeld()
        onPttPress = nil
        onPttRelease = nil
        onCameraToggle = nil
        onMicToggle = nil
        onOpenChat = nil
        onRaiseHand = nil
        onLeave = nil
        screenShareFocusPollTimer?.invalidate()
        screenShareFocusPollTimer = nil
        tearDownScreenSharePiP()
        shareTrack.remove(videoView)
    }

    @objc private func closeScreenShareTapped() {
        closeScreenShare()
    }

    private func closeScreenShare(completion: (() -> Void)? = nil) {
        guard !isClosingDetail, !isBeingDismissed else { return }
        isClosingDetail = true
        view.isUserInteractionEnabled = false
        releasePttIfHeld()
        screenShareFocusPollTimer?.invalidate()
        screenShareFocusPollTimer = nil
        tearDownScreenSharePiP()
        pipHost?.releaseScreenSharePiPHost(self)
        dismiss(animated: true, completion: completion)
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
    
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard !didAutoDismissForPiP else { return }
        didAutoDismissForPiP = true
        pipHost?.retainScreenSharePiPHost(self)
        dismiss(animated: true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        shareTrack.remove(videoView)
        tearDownScreenSharePiP()
        pipHost?.releaseScreenSharePiPHost(self)
        pipHost?.noteScreenShareExpandedSessionEnded()
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
