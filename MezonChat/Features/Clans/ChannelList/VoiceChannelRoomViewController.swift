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

@MainActor
final class VoiceChannelPiPOverlay: NSObject {

    static let shared = VoiceChannelPiPOverlay()

    private static let pipWidth: CGFloat = 200
    private static let pipHeight: CGFloat = 150

    private(set) var bridge: VoiceChannelLiveKitBridge?
    private(set) var context: AccountContext?
    private(set) var channel: Mezon_Api_ChannelDescription?
    private(set) var parentChannelName: String?

    private var pipWindow: UIWindow?
    private let pipView = UIView()
    private let videoView = VideoView()
    private let avatarView = UIImageView()
    private let initialLabel = UILabel()
    private let badgeContainer = UIView()
    private let badgeIcon = UIImageView()
    private let badgeLabel = UILabel()
    private var lastAvatarURL: String?
    private var isDragging = false
    private var participantRefreshCallback: (() -> Void)?

    var didAnnounceMeetJoin = false
    var didAnnounceMeetLeave = false

    private override init() {
        super.init()
        pipView.backgroundColor = UIColor.theme.primary
        pipView.layer.cornerRadius = 10
        pipView.clipsToBounds = true
        pipView.layer.borderWidth = 1
        pipView.layer.borderColor = UIColor.theme.textDisabled.withAlphaComponent(0.5).cgColor

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.layoutMode = .fill
        videoView.isPinchToZoomEnabled = false
        videoView.layer.cornerRadius = 10
        videoView.clipsToBounds = true

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 25
        avatarView.isUserInteractionEnabled = false

        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.font = .systemFont(ofSize: 20, weight: .bold)
        initialLabel.textColor = .white
        initialLabel.textAlignment = .center
        initialLabel.isUserInteractionEnabled = false

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badgeContainer.layer.cornerRadius = 10
        badgeContainer.isUserInteractionEnabled = false

        badgeIcon.translatesAutoresizingMaskIntoConstraints = false
        badgeIcon.contentMode = .scaleAspectFit

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.lineBreakMode = .byTruncatingTail

        videoView.isUserInteractionEnabled = false

        pipView.addSubview(videoView)
        pipView.addSubview(avatarView)
        pipView.addSubview(initialLabel)
        pipView.addSubview(badgeContainer)
        badgeContainer.addSubview(badgeIcon)
        badgeContainer.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: pipView.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: pipView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: pipView.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: pipView.bottomAnchor),

            avatarView.centerXAnchor.constraint(equalTo: pipView.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: pipView.centerYAnchor, constant: -12),
            avatarView.widthAnchor.constraint(equalToConstant: 50),
            avatarView.heightAnchor.constraint(equalToConstant: 50),

            initialLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            initialLabel.widthAnchor.constraint(equalTo: avatarView.widthAnchor),
            initialLabel.heightAnchor.constraint(equalTo: avatarView.heightAnchor),

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
    }

    var isActive: Bool { pipWindow != nil }

    func show(
        bridge: VoiceChannelLiveKitBridge,
        context: AccountContext,
        channel: Mezon_Api_ChannelDescription,
        parentChannelName: String?,
        didAnnounceMeetJoin: Bool,
        didAnnounceMeetLeave: Bool
    ) {
        self.bridge = bridge
        self.context = context
        self.channel = channel
        self.parentChannelName = parentChannelName
        self.didAnnounceMeetJoin = didAnnounceMeetJoin
        self.didAnnounceMeetLeave = didAnnounceMeetLeave

        bridge.onRoomParticipantsChanged = { [weak self] in
            self?.refreshContent()
        }
        bridge.onDisconnected = { [weak self] _ in
            self?.dismiss()
        }

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        let w = VoicePiPPassthroughWindow(windowScene: scene)
        w.windowLevel = .statusBar + 1
        w.backgroundColor = .clear
        w.isUserInteractionEnabled = true
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
        pipView.isUserInteractionEnabled = true
        pipWindow = w

        refreshContent()
    }

    func dismiss() {
        sendMeetLeaveIfNeeded()
        let b = bridge
        videoView.track = nil
        b?.clearCallbacks()
        pipView.removeFromSuperview()
        pipWindow?.isHidden = true
        pipWindow = nil
        bridge = nil
        context = nil
        channel = nil
        lastAvatarURL = nil
        Task { await b?.disconnect() }
    }

    private func sendMeetLeaveIfNeeded() {
        guard !didAnnounceMeetLeave, didAnnounceMeetJoin else { return }
        guard let ctx = context, let ch = channel else { return }
        didAnnounceMeetLeave = true
        if let uid = Int64(ctx.currentUser?.id ?? "") {
            ctx.engine.clanData.applyVoiceLeaved(clanId: ch.clanID, channelId: ch.channelID, userId: uid)
        }
        ctx.account.socket.sendVoiceParticipantMeetState(
            clanId: ch.clanID,
            channelId: ch.channelID,
            roomName: "\(ch.channelID)",
            displayName: ctx.currentUser?.displayName ?? ctx.currentUser?.username ?? "Mezon",
            join: false
        )
    }

    func takeOverBridge() -> (VoiceChannelLiveKitBridge, Bool, Bool)? {
        guard let b = bridge else { return nil }
        bridge?.onRoomParticipantsChanged = nil
        bridge?.onDisconnected = nil
        let joinFlag = didAnnounceMeetJoin
        let leaveFlag = didAnnounceMeetLeave
        videoView.track = nil
        pipView.removeFromSuperview()
        pipWindow?.isHidden = true
        pipWindow = nil
        bridge = nil
        context = nil
        channel = nil
        lastAvatarURL = nil
        return (b, joinFlag, leaveFlag)
    }

    private func refreshContent() {
        guard let bridge, let room = bridge.room else { return }
        let local = room.localParticipant
        let remotes = Array(room.remoteParticipants.values)

        for r in remotes {
            if let track = r.firstScreenShareVideoTrack {
                showVideo(track: track, mirror: false)
                let name = resolveDisplayName(r)
                showBadge(icon: "rectangle.on.rectangle", name: "\(name) Share Screen", micOn: true)
                return
            }
        }

        for r in remotes {
            if let track = r.firstCameraVideoTrack {
                showVideo(track: track, mirror: false)
                let name = resolveDisplayName(r)
                showBadge(icon: r.isMicrophoneEnabled() ? "mic.fill" : "mic.slash.fill", name: name, micOn: r.isMicrophoneEnabled())
                return
            }
        }

        if let track = local.firstScreenShareVideoTrack {
            showVideo(track: track, mirror: false)
            let name = resolveDisplayName(local)
            showBadge(icon: "rectangle.on.rectangle", name: "\(name) Share Screen", micOn: true)
            return
        }

        if let track = local.firstCameraVideoTrack {
            showVideo(track: track, mirror: true)
            let name = resolveDisplayName(local)
            showBadge(icon: local.isMicrophoneEnabled() ? "mic.fill" : "mic.slash.fill", name: name, micOn: local.isMicrophoneEnabled())
            return
        }

        let first: Participant = remotes.first ?? local
        showAvatar(participant: first)
        let name = resolveDisplayName(first)
        showBadge(icon: first.isMicrophoneEnabled() ? "mic.fill" : "mic.slash.fill", name: name, micOn: first.isMicrophoneEnabled())
    }

    private func showVideo(track: VideoTrack, mirror: Bool) {
        avatarView.isHidden = true
        initialLabel.isHidden = true
        videoView.isHidden = false
        videoView.mirrorMode = mirror ? .auto : .off
        if videoView.track !== track {
            videoView.track = track
        }
    }

    private func showAvatar(participant: Participant) {
        videoView.track = nil
        videoView.isHidden = true
        avatarView.isHidden = false

        let key = participant.identity?.stringValue ?? ""
        let url = resolveAvatarURL(key)
        let name = resolveDisplayName(participant)

        if url != lastAvatarURL {
            lastAvatarURL = url
            avatarView.image = nil
            if let raw = url, !raw.isEmpty {
                initialLabel.isHidden = true
                let side = Int(50 * UIScreen.main.scale)
                let proxy = ImgproxyURL.create(from: raw, width: side, height: side)
                ImageCache.shared.loadAvatar(urlString: proxy) { [weak self] img in
                    guard let self else { return }
                    self.avatarView.image = img
                    if img != nil {
                        self.initialLabel.isHidden = true
                    } else {
                        self.initialLabel.isHidden = false
                        self.initialLabel.text = String(name.prefix(1)).uppercased()
                    }
                }
            } else {
                avatarView.backgroundColor = UIColor.theme.colorAvatarDefault
                initialLabel.isHidden = false
                initialLabel.text = String(name.prefix(1)).uppercased()
            }
        }
    }

    private func showBadge(icon: String, name: String, micOn: Bool) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        badgeIcon.image = UIImage(systemName: icon, withConfiguration: cfg)
        badgeIcon.tintColor = micOn ? .white : UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        badgeLabel.text = name
    }

    private func resolveDisplayName(_ participant: Participant) -> String {
        guard let ctx = context else { return participant.name ?? "…" }
        if participant is LocalParticipant {
            if let d = ctx.currentUser?.displayName, !d.isEmpty { return d }
            if let n = ctx.currentUser?.username, !n.isEmpty { return n }
            return "You"
        }
        if let n = participant.name, !n.isEmpty { return n }
        let key = participant.identity?.stringValue ?? ""
        if let profile = ctx.account.postbox.read({ $0.getProfile(userId: key) }) {
            if let d = profile.displayName, !d.isEmpty { return d }
            if !profile.username.isEmpty { return profile.username }
        }
        return key.isEmpty ? "…" : key
    }

    private func resolveAvatarURL(_ key: String) -> String? {
        guard let ctx = context else { return nil }
        if let my = ctx.currentUser?.id, my == key,
           let url = ctx.currentUser?.avatarURL?.absoluteString, !url.isEmpty {
            return url
        }
        if let profile = ctx.account.postbox.read({ $0.getProfile(userId: key) }),
           let av = profile.avatarUrl, !av.isEmpty {
            return av
        }
        return nil
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
        restoreFullScreen()
    }

    private func restoreFullScreen() {
        guard let ctx = context, let ch = channel else { return }
        guard let nav = findVisibleNavigationController() else { return }
        let vc = VoiceChannelRoomViewController(
            context: ctx,
            channel: ch,
            parentChannelName: parentChannelName,
            existingPiPOverlay: self
        )
        nav.pushViewController(vc, animated: true)
    }

    private func findVisibleNavigationController() -> NavigationController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for window in scene.windows where !window.isHidden && window !== pipWindow {
            if let nav = findNavigationControllerInViewHierarchy(window) {
                return nav
            }
            if let root = window.rootViewController {
                if let nav = root.findDeepestNavigationController() {
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

private final class VoicePiPPassthroughWindow: UIWindow {
    var pipView: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let pip = pipView else { return nil }
        let pipPoint = pip.convert(point, from: self)
        if pip.bounds.contains(pipPoint) {
            return pip
        }
        return nil
    }
}

private extension UIViewController {
    func findDeepestNavigationController() -> NavigationController? {
        if let nav = self as? NavigationController {
            if let tab = nav.topViewController as? TabBarController,
               let current = tab.currentController {
                return current.findDeepestNavigationController() ?? nav
            }
            return nav
        }
        if let tab = self as? TabBarController, let current = tab.currentController {
            return current.findDeepestNavigationController()
        }
        if let tab = self as? UITabBarController, let sel = tab.selectedViewController {
            return sel.findDeepestNavigationController()
        }
        if let presented = presentedViewController {
            if let nav = presented.findDeepestNavigationController() { return nav }
        }
        for child in children {
            if let nav = child.findDeepestNavigationController() { return nav }
        }
        return nil
    }
}

final class VoiceChannelRoomViewController: ViewController {

    private let context: AccountContext
    private let channel: Mezon_Api_ChannelDescription
    private let parentChannelName: String?
    private let existingPiPOverlay: VoiceChannelPiPOverlay?

    private var liveKitBridge: VoiceChannelLiveKitBridge?
    private var connectTask: Task<Void, Never>?
    private var didStartVoiceConnection = false
    private var micButton: UIButton!
    private var camButton: UIButton!
    private var didAnnounceMeetJoin = false
    private var didAnnounceMeetLeave = false
    private var audioRouteObserver: NSObjectProtocol?

    private var participantRows: [String: VoiceParticipantRowView] = [:]
    fileprivate var screenSharePiPHostRetain: AnyObject?

    private var callPiPController: AVPictureInPictureController?
    private var callPiPSourceView: UIView?
    private var callPiPContentVC: UIViewController?

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
    private let participantsGrid = UIStackView()
    private var orderedDescriptorKeys: [String] = []

    private let bottomPill = UIView()
    private let bottomControlsStack = UIStackView()

    init(context: AccountContext, channel: Mezon_Api_ChannelDescription, parentChannelName: String? = nil, existingPiPOverlay: VoiceChannelPiPOverlay? = nil) {
        self.context = context
        self.channel = channel
        self.parentChannelName = parentChannelName
        self.existingPiPOverlay = existingPiPOverlay
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
        collapseButton.addTarget(self, action: #selector(minimizeToPiP), for: .touchUpInside)

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
        cameraSwitchButton.isHidden = true
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

        participantsGrid.translatesAutoresizingMaskIntoConstraints = false
        participantsGrid.axis = .vertical
        participantsGrid.spacing = 10
        participantsGrid.alignment = .fill

        contentScroll.addSubview(participantArea)
        participantArea.addSubview(participantsGrid)

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

            participantsGrid.topAnchor.constraint(equalTo: participantArea.topAnchor),
            participantsGrid.leadingAnchor.constraint(equalTo: participantArea.leadingAnchor, constant: 10),
            participantsGrid.trailingAnchor.constraint(equalTo: participantArea.trailingAnchor, constant: -10),
            participantsGrid.bottomAnchor.constraint(equalTo: participantArea.bottomAnchor),

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
        callPiPController?.stopPictureInPicture()
        callPiPController?.delegate = nil
        callPiPController = nil
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

        if let pip = existingPiPOverlay, let (bridge, joinFlag, leaveFlag) = pip.takeOverBridge() {
            self.liveKitBridge = bridge
            self.didAnnounceMeetJoin = joinFlag
            self.didAnnounceMeetLeave = leaveFlag
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
            refreshMicButtonIcon()
            refreshCamButtonIcon()
            refreshSpeakerRouteUI()
            refreshParticipantRowsFromLiveKit()
            setupCallPiP()
            return
        }

        connectTask = Task { @MainActor in
            await self.runVoiceConnectionPipeline()
        }
    }

    private var isMinimizingToPiP = false

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMinimizingToPiP { return }
        if isMovingFromParent || isBeingDismissed {
            if let bridge = liveKitBridge {
                tearDownCallPiP()
                tearDownScreenSharePresentationAndPiP()
                connectTask?.cancel()
                connectTask = nil

                for row in participantRows.values {
                    row.prepareForRemoval()
                }
                participantRows.removeAll()

                isMinimizingToPiP = true
                bridge.clearCallbacks()
                self.liveKitBridge = nil

                VoiceChannelPiPOverlay.shared.show(
                    bridge: bridge,
                    context: context,
                    channel: channel,
                    parentChannelName: parentChannelName,
                    didAnnounceMeetJoin: didAnnounceMeetJoin,
                    didAnnounceMeetLeave: didAnnounceMeetLeave
                )
            } else {
                tearDownCallPiP()
                tearDownScreenSharePresentationAndPiP()
                connectTask?.cancel()
                connectTask = nil
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
        tearDownCallPiP()
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

    @objc private func minimizeToPiP() {
        guard let bridge = liveKitBridge else { return }
        tearDownCallPiP()
        tearDownScreenSharePresentationAndPiP()
        connectTask?.cancel()
        connectTask = nil

        for row in participantRows.values {
            row.prepareForRemoval()
        }
        participantRows.removeAll()

        isMinimizingToPiP = true
        bridge.clearCallbacks()
        self.liveKitBridge = nil

        VoiceChannelPiPOverlay.shared.show(
            bridge: bridge,
            context: context,
            channel: channel,
            parentChannelName: parentChannelName,
            didAnnounceMeetJoin: didAnnounceMeetJoin,
            didAnnounceMeetLeave: didAnnounceMeetLeave
        )

        navigationController?.popViewController(animated: true)
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

            refreshMicButtonIcon()
            AudioManager.shared.isSpeakerOutputPreferred = false
            refreshSpeakerRouteUI()
            refreshCamButtonIcon()
            announceMeetJoinIfNeeded()
            refreshParticipantRowsFromLiveKit()
            setConnectingOverlayVisible(false)
            setupCallPiP()
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

    private func setupCallPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard callPiPController == nil else { return }
        if #available(iOS 15.0, *) {
            let sourceView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            sourceView.isHidden = true
            view.addSubview(sourceView)
            callPiPSourceView = sourceView

            let contentVC = AVPictureInPictureVideoCallViewController()
            contentVC.preferredContentSize = CGSize(width: 360, height: 240)
            contentVC.view.backgroundColor = UIColor.theme.primary

            let pipAvatarView = UIImageView()
            pipAvatarView.translatesAutoresizingMaskIntoConstraints = false
            pipAvatarView.contentMode = .scaleAspectFill
            pipAvatarView.clipsToBounds = true
            pipAvatarView.layer.cornerRadius = 30
            pipAvatarView.backgroundColor = UIColor.theme.colorAvatarDefault

            let pipInitialLabel = UILabel()
            pipInitialLabel.translatesAutoresizingMaskIntoConstraints = false
            pipInitialLabel.font = .systemFont(ofSize: 24, weight: .bold)
            pipInitialLabel.textColor = .white
            pipInitialLabel.textAlignment = .center

            let pipNameLabel = UILabel()
            pipNameLabel.translatesAutoresizingMaskIntoConstraints = false
            pipNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            pipNameLabel.textColor = .white
            pipNameLabel.textAlignment = .center

            let pipStatusLabel = UILabel()
            pipStatusLabel.translatesAutoresizingMaskIntoConstraints = false
            pipStatusLabel.font = .systemFont(ofSize: 11, weight: .regular)
            pipStatusLabel.textColor = UIColor.white.withAlphaComponent(0.7)
            pipStatusLabel.textAlignment = .center
            pipStatusLabel.tag = 9001

            let iconView = UIImageView()
            iconView.translatesAutoresizingMaskIntoConstraints = false
            iconView.contentMode = .scaleAspectFit
            let iconCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            iconView.image = UIImage(systemName: "phone.fill", withConfiguration: iconCfg)
            iconView.tintColor = UIColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1)

            contentVC.view.addSubview(pipAvatarView)
            contentVC.view.addSubview(pipInitialLabel)
            contentVC.view.addSubview(iconView)
            contentVC.view.addSubview(pipNameLabel)
            contentVC.view.addSubview(pipStatusLabel)

            NSLayoutConstraint.activate([
                pipAvatarView.centerXAnchor.constraint(equalTo: contentVC.view.centerXAnchor),
                pipAvatarView.centerYAnchor.constraint(equalTo: contentVC.view.centerYAnchor, constant: -24),
                pipAvatarView.widthAnchor.constraint(equalToConstant: 60),
                pipAvatarView.heightAnchor.constraint(equalToConstant: 60),

                pipInitialLabel.centerXAnchor.constraint(equalTo: pipAvatarView.centerXAnchor),
                pipInitialLabel.centerYAnchor.constraint(equalTo: pipAvatarView.centerYAnchor),
                pipInitialLabel.widthAnchor.constraint(equalTo: pipAvatarView.widthAnchor),

                iconView.trailingAnchor.constraint(equalTo: pipNameLabel.leadingAnchor, constant: -4),
                iconView.centerYAnchor.constraint(equalTo: pipNameLabel.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 14),
                iconView.heightAnchor.constraint(equalToConstant: 14),

                pipNameLabel.centerXAnchor.constraint(equalTo: contentVC.view.centerXAnchor, constant: 10),
                pipNameLabel.topAnchor.constraint(equalTo: pipAvatarView.bottomAnchor, constant: 8),

                pipStatusLabel.centerXAnchor.constraint(equalTo: contentVC.view.centerXAnchor),
                pipStatusLabel.topAnchor.constraint(equalTo: pipNameLabel.bottomAnchor, constant: 2),
            ])

            let displayName: String
            if let d = context.currentUser?.displayName, !d.isEmpty {
                displayName = d
            } else if let n = context.currentUser?.username, !n.isEmpty {
                displayName = n
            } else {
                displayName = "You"
            }
            pipNameLabel.text = displayName
            pipStatusLabel.text = NSLocalizedString("voiceChannel.pipStatus", tableName: nil, bundle: .main, value: "You're alone on the call", comment: "")

            if let avatarURLStr = context.currentUser?.avatarURL?.absoluteString, !avatarURLStr.isEmpty {
                pipInitialLabel.isHidden = true
                let side = Int(60 * UIScreen.main.scale)
                let proxy = ImgproxyURL.create(from: avatarURLStr, width: side, height: side)
                ImageCache.shared.loadAvatar(urlString: proxy) { img in
                    pipAvatarView.image = img
                    if img == nil {
                        pipInitialLabel.isHidden = false
                        pipInitialLabel.text = String(displayName.prefix(1)).uppercased()
                    }
                }
            } else {
                pipInitialLabel.isHidden = false
                pipInitialLabel.text = String(displayName.prefix(1)).uppercased()
            }

            callPiPContentVC = contentVC

            let source = AVPictureInPictureController.ContentSource(
                activeVideoCallSourceView: sourceView,
                contentViewController: contentVC
            )
            let pip = AVPictureInPictureController(contentSource: source)
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            pip.delegate = self
            callPiPController = pip
        }
    }

    private func tearDownCallPiP() {
        callPiPController?.stopPictureInPicture()
        callPiPController?.delegate = nil
        callPiPController = nil
        callPiPSourceView?.removeFromSuperview()
        callPiPSourceView = nil
        callPiPContentVC = nil
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
        orderedDescriptorKeys = orderedKeys
        rebuildGrid()
        updateCallPiPContent(room: room)
    }

    private func updateCallPiPContent(room: Room) {
        guard let contentVC = callPiPContentVC else { return }
        guard let statusLabel = contentVC.view.viewWithTag(9001) as? UILabel else { return }
        let remoteCount = room.remoteParticipants.count
        if remoteCount == 0 {
            statusLabel.text = NSLocalizedString("voiceChannel.pipStatus", tableName: nil, bundle: .main, value: "You're alone on the call", comment: "")
        } else {
            let total = remoteCount + 1
            statusLabel.text = String(format: NSLocalizedString("voiceChannel.pipParticipants", tableName: nil, bundle: .main, value: "%d participants", comment: ""), total)
        }
    }

    private func rebuildGrid() {
        for v in participantsGrid.arrangedSubviews {
            participantsGrid.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let tiles: [VoiceParticipantRowView] = orderedDescriptorKeys.compactMap { participantRows[$0] }
        var i = 0
        while i < tiles.count {
            if i + 1 < tiles.count {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 10
                row.alignment = .fill
                row.distribution = .fillEqually
                row.addArrangedSubview(tiles[i])
                row.addArrangedSubview(tiles[i + 1])
                row.heightAnchor.constraint(equalToConstant: 150).isActive = true
                participantsGrid.addArrangedSubview(row)
                i += 2
            } else {
                let wrapper = UIView()
                wrapper.translatesAutoresizingMaskIntoConstraints = false
                let tile = tiles[i]
                tile.translatesAutoresizingMaskIntoConstraints = false
                wrapper.addSubview(tile)
                let gridWidth = participantsGrid.bounds.width
                let tileWidth = max(0, (gridWidth - 10) / 2)
                NSLayoutConstraint.activate([
                    wrapper.heightAnchor.constraint(equalToConstant: 150),
                    tile.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                    tile.topAnchor.constraint(equalTo: wrapper.topAnchor),
                    tile.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                    tile.widthAnchor.constraint(equalToConstant: tileWidth > 0 ? tileWidth : 170),
                ])
                participantsGrid.addArrangedSubview(wrapper)
                i += 1
            }
        }
    }

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
        if let profile = context.account.postbox.read({ $0.getProfile(userId: userIdKey) }) {
            if let d = profile.displayName, !d.isEmpty { return d }
            if !profile.username.isEmpty { return profile.username }
        }
        guard let uid = Int64(userIdKey),
              let list = context.engine.clanData.getClanUsers(clanId: channel.clanID) else {
            return userIdKey.isEmpty ? "…" : userIdKey
        }
        for cu in list.clanUsers where cu.user.id == uid {
            if !cu.clanNick.isEmpty { return cu.clanNick }
            if !cu.user.displayName.isEmpty { return cu.user.displayName }
            if !cu.user.username.isEmpty { return cu.user.username }
        }
        return userIdKey
    }

    private func resolveAvatarURL(identityKey: String) -> String? {
        if let my = context.currentUser?.id, my == identityKey,
           let url = context.currentUser?.avatarURL?.absoluteString, !url.isEmpty {
            return url
        }
        if let profile = context.account.postbox.read({ $0.getProfile(userId: identityKey) }),
           let av = profile.avatarUrl, !av.isEmpty {
            return av
        }
        guard let uid = Int64(identityKey),
              let list = context.engine.clanData.getClanUsers(clanId: channel.clanID) else { return nil }
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
        cameraSwitchButton.isHidden = !cameraOn
    }

    private func handleLiveKitDisconnected(error: LiveKitError?) {
        guard liveKitBridge != nil else { return }

        tearDownCallPiP()
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
        guard #available(iOS 15.0, *) else { return }
        let vc = ScreenShareExpandedViewController(track: track, displayName: displayName)
        vc.pipHost = self
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func tearDownScreenSharePresentationAndPiP() {
        if #available(iOS 15.0, *) {
            if let expanded = presentedViewController as? ScreenShareExpandedViewController {
                expanded.tearDownForVoiceRoomLeaving()
                dismiss(animated: false)
            }
            if let retained = screenSharePiPHostRetain as? ScreenShareExpandedViewController {
                retained.tearDownForVoiceRoomLeaving()
            }
        }
        screenSharePiPHostRetain = nil
    }

    fileprivate func retainScreenSharePiPHost(_ vc: AnyObject) {
        if #available(iOS 15.0, *) {
            if let old = screenSharePiPHostRetain as? ScreenShareExpandedViewController, old !== vc {
                old.tearDownForVoiceRoomLeaving()
            }
        }
        screenSharePiPHostRetain = vc
    }

    fileprivate func releaseScreenSharePiPHost(_ vc: AnyObject) {
        guard screenSharePiPHostRetain === vc else { return }
        screenSharePiPHostRetain = nil
    }
}

extension VoiceChannelRoomViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pictureInPictureController === callPiPController else { return }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard pictureInPictureController === callPiPController else { return }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        guard pictureInPictureController === callPiPController else { return }
        AppLogger.network.error("[VoiceChannel] Call PiP failed: \(error)")
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        guard pictureInPictureController === callPiPController else {
            completionHandler(false)
            return
        }
        completionHandler(true)
    }
}

@available(iOS 15.0, *)
private final class ScreenShareExpandedViewController: AVPictureInPictureVideoCallViewController, AVPictureInPictureControllerDelegate, UIScrollViewDelegate {

    weak var pipHost: VoiceChannelRoomViewController?

    private let shareTrack: VideoTrack
    private let personName: String
    private let videoView = VideoView()
    private var pipController: AVPictureInPictureController?
    private var didAutoDismissForPiP = false

    private let scrollView = UIScrollView()
    private let videoContainer = UIView()

    private let minimizeButton = UIButton(type: .system)
    private var controlsVisible = true

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var shouldAutorotate: Bool { true }

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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false

        videoContainer.translatesAutoresizingMaskIntoConstraints = false
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.layoutMode = .fit
        videoView.mirrorMode = .off
        videoView.isPinchToZoomEnabled = false

        view.addSubview(scrollView)
        scrollView.addSubview(videoContainer)
        videoContainer.addSubview(videoView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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

        let minimizeCfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        minimizeButton.translatesAutoresizingMaskIntoConstraints = false
        minimizeButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left", withConfiguration: minimizeCfg), for: .normal)
        minimizeButton.tintColor = .white
        minimizeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        minimizeButton.layer.cornerRadius = 20
        minimizeButton.addTarget(self, action: #selector(closeScreenShareTapped), for: .touchUpInside)
        view.addSubview(minimizeButton)

        NSLayoutConstraint.activate([
            minimizeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            minimizeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            minimizeButton.widthAnchor.constraint(equalToConstant: 40),
            minimizeButton.heightAnchor.constraint(equalToConstant: 40),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControls))
        tap.numberOfTapsRequired = 1
        scrollView.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        videoView.track = shareTrack
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        videoContainer
    }

    @objc private func toggleControls() {
        controlsVisible.toggle()
        UIView.animate(withDuration: 0.25) {
            self.minimizeButton.alpha = self.controlsVisible ? 1 : 0
        }
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

    @objc private func closeScreenShareTapped() {
        pipController?.stopPictureInPicture()
        pipHost?.releaseScreenSharePiPHost(self)
        dismiss(animated: true)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        AppLogger.network.error("[VoiceChannel] PiP failed: \(error)")
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
    private let videoView = VideoView()
    private let avatarView = UIImageView()
    private let initialLabel = UILabel()
    private let expandButton = UIButton(type: .system)
    private let badgeContainer = UIView()
    private let badgeIcon = UIImageView()
    private let badgeLabel = UILabel()
    private var lastAvatarURL: String?

    init(identityKey: String, tileKind: VoiceParticipantTileKind) {
        self.identityKey = identityKey
        self.tileKind = tileKind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true

        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 10
        card.clipsToBounds = true
        card.layer.borderWidth = 1

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.layoutMode = .fill
        videoView.isPinchToZoomEnabled = false
        videoView.layer.cornerRadius = 10
        videoView.clipsToBounds = true

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 25

        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.font = .systemFont(ofSize: 20, weight: .bold)
        initialLabel.textColor = .white
        initialLabel.textAlignment = .center

        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.isHidden = tileKind != .screenShare
        let expandCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: expandCfg), for: .normal)
        expandButton.tintColor = .white
        expandButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        expandButton.layer.cornerRadius = 6
        expandButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        expandButton.isUserInteractionEnabled = tileKind == .screenShare
        expandButton.addTarget(self, action: #selector(expandScreenShareTapped), for: .touchUpInside)

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badgeContainer.layer.cornerRadius = 12

        badgeIcon.translatesAutoresizingMaskIntoConstraints = false
        badgeIcon.contentMode = .scaleAspectFit
        badgeIcon.setContentHuggingPriority(.required, for: .horizontal)
        badgeIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.numberOfLines = 1

        addSubview(card)
        card.addSubview(videoView)
        card.addSubview(avatarView)
        card.addSubview(initialLabel)
        if tileKind == .screenShare {
            card.addSubview(expandButton)
        }
        card.addSubview(badgeContainer)
        badgeContainer.addSubview(badgeIcon)
        badgeContainer.addSubview(badgeLabel)

        var constraints: [NSLayoutConstraint] = [
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),

            videoView.topAnchor.constraint(equalTo: card.topAnchor),
            videoView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            videoView.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            avatarView.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            avatarView.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: -10),
            avatarView.widthAnchor.constraint(equalToConstant: 50),
            avatarView.heightAnchor.constraint(equalToConstant: 50),

            initialLabel.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            initialLabel.widthAnchor.constraint(equalTo: avatarView.widthAnchor),
            initialLabel.heightAnchor.constraint(equalTo: avatarView.heightAnchor),

            badgeContainer.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            badgeContainer.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            badgeContainer.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 6),
            badgeContainer.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -6),

            badgeIcon.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 8),
            badgeIcon.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),
            badgeIcon.widthAnchor.constraint(equalToConstant: 14),
            badgeIcon.heightAnchor.constraint(equalToConstant: 14),

            badgeLabel.leadingAnchor.constraint(equalTo: badgeIcon.trailingAnchor, constant: 4),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -8),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

            badgeContainer.heightAnchor.constraint(equalToConstant: 24),
        ]
        if tileKind == .screenShare {
            constraints.append(contentsOf: [
                expandButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                expandButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func expandScreenShareTapped() {
        onExpandScreenShare?()
    }

    deinit {
        videoView.track = nil
    }

    func prepareForRemoval() {
        videoView.track = nil
    }

    func applyTheme() {
        card.backgroundColor = UIColor.theme.secondary
        card.layer.borderColor = UIColor.theme.borderDim.cgColor
    }

    func configure(
        displayName: String,
        micOn: Bool,
        speaking: Bool,
        avatarURL: String?,
        videoTrack: VideoTrack?,
        mirrorVideo: Bool
    ) {
        let iconCfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        switch tileKind {
        case .mainVideo:
            let micName = micOn ? "mic.fill" : "mic.slash.fill"
            badgeIcon.image = UIImage(systemName: micName, withConfiguration: iconCfg)
            badgeIcon.tintColor = micOn ? .white : UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
            badgeLabel.text = displayName
        case .screenShare:
            badgeIcon.image = UIImage(systemName: "rectangle.on.rectangle", withConfiguration: iconCfg)
            badgeIcon.tintColor = .white
            badgeLabel.text = "\(displayName) Share Screen"
        }

        if let track = videoTrack {
            avatarView.isHidden = true
            initialLabel.isHidden = true
            videoView.isHidden = false
            videoView.mirrorMode = mirrorVideo ? .auto : .off
            if videoView.track !== track {
                videoView.track = track
            }
        } else {
            videoView.track = nil
            videoView.isHidden = true
            avatarView.isHidden = false
            initialLabel.isHidden = (avatarURL != nil && !(avatarURL ?? "").isEmpty)
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
                initialLabel.isHidden = true
                let side = Int(50 * UIScreen.main.scale)
                let proxy = ImgproxyURL.create(from: raw, width: side, height: side)
                ImageCache.shared.loadAvatar(urlString: proxy) { [weak self] img in
                    guard let self else { return }
                    self.avatarView.image = img
                    if img != nil {
                        self.initialLabel.isHidden = true
                    } else {
                        self.initialLabel.isHidden = false
                        self.initialLabel.text = String(displayName.prefix(1)).uppercased()
                    }
                }
            } else {
                avatarView.image = nil
                avatarView.backgroundColor = UIColor.theme.colorAvatarDefault
                initialLabel.isHidden = false
                initialLabel.text = String(displayName.prefix(1)).uppercased()
            }
        }
    }
}
