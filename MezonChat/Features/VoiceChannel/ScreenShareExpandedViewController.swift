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
final class ScreenShareExpandedViewController: AVPictureInPictureVideoCallViewController, AVPictureInPictureControllerDelegate, UIScrollViewDelegate {

    weak var pipHost: ScreenShareExpandedPiPHost?

    var onPttPress: (() -> Void)?
    var onPttRelease: (() -> Void)?
    var showsPttControl = false

    private let shareTrack: RTCVideoTrack
    private let personName: String
    private let videoView = RTCMTLVideoView()
    private var pipController: AVPictureInPictureController?
    private var didAutoDismissForPiP = false
    private var screenShareFocusPollTimer: Foundation.Timer?

    private let pttPill = UIControl()
    private let pttTint = UIView()
    private let pttIcon = UIImageView()
    private let pttLabel = UILabel()
    private var pttHoldWork: DispatchWorkItem?
    private var pttHoldTriggered = false
    private var pttHintView: UIView?
    private var pttDimWork: DispatchWorkItem?

    private var pipSourceView: UIView?
    private var pipBackgroundObserver: NSObjectProtocol?
    private var pipForegroundObserver: NSObjectProtocol?
    private var pipActiveObserver: NSObjectProtocol?

    private let scrollView = UIScrollView()
    private let videoContainer = UIView()

    private let dismissDetailButton = UIButton(type: .system)

    private var scrollTopConstraint: NSLayoutConstraint!
    private var scrollLeadingConstraint: NSLayoutConstraint!
    private var scrollTrailingConstraint: NSLayoutConstraint!
    private var scrollBottomConstraint: NSLayoutConstraint!
    private var dismissDetailTopConstraint: NSLayoutConstraint!
    private var dismissDetailTrailingConstraint: NSLayoutConstraint!

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

        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.videoContentMode = .scaleAspectFit
        videoView.backgroundColor = .clear

        view.addSubview(scrollView)
        scrollView.addSubview(videoContainer)
        videoContainer.addSubview(videoView)

        scrollTopConstraint = scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0)
        scrollLeadingConstraint = scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 0)
        scrollTrailingConstraint = scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: 0)
        scrollBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 0)

        NSLayoutConstraint.activate([
            scrollTopConstraint,
            scrollLeadingConstraint,
            scrollTrailingConstraint,
            scrollBottomConstraint,

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

        dismissDetailTopConstraint = dismissDetailButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        dismissDetailTrailingConstraint = dismissDetailButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            dismissDetailTopConstraint,
            dismissDetailTrailingConstraint,
            dismissDetailButton.widthAnchor.constraint(equalToConstant: 44),
            dismissDetailButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        setupPttControl()

        shareTrack.add(videoView)
        applyScreenShareLayoutForCurrentBounds()
        setupScreenSharePiP()
    }

    private func setupPttControl() {
        pttPill.translatesAutoresizingMaskIntoConstraints = false
        pttPill.backgroundColor = .clear
        pttPill.layer.cornerRadius = 29
        pttPill.clipsToBounds = true
        pttPill.isHidden = !showsPttControl
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
        pttLabel.text = NSLocalizedString("voiceChannel.pushToTalk", tableName: nil, bundle: .main, value: "Push to Talk", comment: "")
        pttLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        pttLabel.textColor = .white
        pttLabel.isUserInteractionEnabled = false

        let content = UIStackView(arrangedSubviews: [pttIcon, pttLabel])
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
            pttPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            pttPill.heightAnchor.constraint(equalToConstant: 58),
            pttPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            pttIcon.widthAnchor.constraint(equalToConstant: 26),
            pttIcon.heightAnchor.constraint(equalToConstant: 26),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: pttPill.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: pttPill.trailingAnchor, constant: -24),
            content.centerXAnchor.constraint(equalTo: pttPill.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: pttPill.centerYAnchor),
        ])
    }

    func setPttControlVisible(_ visible: Bool) {
        showsPttControl = visible
        pttPill.isHidden = !visible
        if visible {
            restorePttDim()
            schedulePttDim()
        } else {
            releasePttIfHeld()
        }
    }

    private func schedulePttDim() {
        pttDimWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pttHoldTriggered else { return }
            self.pttDimWork = nil
            UIView.animate(withDuration: 0.4) {
                self.pttPill.alpha = 0.55
            }
        }
        pttDimWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func restorePttDim() {
        pttDimWork?.cancel()
        pttDimWork = nil
        UIView.animate(withDuration: 0.12) {
            self.pttPill.alpha = 1
        }
    }

    func setPttActive(_ active: Bool) {
        guard !active, pttHoldTriggered else { return }
        pttHoldTriggered = false
        setPttPressed(false)
        stopPttPulse()
    }

    @objc private func pttTouchDown() {
        restorePttDim()
        pttHoldWork?.cancel()
        pttHoldTriggered = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pttHoldWork = nil
            self.pttHoldTriggered = true
            self.setPttPressed(true)
            self.startPttPulse()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.onPttPress?()
        }
        pttHoldWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    @objc private func pttTouchUp() {
        pttHoldWork?.cancel()
        pttHoldWork = nil
        if pttHoldTriggered {
            pttHoldTriggered = false
            setPttPressed(false)
            stopPttPulse()
            onPttRelease?()
        } else {
            showPttHoldHint()
        }
        schedulePttDim()
    }

    private func releasePttIfHeld() {
        pttHoldWork?.cancel()
        pttHoldWork = nil
        pttDimWork?.cancel()
        pttDimWork = nil
        guard pttHoldTriggered else { return }
        pttHoldTriggered = false
        setPttPressed(false)
        stopPttPulse()
        onPttRelease?()
    }

    private func setPttPressed(_ pressed: Bool) {
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        if pressed {
            pttTint.backgroundColor = UIColor.theme.bgViolet.withAlphaComponent(0.9)
            pttIcon.image = UIImage(systemName: "mic.fill", withConfiguration: iconCfg)?.withRenderingMode(.alwaysTemplate)
        } else {
            pttTint.backgroundColor = .clear
            pttIcon.image = UIImage(systemName: "mic.slash.fill", withConfiguration: iconCfg)?.withRenderingMode(.alwaysTemplate)
        }
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

    private func applyScreenShareLayoutForCurrentBounds() {
        let landscape = view.bounds.width > view.bounds.height
        let margin: CGFloat = landscape ? 20 : 0
        scrollTopConstraint.constant = margin
        scrollLeadingConstraint.constant = margin
        scrollTrailingConstraint.constant = -margin
        scrollBottomConstraint.constant = -margin
        dismissDetailTopConstraint.constant = 12 + margin
        dismissDetailTrailingConstraint.constant = -(12 + margin)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyScreenShareLayoutForCurrentBounds()
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
        if showsPttControl {
            schedulePttDim()
        }
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
            self.applyScreenShareLayoutForCurrentBounds()
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
        screenShareFocusPollTimer?.invalidate()
        screenShareFocusPollTimer = nil
        tearDownScreenSharePiP()
        shareTrack.remove(videoView)
    }

    @objc private func closeScreenShareTapped() {
        releasePttIfHeld()
        screenShareFocusPollTimer?.invalidate()
        screenShareFocusPollTimer = nil
        tearDownScreenSharePiP()
        pipHost?.releaseScreenSharePiPHost(self)
        dismiss(animated: true)
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
