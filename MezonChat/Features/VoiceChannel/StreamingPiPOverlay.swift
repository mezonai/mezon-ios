import UIKit
import LiveKitWebRTC

@MainActor
final class StreamingPiPOverlay: NSObject {

    static let shared = StreamingPiPOverlay()

    private static let pipWidth: CGFloat = 200
    private static let pipHeight: CGFloat = 150

    private(set) var context: AccountContext?
    private(set) var channel: Mezon_Api_ChannelDescription?
    private(set) var parentChannelName: String?

    private var pipWindow: UIWindow?
    private let pipView = UIView()
    private let pipChromeBackdrop = UIView()
    private let backgroundImageView = UIImageView()
    private let streamBannerView = UIImageView()
    private let videoView = PeerCallVideoRenderView()
    private let placeholderView = UIImageView()
    private let badgeContainer = UIView()
    private let badgeIcon = UIImageView()
    private let badgeLabel = UILabel()
    private var isDragging = false
    private var themeChangeObserver: NSObjectProtocol?

    private override init() {
        super.init()
        pipView.layer.cornerRadius = 10
        pipView.clipsToBounds = true
        pipView.layer.borderWidth = 1

        pipChromeBackdrop.translatesAutoresizingMaskIntoConstraints = false
        pipChromeBackdrop.isUserInteractionEnabled = false

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.isMirrored = true
        videoView.isUserInteractionEnabled = false
        videoView.isHidden = true

        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.isUserInteractionEnabled = false
        backgroundImageView.isHidden = true

        streamBannerView.translatesAutoresizingMaskIntoConstraints = false
        streamBannerView.contentMode = .scaleAspectFit
        streamBannerView.clipsToBounds = true
        streamBannerView.isUserInteractionEnabled = false
        streamBannerView.isHidden = true
        streamBannerView.image = UIImage(named: "Channel/channelStream")?.withRenderingMode(.alwaysTemplate)
        streamBannerView.tintColor = UIColor.theme.textStrong

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.contentMode = .scaleAspectFit
        placeholderView.image = UIImage(named: "Channel/channelStream")?.withRenderingMode(.alwaysTemplate)
        placeholderView.tintColor = UIColor.theme.textStrong
        placeholderView.isUserInteractionEnabled = false

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badgeContainer.layer.cornerRadius = 10
        badgeContainer.isUserInteractionEnabled = false

        badgeIcon.translatesAutoresizingMaskIntoConstraints = false
        badgeIcon.contentMode = .scaleAspectFit
        badgeIcon.image = UIImage(named: "Channel/channelStream")?.withRenderingMode(.alwaysTemplate)
        badgeIcon.tintColor = .white

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.lineBreakMode = .byTruncatingTail

        pipView.addSubview(pipChromeBackdrop)
        pipView.addSubview(backgroundImageView)
        pipView.addSubview(streamBannerView)
        pipView.addSubview(videoView)
        pipView.addSubview(placeholderView)
        pipView.addSubview(badgeContainer)
        badgeContainer.addSubview(badgeIcon)
        badgeContainer.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            pipChromeBackdrop.topAnchor.constraint(equalTo: pipView.topAnchor),
            pipChromeBackdrop.leadingAnchor.constraint(equalTo: pipView.leadingAnchor),
            pipChromeBackdrop.trailingAnchor.constraint(equalTo: pipView.trailingAnchor),
            pipChromeBackdrop.bottomAnchor.constraint(equalTo: pipView.bottomAnchor),

            videoView.topAnchor.constraint(equalTo: pipView.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: pipView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: pipView.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: pipView.bottomAnchor),

            backgroundImageView.topAnchor.constraint(equalTo: pipView.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: pipView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: pipView.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: pipView.bottomAnchor),

            streamBannerView.centerXAnchor.constraint(equalTo: pipView.centerXAnchor),
            streamBannerView.centerYAnchor.constraint(equalTo: pipView.centerYAnchor, constant: -12),
            streamBannerView.widthAnchor.constraint(equalToConstant: 72),
            streamBannerView.heightAnchor.constraint(equalToConstant: 72),

            placeholderView.centerXAnchor.constraint(equalTo: pipView.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: pipView.centerYAnchor, constant: -12),
            placeholderView.widthAnchor.constraint(equalToConstant: 48),
            placeholderView.heightAnchor.constraint(equalToConstant: 48),

            badgeContainer.bottomAnchor.constraint(equalTo: pipView.bottomAnchor, constant: -6),
            badgeContainer.centerXAnchor.constraint(equalTo: pipView.centerXAnchor),
            badgeContainer.leadingAnchor.constraint(greaterThanOrEqualTo: pipView.leadingAnchor, constant: 6),
            badgeContainer.trailingAnchor.constraint(lessThanOrEqualTo: pipView.trailingAnchor, constant: -6),
            badgeContainer.heightAnchor.constraint(equalToConstant: 20),

            badgeIcon.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            badgeIcon.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),
            badgeIcon.widthAnchor.constraint(equalToConstant: 12),
            badgeIcon.heightAnchor.constraint(equalToConstant: 12),

            badgeLabel.leadingAnchor.constraint(equalTo: badgeIcon.trailingAnchor, constant: 3),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pipView.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        pipView.addGestureRecognizer(tap)
        pipView.isUserInteractionEnabled = true

        applyPiPChromeTheme()
        themeChangeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyPiPChromeTheme()
            }
        }
    }

    var isActive: Bool { pipWindow != nil }

    func show(
        context: AccountContext,
        channel: Mezon_Api_ChannelDescription,
        parentChannelName: String?
    ) {
        self.context = context
        self.channel = channel
        self.parentChannelName = parentChannelName

        badgeLabel.text = channel.channelLabel

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }

        let w = StreamingPiPPassthroughWindow(windowScene: scene)
        w.windowLevel = .statusBar + 1
        w.backgroundColor = .clear
        w.isUserInteractionEnabled = true
        switch ThemeManager.shared.current {
        case .light, .sunrise:
            w.overrideUserInterfaceStyle = .light
        case .dark, .redDark, .purpleHaze, .abyssDark, .sunset:
            w.overrideUserInterfaceStyle = .dark
        case .system:
            w.overrideUserInterfaceStyle = .unspecified
        }
        w.pipView = pipView

        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        rootVC.view.isUserInteractionEnabled = false
        w.rootViewController = rootVC
        w.isHidden = false

        let safeTop = scene.windows.first?.safeAreaInsets.top ?? 50
        pipView.frame = CGRect(
            x: 10,
            y: safeTop + 10,
            width: Self.pipWidth,
            height: Self.pipHeight
        )
        rootVC.view.addSubview(pipView)
        pipView.alpha = 1
        pipView.isUserInteractionEnabled = true
        pipWindow = w

        applyPiPChromeTheme()
        bindSession()
        refreshContent()
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func dismiss(disconnectSession: Bool = true) {
        UIApplication.shared.isIdleTimerDisabled = false
        unbindSession()
        videoView.attach(track: nil)
        pipView.removeFromSuperview()
        pipWindow?.isHidden = true
        pipWindow = nil
        context = nil
        channel = nil
        parentChannelName = nil
        if disconnectSession {
            StreamingWebRTCSession.shared.disconnect()
        }
    }

    func prepareForFullScreenRestore() {
        unbindSession()
        pipView.alpha = 0
        pipView.isUserInteractionEnabled = false
        pipWindow?.isHidden = true
        pipView.removeFromSuperview()
        pipWindow = nil
    }

    private func bindSession() {
        StreamingWebRTCSession.shared.onStreamingStateChanged = { [weak self] in
            self?.refreshContent()
        }
        StreamingWebRTCSession.shared.onRemoteVideoTrackChanged = { [weak self] track in
            self?.videoView.attach(track: track)
            self?.refreshContent()
        }
    }

    private func unbindSession() {
        if StreamingWebRTCSession.shared.onStreamingStateChanged != nil {
            StreamingWebRTCSession.shared.onStreamingStateChanged = nil
        }
        if StreamingWebRTCSession.shared.onRemoteVideoTrackChanged != nil {
            StreamingWebRTCSession.shared.onRemoteVideoTrackChanged = nil
        }
    }

    private func refreshContent() {
        let session = StreamingWebRTCSession.shared
        let hasVideo = session.isRemoteVideoStream
        let isActive = session.isStreaming

        videoView.isHidden = !hasVideo
        backgroundImageView.isHidden = hasVideo || !isActive
        streamBannerView.isHidden = hasVideo || !isActive || hasStreamChannelAvatar
        placeholderView.isHidden = isActive || hasVideo

        if hasVideo {
            videoView.attach(track: session.remoteVideoTrack)
        } else if isActive {
            loadStreamBackgroundIfNeeded()
        }
    }

    private var hasStreamChannelAvatar: Bool {
        guard let channel else { return false }
        return !channel.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadStreamBackgroundIfNeeded() {
        guard let channel, hasStreamChannelAvatar else {
            backgroundImageView.image = nil
            return
        }
        let raw = channel.channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        let px = Int(Self.pipWidth * UIScreen.main.scale)
        let proxy = ImgproxyURL.create(from: raw, width: max(px, 300), height: max(px, 300))
        ImageCache.shared.loadAvatar(urlString: proxy) { [weak self] image in
            self?.backgroundImageView.image = image
        }
    }

    private func applyPiPChromeTheme() {
        let t = UIColor.theme
        pipChromeBackdrop.backgroundColor = t.primary
        pipView.backgroundColor = t.primary
        pipView.layer.borderColor = t.textDisabled.withAlphaComponent(0.5).cgColor
        placeholderView.tintColor = t.textStrong
        streamBannerView.tintColor = t.textStrong
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = pipView.superview else { return }
        let translation = gesture.translation(in: superview)

        switch gesture.state {
        case .began:
            isDragging = false
        case .changed:
            if abs(translation.x) > 5 || abs(translation.y) > 5 {
                isDragging = true
            }
            if isDragging {
                var newCenter = CGPoint(
                    x: pipView.center.x + translation.x,
                    y: pipView.center.y + translation.y
                )
                let halfW = pipView.bounds.width / 2
                let halfH = pipView.bounds.height / 2
                newCenter.x = max(halfW, min(superview.bounds.width - halfW, newCenter.x))
                newCenter.y = max(halfH, min(superview.bounds.height - halfH, newCenter.y))
                pipView.center = newCenter
                gesture.setTranslation(.zero, in: superview)
            }
        case .ended, .cancelled:
            isDragging = false
        default:
            break
        }
    }

    @objc private func handleTap() {
        guard !isDragging else { return }
        restoreFullScreen(animated: true)
    }

    @discardableResult
    func restoreFullScreen(animated: Bool) -> Bool {
        guard let ctx = context, let ch = channel else { return false }
        guard let nav = findVisibleNavigationController() else { return false }

        let vc = StreamingRoomViewController(
            context: ctx,
            channel: ch,
            parentChannelName: parentChannelName,
            existingPiPOverlay: self
        )
        vc.loadViewIfNeeded()
        if animated {
            nav.pushViewController(vc, animated: true)
        } else {
            UIView.performWithoutAnimation {
                nav.pushViewController(vc, animated: false)
                nav.view.layoutIfNeeded()
            }
        }
        return true
    }

    private func findVisibleNavigationController() -> NavigationController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for window in scene.windows where !window.isHidden && window !== pipWindow {
            if let nav = findNavigationControllerInViewHierarchy(window) {
                return nav
            }
            if let root = window.rootViewController {
                if let nav = root.streamingFindDeepestNavigationController() {
                    return nav
                }
            }
        }
        return nil
    }

    private func findNavigationControllerInViewHierarchy(_ view: UIView) -> NavigationController? {
        if let vc = view.next as? NavigationController {
            return vc
        }
        for sub in view.subviews {
            if let nav = findNavigationControllerInViewHierarchy(sub) {
                return nav
            }
        }
        return nil
    }
}

private final class StreamingPiPPassthroughWindow: UIWindow {
    var pipView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let pip = pipView,
              !pip.isHidden,
              pip.alpha > 0.01,
              pip.isUserInteractionEnabled else { return nil }
        let pipPoint = pip.convert(point, from: self)
        if pip.bounds.contains(pipPoint) {
            return pip
        }
        return nil
    }
}

private extension UIViewController {
    func streamingFindDeepestNavigationController() -> NavigationController? {
        if let nav = self as? NavigationController {
            if let tab = nav.topViewController as? TabBarController,
               let current = tab.currentController {
                return current.streamingFindDeepestNavigationController() ?? nav
            }
            return nav
        }
        if let tab = self as? TabBarController, let current = tab.currentController {
            return current.streamingFindDeepestNavigationController()
        }
        if let tab = self as? UITabBarController, let sel = tab.selectedViewController {
            return sel.streamingFindDeepestNavigationController()
        }
        if let presented = presentedViewController {
            if let nav = presented.streamingFindDeepestNavigationController() { return nav }
        }
        for child in children {
            if let nav = child.streamingFindDeepestNavigationController() { return nav }
        }
        return nil
    }
}
