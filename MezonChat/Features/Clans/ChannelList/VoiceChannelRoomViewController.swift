import UIKit
import AVFoundation
import AVKit
import MediaPlayer
import AsyncDisplayKit
import LiveKit

private let kVoiceKomuAgentDefaultAvatarURL =
    "https://imgproxy.mezon.ai/K0YUZRIosDOcz5lY6qrgC6UIXmQgWzLjZv7VJ1RAA8c/rs:fit:100:100:1/mb:2097152/plain/https://cdn.mezon.vn/0/0/1779484387973271600/1737423959329_undefined173740153013517374015248704886401586613166392.png@webp"

private enum VoiceParticipantTileKind {
    case mainVideo
    case screenShare
}

private enum VoiceMoreToolsPopoverMetrics {
    static let buttonSide: CGFloat = 40
    static let imageInset: CGFloat = 11
    static var panelContentWidth: CGFloat { buttonSide + 20 }
    static var buttonCornerRadius: CGFloat { buttonSide / 2 }
    static var symbolPointSize: CGFloat { 16 }
}

private struct VoiceParticipantTileDescriptor {
    let rowKey: String
    let participant: Participant
    let kind: VoiceParticipantTileKind
}

@MainActor
private func voiceChannelFindClanUser(context: AccountContext, clanId: Int64, identityKey: String) -> Mezon_Api_ClanUserList.ClanUser? {
    let key = identityKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, let list = context.engine.clanData.getClanUsers(clanId: clanId) else { return nil }
    if let uid = Int64(key) {
        for cu in list.clanUsers where cu.user.id == uid { return cu }
    }
    for cu in list.clanUsers where String(cu.user.id) == key { return cu }
    return nil
}

@MainActor
private func voiceChannelDisplayNameFromClanUser(_ cu: Mezon_Api_ClanUserList.ClanUser) -> String? {
    if !cu.clanNick.isEmpty { return cu.clanNick }
    if !cu.user.displayName.isEmpty { return cu.user.displayName }
    if !cu.user.username.isEmpty { return cu.user.username }
    return nil
}

@MainActor
private func voiceChannelAvatarURLFromClanUser(_ cu: Mezon_Api_ClanUserList.ClanUser) -> String? {
    if !cu.clanAvatar.isEmpty { return cu.clanAvatar }
    if !cu.user.avatarURL.isEmpty { return cu.user.avatarURL }
    return nil
}

@MainActor
private func voiceChannelMeetStateDisplayName(context: AccountContext, clanId: Int64) -> String {
    if let idStr = context.currentUser?.id,
       let cu = voiceChannelFindClanUser(context: context, clanId: clanId, identityKey: idStr),
       let name = voiceChannelDisplayNameFromClanUser(cu) {
        return name
    }
    if let d = context.currentUser?.displayName, !d.isEmpty { return d }
    if let n = context.currentUser?.username, !n.isEmpty { return n }
    return "Mezon"
}

@MainActor
private func voiceChannelResolveAvatarURL(context: AccountContext, clanId: Int64, identityKey: String) -> String? {
    if let cu = voiceChannelFindClanUser(context: context, clanId: clanId, identityKey: identityKey),
       let url = voiceChannelAvatarURLFromClanUser(cu), !url.isEmpty {
        return url
    }
    if let my = context.currentUser?.id, my == identityKey,
       let url = context.currentUser?.avatarURL?.absoluteString, !url.isEmpty {
        return url
    }
    if let profile = context.account.postbox.read({ $0.getProfile(userId: identityKey) }),
       let av = profile.avatarUrl, !av.isEmpty {
        return av
    }
    return nil
}

@MainActor
private func voiceChannelResolveDisplayNameForUserId(context: AccountContext, clanId: Int64, userId: Int64) -> String {
    let key = "\(userId)"
    if let cu = voiceChannelFindClanUser(context: context, clanId: clanId, identityKey: key),
       let name = voiceChannelDisplayNameFromClanUser(cu) {
        return name
    }
    if context.currentUser?.id == key {
        if let d = context.currentUser?.displayName, !d.isEmpty { return d }
        if let n = context.currentUser?.username, !n.isEmpty { return n }
        return NSLocalizedString("voiceChannel.placeholderYou", tableName: nil, bundle: .main, value: "You", comment: "")
    }
    if let profile = context.account.postbox.read({ $0.getProfile(userId: key) }) {
        if let d = profile.displayName, !d.isEmpty { return d }
        if !profile.username.isEmpty { return profile.username }
    }
    return key
}

@MainActor
private func voiceChannelShortProfileSubtitleLine(cu: Mezon_Api_ClanUserList.ClanUser?, identityFallback: String) -> String {
    if let cu {
        if !cu.user.username.isEmpty { return cu.user.username }
        if !cu.user.displayName.isEmpty { return cu.user.displayName }
    }
    return identityFallback
}

@MainActor
private func voiceChannelResolveDisplayName(context: AccountContext, clanId: Int64, participant: Participant) -> String {
    let isLocal = participant is LocalParticipant
    let idKey: String
    if isLocal {
        idKey = context.currentUser?.id ?? ""
    } else {
        idKey = participant.identity?.stringValue ?? ""
    }
    if let cu = voiceChannelFindClanUser(context: context, clanId: clanId, identityKey: idKey),
       let name = voiceChannelDisplayNameFromClanUser(cu) {
        return name
    }
    if isLocal {
        if let d = context.currentUser?.displayName, !d.isEmpty { return d }
        if let n = context.currentUser?.username, !n.isEmpty { return n }
        return NSLocalizedString("voiceChannel.placeholderYou", tableName: nil, bundle: .main, value: "You", comment: "")
    }
    if let n = participant.name, !n.isEmpty { return n }
    if let profile = context.account.postbox.read({ $0.getProfile(userId: idKey) }) {
        if let d = profile.displayName, !d.isEmpty { return d }
        if !profile.username.isEmpty { return profile.username }
    }
    return idKey.isEmpty ? "…" : idKey
}

private func liveKitDisconnectIsFatal(_ error: LiveKitError?) -> Bool {
    guard let lk = error else { return false }
    switch lk.type {
    case .participantRemoved, .duplicateIdentity, .roomDeleted, .cancelled, .insufficientPermissions:
        return true
    default:
        return false
    }
}

fileprivate enum VoiceChannelPiPPreservedAudioRoute {
    case speaker
    case earpiece
    case bluetooth
}

@MainActor
fileprivate func applyVoiceChannelPreservedAudioRouteToSession(_ route: VoiceChannelPiPPreservedAudioRoute) {
    let session = AVAudioSession.sharedInstance()
    do {
        switch route {
        case .speaker:
            AudioManager.shared.isSpeakerOutputPreferred = true
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.speaker)
        case .bluetooth:
            AudioManager.shared.isSpeakerOutputPreferred = false
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.none)
        case .earpiece:
            AudioManager.shared.isSpeakerOutputPreferred = false
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.overrideOutputAudioPort(.none)
        }
    } catch {
    }
}

private final class VoiceHeaderSystemAudioRouteControl: UIView {
    private let stateIconView = UIImageView()
    private let volumeView = MPVolumeView()
    private let hitProxy = UIButton(type: .custom)
    private weak var routePickerButton: UIButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        stateIconView.translatesAutoresizingMaskIntoConstraints = false
        stateIconView.contentMode = .scaleAspectFit
        stateIconView.isUserInteractionEnabled = false

        volumeView.showsVolumeSlider = false
        volumeView.showsRouteButton = true
        volumeView.backgroundColor = .clear
        volumeView.isUserInteractionEnabled = false
        volumeView.translatesAutoresizingMaskIntoConstraints = false

        hitProxy.translatesAutoresizingMaskIntoConstraints = false
        hitProxy.backgroundColor = .clear
        hitProxy.accessibilityLabel = NSLocalizedString("voiceChannel.audioRouteTitle", tableName: nil, bundle: .main, value: "Audio output", comment: "")
        hitProxy.addTarget(self, action: #selector(hitProxyTapped), for: .touchUpInside)

        addSubview(stateIconView)
        addSubview(volumeView)
        addSubview(hitProxy)
        NSLayoutConstraint.activate([
            stateIconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stateIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stateIconView.widthAnchor.constraint(equalToConstant: 22),
            stateIconView.heightAnchor.constraint(equalToConstant: 22),
            volumeView.topAnchor.constraint(equalTo: topAnchor),
            volumeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            volumeView.leadingAnchor.constraint(equalTo: leadingAnchor),
            volumeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hitProxy.topAnchor.constraint(equalTo: topAnchor),
            hitProxy.bottomAnchor.constraint(equalTo: bottomAnchor),
            hitProxy.leadingAnchor.constraint(equalTo: leadingAnchor),
            hitProxy.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        DispatchQueue.main.async { [weak self] in
            self?.stripSystemRouteButtonChrome()
        }
    }

    private func stripSystemRouteButtonChrome() {
        for sub in volumeView.subviews {
            if let b = sub as? UIButton {
                routePickerButton = b
                b.isUserInteractionEnabled = false
                b.alpha = 0
                b.setImage(nil, for: .normal)
                b.setImage(nil, for: .highlighted)
                b.setImage(nil, for: .selected)
                b.setBackgroundImage(nil, for: .normal)
            }
        }
    }

    @objc private func hitProxyTapped() {
        routePickerButton?.sendActions(for: .touchUpInside)
    }

    func applyHeaderChrome(background: UIColor, border: UIColor) {
        backgroundColor = background
        layer.cornerRadius = 20
        layer.borderWidth = 1
        layer.borderColor = border.cgColor
    }

    func applyTint(_ color: UIColor) {
        volumeView.tintColor = .clear
        stateIconView.tintColor = color
    }

    func setRouteStateSymbol(systemName: String, pointSize: CGFloat, weight: UIImage.SymbolWeight) {
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        stateIconView.image = UIImage(systemName: systemName, withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate)
    }
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
    private var preservedAudioRoute: VoiceChannelPiPPreservedAudioRoute?

    private var pipWindow: UIWindow?
    private let pipView = UIView()
    private let pipChromeBackdrop = UIView()
    private let videoView = VideoView()
    private let systemCallPiPVideoView = VideoView()
    private let avatarView = UIImageView()
    private let initialLabel = UILabel()
    private let badgeContainer = UIView()
    private let badgeIcon = UIImageView()
    private let badgeLabel = UILabel()
    private var lastAvatarURL: String?
    private var isDragging = false
    private var participantRefreshCallback: (() -> Void)?

    private var systemCallPiPController: AVPictureInPictureController?
    private var systemCallPiPSourceView: UIView?
    private var systemCallPiPContentVC: UIViewController?
    private var systemCallPiPBackgroundObserver: NSObjectProtocol?
    private var themeChangeObserver: NSObjectProtocol?

    private weak var overlayPiPRootViewController: UIViewController?
    private var overlayLiveKitReconnectTask: Task<Void, Never>?
    private static let overlayLiveKitReconnectMax = 5

    var didAnnounceMeetJoin = false
    var didAnnounceMeetLeave = false
    private(set) var crossClanVoiceExitAlignClanId: Int64?

    private override init() {
        super.init()
        pipView.layer.cornerRadius = 10
        pipView.clipsToBounds = true
        pipView.layer.borderWidth = 1

        pipChromeBackdrop.translatesAutoresizingMaskIntoConstraints = false
        pipChromeBackdrop.isUserInteractionEnabled = false

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.layoutMode = .fill
        videoView.isPinchToZoomEnabled = false
        videoView.isOpaque = false
        videoView.backgroundColor = .clear
        videoView.layer.cornerRadius = 10
        videoView.clipsToBounds = true

        systemCallPiPVideoView.translatesAutoresizingMaskIntoConstraints = false
        systemCallPiPVideoView.layoutMode = .fill
        systemCallPiPVideoView.isPinchToZoomEnabled = false
        systemCallPiPVideoView.isOpaque = false
        systemCallPiPVideoView.backgroundColor = .clear
        systemCallPiPVideoView.layer.cornerRadius = 10
        systemCallPiPVideoView.clipsToBounds = true
        systemCallPiPVideoView.isUserInteractionEnabled = false
        systemCallPiPVideoView.isHidden = true

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

        pipView.addSubview(pipChromeBackdrop)
        pipView.addSubview(videoView)
        pipView.addSubview(avatarView)
        pipView.addSubview(initialLabel)
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

    private func applyPiPChromeTheme() {
        let t = UIColor.theme
        pipChromeBackdrop.backgroundColor = t.primary
        pipView.backgroundColor = t.primary
        pipView.layer.borderColor = t.textDisabled.withAlphaComponent(0.5).cgColor
        initialLabel.textColor = t.textStrong
        if #available(iOS 15.0, *), let vc = systemCallPiPContentVC {
            vc.view.backgroundColor = t.primary
            if let pipNameLabel = vc.view.viewWithTag(VoiceCallSystemPiPViewTag.name) as? UILabel {
                pipNameLabel.textColor = t.textStrong
            }
            if let pipStatusLabel = vc.view.viewWithTag(VoiceCallSystemPiPViewTag.status) as? UILabel {
                pipStatusLabel.textColor = t.textDisabled
            }
            if let pipInitialLabel = vc.view.viewWithTag(VoiceCallSystemPiPViewTag.initial) as? UILabel {
                pipInitialLabel.textColor = t.textStrong
            }
        }
    }

    var isActive: Bool { pipWindow != nil }

    fileprivate func show(
        bridge: VoiceChannelLiveKitBridge,
        context: AccountContext,
        channel: Mezon_Api_ChannelDescription,
        parentChannelName: String?,
        didAnnounceMeetJoin: Bool,
        didAnnounceMeetLeave: Bool,
        preservedAudioRoute: VoiceChannelPiPPreservedAudioRoute,
        crossClanVoiceExitAlignClanId: Int64? = nil
    ) {
        self.crossClanVoiceExitAlignClanId = crossClanVoiceExitAlignClanId
        self.bridge = bridge
        self.context = context
        self.channel = channel
        self.parentChannelName = parentChannelName
        self.didAnnounceMeetJoin = didAnnounceMeetJoin
        self.didAnnounceMeetLeave = didAnnounceMeetLeave
        self.preservedAudioRoute = preservedAudioRoute

        bridge.onRoomParticipantsChanged = { [weak self] in
            self?.refreshContent()
        }
        bridge.onDisconnected = { [weak self] err in
            self?.handleOverlayLiveKitDisconnected(error: err)
        }

        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else {
            return
        }
        let w = VoicePiPPassthroughWindow(windowScene: scene)
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
        overlayPiPRootViewController = rootVC

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

        applyPiPChromeTheme()
        refreshContent()
        setupOverlaySystemCallPiP(rootVC: rootVC)
        applyPiPChromeTheme()
        applyVoiceChannelPreservedAudioRouteToSession(preservedAudioRoute)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func applyCrossClanVoiceHomeExitFromPiPIfNeeded(alignClanId: Int64?, channelId: Int64) {
        guard let alignClanId, alignClanId != 0, channelId != 0 else { return }
        NotificationCenter.default.post(
            name: .mezonAlignHomeAfterCrossClanVoice,
            object: nil,
            userInfo: ["clanId": alignClanId, "channelId": channelId]
        )
        findVisibleNavigationController()?.popToRoot(animated: true)
    }

    func dismiss() {
        let savedAlign = crossClanVoiceExitAlignClanId
        let savedChannelId = channel?.channelID ?? 0
        UIApplication.shared.isIdleTimerDisabled = false
        overlayLiveKitReconnectTask?.cancel()
        overlayLiveKitReconnectTask = nil
        overlayPiPRootViewController = nil
        sendMeetLeaveIfNeeded()
        tearDownOverlaySystemCallPiP()
        let b = bridge
        videoView.track = nil
        systemCallPiPVideoView.track = nil
        b?.clearCallbacks()
        pipView.removeFromSuperview()
        pipWindow?.isHidden = true
        pipWindow = nil
        bridge = nil
        context = nil
        channel = nil
        lastAvatarURL = nil
        preservedAudioRoute = nil
        crossClanVoiceExitAlignClanId = nil
        applyCrossClanVoiceHomeExitFromPiPIfNeeded(alignClanId: savedAlign, channelId: savedChannelId)
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
            displayName: voiceChannelMeetStateDisplayName(context: ctx, clanId: ch.clanID),
            join: false
        )
    }

    private func handleOverlayLiveKitDisconnected(error: LiveKitError?) {
        guard bridge != nil else { return }
        overlayLiveKitReconnectTask?.cancel()
        if liveKitDisconnectIsFatal(error) {
            dismiss()
            return
        }
        tearDownOverlaySystemCallPiP()
        overlayLiveKitReconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.executeOverlayLiveKitReconnect()
        }
    }

    private func executeOverlayLiveKitReconnect() async {
        guard bridge != nil, context != nil, let ch = channel else { return }
        let meetURL = MezonConfig.meetWebSocketURLString
        let roomName = "\(ch.channelID)"
        for attempt in 1...Self.overlayLiveKitReconnectMax {
            guard self.bridge != nil, pipWindow != nil else { return }
            let delaySec = attempt == 1 ? 0.4 : min(Double(attempt) * 1.2, 12.0)
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            if Task.isCancelled { return }
            guard let b = self.bridge, let ctx2 = self.context, let ch2 = self.channel else { return }
            await ctx2.waitForSessionReady()
            if Task.isCancelled { return }
            guard let token = await ctx2.getToken() else {
                dismiss()
                return
            }
            do {
                let jwt = try await ctx2.account.network.generateMeetToken(
                    channelId: ch2.channelID,
                    roomName: roomName,
                    token: token
                )
                guard !jwt.isEmpty else { continue }
                try await b.connect(url: meetURL, token: jwt)
                if Task.isCancelled { return }
                refreshContent()
                if let root = overlayPiPRootViewController {
                    setupOverlaySystemCallPiP(rootVC: root)
                    applyPiPChromeTheme()
                }
                if let route = preservedAudioRoute {
                    applyVoiceChannelPreservedAudioRouteToSession(route)
                }
                return
            } catch {
            }
        }
        dismiss()
    }

    fileprivate func takeOverBridge() -> (VoiceChannelLiveKitBridge, Bool, Bool, VoiceChannelPiPPreservedAudioRoute?)? {
        overlayLiveKitReconnectTask?.cancel()
        overlayLiveKitReconnectTask = nil
        overlayPiPRootViewController = nil
        tearDownOverlaySystemCallPiP()
        guard let b = bridge else { return nil }
        bridge?.onRoomParticipantsChanged = nil
        bridge?.onDisconnected = nil
        let joinFlag = didAnnounceMeetJoin
        let leaveFlag = didAnnounceMeetLeave
        let route = preservedAudioRoute
        preservedAudioRoute = nil
        videoView.track = nil
        systemCallPiPVideoView.track = nil
        pipView.removeFromSuperview()
        pipWindow?.isHidden = true
        pipWindow = nil
        bridge = nil
        context = nil
        channel = nil
        lastAvatarURL = nil
        crossClanVoiceExitAlignClanId = nil
        return (b, joinFlag, leaveFlag, route)
    }

    private func refreshContent() {
        guard let bridge, let room = bridge.room else { return }
        defer { updateOverlaySystemCallPiPStatusFromRoom() }
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

        if let track = local.firstScreenShareVideoTrack {
            showVideo(track: track, mirror: false)
            let name = resolveDisplayName(local)
            showBadge(icon: "rectangle.on.rectangle", name: "\(name) Share Screen", micOn: true)
            return
        }

        if let track = local.firstCameraVideoTrack {
            let mirrorLocal = bridge.currentCameraCapturePosition() == .front
            showVideo(track: track, mirror: mirrorLocal)
            let name = resolveDisplayName(local)
            showBadge(icon: local.isMicrophoneEnabled() ? "mic.fill" : "mic.slash.fill", name: name, micOn: local.isMicrophoneEnabled())
            return
        }

        showAvatar(participant: local)
        let name = resolveDisplayName(local)
        showBadge(icon: local.isMicrophoneEnabled() ? "mic.fill" : "mic.slash.fill", name: name, micOn: local.isMicrophoneEnabled())
    }

    private func showVideo(track: VideoTrack, mirror: Bool) {
        avatarView.isHidden = true
        initialLabel.isHidden = true
        videoView.isHidden = false
        videoView.alpha = 1
        videoView.mirrorMode = mirror ? .auto : .off
        if videoView.track !== track {
            videoView.track = track
        }
        if let container = systemCallPiPContentVC?.view {
            systemCallPiPVideoView.isHidden = false
            systemCallPiPVideoView.alpha = 1
            systemCallPiPVideoView.mirrorMode = mirror ? .auto : .off
            if systemCallPiPVideoView.track !== track {
                systemCallPiPVideoView.track = track
            }
            voiceCallSystemPiPSetChromeHidden(container, hidden: true)
        }
    }

    private func showAvatar(participant: Participant) {
        videoView.track = nil
        videoView.isHidden = true
        videoView.alpha = 0
        if let container = systemCallPiPContentVC?.view {
            systemCallPiPVideoView.track = nil
            systemCallPiPVideoView.isHidden = true
            systemCallPiPVideoView.alpha = 0
            voiceCallSystemPiPSetChromeHidden(container, hidden: false)
        }
        avatarView.isHidden = false

        let key = participant.identity?.stringValue ?? ""
        let url = resolveAvatarURL(key, participant: participant)
        let name = resolveDisplayName(participant)

        if url != lastAvatarURL {
            lastAvatarURL = url
            avatarView.image = nil
            if let raw = url, !raw.isEmpty {
                initialLabel.isHidden = true
                let proxy = ImgproxyURL.create(from: raw, width: 150, height: 150)
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
        badgeIcon.tintColor = .white
        badgeLabel.text = name
    }

    private func resolveDisplayName(_ participant: Participant) -> String {
        guard let ctx = context, let ch = channel else { return participant.name ?? "…" }
        return voiceChannelResolveDisplayName(context: ctx, clanId: ch.clanID, participant: participant)
    }

    private func resolveAvatarURL(_ key: String, participant: Participant) -> String? {
        if participant.kind == .agent {
            return kVoiceKomuAgentDefaultAvatarURL
        }
        guard let ctx = context, let ch = channel else { return nil }
        return voiceChannelResolveAvatarURL(context: ctx, clanId: ch.clanID, identityKey: key)
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
            voiceChannelCrossClanExitAlignClanId: crossClanVoiceExitAlignClanId,
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

    private func setupOverlaySystemCallPiP(rootVC: UIViewController) {
        guard #available(iOS 15.0, *) else {
            return
        }
        tearDownOverlaySystemCallPiP()
        guard let ctx = context, let ch = channel else {
            return
        }
        guard let (sourceView, contentVC, pip) = VoiceCallSystemPiPFactory.make(sourceSuperview: rootVC.view, context: ctx, clanId: ch.clanID) else {
            return
        }
        systemCallPiPSourceView = sourceView
        systemCallPiPContentVC = contentVC
        systemCallPiPVideoView.removeFromSuperview()
        contentVC.view.insertSubview(systemCallPiPVideoView, at: 0)
        NSLayoutConstraint.activate([
            systemCallPiPVideoView.topAnchor.constraint(equalTo: contentVC.view.topAnchor),
            systemCallPiPVideoView.leadingAnchor.constraint(equalTo: contentVC.view.leadingAnchor),
            systemCallPiPVideoView.trailingAnchor.constraint(equalTo: contentVC.view.trailingAnchor),
            systemCallPiPVideoView.bottomAnchor.constraint(equalTo: contentVC.view.bottomAnchor),
        ])
        pip.delegate = self
        systemCallPiPController = pip
        systemCallPiPBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tryStartOverlaySystemPiPIfNeeded()
            }
        }
        updateOverlaySystemCallPiPStatusFromRoom()
        refreshContent()
    }

    private func tryStartOverlaySystemPiPIfNeeded() {
        guard #available(iOS 15.0, *) else {
            return
        }
        guard let pip = systemCallPiPController else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pipWindow != nil else { return }
            guard pip === self.systemCallPiPController else { return }
            guard pip.isPictureInPicturePossible else {
                return
            }
            guard !pip.isPictureInPictureActive else {
                return
            }
            pip.startPictureInPicture()
        }
    }

    private func updateOverlaySystemCallPiPStatusFromRoom() {
        guard #available(iOS 15.0, *) else { return }
        guard let contentVC = systemCallPiPContentVC, let bridge, let room = bridge.room else { return }
        guard let statusLabel = contentVC.view.viewWithTag(VoiceCallSystemPiPViewTag.status) as? UILabel else { return }
        let remoteCount = room.remoteParticipants.count
        if remoteCount == 0 {
            statusLabel.text = NSLocalizedString("voiceChannel.pipStatus", tableName: nil, bundle: .main, value: "You're alone on the call", comment: "")
        } else {
            let total = remoteCount + 1
            statusLabel.text = String(format: NSLocalizedString("voiceChannel.pipParticipants", tableName: nil, bundle: .main, value: "%d participants", comment: ""), total)
        }
    }

    private func tearDownOverlaySystemCallPiP() {
        if let obs = systemCallPiPBackgroundObserver {
            NotificationCenter.default.removeObserver(obs)
            systemCallPiPBackgroundObserver = nil
        }
        let pip = systemCallPiPController
        if pip?.isPictureInPictureActive == true {
            pip?.stopPictureInPicture()
        }
        pip?.delegate = nil
        systemCallPiPController = nil
        systemCallPiPVideoView.track = nil
        systemCallPiPVideoView.removeFromSuperview()
        systemCallPiPSourceView?.removeFromSuperview()
        systemCallPiPSourceView = nil
        systemCallPiPContentVC = nil
    }
}

extension VoiceChannelPiPOverlay: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self, pictureInPictureController === self.systemCallPiPController else { return }
            self.tearDownOverlaySystemCallPiP()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(false)
                return
            }
            guard pictureInPictureController === self.systemCallPiPController else {
                completionHandler(false)
                return
            }
            completionHandler(true)
        }
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

private enum VoiceCallSystemPiPViewTag {
    static let status = 9001
    static let name = 9002
    static let initial = 9003
    static let avatar = 9010
    static let phoneIcon = 9011
}

@MainActor
private func voiceCallSystemPiPChromeTags() -> [Int] {
    [VoiceCallSystemPiPViewTag.status, VoiceCallSystemPiPViewTag.name, VoiceCallSystemPiPViewTag.initial, VoiceCallSystemPiPViewTag.avatar, VoiceCallSystemPiPViewTag.phoneIcon]
}

@MainActor
private func voiceCallSystemPiPSetChromeHidden(_ container: UIView, hidden: Bool) {
    for tag in voiceCallSystemPiPChromeTags() {
        container.viewWithTag(tag)?.isHidden = hidden
    }
}

@available(iOS 15.0, *)
private enum VoiceCallSystemPiPFactory {
    @MainActor
    static func make(sourceSuperview: UIView, context: AccountContext, clanId: Int64) -> (UIView, AVPictureInPictureVideoCallViewController, AVPictureInPictureController)? {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            return nil
        }

        let sourceView = UIView()
        sourceView.translatesAutoresizingMaskIntoConstraints = false
        sourceView.isUserInteractionEnabled = false
        sourceView.alpha = 0.02
        sourceSuperview.addSubview(sourceView)
        NSLayoutConstraint.activate([
            sourceView.widthAnchor.constraint(equalToConstant: 2),
            sourceView.heightAnchor.constraint(equalToConstant: 2),
            sourceView.leadingAnchor.constraint(equalTo: sourceSuperview.safeAreaLayoutGuide.leadingAnchor),
            sourceView.bottomAnchor.constraint(equalTo: sourceSuperview.safeAreaLayoutGuide.bottomAnchor),
        ])

        let contentVC = AVPictureInPictureVideoCallViewController()
        contentVC.preferredContentSize = CGSize(width: 360, height: 240)
        contentVC.view.backgroundColor = UIColor.theme.primary

        let pipAvatarView = UIImageView()
        pipAvatarView.translatesAutoresizingMaskIntoConstraints = false
        pipAvatarView.contentMode = .scaleAspectFill
        pipAvatarView.clipsToBounds = true
        pipAvatarView.layer.cornerRadius = 30
        pipAvatarView.tag = VoiceCallSystemPiPViewTag.avatar
        pipAvatarView.backgroundColor = UIColor.theme.colorAvatarDefault

        let pipInitialLabel = UILabel()
        pipInitialLabel.translatesAutoresizingMaskIntoConstraints = false
        pipInitialLabel.font = .systemFont(ofSize: 24, weight: .bold)
        pipInitialLabel.textColor = UIColor.theme.textStrong
        pipInitialLabel.textAlignment = .center
        pipInitialLabel.tag = VoiceCallSystemPiPViewTag.initial

        let pipNameLabel = UILabel()
        pipNameLabel.translatesAutoresizingMaskIntoConstraints = false
        pipNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pipNameLabel.textColor = UIColor.theme.textStrong
        pipNameLabel.textAlignment = .center
        pipNameLabel.tag = VoiceCallSystemPiPViewTag.name

        let pipStatusLabel = UILabel()
        pipStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        pipStatusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        pipStatusLabel.textColor = UIColor.theme.textDisabled
        pipStatusLabel.textAlignment = .center
        pipStatusLabel.tag = VoiceCallSystemPiPViewTag.status

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tag = VoiceCallSystemPiPViewTag.phoneIcon
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

        let displayName = voiceChannelMeetStateDisplayName(context: context, clanId: clanId)
        pipNameLabel.text = displayName
        pipStatusLabel.text = NSLocalizedString("voiceChannel.pipStatus", tableName: nil, bundle: .main, value: "You're alone on the call", comment: "")

        let localId = context.currentUser?.id ?? ""
        let avatarURLStr = voiceChannelResolveAvatarURL(context: context, clanId: clanId, identityKey: localId)
        if let avatarURLStr, !avatarURLStr.isEmpty {
            pipInitialLabel.isHidden = true
            let proxy = ImgproxyURL.create(from: avatarURLStr, width: 150, height: 150)
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

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentVC
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        return (sourceView, contentVC, pip)
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
    private let voiceChannelCrossClanExitAlignClanId: Int64?
    private let existingPiPOverlay: VoiceChannelPiPOverlay?

    private var liveKitBridge: VoiceChannelLiveKitBridge?
    private var connectTask: Task<Void, Never>?
    private var voiceReactionDisposable: Disposable?
    private var didStartVoiceConnection = false
    private var micButton: UIButton!
    private var camButton: UIButton!
    private var raiseHandButton: UIButton!
    private var isLocalRaiseHandActive = false
    private var raisedHandUserIds: Set<Int64> = []
    private var raiseHandBannerVisibleUserIds: Set<Int64> = []
    private var raiseHandBannerHideWorkItems: [Int64: DispatchWorkItem] = [:]
    private let raiseHandBannerAutoHideInterval: TimeInterval = 10
    private var didAnnounceMeetJoin = false
    private var didAnnounceMeetLeave = false
    private var audioRouteObserver: NSObjectProtocol?

    private var participantRows: [String: VoiceParticipantRowView] = [:]
    fileprivate var screenSharePiPHostRetain: AnyObject?

    private var callPiPController: AVPictureInPictureController?
    private var callPiPSourceView: UIView?
    private var callPiPContentVC: UIViewController?
    private let callPiPVideoView: VideoView = {
        let v = VideoView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layoutMode = .fill
        v.isPinchToZoomEnabled = false
        v.isOpaque = false
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }()
    private var callPiPBackgroundObserver: NSObjectProtocol?

    private let connectingOverlay = UIView()
    private let connectingSpinner = UIActivityIndicatorView(style: .large)
    private let connectingLabel = UILabel()
    private let voiceReactionOverlay = VoiceCallReactionFlightView()
    private let raiseHandBannerStack = UIStackView()

    private let headerBar = UIView()
    private let headerLeft = UIStackView()
    private let headerRight = UIStackView()
    private let collapseButton = UIButton(type: .custom)
    private let channelTitleLabel = UILabel()
    private let cameraSwitchButton = UIButton(type: .custom)
    private let audioRouteControl = VoiceHeaderSystemAudioRouteControl()
    private let agentToggleButton = UIButton(type: .custom)
    private let agentToggleSpinner = UIActivityIndicatorView(style: .medium)
    private var voiceAgentEnabled = false
    private var isAgentToggleLoading = false
    private let moreButton = UIButton(type: .custom)
    private var voiceMoreToolsHost: UIView?
    private weak var voiceReactionEmojiPickerSheet: ReactionEmojiPickerSheetController?
    private weak var voiceReactionSoundStickerPickerSheet: ReactionSoundStickerPickerSheetController?

    private let contentScroll = UIScrollView()
    private let participantArea = UIView()
    private let participantsGrid = UIStackView()
    private var orderedDescriptorKeys: [String] = []
    private var lastSyncedParticipantTileMetrics: VoiceParticipantTileLayoutMetrics?
    private var participantStateRefreshWorkItem: DispatchWorkItem?
    private var participantOrderRebuildWorkItem: DispatchWorkItem?
    private var voiceParticipantListUserScrolling = false
    private var pendingParticipantStateRefreshAfterScroll = false

    private var didUnlockOrientationForScreenShareDetail = false

    private var liveKitReconnectTask: Task<Void, Never>?
    private static let liveKitManualReconnectMax = 5
    private var didPrefetchVoiceChannelPermissions = false

    private let bottomPill = UIView()
    private let bottomControlsStack = UIStackView()

    init(context: AccountContext, channel: Mezon_Api_ChannelDescription, parentChannelName: String? = nil, voiceChannelCrossClanExitAlignClanId alignId: Int64? = nil, existingPiPOverlay: VoiceChannelPiPOverlay? = nil) {
        self.context = context
        self.channel = channel
        self.parentChannelName = parentChannelName
        self.voiceChannelCrossClanExitAlignClanId = alignId ?? existingPiPOverlay?.crossClanVoiceExitAlignClanId
        self.existingPiPOverlay = existingPiPOverlay
        super.init(navigationBarPresentationData: nil)
        hidesBottomBarWhenPushed = true
        self.attemptNavigation = { _ in return false }
        lockOrientation = true
        lockedOrientation = .portrait
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    private func popVoiceRoomOrAlignHomeAfterCrossClanVoice() {
        guard let align = voiceChannelCrossClanExitAlignClanId, align != 0 else {
            navigationController?.popViewController(animated: true)
            return
        }
        let chId = channel.channelID
        NotificationCenter.default.post(
            name: .mezonAlignHomeAfterCrossClanVoice,
            object: nil,
            userInfo: ["clanId": align, "channelId": chId]
        )
        if let nav = navigationController as? NavigationController {
            nav.popToRoot(animated: true)
        } else {
            navigationController?.popToRootViewController(animated: true)
        }
    }

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
        audioRouteControl.translatesAutoresizingMaskIntoConstraints = false
        audioRouteControl.applyHeaderChrome(background: UIColor.theme.secondary, border: UIColor.theme.border)
        audioRouteControl.applyTint(UIColor.theme.white)
        styleHeaderCircleButton(moreButton, systemImage: "ellipsis", pointSize: 18)
        moreButton.tintColor = UIColor.theme.white
        moreButton.addTarget(self, action: #selector(moreButtonTapped), for: .touchUpInside)

        styleVoiceAgentHeaderButton(agentToggleButton)
        agentToggleButton.addTarget(self, action: #selector(agentToggleTapped), for: .touchUpInside)
        agentToggleSpinner.hidesWhenStopped = true
        agentToggleSpinner.translatesAutoresizingMaskIntoConstraints = false
        agentToggleButton.addSubview(agentToggleSpinner)
        NSLayoutConstraint.activate([
            agentToggleSpinner.centerXAnchor.constraint(equalTo: agentToggleButton.centerXAnchor),
            agentToggleSpinner.centerYAnchor.constraint(equalTo: agentToggleButton.centerYAnchor),
        ])
        agentToggleButton.isHidden = !voiceChannelCanManageVoice()
        refreshVoiceAgentButtonAppearance()

        headerRight.addArrangedSubview(agentToggleButton)
        headerRight.addArrangedSubview(cameraSwitchButton)
        headerRight.addArrangedSubview(audioRouteControl)
        headerRight.addArrangedSubview(moreButton)

        headerBar.addSubview(headerLeft)
        headerBar.addSubview(headerRight)

        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.alwaysBounceVertical = true
        contentScroll.showsVerticalScrollIndicator = false
        contentScroll.delaysContentTouches = false
        contentScroll.delegate = self

        participantArea.translatesAutoresizingMaskIntoConstraints = false

        participantsGrid.translatesAutoresizingMaskIntoConstraints = false
        participantsGrid.axis = .vertical
        participantsGrid.spacing = 10
        participantsGrid.alignment = .fill
        participantsGrid.distribution = .equalSpacing

        contentScroll.addSubview(participantArea)
        participantArea.addSubview(participantsGrid)

        bottomPill.translatesAutoresizingMaskIntoConstraints = false
        bottomPill.backgroundColor = UIColor.theme.secondary
        bottomPill.clipsToBounds = true

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
        let hand = makeControlBarIconButton(systemName: "hand.raised.fill", action: #selector(raiseHandTapped))
        raiseHandButton = hand
        refreshRaiseHandButtonAppearance()
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
        raiseHandBannerStack.axis = .vertical
        raiseHandBannerStack.alignment = .trailing
        raiseHandBannerStack.spacing = 8
        raiseHandBannerStack.translatesAutoresizingMaskIntoConstraints = false
        raiseHandBannerStack.isHidden = true
        view.insertSubview(raiseHandBannerStack, aboveSubview: contentScroll)
        voiceReactionOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(voiceReactionOverlay)
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
            agentToggleButton.widthAnchor.constraint(equalToConstant: 40),
            agentToggleButton.heightAnchor.constraint(equalToConstant: 40),
            audioRouteControl.widthAnchor.constraint(equalToConstant: 40),
            audioRouteControl.heightAnchor.constraint(equalToConstant: 40),
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

            voiceReactionOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            voiceReactionOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            voiceReactionOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            voiceReactionOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            raiseHandBannerStack.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: 6),
            raiseHandBannerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            raiseHandBannerStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 72),
        ])

        voiceReactionOverlay.onSoundReactionTilePlayingChanged = { [weak self] userId, playing in
            guard let self else { return }
            let rowKey = "\(userId)|main"
            guard let row = self.participantRows[rowKey] else { return }
            row.setSoundReactionCornerVisible(playing)
        }
        voiceReactionOverlay.onSoundReactionTileBadgesClearAll = { [weak self] in
            guard let self else { return }
            for row in self.participantRows.values {
                row.setSoundReactionCornerVisible(false)
            }
        }
        voiceReactionOverlay.onRaiseHandStateChanged = { [weak self] userId, raised in
            self?.applyRaiseHandTileState(userId: userId, raised: raised)
        }
        voiceReactionOverlay.onRaiseHandDisplayReset = { [weak self] in
            self?.clearAllRaiseHandTileBadges()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: ThemeManager.didChangeNotification, object: nil)

        audioRouteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.syncCurrentAudioOutputFromSession()
            self.refreshSpeakerRouteUI()
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

    private func styleVoiceAgentHeaderButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.theme.secondary
        button.layer.cornerRadius = 20
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.theme.border.cgColor
        if let base = UIImage(named: "Channel/VoiceAgentControl") {
            if #available(iOS 15.0, *) {
                let img = base.withTintColor(
                    UIColor.theme.textStrong, renderingMode: .alwaysOriginal)
                button.setImage(img, for: .normal)
            } else {
                button.setImage(base.withRenderingMode(.alwaysTemplate), for: .normal)
            }
        }
        button.imageView?.contentMode = .scaleAspectFit
        button.imageEdgeInsets = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
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
        voiceReactionDisposable?.dispose()
        liveKitReconnectTask?.cancel()
        if let obs = callPiPBackgroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        callPiPController?.stopPictureInPicture()
        callPiPController?.delegate = nil
        callPiPController = nil
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
        if let audioRouteObserver {
            NotificationCenter.default.removeObserver(audioRouteObserver)
        }
        raiseHandBannerHideWorkItems.values.forEach { $0.cancel() }
        raiseHandBannerHideWorkItems.removeAll()
        dismissVoiceMoreToolsPopover()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        applyTheme()
        bindVoiceReactionSocketIfActive()
    }

    private func bindVoiceReactionSocketIfActive() {
        guard !isMinimizingToPiP else { return }
        voiceReactionDisposable?.dispose()
        voiceReactionDisposable = MezonSocket.shared.events().start(next: { [weak self] event in
            guard let self, !self.isMinimizingToPiP else { return }
            switch event {
            case .voiceReaction(let msg):
                guard msg.channelID == self.channel.channelID else { return }
                self.voiceReactionOverlay.handle(message: msg, context: self.context, clanId: self.channel.clanID)
            case .aiAgentEnabled(let ev):
                guard ev.channelID == self.channel.channelID else { return }
                if ev.clanID != 0, ev.clanID != self.channel.clanID { return }
                if !ev.roomName.isEmpty, ev.roomName != "\(self.channel.channelID)" { return }
                self.applyVoiceAgentEnabledFromServer(ev.enabled)
            default:
                break
            }
        })
        prewarmVoiceReactionEmojiCache()
    }

    private func prewarmVoiceReactionEmojiCache() {
        let emojiIds: [String] = {
            guard let cache = context.engine.data.cachedEmojiList(clanId: 0) else { return [] }
            var ids: [String] = []
            ids.reserveCapacity(cache.emojis.count)
            for e in cache.emojis where e.id != 0 {
                ids.append(String(e.id))
            }
            return ids
        }()
        guard !emojiIds.isEmpty else { return }
        voiceReactionOverlay.prewarmEmojiCache(emojiIds: emojiIds)
    }

    private func unbindVoiceReactionSocketForPiP() {
        voiceReactionDisposable?.dispose()
        voiceReactionDisposable = nil
        voiceReactionEmojiPickerSheet?.dismiss(animated: false)
        voiceReactionSoundStickerPickerSheet?.dismiss(animated: false)
        voiceReactionOverlay.reset()
    }

    @objc private func moreButtonTapped() {
        if voiceMoreToolsHost != nil {
            dismissVoiceMoreToolsPopover()
            return
        }
        presentVoiceMoreToolsPopover()
    }

    @objc private func dismissVoiceMoreToolsPopover() {
        voiceMoreToolsHost?.removeFromSuperview()
        voiceMoreToolsHost = nil
    }

    private func presentationWindowHost() -> WindowHost? {
        if let w = window { return w }
        if let nav = navigationController as? NavigationController, let cw = nav.currentWindow {
            return cw
        }
        return view.windowHost
    }

    private func navigationControllerForGlobalOverlay() -> NavigationController? {
        if let nav = navigationController as? NavigationController { return nav }
        if let root = view.window?.rootViewController {
            return root.findDeepestNavigationController()
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return nil }
        for w in scene.windows where !w.isHidden {
            if let nav = w.rootViewController?.findDeepestNavigationController() { return nav }
        }
        return nil
    }

    private func presentVoiceMoreToolsPopover() {
        guard voiceMoreToolsHost == nil, view.window != nil else { return }
        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.backgroundColor = .clear
        host.isUserInteractionEnabled = true

        let dismissTap = UIButton(type: .custom)
        dismissTap.translatesAutoresizingMaskIntoConstraints = false
        dismissTap.backgroundColor = .clear
        dismissTap.addTarget(self, action: #selector(dismissVoiceMoreToolsPopover), for: .touchUpInside)

        let blurStyle: UIBlurEffect.Style = {
            if #available(iOS 15.0, *) { return .systemChromeMaterialDark }
            return .dark
        }()
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 20
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false

        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = .clear
        panel.layer.cornerRadius = 20
        panel.clipsToBounds = true
        panel.isUserInteractionEnabled = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = true

        let emojiBtn = makeVoiceMoreToolCircleButton(image: UIImage(named: "Chat/FaceIcon"), fallbackSystemName: "face.smiling")
        emojiBtn.addTarget(self, action: #selector(voiceMoreToolsEmojiTapped), for: .touchUpInside)
        let soundBtn = makeVoiceMoreToolCircleButton(image: UIImage(named: "Channel/channelVoice"), fallbackSystemName: "speaker.wave.2.fill")
        soundBtn.addTarget(self, action: #selector(voiceMoreToolsSoundTapped), for: .touchUpInside)
        stack.addArrangedSubview(emojiBtn)
        stack.addArrangedSubview(soundBtn)

        panel.addSubview(stack)
        view.addSubview(host)
        view.bringSubviewToFront(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.layoutIfNeeded()

        host.addSubview(dismissTap)
        host.addSubview(blur)
        host.addSubview(panel)

        let anchor = moreButton.convert(moreButton.bounds, to: host)
        let blurW = VoiceMoreToolsPopoverMetrics.panelContentWidth
        let panelTrailingInset = max(0, host.bounds.width - anchor.maxX)
        NSLayoutConstraint.activate([
            dismissTap.topAnchor.constraint(equalTo: host.topAnchor),
            dismissTap.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            dismissTap.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            dismissTap.bottomAnchor.constraint(equalTo: host.bottomAnchor),

            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),

            panel.widthAnchor.constraint(equalToConstant: blurW),
            panel.topAnchor.constraint(equalTo: host.topAnchor, constant: anchor.maxY + 6),
            panel.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -panelTrailingInset),

            blur.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            blur.topAnchor.constraint(equalTo: panel.topAnchor),
            blur.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])

        host.layoutIfNeeded()
        voiceMoreToolsHost = host
    }

    private func makeVoiceMoreToolCircleButton(image: UIImage?, fallbackSystemName: String) -> UIButton {
        let b = UIButton(type: .custom)
        b.translatesAutoresizingMaskIntoConstraints = false
        let inset = VoiceMoreToolsPopoverMetrics.imageInset
        b.imageEdgeInsets = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        b.imageView?.contentMode = .scaleAspectFit
        let cfg = UIImage.SymbolConfiguration(pointSize: VoiceMoreToolsPopoverMetrics.symbolPointSize, weight: .medium)
        let resolved = image?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: fallbackSystemName, withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate)
        b.setImage(resolved, for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        let side = VoiceMoreToolsPopoverMetrics.buttonSide
        b.layer.cornerRadius = VoiceMoreToolsPopoverMetrics.buttonCornerRadius
        b.clipsToBounds = true
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: side),
            b.heightAnchor.constraint(equalToConstant: side),
        ])
        return b
    }

    @objc private func voiceMoreToolsEmojiTapped() {
        dismissVoiceMoreToolsPopover()
        presentReactionEmojiPickerForVoiceChannel(mediaType: 0)
    }

    @objc private func voiceMoreToolsSoundTapped() {
        dismissVoiceMoreToolsPopover()
        presentReactionSoundStickerPickerForVoiceChannel()
    }

    private func presentReactionEmojiPickerForVoiceChannel(mediaType: Int32) {
        view.endEditing(true)
        let sheet = ReactionEmojiPickerSheetController(engine: context.engine, dismissOnEmojiSelect: false) { [weak self] emojiId, _ in
            self?.sendVoiceChannelEmojiReaction(emojiId: emojiId, mediaType: mediaType)
        }
        sheet.onDismiss = { [weak self] in
            self?.voiceReactionEmojiPickerSheet = nil
        }
        voiceReactionEmojiPickerSheet = sheet

        let navForOverlay = navigationControllerForGlobalOverlay()
        if let nav = navForOverlay {
            nav.presentOverlay(controller: sheet, inGlobal: true)
        } else if let host = presentationWindowHost() {
            host.presentInGlobalOverlay(sheet)
        } else {
            return
        }

        sheet.animateIn()
        DispatchQueue.main.async { [weak sheet] in
            navForOverlay?.requestLayout(transition: .immediate)
            sheet?.animateIn()
        }
    }

    private func presentReactionSoundStickerPickerForVoiceChannel() {
        view.endEditing(true)
        let sheet = ReactionSoundStickerPickerSheetController(engine: context.engine, dismissOnStickerSelect: true) { [weak self] sticker in
            self?.sendVoiceChannelSoundReaction(sticker: sticker)
        }
        sheet.onDismiss = { [weak self] in
            self?.voiceReactionSoundStickerPickerSheet = nil
        }
        voiceReactionSoundStickerPickerSheet = sheet

        let navForOverlay = navigationControllerForGlobalOverlay()
        if let nav = navForOverlay {
            nav.presentOverlay(controller: sheet, inGlobal: true)
        } else if let host = presentationWindowHost() {
            host.presentInGlobalOverlay(sheet)
        } else {
            return
        }

        sheet.animateIn()
        DispatchQueue.main.async { [weak sheet] in
            navForOverlay?.requestLayout(transition: .immediate)
            sheet?.animateIn()
        }
    }

    private func sendVoiceChannelSoundReaction(sticker: CachedClanStickerRecord) {
        let urlStr = StickersPanel.resolvedStickerMediaURLString(for: sticker)
        guard !urlStr.isEmpty, let url = URL(string: urlStr), url.scheme != nil else { return }
        guard let uidStr = context.currentUser?.id, let senderId = Int64(uidStr) else { return }
        MezonSocket.shared.sendVoiceReaction(
            channelId: channel.channelID,
            senderId: senderId,
            emojis: ["sound:\(urlStr)"],
            mediaType: StickerMediaType.audio.rawValue
        )
    }

    private func sendVoiceChannelEmojiReaction(emojiId: String, mediaType: Int32) {
        guard !emojiId.isEmpty, let uidStr = context.currentUser?.id, let senderId = Int64(uidStr) else { return }
        MezonSocket.shared.sendVoiceReaction(
            channelId: channel.channelID,
            senderId: senderId,
            emojis: [emojiId],
            mediaType: mediaType
        )
    }

    @objc private func raiseHandTapped() {
        isLocalRaiseHandActive.toggle()
        if let uid = Int64(context.currentUser?.id ?? "") {
            applyRaiseHandTileState(userId: uid, raised: isLocalRaiseHandActive)
        }
        sendRaiseHandSocket(raised: isLocalRaiseHandActive)
        refreshRaiseHandButtonAppearance()
    }

    private func sendRaiseHandSocket(raised: Bool) {
        guard let uidStr = context.currentUser?.id, let senderId = Int64(uidStr) else { return }
        let cid = channel.channelID
        let name = voiceReactionLocalDisplayName()
        let avatar = voiceReactionLocalAvatarString()
        let emojis: [String]
        if raised {
            emojis = [
                "raising-up:\(cid)",
                "sender-name:\(name)",
                "sender-avatar:\(avatar)",
            ]
        } else {
            emojis = [
                "raising-down:\(cid)",
                "sender-name:\(name)",
                "sender-avatar:\(avatar)",
            ]
        }
        MezonSocket.shared.sendVoiceReaction(
            channelId: channel.channelID,
            senderId: senderId,
            emojis: emojis,
            mediaType: 0
        )
    }

    private func voiceReactionLocalDisplayName() -> String {
        if let d = context.currentUser?.displayName, !d.isEmpty { return d }
        if let n = context.currentUser?.username, !n.isEmpty { return n }
        return ""
    }

    private func voiceReactionLocalAvatarString() -> String {
        context.currentUser?.avatarURL?.absoluteString ?? ""
    }

    private func refreshRaiseHandButtonAppearance() {
        guard raiseHandButton != nil else { return }
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        raiseHandButton.setImage(
            UIImage(systemName: "hand.raised.fill", withConfiguration: cfg)?.withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        if isLocalRaiseHandActive {
            raiseHandButton.tintColor = UIColor.theme.textLink
            raiseHandButton.backgroundColor = UIColor.theme.textLink.withAlphaComponent(0.22)
        } else {
            raiseHandButton.tintColor = UIColor.theme.textStrong
            raiseHandButton.backgroundColor = UIColor.theme.tertiary
        }
    }

    private func lowerRaiseHandIfActive() {
        guard isLocalRaiseHandActive else { return }
        isLocalRaiseHandActive = false
        if let uid = Int64(context.currentUser?.id ?? "") {
            applyRaiseHandTileState(userId: uid, raised: false)
        }
        sendRaiseHandSocket(raised: false)
        refreshRaiseHandButtonAppearance()
    }

    private func applyRaiseHandTileState(userId: Int64, raised: Bool) {
        if raised {
            raisedHandUserIds.insert(userId)
            raiseHandBannerVisibleUserIds.insert(userId)
            scheduleRaiseHandBannerAutoHide(for: userId)
        } else {
            raisedHandUserIds.remove(userId)
            cancelRaiseHandBannerAutoHide(for: userId)
            raiseHandBannerVisibleUserIds.remove(userId)
        }
        let idStr = "\(userId)"
        for (key, row) in participantRows {
            let base = key.components(separatedBy: "|").first ?? key
            if base == idStr {
                row.setRaiseHandCornerVisible(raised)
            }
        }
        refreshRaiseHandTopBanners()
    }

    private func clearAllRaiseHandTileBadges() {
        raisedHandUserIds.removeAll()
        raiseHandBannerVisibleUserIds.removeAll()
        raiseHandBannerHideWorkItems.values.forEach { $0.cancel() }
        raiseHandBannerHideWorkItems.removeAll()
        participantRows.values.forEach { $0.setRaiseHandCornerVisible(false) }
        refreshRaiseHandTopBanners()
    }

    private func scheduleRaiseHandBannerAutoHide(for userId: Int64) {
        raiseHandBannerHideWorkItems[userId]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.raiseHandBannerHideWorkItems[userId] = nil
            if let localId = Int64(self.context.currentUser?.id ?? ""), localId == userId {
                self.isLocalRaiseHandActive = false
                self.sendRaiseHandSocket(raised: false)
                self.refreshRaiseHandButtonAppearance()
            }
            self.applyRaiseHandTileState(userId: userId, raised: false)
        }
        raiseHandBannerHideWorkItems[userId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + raiseHandBannerAutoHideInterval, execute: work)
    }

    private func cancelRaiseHandBannerAutoHide(for userId: Int64) {
        raiseHandBannerHideWorkItems[userId]?.cancel()
        raiseHandBannerHideWorkItems[userId] = nil
    }

    private func refreshRaiseHandTopBanners() {
        raiseHandBannerStack.arrangedSubviews.forEach {
            raiseHandBannerStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard !raiseHandBannerVisibleUserIds.isEmpty else {
            raiseHandBannerStack.isHidden = true
            return
        }
        raiseHandBannerStack.isHidden = false
        for uid in raiseHandBannerVisibleUserIds.sorted() {
            raiseHandBannerStack.addArrangedSubview(makeRaiseHandTopBannerPill(userId: uid))
        }
    }

    private func makeRaiseHandTopBannerPill(userId: Int64) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.backgroundColor = UIColor.theme.tertiary
        wrap.layer.cornerRadius = 14
        wrap.clipsToBounds = true
        wrap.layer.borderWidth = 1
        wrap.layer.borderColor = UIColor.theme.borderHighlight.cgColor

        let avatar = UIImageView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 16
        avatar.backgroundColor = UIColor.theme.tertiary

        let key = "\(userId)"
        if let raw = voiceChannelResolveAvatarURL(context: context, clanId: channel.clanID, identityKey: key), !raw.isEmpty {
            let proxy = ImgproxyURL.create(from: raw, width: 150, height: 150)
            ImageCache.shared.loadAvatar(urlString: proxy) { img in
                avatar.image = img
            }
        }

        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = UIColor.theme.textStrong
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.numberOfLines = 1
        nameLabel.text = voiceChannelResolveDisplayNameForUserId(context: context, clanId: channel.clanID, userId: userId)

        let hand = UIImageView(image: UIImage(systemName: "hand.raised.fill"))
        hand.translatesAutoresizingMaskIntoConstraints = false
        hand.tintColor = UIColor(red: 0.95, green: 0.58, blue: 0.2, alpha: 1)
        hand.contentMode = .scaleAspectFit

        wrap.addSubview(avatar)
        wrap.addSubview(nameLabel)
        wrap.addSubview(hand)

        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            avatar.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 6),
            avatar.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -6),
            avatar.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 6),
            avatar.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),
            nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 168),
            hand.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            hand.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -10),
            hand.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            hand.widthAnchor.constraint(equalToConstant: 24),
            hand.heightAnchor.constraint(equalToConstant: 24),
        ])
        return wrap
    }

    private func syncRaiseHandBadgesToParticipantRows() {
        for (key, row) in participantRows {
            let base = key.components(separatedBy: "|").first ?? key
            guard let uid = Int64(base) else { continue }
            row.setRaiseHandCornerVisible(raisedHandUserIds.contains(uid))
        }
    }

    private func applyLiveKitBridgeAfterTakeover(
        _ bridge: VoiceChannelLiveKitBridge,
        joinFlag: Bool,
        leaveFlag: Bool,
        preservedAudioRoute: VoiceChannelPiPPreservedAudioRoute?
    ) {
        liveKitBridge = bridge
        didAnnounceMeetJoin = joinFlag
        didAnnounceMeetLeave = leaveFlag
        isMinimizingToPiP = false
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
        bridge.onParticipantStateUpdated = { [weak self] in
            self?.scheduleParticipantStateRefresh()
        }
        refreshMicButtonIcon()
        refreshCamButtonIcon()
        if let preservedAudioRoute {
            switch preservedAudioRoute {
            case .speaker: currentAudioOutput = .speaker
            case .earpiece: currentAudioOutput = .earpiece
            case .bluetooth: currentAudioOutput = .bluetooth
            }
            applyAudioRoute()
        } else {
            detectInitialAudioRoute()
        }
        refreshParticipantRowsFromLiveKit()
        setupCallPiP()
        bindVoiceReactionSocketIfActive()
    }

    private func pipPreservedRouteFromCurrentOutput() -> VoiceChannelPiPPreservedAudioRoute {
        switch currentAudioOutput {
        case .speaker: return .speaker
        case .earpiece: return .earpiece
        case .bluetooth: return .bluetooth
        }
    }

    @discardableResult
    private func resumeVoiceRoomFromPiPOverlayIfNeeded() -> Bool {
        guard liveKitBridge == nil else { return false }
        let pip = VoiceChannelPiPOverlay.shared
        guard pip.isActive, let pipCh = pip.channel,
              pipCh.channelID == channel.channelID, pipCh.clanID == channel.clanID,
              let (bridge, joinFlag, leaveFlag, route) = pip.takeOverBridge() else { return false }
        applyLiveKitBridgeAfterTakeover(bridge, joinFlag: joinFlag, leaveFlag: leaveFlag, preservedAudioRoute: route)
        return true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didPrefetchVoiceChannelPermissions {
            didPrefetchVoiceChannelPermissions = true
            Task { await prefetchVoiceChannelPermissions() }
        }
        if resumeVoiceRoomFromPiPOverlayIfNeeded() {
            didStartVoiceConnection = true
            return
        }
        guard !didStartVoiceConnection else { return }
        didStartVoiceConnection = true

        if let pip = existingPiPOverlay, let (bridge, joinFlag, leaveFlag, route) = pip.takeOverBridge() {
            applyLiveKitBridgeAfterTakeover(bridge, joinFlag: joinFlag, leaveFlag: leaveFlag, preservedAudioRoute: route)
            return
        }

        connectTask = Task { @MainActor in
            await self.runVoiceConnectionPipeline()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        dismissVoiceMoreToolsPopover()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncParticipantTileGridLayout()
        bottomPill.layer.cornerRadius = bottomPill.bounds.height / 2
    }

    private func gridWidthForParticipantLayout() -> CGFloat {
        let w = participantsGrid.bounds.width
        if w > 1 { return w }
        return max(280, view.bounds.width - 40)
    }

    private func syncParticipantTileGridLayout() {
        guard !participantRows.isEmpty else { return }
        let gw = gridWidthForParticipantLayout()
        let m = voiceParticipantTileLayoutMetrics(gridWidth: gw)
        if lastSyncedParticipantTileMetrics == m { return }
        lastSyncedParticipantTileMetrics = m
        for row in participantsGrid.arrangedSubviews {
            if let h = row as? UIStackView, h.axis == .horizontal {
                for c in h.constraints where c.firstAttribute == .height && c.relation == .equal {
                    c.constant = m.tileHeight
                }
                for v in h.arrangedSubviews {
                    (v as? VoiceParticipantRowView)?.applyLayoutMetrics(m)
                }
            } else if let tile = row.subviews.first as? VoiceParticipantRowView {
                let wrapper = row
                for c in wrapper.constraints where c.firstAttribute == .height {
                    c.constant = m.tileHeight
                }
                for c in tile.constraints where c.firstAttribute == .width {
                    c.constant = m.columnWidth
                }
                tile.applyLayoutMetrics(m)
            }
        }
    }

    private func scheduleParticipantStateRefresh() {
        if voiceParticipantListUserScrolling {
            pendingParticipantStateRefreshAfterScroll = true
            return
        }
        participantStateRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.participantStateRefreshWorkItem = nil
            self.updateParticipantTilesInPlace()
        }
        participantStateRefreshWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func flushPendingParticipantStateRefresh() {
        participantStateRefreshWorkItem?.cancel()
        participantStateRefreshWorkItem = nil
        if pendingParticipantStateRefreshAfterScroll {
            pendingParticipantStateRefreshAfterScroll = false
            updateParticipantTilesInPlace()
        }
    }

    private func voiceParticipantListScrollInteractionEnded() {
        voiceParticipantListUserScrolling = false
        lastSyncedParticipantTileMetrics = nil
        syncParticipantTileGridLayout()
        syncParticipantGridOrderAfterScrollIfNeeded()
        flushPendingParticipantStateRefresh()
    }

    private func syncParticipantGridOrderAfterScrollIfNeeded() {
        guard let bridge = liveKitBridge, let room = bridge.room else { return }
        let ordered = orderedParticipants(room: room)
        let descriptors = voiceTileDescriptors(participants: ordered)
        let keys = descriptors.map(\.rowKey)
        applyParticipantGridOrdering(orderedKeys: keys)
    }

    private func applyParticipantGridOrdering(orderedKeys: [String]) {
        let previousKeys = orderedDescriptorKeys
        let prevSet = Set(previousKeys)
        let newSet = Set(orderedKeys)
        if prevSet != newSet {
            participantOrderRebuildWorkItem?.cancel()
            participantOrderRebuildWorkItem = nil
            orderedDescriptorKeys = orderedKeys
            rebuildGrid()
            syncRaiseHandBadgesToParticipantRows()
        } else if previousKeys != orderedKeys {
            if voiceParticipantListUserScrolling {
                participantOrderRebuildWorkItem?.cancel()
                participantOrderRebuildWorkItem = nil
                syncRaiseHandBadgesToParticipantRows()
                return
            }
            participantOrderRebuildWorkItem?.cancel()
            let keysSnapshot = orderedKeys
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.participantOrderRebuildWorkItem = nil
                if Set(self.orderedDescriptorKeys) != Set(keysSnapshot) { return }
                if self.orderedDescriptorKeys == keysSnapshot { return }
                self.orderedDescriptorKeys = keysSnapshot
                self.rebuildGrid()
                self.syncRaiseHandBadgesToParticipantRows()
            }
            participantOrderRebuildWorkItem = work
            DispatchQueue.main.async(execute: work)
        } else {
            participantOrderRebuildWorkItem?.cancel()
            participantOrderRebuildWorkItem = nil
            syncRaiseHandBadgesToParticipantRows()
        }
    }

    private var isMinimizingToPiP = false
    private var isScreenShareExpandedPresented = false
    private var screenShareExpandedSourceParticipantKey: String?
    private weak var screenShareExpandedSourceTrack: VideoTrack?
    private var screenShareExpandedPresentedAt: Date?

    private var isScreenShareDetailCoveringVoiceRoom: Bool {
        if isScreenShareExpandedPresented { return true }
        if #available(iOS 15.0, *) {
            return presentedViewController is ScreenShareExpandedViewController
        }
        return false
    }

    fileprivate func screenShareExpandedDidDismiss() {
        isScreenShareExpandedPresented = false
    }

    fileprivate func noteScreenShareExpandedSessionEnded() {
        screenShareExpandedSourceParticipantKey = nil
        screenShareExpandedSourceTrack = nil
        screenShareExpandedPresentedAt = nil
    }

    private func participant(forSourceParticipantKey key: String, room: Room) -> Participant? {
        if participantRowKey(room.localParticipant) == key { return room.localParticipant }
        for r in room.remoteParticipants.values {
            if participantRowKey(r) == key { return r }
        }
        return nil
    }

    private func resolveScreenShareVideoPublication(_ p: Participant) -> TrackPublication? {
        if let pub = p.firstScreenSharePublication { return pub }
        return p.videoTracks.first(where: { $0.name == Track.screenShareVideoName })
    }

    private func participantHasLiveScreenShareVideoAttached(_ p: Participant) -> Bool {
        p.trackPublications.values.contains { pub in
            guard pub.kind == .video, pub.track != nil else { return false }
            if pub.source == .screenShareVideo { return true }
            return pub.name == Track.screenShareVideoName
        }
    }

    fileprivate func dismissScreenShareExpandedIfSourceShareEnded() {
        guard let key = screenShareExpandedSourceParticipantKey else { return }
        guard let bridge = liveKitBridge, let room = bridge.room else { return }
        guard let p = participant(forSourceParticipantKey: key, room: room) else {
            tearDownScreenSharePresentationAndPiP()
            return
        }
        let pastAttachGrace = screenShareExpandedPresentedAt.map { Date().timeIntervalSince($0) >= 2.0 } ?? true
        if pastAttachGrace, !participantHasLiveScreenShareVideoAttached(p) {
            tearDownScreenSharePresentationAndPiP()
            return
        }
        if !p.isScreenShareEnabled() {
            tearDownScreenSharePresentationAndPiP()
            return
        }
        if let pub = resolveScreenShareVideoPublication(p), pub.streamState == .paused {
            tearDownScreenSharePresentationAndPiP()
            return
        }
        if let rpub = resolveScreenShareVideoPublication(p) as? RemoteTrackPublication,
           rpub.subscriptionState == .unsubscribed {
            tearDownScreenSharePresentationAndPiP()
            return
        }
        let current: VideoTrack? = p.firstScreenShareVideoTrack
            ?? (resolveScreenShareVideoPublication(p).flatMap { $0.track as? VideoTrack })
        if pastAttachGrace, current == nil {
            tearDownScreenSharePresentationAndPiP()
            return
        }
        if let shown = screenShareExpandedSourceTrack, let current, current !== shown {
            tearDownScreenSharePresentationAndPiP()
        }
    }

    private func voiceRoomShouldTransferToPiPWhenDisappearing() -> Bool {
        if isScreenShareDetailCoveringVoiceRoom { return false }
        if isMovingFromParent || isBeingDismissed { return true }
        if presentedViewController != nil { return false }
        if let nav = navigationController, nav.topViewController !== self { return true }
        return false
    }

    @discardableResult
    private func voiceRoomPerformPiPHandoffIfStillInCall() -> Bool {
        if isMinimizingToPiP { return false }
        liveKitReconnectTask?.cancel()
        liveKitReconnectTask = nil
        if let bridge = liveKitBridge {
            let preservedRoute = pipPreservedRouteFromCurrentOutput()
            unbindVoiceReactionSocketForPiP()
            tearDownCallPiP()
            tearDownScreenSharePresentationAndPiP()
            connectTask?.cancel()
            connectTask = nil
            participantStateRefreshWorkItem?.cancel()
            participantStateRefreshWorkItem = nil
            participantOrderRebuildWorkItem?.cancel()
            participantOrderRebuildWorkItem = nil

            for row in participantRows.values {
                row.prepareForRemoval()
            }
            participantRows.removeAll()
            lastSyncedParticipantTileMetrics = nil
            orderedDescriptorKeys = []

            isMinimizingToPiP = true
            bridge.clearCallbacks()
            liveKitBridge = nil

            VoiceChannelPiPOverlay.shared.show(
                bridge: bridge,
                context: context,
                channel: channel,
                parentChannelName: parentChannelName,
                didAnnounceMeetJoin: didAnnounceMeetJoin,
                didAnnounceMeetLeave: didAnnounceMeetLeave,
                preservedAudioRoute: preservedRoute,
                crossClanVoiceExitAlignClanId: voiceChannelCrossClanExitAlignClanId
            )
            return true
        } else {
            unbindVoiceReactionSocketForPiP()
            tearDownCallPiP()
            tearDownScreenSharePresentationAndPiP()
            connectTask?.cancel()
            connectTask = nil
            return false
        }
    }

    private func voiceStripSelfFromNavWhenCoveredAfterPiPHandoff(
        wasMovingFromParent: Bool,
        wasBeingDismissed: Bool
    ) {
        guard !wasMovingFromParent, !wasBeingDismissed else { return }
        guard presentedViewController == nil else { return }
        guard let nav = navigationController, nav.topViewController !== self else { return }
        var vcs = nav.viewControllers
        guard let i = vcs.firstIndex(where: { $0 === self }) else { return }
        vcs.remove(at: i)
        nav.setViewControllers(vcs, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissVoiceMoreToolsPopover()
        let handoff = voiceRoomShouldTransferToPiPWhenDisappearing()
        if !handoff && !isMinimizingToPiP && !isScreenShareDetailCoveringVoiceRoom {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        let movingFromParent = isMovingFromParent
        let beingDismissed = isBeingDismissed
        if isMinimizingToPiP { return }
        guard handoff else { return }
        let didHandoffBridgeToPiP = voiceRoomPerformPiPHandoffIfStillInCall()
        if didHandoffBridgeToPiP {
            DispatchQueue.main.async { [weak self] in
                self?.voiceStripSelfFromNavWhenCoveredAfterPiPHandoff(
                    wasMovingFromParent: movingFromParent,
                    wasBeingDismissed: beingDismissed
                )
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMinimizingToPiP { return }
        if isScreenShareDetailCoveringVoiceRoom { return }
        guard isViewLoaded, view.window == nil else { return }
        if presentedViewController != nil { return }
        guard liveKitBridge != nil else { return }
        voiceRoomPerformPiPHandoffIfStillInCall()
    }

    @objc private func applyTheme() {
        view.backgroundColor = UIColor.theme.black
        displayNode.backgroundColor = UIColor.theme.black
        channelTitleLabel.textColor = UIColor.theme.textStrong
        collapseButton.backgroundColor = UIColor.theme.secondary
        collapseButton.layer.borderColor = UIColor.theme.border.cgColor
        cameraSwitchButton.backgroundColor = UIColor.theme.secondary
        cameraSwitchButton.layer.borderColor = UIColor.theme.border.cgColor
        audioRouteControl.applyHeaderChrome(background: UIColor.theme.secondary, border: UIColor.theme.border)
        audioRouteControl.applyTint(UIColor.theme.white)
        moreButton.backgroundColor = UIColor.theme.secondary
        moreButton.layer.borderColor = UIColor.theme.border.cgColor
        if !agentToggleButton.isHidden {
            refreshVoiceAgentButtonAppearance()
        }
        bottomPill.backgroundColor = UIColor.theme.secondary
        connectingLabel.textColor = UIColor.theme.textStrong
        participantRows.values.forEach { $0.applyTheme() }
        refreshSpeakerRouteUI()
        refreshCamButtonIcon()
        refreshRaiseHandButtonAppearance()
        refreshRaiseHandTopBanners()
        if #available(iOS 15.0, *) {
            applyInlineCallPiPContentTheme()
        }
    }

    @available(iOS 15.0, *)
    private func applyInlineCallPiPContentTheme() {
        guard let vc = callPiPContentVC else { return }
        let t = UIColor.theme
        vc.view.backgroundColor = t.primary
        (vc.view.viewWithTag(VoiceCallSystemPiPViewTag.status) as? UILabel)?.textColor = t.textDisabled
        (vc.view.viewWithTag(VoiceCallSystemPiPViewTag.name) as? UILabel)?.textColor = t.textStrong
        (vc.view.viewWithTag(VoiceCallSystemPiPViewTag.initial) as? UILabel)?.textColor = t.textStrong
    }

    @objc private func popTapped() {
        lowerRaiseHandIfActive()
        dismissVoiceMoreToolsPopover()
        unbindVoiceReactionSocketForPiP()
        liveKitReconnectTask?.cancel()
        liveKitReconnectTask = nil
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
            self.popVoiceRoomOrAlignHomeAfterCrossClanVoice()
        }
    }

    @objc private func minimizeToPiP() {
        guard let bridge = liveKitBridge else { return }
        let preservedRoute = pipPreservedRouteFromCurrentOutput()
        lowerRaiseHandIfActive()
        dismissVoiceMoreToolsPopover()
        unbindVoiceReactionSocketForPiP()
        liveKitReconnectTask?.cancel()
        liveKitReconnectTask = nil
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
            didAnnounceMeetLeave: didAnnounceMeetLeave,
            preservedAudioRoute: preservedRoute,
            crossClanVoiceExitAlignClanId: voiceChannelCrossClanExitAlignClanId
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
            bridge.onParticipantStateUpdated = { [weak self] in
                self?.scheduleParticipantStateRefresh()
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
            detectInitialAudioRoute()
            refreshCamButtonIcon()
            announceMeetJoinIfNeeded()
            refreshParticipantRowsFromLiveKit()
            setConnectingOverlayVisible(false)
            setupCallPiP()
        } catch {
            setConnectingOverlayVisible(false)
            if !Task.isCancelled {
                presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: error.localizedDescription)
            }
            liveKitBridge = nil
        }
    }

    private func setConnectingOverlayVisible(_ visible: Bool) {
        connectingOverlay.isHidden = !visible
        connectingOverlay.isUserInteractionEnabled = visible
        if visible {
            connectingSpinner.startAnimating()
            view.bringSubviewToFront(connectingOverlay)
        } else {
            connectingSpinner.stopAnimating()
            view.bringSubviewToFront(headerBar)
            view.bringSubviewToFront(bottomPill)
            view.bringSubviewToFront(raiseHandBannerStack)
            view.bringSubviewToFront(voiceReactionOverlay)
        }
    }

    private func setupCallPiP() {
        guard #available(iOS 15.0, *) else {
            return
        }
        tearDownCallPiP()
        guard let (sourceView, contentVC, pip) = VoiceCallSystemPiPFactory.make(sourceSuperview: view, context: context, clanId: channel.clanID) else {
            return
        }
        callPiPSourceView = sourceView
        callPiPContentVC = contentVC
        callPiPVideoView.removeFromSuperview()
        contentVC.view.insertSubview(callPiPVideoView, at: 0)
        NSLayoutConstraint.activate([
            callPiPVideoView.topAnchor.constraint(equalTo: contentVC.view.topAnchor),
            callPiPVideoView.leadingAnchor.constraint(equalTo: contentVC.view.leadingAnchor),
            callPiPVideoView.trailingAnchor.constraint(equalTo: contentVC.view.trailingAnchor),
            callPiPVideoView.bottomAnchor.constraint(equalTo: contentVC.view.bottomAnchor),
        ])
        pip.delegate = self
        callPiPController = pip
        if callPiPBackgroundObserver == nil {
            callPiPBackgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.tryStartCallPiPIfNeeded()
            }
        }
        if let room = liveKitBridge?.room {
            updateCallPiPContent(room: room)
        }
    }

    private func tryStartCallPiPIfNeeded() {
        guard #available(iOS 15.0, *) else {
            return
        }
        guard let pip = callPiPController else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            guard pip === self.callPiPController else { return }
            guard pip.isPictureInPicturePossible else {
                return
            }
            guard !pip.isPictureInPictureActive else {
                return
            }
            pip.startPictureInPicture()
        }
    }

    private func tearDownCallPiP() {
        if let obs = callPiPBackgroundObserver {
            NotificationCenter.default.removeObserver(obs)
            callPiPBackgroundObserver = nil
        }
        let pip = callPiPController
        if pip?.isPictureInPictureActive == true {
            pip?.stopPictureInPicture()
        }
        pip?.delegate = nil
        callPiPController = nil
        callPiPVideoView.track = nil
        callPiPVideoView.removeFromSuperview()
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
        voiceChannelMeetStateDisplayName(context: context, clanId: channel.clanID)
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

    private func updateParticipantTilesInPlace() {
        guard let bridge = liveKitBridge, let room = bridge.room else { return }
        let allParticipants: [Participant] = [room.localParticipant] + Array(room.remoteParticipants.values)
        var participantByKey: [String: Participant] = [:]
        for p in allParticipants {
            let key = participantRowKey(p)
            if !key.isEmpty { participantByKey[key] = p }
        }
        for (rowKey, row) in participantRows {
            let baseKey = rowKey.components(separatedBy: "|").first ?? rowKey
            guard let p = participantByKey[baseKey] else { continue }
            let isLocal = p is LocalParticipant
            let isScreen = rowKey.hasSuffix("|screen")
            let display = resolveDisplayName(participant: p)
            let videoTrack: VideoTrack?
            let mirrorVideo: Bool
            let speaking: Bool
            if isScreen {
                videoTrack = p.firstScreenShareVideoTrack
                mirrorVideo = false
                speaking = false
            } else {
                videoTrack = p.firstCameraVideoTrack
                mirrorVideo = isLocal && bridge.currentCameraCapturePosition() == .front
                speaking = p.isSpeaking
            }
            row.configure(
                displayName: display,
                micOn: p.isMicrophoneEnabled(),
                speaking: speaking,
                avatarURL: resolveAvatarURL(identityKey: baseKey, participant: p),
                videoTrack: videoTrack,
                mirrorVideo: mirrorVideo
            )
            applyParticipantRowCallbacks(rowKey: rowKey, row: row, participant: p, displayName: display)
        }
        refreshMicButtonIcon()
        if let room = bridge.room {
            let ordered = orderedParticipants(room: room)
            let descriptors = voiceTileDescriptors(participants: ordered)
            applyParticipantGridOrdering(orderedKeys: descriptors.map(\.rowKey))
            updateCallPiPContent(room: room)
        }
        dismissScreenShareExpandedIfSourceShareEnded()
        syncVoiceAgentToggleFromRoomState()
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
            let display = resolveDisplayName(participant: p)
            let avatarURL = resolveAvatarURL(identityKey: baseKey, participant: p)
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
                mirrorVideo = isLocal && bridge.currentCameraCapturePosition() == .front
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
            applyParticipantRowCallbacks(rowKey: d.rowKey, row: row, participant: p, displayName: display)
        }
        let nextKeys = Set(orderedKeys)
        let stale = participantRows.keys.filter { !nextKeys.contains($0) }
        for k in stale {
            participantRows[k]?.prepareForRemoval()
            participantRows[k]?.removeFromSuperview()
            participantRows.removeValue(forKey: k)
        }
        applyParticipantGridOrdering(orderedKeys: orderedKeys)
        updateCallPiPContent(room: room)
        dismissScreenShareExpandedIfSourceShareEnded()
        syncVoiceAgentToggleFromRoomState()
    }

    private func updateCallPiPContent(room: Room) {
        guard let contentVC = callPiPContentVC, let root = contentVC.view else { return }
        let local = room.localParticipant
        let remotes = Array(room.remoteParticipants.values)
        var pipTrack: VideoTrack?
        var pipMirror = false
        for r in remotes {
            if let t = r.firstScreenShareVideoTrack {
                pipTrack = t
                pipMirror = false
                break
            }
        }
        if pipTrack == nil, let t = local.firstScreenShareVideoTrack {
            pipTrack = t
            pipMirror = false
        }
        if pipTrack == nil, let t = local.firstCameraVideoTrack {
            pipTrack = t
            pipMirror = liveKitBridge?.currentCameraCapturePosition() == .front
        }
        if let pipTrack {
            callPiPVideoView.mirrorMode = pipMirror ? .auto : .off
            if callPiPVideoView.track !== pipTrack {
                callPiPVideoView.track = pipTrack
            }
            callPiPVideoView.isHidden = false
            callPiPVideoView.alpha = 1
            voiceCallSystemPiPSetChromeHidden(root, hidden: true)
        } else {
            callPiPVideoView.isHidden = true
            callPiPVideoView.track = nil
            callPiPVideoView.alpha = 0
            voiceCallSystemPiPSetChromeHidden(root, hidden: false)
        }
        guard let statusLabel = root.viewWithTag(VoiceCallSystemPiPViewTag.status) as? UILabel else { return }
        let remoteCount = room.remoteParticipants.count
        if remoteCount == 0 {
            statusLabel.text = NSLocalizedString("voiceChannel.pipStatus", tableName: nil, bundle: .main, value: "You're alone on the call", comment: "")
        } else {
            let total = remoteCount + 1
            statusLabel.text = String(format: NSLocalizedString("voiceChannel.pipParticipants", tableName: nil, bundle: .main, value: "%d participants", comment: ""), total)
        }
    }

    private func rebuildGrid() {
        let savedOffset = contentScroll.contentOffset
        let wasUserInteracting = contentScroll.isTracking || contentScroll.isDragging || contentScroll.isDecelerating
        UIView.performWithoutAnimation {
            for v in participantsGrid.arrangedSubviews {
                participantsGrid.removeArrangedSubview(v)
                v.removeFromSuperview()
            }
            let gw = gridWidthForParticipantLayout()
            let m = voiceParticipantTileLayoutMetrics(gridWidth: gw)
            lastSyncedParticipantTileMetrics = m
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
                    row.heightAnchor.constraint(equalToConstant: m.tileHeight).isActive = true
                    participantsGrid.addArrangedSubview(row)
                    i += 2
                } else {
                    let wrapper = UIView()
                    wrapper.translatesAutoresizingMaskIntoConstraints = false
                    let tile = tiles[i]
                    tile.translatesAutoresizingMaskIntoConstraints = false
                    wrapper.addSubview(tile)
                    NSLayoutConstraint.activate([
                        wrapper.heightAnchor.constraint(equalToConstant: m.tileHeight),
                        tile.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                        tile.topAnchor.constraint(equalTo: wrapper.topAnchor),
                        tile.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                        tile.widthAnchor.constraint(equalToConstant: m.columnWidth),
                    ])
                    participantsGrid.addArrangedSubview(wrapper)
                    i += 1
                }
            }
            for t in tiles {
                t.applyLayoutMetrics(m)
            }
            syncRaiseHandBadgesToParticipantRows()
            contentScroll.layoutIfNeeded()
            let maxY = max(0, contentScroll.contentSize.height
                + contentScroll.adjustedContentInset.top
                + contentScroll.adjustedContentInset.bottom
                - contentScroll.bounds.height)
            let clampedY = min(max(savedOffset.y, -contentScroll.adjustedContentInset.top), maxY)
            let target = CGPoint(x: savedOffset.x, y: clampedY)
            if !wasUserInteracting && target != contentScroll.contentOffset {
                contentScroll.setContentOffset(target, animated: false)
            } else if wasUserInteracting {
                contentScroll.contentOffset = CGPoint(x: savedOffset.x, y: max(savedOffset.y, -contentScroll.adjustedContentInset.top))
            }
        }
    }

    private func voiceTileDescriptors(participants: [Participant]) -> [VoiceParticipantTileDescriptor] {
        var screens: [VoiceParticipantTileDescriptor] = []
        var mains: [VoiceParticipantTileDescriptor] = []
        for p in participants {
            let base = participantRowKey(p)
            if base.isEmpty { continue }
            if p.firstScreenShareVideoTrack != nil {
                screens.append(VoiceParticipantTileDescriptor(rowKey: "\(base)|screen", participant: p, kind: .screenShare))
            }
            mains.append(VoiceParticipantTileDescriptor(rowKey: "\(base)|main", participant: p, kind: .mainVideo))
        }
        return screens + mains
    }

    private func participantRowKey(_ p: Participant) -> String {
        if let id = p.identity?.stringValue, !id.isEmpty { return id }
        if let sid = p.sid { return String(describing: sid) }
        return ""
    }

    private func participantSortPriority(_ p: Participant, isLocal: Bool) -> Int {
        if p.firstScreenShareVideoTrack != nil { return 0 }
        if p.isMicrophoneEnabled() { return 1 }
        if p.firstCameraVideoTrack != nil { return 2 }
        if isLocal { return 3 }
        return 4
    }

    private func orderedParticipants(room: Room) -> [Participant] {
        let local = room.localParticipant
        var all: [(Participant, Bool)] = [(local, true)]
        for r in room.remoteParticipants.values {
            all.append((r, false))
        }
        all.sort { a, b in
            let pa = participantSortPriority(a.0, isLocal: a.1)
            let pb = participantSortPriority(b.0, isLocal: b.1)
            if pa != pb { return pa < pb }
            let na = a.0.name ?? a.0.identity?.stringValue ?? ""
            let nb = b.0.name ?? b.0.identity?.stringValue ?? ""
            return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending
        }
        return all.map(\.0)
    }

    private func resolveDisplayName(participant: Participant) -> String {
        voiceChannelResolveDisplayName(context: context, clanId: channel.clanID, participant: participant)
    }

    private func resolveAvatarURL(identityKey: String, participant: Participant) -> String? {
        if participant.kind == .agent {
            return kVoiceKomuAgentDefaultAvatarURL
        }
        return voiceChannelResolveAvatarURL(context: context, clanId: channel.clanID, identityKey: identityKey)
    }

    private func syncVoiceAgentToggleFromRoomState() {
        guard !isAgentToggleLoading, !agentToggleButton.isHidden else { return }
        guard let room = liveKitBridge?.room else { return }
        let all: [Participant] = [room.localParticipant] + Array(room.remoteParticipants.values)
        let hasAgent = all.contains { $0.kind == .agent }
        if hasAgent, !voiceAgentEnabled {
            voiceAgentEnabled = true
            refreshVoiceAgentButtonAppearance()
        }
    }

    private enum AudioOutputMode {
        case speaker
        case earpiece
        case bluetooth
    }

    private var currentAudioOutput: AudioOutputMode = .earpiece

    private func ensureVoiceChannelAudioSessionCategory() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
        }
    }

    private func syncCurrentAudioOutputFromSession() {
        let session = AVAudioSession.sharedInstance()
        guard let port = session.currentRoute.outputs.first?.portType else {
            currentAudioOutput = .earpiece
            AudioManager.shared.isSpeakerOutputPreferred = false
            return
        }
        switch port {
        case .builtInSpeaker:
            currentAudioOutput = .speaker
            AudioManager.shared.isSpeakerOutputPreferred = true
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            currentAudioOutput = .bluetooth
            AudioManager.shared.isSpeakerOutputPreferred = false
        case .headphones, .headsetMic:
            currentAudioOutput = .earpiece
            AudioManager.shared.isSpeakerOutputPreferred = false
        case .builtInReceiver:
            currentAudioOutput = .earpiece
            AudioManager.shared.isSpeakerOutputPreferred = false
        default:
            if Self.audioRouteHasBluetooth(session) {
                currentAudioOutput = .bluetooth
            } else {
                currentAudioOutput = .earpiece
            }
            AudioManager.shared.isSpeakerOutputPreferred = false
        }
    }

    private func detectInitialAudioRoute() {
        ensureVoiceChannelAudioSessionCategory()
        syncCurrentAudioOutputFromSession()
        refreshSpeakerRouteUI()
    }

    private func applyAudioRoute() {
        switch currentAudioOutput {
        case .speaker: applyVoiceChannelPreservedAudioRouteToSession(.speaker)
        case .earpiece: applyVoiceChannelPreservedAudioRouteToSession(.earpiece)
        case .bluetooth: applyVoiceChannelPreservedAudioRouteToSession(.bluetooth)
        }
        syncCurrentAudioOutputFromSession()
        refreshSpeakerRouteUI()
    }

    private func refreshSpeakerRouteUI() {
        let t = UIColor.theme.white
        audioRouteControl.applyTint(t)
        let session = AVAudioSession.sharedInstance()
        let systemName: String
        if let port = session.currentRoute.outputs.first?.portType {
            switch port {
            case .headphones, .headsetMic:
                systemName = "headphones"
                audioRouteControl.setRouteStateSymbol(systemName: systemName, pointSize: 16, weight: .medium)
                return
            default:
                break
            }
        }
        let bluetooth = Self.audioRouteHasBluetooth(session)
        if bluetooth && currentAudioOutput != .speaker {
            systemName = "headphones"
        } else if currentAudioOutput == .speaker {
            systemName = "speaker.wave.2.fill"
        } else {
            systemName = "iphone.radiowaves.left.and.right"
        }
        audioRouteControl.setRouteStateSymbol(systemName: systemName, pointSize: 16, weight: .medium)
    }

    private static func audioRouteHasBluetooth(_ session: AVAudioSession) -> Bool {
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
                self.refreshParticipantRowsFromLiveKit()
            } catch {
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

    private func performLiveKitFinalTeardown(error: LiveKitError?) {
        tearDownCallPiP()
        tearDownScreenSharePresentationAndPiP()

        if error?.type == .roomDeleted {
            context.engine.clanData.applyVoiceEnded(clanId: channel.clanID, channelId: channel.channelID)
        }

        connectTask?.cancel()
        connectTask = nil
        liveKitReconnectTask?.cancel()
        liveKitReconnectTask = nil
        participantStateRefreshWorkItem?.cancel()
        participantStateRefreshWorkItem = nil
        participantOrderRebuildWorkItem?.cancel()
        participantOrderRebuildWorkItem = nil

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
                    self?.popVoiceRoomOrAlignHomeAfterCrossClanVoice()
                }
            case .cancelled:
                popVoiceRoomOrAlignHomeAfterCrossClanVoice()
            default:
                presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Voice", comment: ""),
                    message: lk.localizedDescription
                ) { [weak self] in
                    self?.popVoiceRoomOrAlignHomeAfterCrossClanVoice()
                }
            }
        } else {
            popVoiceRoomOrAlignHomeAfterCrossClanVoice()
        }
    }

    private func handleLiveKitDisconnected(error: LiveKitError?) {
        guard liveKitBridge != nil else { return }

        if liveKitDisconnectIsFatal(error) {
            performLiveKitFinalTeardown(error: error)
            return
        }

        tearDownCallPiP()
        tearDownScreenSharePresentationAndPiP()


        connectTask?.cancel()
        connectTask = nil

        liveKitReconnectTask?.cancel()
        liveKitReconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.executeMainLiveKitReconnect()
        }
        setConnectingOverlayVisible(true)
    }

    private func executeMainLiveKitReconnect() async {
        let meetURL = MezonConfig.meetWebSocketURLString
        let roomName = "\(channel.channelID)"
        for attempt in 1...Self.liveKitManualReconnectMax {
            guard liveKitBridge != nil else { return }
            let delaySec = attempt == 1 ? 0.4 : min(Double(attempt) * 1.2, 12.0)
            try? await Task.sleep(nanoseconds: UInt64(delaySec * 1_000_000_000))
            if Task.isCancelled { return }
            guard let bridge = liveKitBridge else { return }
            await context.waitForSessionReady()
            if Task.isCancelled { return }
            guard let token = await context.getToken() else {
                performLiveKitFinalTeardown(error: nil)
                return
            }
            do {
                let jwt = try await context.account.network.generateMeetToken(
                    channelId: channel.channelID,
                    roomName: roomName,
                    token: token
                )
                guard !jwt.isEmpty else { continue }
                try await bridge.connect(url: meetURL, token: jwt)
                if Task.isCancelled { return }
                setConnectingOverlayVisible(false)
                refreshMicButtonIcon()
                applyAudioRoute()
                refreshCamButtonIcon()
                refreshParticipantRowsFromLiveKit()
                setupCallPiP()
                liveKitReconnectTask = nil
                return
            } catch {
            }
        }
        performLiveKitFinalTeardown(error: nil)
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

    private func prefetchVoiceChannelPermissions() async {
        guard let token = await context.getToken() else { return }
        do {
            let response = try await context.account.network.listUserPermissionInChannel(
                clanId: channel.clanID,
                channelId: channel.channelID,
                token: token
            )
            let records = response.permissions.permissions.map { PermissionRecord(from: $0) }
            let channelId = channel.channelID
            context.account.postbox.writeSync { tx in
                tx.updateChannelPermissions(records, channelId: channelId)
            }
        } catch {
        }
    }

    private func voiceChannelCanManageVoice() -> Bool {
        let clanId = channel.clanID

        guard let roleList = context.engine.clanData.getUserPermissions(clanId: clanId) else { return false }
        let maxLevel = roleList.maxLevelPermission

        guard let allPerms = context.engine.clanData.getAllPermissions() else { return false }
        guard let manageChannelPerm = allPerms.permissions.first(where: {
            $0.slug.lowercased().replacingOccurrences(of: "_", with: "-") == "manage-channel"
        }) else { return false }

        return manageChannelPerm.level <= maxLevel
    }

    private func applyVoiceAgentEnabledFromServer(_ enabled: Bool) {
        voiceAgentEnabled = enabled
        refreshVoiceAgentButtonAppearance()
    }

    private func refreshVoiceAgentButtonAppearance() {
        let iconTint = voiceAgentEnabled ? UIColor.theme.white : UIColor.theme.textStrong
        if isAgentToggleLoading {
            agentToggleSpinner.startAnimating()
            agentToggleButton.setImage(nil, for: .normal)
        } else {
            agentToggleSpinner.stopAnimating()
            if let base = UIImage(named: "Channel/VoiceAgentControl") {
                if #available(iOS 15.0, *) {
                    let img = base.withTintColor(
                        iconTint, renderingMode: .alwaysOriginal)
                    agentToggleButton.setImage(img, for: .normal)
                } else {
                    agentToggleButton.setImage(
                        base.withRenderingMode(.alwaysTemplate), for: .normal)
                }
            }
        }
        agentToggleButton.isEnabled = !isAgentToggleLoading
        if voiceAgentEnabled {
            agentToggleButton.backgroundColor = UIColor.theme.bgViolet
            agentToggleButton.layer.borderColor = UIColor.theme.borderHighlight.cgColor
            agentToggleButton.layer.borderWidth = 1.5
        } else {
            agentToggleButton.backgroundColor = UIColor.theme.secondary
            agentToggleButton.layer.borderColor = UIColor.theme.border.cgColor
            agentToggleButton.layer.borderWidth = 1
        }
        agentToggleButton.tintColor = iconTint
        agentToggleSpinner.color = iconTint
    }

    @objc private func agentToggleTapped() {
        guard !isAgentToggleLoading, voiceChannelCanManageVoice(), !agentToggleButton.isHidden else { return }
        let wasEnabled = voiceAgentEnabled
        isAgentToggleLoading = true
        voiceAgentEnabled.toggle()
        refreshVoiceAgentButtonAppearance()
        let ch = channel
        let roomName = "\(ch.channelID)"
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isAgentToggleLoading = false
                self.refreshVoiceAgentButtonAppearance()
            }
            guard let token = await self.context.getToken() else {
                self.voiceAgentEnabled = wasEnabled
                self.refreshVoiceAgentButtonAppearance()
                self.presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Error", comment: ""),
                    message: NSLocalizedString("voiceChannel.agentNoSession", tableName: nil, bundle: .main, value: "Could not verify your session.", comment: ""))
                return
            }
            do {
                if wasEnabled {
                    try await self.context.account.network.disconnectAgentFromVoiceChannel(channelId: ch.channelID, roomName: roomName, token: token)
                } else {
                    try await self.context.account.network.addAgentToVoiceChannel(channelId: ch.channelID, roomName: roomName, token: token)
                }
            } catch {
                self.voiceAgentEnabled = wasEnabled
                self.refreshVoiceAgentButtonAppearance()
                self.presentVoiceAlert(
                    title: NSLocalizedString("voiceChannel.errorTitle", tableName: nil, bundle: .main, value: "Error", comment: ""),
                    message: error.localizedDescription)
            }
        }
    }

    private func voiceParticipantIsSelf(identityKey: String, clanUser: Mezon_Api_ClanUserList.ClanUser?) -> Bool {
        if let myId = context.currentUser?.id, myId == identityKey { return true }
        if let u = clanUser?.user.username, !u.isEmpty,
           let my = context.currentUser?.username, !my.isEmpty, u == my { return true }
        return false
    }

    private func applyParticipantRowCallbacks(rowKey: String, row: VoiceParticipantRowView, participant: Participant, displayName: String) {
        if rowKey.hasSuffix("|screen") {
            row.onMainTileLongPress = nil
            let sourceKey = participantRowKey(participant)
            row.onExpandScreenShare = { [weak self] in
                guard let self, let track = participant.firstScreenShareVideoTrack else { return }
                self.presentScreenShareExpanded(track: track, displayName: displayName, sourceParticipantKey: sourceKey)
            }
            return
        }
        row.onExpandScreenShare = nil
        if participant is LocalParticipant {
            row.onMainTileLongPress = nil
        } else {
            row.onMainTileLongPress = { [weak self] in
                self?.presentParticipantShortProfile(for: participant)
            }
        }
    }

    private func presentParticipantShortProfile(for participant: Participant) {
        if VoiceChannelPiPOverlay.shared.isActive { return }
        guard liveKitBridge?.room != nil else { return }
        let idKey = participant.identity?.stringValue ?? ""
        guard !idKey.isEmpty else { return }
        let cu = voiceChannelFindClanUser(context: context, clanId: channel.clanID, identityKey: idKey)
        if voiceParticipantIsSelf(identityKey: idKey, clanUser: cu) { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prefetchVoiceChannelPermissions()
            guard self.liveKitBridge?.room != nil else { return }
            let micOn = participant.isMicrophoneEnabled()
            let subtitle = voiceChannelShortProfileSubtitleLine(cu: cu, identityFallback: idKey)
            let display = self.resolveDisplayName(participant: participant)
            let avatarURL = voiceChannelResolveAvatarURL(context: self.context, clanId: self.channel.clanID, identityKey: idKey)
            let canManage = self.voiceChannelCanManageVoice()
            let roomName = "\(self.channel.channelID)"

            var apiUser = Mezon_Api_User()
            if let cu {
                apiUser = cu.user
            } else if let uid = Int64(idKey) {
                apiUser.id = uid
            }
            apiUser.displayName = display
            if !subtitle.isEmpty {
                apiUser.username = subtitle
            }
            if let avatarURL, !avatarURL.isEmpty {
                apiUser.avatarURL = avatarURL
            }

            let voiceActions: MemberProfileVoiceChannelActions? = canManage
                ? MemberProfileVoiceChannelActions(
                    showMute: micOn,
                    showKick: true,
                    confirmUserLabel: display.isEmpty ? subtitle : display,
                    onMute: { [weak self] in
                        guard let self else { return }
                        guard let token = await self.context.getToken() else {
                            throw NSError(domain: "VoiceChannel", code: 0, userInfo: [
                                NSLocalizedDescriptionKey: NSLocalizedString(
                                    "voiceChannel.shortProfile.notSignedIn", tableName: nil, bundle: .main, value: "Not signed in", comment: ""),
                            ])
                        }
                        try await self.context.account.network.muteMezonMeetParticipant(
                            clanId: self.channel.clanID,
                            channelId: self.channel.channelID,
                            roomName: roomName,
                            username: idKey,
                            token: token
                        )
                    },
                    onKick: { [weak self] in
                        guard let self else { return }
                        guard let token = await self.context.getToken() else {
                            throw NSError(domain: "VoiceChannel", code: 0, userInfo: [
                                NSLocalizedDescriptionKey: NSLocalizedString(
                                    "voiceChannel.shortProfile.notSignedIn", tableName: nil, bundle: .main, value: "Not signed in", comment: ""),
                            ])
                        }
                        try await self.context.account.network.removeMezonMeetParticipant(
                            clanId: self.channel.clanID,
                            channelId: self.channel.channelID,
                            roomName: roomName,
                            username: idKey,
                            token: token
                        )
                    }
                )
                : nil

            let sheet = MemberProfileSheetController(
                user: apiUser,
                context: self.context,
                isCurrentUser: false,
                voiceChannelActions: voiceActions,
                onSendMessage: { [weak self] dmChannel in
                    guard let self else { return }
                    self.context.currentClanId = 0
                    let chatVC = ChatViewController(
                        clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                    self.navigationController?.pushViewController(chatVC, animated: true)
                }
            )

            let navForOverlay = self.navigationControllerForGlobalOverlay()
            if let nav = navForOverlay {
                nav.presentOverlay(controller: sheet, inGlobal: true)
            } else if let host = self.presentationWindowHost() {
                host.presentInGlobalOverlay(sheet)
            } else {
                self.presentInGlobalOverlay(sheet)
            }
            sheet.animateIn()
            DispatchQueue.main.async { [weak sheet] in
                navForOverlay?.requestLayout(transition: .immediate)
                sheet?.animateIn()
            }
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

    private func presentScreenShareExpanded(track: VideoTrack, displayName: String, sourceParticipantKey: String) {
        tearDownScreenSharePresentationAndPiP()
        guard #available(iOS 15.0, *) else { return }
        screenShareExpandedPresentedAt = Date()
        screenShareExpandedSourceParticipantKey = sourceParticipantKey
        screenShareExpandedSourceTrack = track
        unlockOrientationForScreenShareDetail()
        let vc = ScreenShareExpandedViewController(track: track, displayName: displayName)
        vc.pipHost = self
        vc.modalPresentationStyle = .fullScreen
        isScreenShareExpandedPresented = true
        present(vc, animated: true)
    }

    private func unlockOrientationForScreenShareDetail() {
        guard !didUnlockOrientationForScreenShareDetail else { return }
        didUnlockOrientationForScreenShareDetail = true
        lockOrientation = false
        lockedOrientation = nil
        window?.invalidateSupportedOrientations()
        UIViewController.attemptRotationToDeviceOrientation()
    }

    fileprivate func restoreOrientationLockAfterScreenShareDetailIfNeeded() {
        guard didUnlockOrientationForScreenShareDetail else { return }
        didUnlockOrientationForScreenShareDetail = false
        lockOrientation = true
        lockedOrientation = .portrait
        window?.invalidateSupportedOrientations()
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        UIViewController.attemptRotationToDeviceOrientation()
    }

    @available(iOS 15.0, *)
    private func findScreenShareExpandedPresenter() -> (presenter: UIViewController, expanded: ScreenShareExpandedViewController)? {
        var cur: UIViewController? = self
        while let c = cur {
            if let exp = c.presentedViewController as? ScreenShareExpandedViewController {
                return (c, exp)
            }
            cur = c.presentedViewController
        }
        return nil
    }

    @available(iOS 15.0, *)
    private func searchScreenShareExpanded(in vc: UIViewController) -> ScreenShareExpandedViewController? {
        if let e = vc as? ScreenShareExpandedViewController {
            return e
        }
        if let p = vc.presentedViewController, let found = searchScreenShareExpanded(in: p) {
            return found
        }
        if let nav = vc as? UINavigationController, let top = nav.visibleViewController ?? nav.topViewController {
            if let found = searchScreenShareExpanded(in: top) {
                return found
            }
        }
        if let tab = vc as? UITabBarController, let sel = tab.selectedViewController {
            if let found = searchScreenShareExpanded(in: sel) {
                return found
            }
        }
        for child in vc.children {
            if let found = searchScreenShareExpanded(in: child) {
                return found
            }
        }
        return nil
    }

    @available(iOS 15.0, *)
    private func findScreenShareExpandedViewControllerInKeyWindowHierarchy() -> ScreenShareExpandedViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows where !window.isHidden {
                guard let root = window.rootViewController else { continue }
                if let found = searchScreenShareExpanded(in: root) {
                    return found
                }
            }
        }
        return nil
    }

    private func tearDownScreenSharePresentationAndPiP() {
        noteScreenShareExpandedSessionEnded()
        if #available(iOS 15.0, *) {
            if let (presenter, expanded) = findScreenShareExpandedPresenter() {
                isScreenShareExpandedPresented = false
                expanded.tearDownForVoiceRoomLeaving()
                presenter.dismiss(animated: false)
            } else if let expanded = presentedViewController as? ScreenShareExpandedViewController {
                isScreenShareExpandedPresented = false
                expanded.tearDownForVoiceRoomLeaving()
                dismiss(animated: false)
            } else if let expanded = findScreenShareExpandedViewControllerInKeyWindowHierarchy() {
                isScreenShareExpandedPresented = false
                expanded.tearDownForVoiceRoomLeaving()
                expanded.dismiss(animated: false)
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

extension VoiceChannelRoomViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === contentScroll else { return }
        voiceParticipantListUserScrolling = true
        participantOrderRebuildWorkItem?.cancel()
        participantOrderRebuildWorkItem = nil
        if participantStateRefreshWorkItem != nil {
            participantStateRefreshWorkItem?.cancel()
            participantStateRefreshWorkItem = nil
            pendingParticipantStateRefreshAfterScroll = true
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === contentScroll else { return }
        if !decelerate {
            voiceParticipantListScrollInteractionEnded()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === contentScroll else { return }
        voiceParticipantListScrollInteractionEnded()
    }
}

extension VoiceChannelRoomViewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {}

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        guard pictureInPictureController === callPiPController else { return }
        tearDownCallPiP()
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
    private var screenShareFocusPollTimer: Foundation.Timer?

    private let scrollView = UIScrollView()
    private let videoContainer = UIView()

    private let dismissDetailButton = UIButton(type: .system)

    private var scrollTopConstraint: NSLayoutConstraint!
    private var scrollLeadingConstraint: NSLayoutConstraint!
    private var scrollTrailingConstraint: NSLayoutConstraint!
    private var scrollBottomConstraint: NSLayoutConstraint!
    private var dismissDetailTopConstraint: NSLayoutConstraint!
    private var dismissDetailTrailingConstraint: NSLayoutConstraint!

    init(track: VideoTrack, displayName: String) {
        self.shareTrack = track
        self.personName = displayName
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        preferredContentSize = CGSize(width: 1920, height: 1080)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func voiceRoomHostForDismiss() -> VoiceChannelRoomViewController? {
        pipHost ?? presentingViewController as? VoiceChannelRoomViewController
    }

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

        videoView.track = shareTrack
        applyScreenShareLayoutForCurrentBounds()
    }

    private func applyScreenShareLayoutForCurrentBounds() {
        let landscape = view.bounds.width > view.bounds.height
        let margin: CGFloat = landscape ? 20 : 0
        videoView.layoutMode = .fit
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
            self?.voiceRoomHostForDismiss()?.dismissScreenShareExpandedIfSourceShareEnded()
        }
        RunLoop.main.add(timer, forMode: .common)
        screenShareFocusPollTimer = timer
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
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
        videoView.track = nil
        pipController?.delegate = nil
        pipController = nil
    }

    fileprivate func tearDownForVoiceRoomLeaving() {
        screenShareFocusPollTimer?.invalidate()
        screenShareFocusPollTimer = nil
        pipController?.stopPictureInPicture()
        videoView.track = nil
        pipController?.delegate = nil
        pipController = nil
    }

    @objc private func closeScreenShareTapped() {
        screenShareFocusPollTimer?.invalidate()
        screenShareFocusPollTimer = nil
        pipController?.stopPictureInPicture()
        pipHost?.releaseScreenSharePiPHost(self)
        dismiss(animated: true)
    }

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
        videoView.track = nil
        pipController?.delegate = nil
        pipController = nil
        pipHost?.releaseScreenSharePiPHost(self)
        pipHost?.noteScreenShareExpandedSessionEnded()
    }
}

private struct VoiceParticipantTileLayoutMetrics: Equatable {
    var tileHeight: CGFloat
    var columnWidth: CGFloat
    var avatarDiameter: CGFloat
    var avatarCenterYOffset: CGFloat
    var badgeHeight: CGFloat
    var badgeIconSide: CGFloat
    var badgeFontSize: CGFloat
    var initialFontSize: CGFloat
    var soundCornerSide: CGFloat
    var soundIconSide: CGFloat
    var raiseHandCornerSide: CGFloat
    var raiseHandIconSide: CGFloat
    var cardCornerRadius: CGFloat
    var expandSymbolPointSize: CGFloat

    static let fallback = VoiceParticipantTileLayoutMetrics(
        tileHeight: 150,
        columnWidth: 170,
        avatarDiameter: 50,
        avatarCenterYOffset: -10,
        badgeHeight: 24,
        badgeIconSide: 14,
        badgeFontSize: 12,
        initialFontSize: 20,
        soundCornerSide: 28,
        soundIconSide: 16,
        raiseHandCornerSide: 26,
        raiseHandIconSide: 15,
        cardCornerRadius: 10,
        expandSymbolPointSize: 14
    )
}

private func voiceParticipantTileLayoutMetrics(gridWidth: CGFloat) -> VoiceParticipantTileLayoutMetrics {
    let inner = max(200, gridWidth)
    let col = max(90, (inner - 10) / 2)
    let ref: CGFloat = 168
    let s = min(1.45, max(0.76, col / ref))
    let tileH = max(122, min(318, col * 0.86))
    let avatar = max(44, min(126, 50 * s))
    let avY = max(-22, min(-6, -10 * s))
    let badgeH = max(20, min(34, 24 * s))
    let badgeIconS = max(12, min(18, 14 * s))
    let badgeFont = max(10, min(16, 12 * s))
    let initialF = max(16, min(26, 20 * s))
    let soundC = max(24, min(36, 28 * s))
    let soundI = max(14, min(20, 16 * s))
    let raiseC = max(22, min(32, 26 * s))
    let raiseI = max(12, min(18, 15 * s))
    let cardR = max(8, min(16, 10 * s))
    let expSym = max(12, min(18, 14 * s))
    return VoiceParticipantTileLayoutMetrics(
        tileHeight: tileH,
        columnWidth: col,
        avatarDiameter: avatar,
        avatarCenterYOffset: avY,
        badgeHeight: badgeH,
        badgeIconSide: badgeIconS,
        badgeFontSize: badgeFont,
        initialFontSize: initialF,
        soundCornerSide: soundC,
        soundIconSide: soundI,
        raiseHandCornerSide: raiseC,
        raiseHandIconSide: raiseI,
        cardCornerRadius: cardR,
        expandSymbolPointSize: expSym
    )
}

private final class VoiceParticipantRowView: UIView {

    let identityKey: String
    var onExpandScreenShare: (() -> Void)?
    var onMainTileLongPress: (() -> Void)?
    private let tileKind: VoiceParticipantTileKind
    private let card = UIView()
    private let videoView = VideoView()
    private let avatarView = UIImageView()
    private let initialLabel = UILabel()
    private let expandButton = UIButton(type: .system)
    private let badgeContainer = UIView()
    private let badgeIcon = UIImageView()
    private let badgeLabel = UILabel()
    private let soundReactionCorner = UIView()
    private let soundReactionIcon = UIImageView()
    private var soundReactionCornerVisible = false
    private let raiseHandCorner = UIView()
    private let raiseHandIcon = UIImageView()
    private var raiseHandCornerVisible = false
    private var soundReactionTrailingToCard: NSLayoutConstraint?
    private var soundReactionTrailingToRaiseHand: NSLayoutConstraint?
    private var lastAvatarURL: String?
    private var lastTileVisualState: (displayName: String, micOn: Bool, speaking: Bool, mirrorVideo: Bool, track: VideoTrack?, avatarURL: String?)?
    private var badgeMicOn = true
    private var layoutMetrics = VoiceParticipantTileLayoutMetrics.fallback
    private var avatarWidthConstraint: NSLayoutConstraint!
    private var avatarHeightConstraint: NSLayoutConstraint!
    private var avatarCenterYConstraint: NSLayoutConstraint!
    private var badgeHeightConstraint: NSLayoutConstraint!
    private var badgeIconWidthConstraint: NSLayoutConstraint!
    private var badgeIconHeightConstraint: NSLayoutConstraint!
    private var soundCornerWidthConstraint: NSLayoutConstraint!
    private var soundCornerHeightConstraint: NSLayoutConstraint!
    private var soundIconWidthConstraint: NSLayoutConstraint!
    private var soundIconHeightConstraint: NSLayoutConstraint!
    private var raiseHandCornerWidthConstraint: NSLayoutConstraint!
    private var raiseHandCornerHeightConstraint: NSLayoutConstraint!
    private var raiseHandIconWidthConstraint: NSLayoutConstraint!
    private var raiseHandIconHeightConstraint: NSLayoutConstraint!

    init(identityKey: String, tileKind: VoiceParticipantTileKind) {
        self.identityKey = identityKey
        self.tileKind = tileKind
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true

        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = layoutMetrics.cardCornerRadius
        card.clipsToBounds = true
        card.layer.borderWidth = 1

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.layoutMode = .fill
        videoView.isPinchToZoomEnabled = false
        videoView.isUserInteractionEnabled = false
        videoView.layer.cornerRadius = layoutMetrics.cardCornerRadius
        videoView.clipsToBounds = true
        videoView.isHidden = true

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = layoutMetrics.avatarDiameter / 2

        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.font = .systemFont(ofSize: layoutMetrics.initialFontSize, weight: .bold)
        initialLabel.textColor = .white
        initialLabel.textAlignment = .center

        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.isHidden = tileKind != .screenShare
        let expandCfg = UIImage.SymbolConfiguration(pointSize: layoutMetrics.expandSymbolPointSize, weight: .medium)
        expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: expandCfg), for: .normal)
        expandButton.tintColor = .white
        expandButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        expandButton.layer.cornerRadius = 6
        expandButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        expandButton.isUserInteractionEnabled = tileKind == .screenShare
        expandButton.addTarget(self, action: #selector(expandScreenShareTapped), for: .touchUpInside)

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badgeContainer.layer.cornerRadius = layoutMetrics.badgeHeight / 2

        badgeIcon.translatesAutoresizingMaskIntoConstraints = false
        badgeIcon.contentMode = .scaleAspectFit
        badgeIcon.setContentHuggingPriority(.required, for: .horizontal)
        badgeIcon.setContentCompressionResistancePriority(.required, for: .horizontal)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: layoutMetrics.badgeFontSize, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.lineBreakMode = .byTruncatingTail
        badgeLabel.numberOfLines = 1

        soundReactionCorner.translatesAutoresizingMaskIntoConstraints = false
        soundReactionCorner.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        soundReactionCorner.layer.cornerRadius = layoutMetrics.soundCornerSide / 2
        soundReactionCorner.isHidden = true
        soundReactionIcon.translatesAutoresizingMaskIntoConstraints = false
        soundReactionIcon.contentMode = .scaleAspectFit
        let soundCfg = UIImage.SymbolConfiguration(pointSize: layoutMetrics.soundIconSide * 0.88, weight: .semibold)
        soundReactionIcon.image = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: soundCfg)
        soundReactionIcon.tintColor = UIColor(red: 0.35, green: 0.78, blue: 0.95, alpha: 1)
        soundReactionCorner.addSubview(soundReactionIcon)

        raiseHandCorner.translatesAutoresizingMaskIntoConstraints = false
        raiseHandCorner.backgroundColor = UIColor(red: 0.22, green: 0.48, blue: 0.95, alpha: 1)
        raiseHandCorner.layer.cornerRadius = layoutMetrics.raiseHandCornerSide / 2
        raiseHandCorner.isHidden = true
        raiseHandIcon.translatesAutoresizingMaskIntoConstraints = false
        raiseHandIcon.contentMode = .scaleAspectFit
        let raiseCfg = UIImage.SymbolConfiguration(pointSize: layoutMetrics.raiseHandIconSide * 0.9, weight: .semibold)
        raiseHandIcon.image = UIImage(systemName: "hand.raised.fill", withConfiguration: raiseCfg)
        raiseHandIcon.tintColor = .white
        raiseHandCorner.addSubview(raiseHandIcon)

        addSubview(card)
        card.addSubview(videoView)
        card.addSubview(avatarView)
        card.addSubview(initialLabel)
        if tileKind == .screenShare {
            card.addSubview(expandButton)
        }
        card.addSubview(badgeContainer)
        card.addSubview(soundReactionCorner)
        card.addSubview(raiseHandCorner)
        badgeContainer.addSubview(badgeIcon)
        badgeContainer.addSubview(badgeLabel)

        avatarCenterYConstraint = avatarView.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: layoutMetrics.avatarCenterYOffset)
        avatarWidthConstraint = avatarView.widthAnchor.constraint(equalToConstant: layoutMetrics.avatarDiameter)
        avatarHeightConstraint = avatarView.heightAnchor.constraint(equalToConstant: layoutMetrics.avatarDiameter)
        badgeHeightConstraint = badgeContainer.heightAnchor.constraint(equalToConstant: layoutMetrics.badgeHeight)
        badgeIconWidthConstraint = badgeIcon.widthAnchor.constraint(equalToConstant: layoutMetrics.badgeIconSide)
        badgeIconHeightConstraint = badgeIcon.heightAnchor.constraint(equalToConstant: layoutMetrics.badgeIconSide)
        soundCornerWidthConstraint = soundReactionCorner.widthAnchor.constraint(equalToConstant: layoutMetrics.soundCornerSide)
        soundCornerHeightConstraint = soundReactionCorner.heightAnchor.constraint(equalToConstant: layoutMetrics.soundCornerSide)
        soundIconWidthConstraint = soundReactionIcon.widthAnchor.constraint(equalToConstant: layoutMetrics.soundIconSide)
        soundIconHeightConstraint = soundReactionIcon.heightAnchor.constraint(equalToConstant: layoutMetrics.soundIconSide)
        raiseHandCornerWidthConstraint = raiseHandCorner.widthAnchor.constraint(equalToConstant: layoutMetrics.raiseHandCornerSide)
        raiseHandCornerHeightConstraint = raiseHandCorner.heightAnchor.constraint(equalToConstant: layoutMetrics.raiseHandCornerSide)
        raiseHandIconWidthConstraint = raiseHandIcon.widthAnchor.constraint(equalToConstant: layoutMetrics.raiseHandIconSide)
        raiseHandIconHeightConstraint = raiseHandIcon.heightAnchor.constraint(equalToConstant: layoutMetrics.raiseHandIconSide)

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
            avatarCenterYConstraint,
            avatarWidthConstraint,
            avatarHeightConstraint,

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
            badgeIconWidthConstraint,
            badgeIconHeightConstraint,

            badgeLabel.leadingAnchor.constraint(equalTo: badgeIcon.trailingAnchor, constant: 4),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -8),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

            badgeHeightConstraint,

            soundCornerWidthConstraint,
            soundCornerHeightConstraint,
            soundReactionIcon.centerXAnchor.constraint(equalTo: soundReactionCorner.centerXAnchor),
            soundReactionIcon.centerYAnchor.constraint(equalTo: soundReactionCorner.centerYAnchor),
            soundIconWidthConstraint,
            soundIconHeightConstraint,

            raiseHandCornerWidthConstraint,
            raiseHandCornerHeightConstraint,
            raiseHandIcon.centerXAnchor.constraint(equalTo: raiseHandCorner.centerXAnchor),
            raiseHandIcon.centerYAnchor.constraint(equalTo: raiseHandCorner.centerYAnchor),
            raiseHandIconWidthConstraint,
            raiseHandIconHeightConstraint,
        ]
        if tileKind == .screenShare {
            constraints.append(contentsOf: [
                expandButton.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                expandButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
                soundReactionCorner.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                soundReactionCorner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                raiseHandCorner.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                raiseHandCorner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            ])
        } else {
            let stCard = soundReactionCorner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8)
            let stRaise = soundReactionCorner.trailingAnchor.constraint(equalTo: raiseHandCorner.leadingAnchor, constant: -6)
            soundReactionTrailingToCard = stCard
            soundReactionTrailingToRaiseHand = stRaise
            constraints.append(contentsOf: [
                soundReactionCorner.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                stCard,
                raiseHandCorner.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                raiseHandCorner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        if tileKind == .mainVideo {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(mainTileLongPressed(_:)))
            lp.minimumPressDuration = 0.45
            card.addGestureRecognizer(lp)
        }
        applyTheme()
    }

    @objc private func mainTileLongPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        onMainTileLongPress?()
    }

    func applyLayoutMetrics(_ m: VoiceParticipantTileLayoutMetrics) {
        layoutMetrics = m
        avatarWidthConstraint.constant = m.avatarDiameter
        avatarHeightConstraint.constant = m.avatarDiameter
        avatarCenterYConstraint.constant = m.avatarCenterYOffset
        badgeHeightConstraint.constant = m.badgeHeight
        badgeIconWidthConstraint.constant = m.badgeIconSide
        badgeIconHeightConstraint.constant = m.badgeIconSide
        soundCornerWidthConstraint.constant = m.soundCornerSide
        soundCornerHeightConstraint.constant = m.soundCornerSide
        soundIconWidthConstraint.constant = m.soundIconSide
        soundIconHeightConstraint.constant = m.soundIconSide
        raiseHandCornerWidthConstraint.constant = m.raiseHandCornerSide
        raiseHandCornerHeightConstraint.constant = m.raiseHandCornerSide
        raiseHandIconWidthConstraint.constant = m.raiseHandIconSide
        raiseHandIconHeightConstraint.constant = m.raiseHandIconSide
        card.layer.cornerRadius = m.cardCornerRadius
        videoView.layer.cornerRadius = m.cardCornerRadius
        avatarView.layer.cornerRadius = m.avatarDiameter / 2
        badgeContainer.layer.cornerRadius = m.badgeHeight / 2
        soundReactionCorner.layer.cornerRadius = m.soundCornerSide / 2
        raiseHandCorner.layer.cornerRadius = m.raiseHandCornerSide / 2
        badgeLabel.font = .systemFont(ofSize: m.badgeFontSize, weight: .semibold)
        initialLabel.font = .systemFont(ofSize: m.initialFontSize, weight: .bold)
        if tileKind == .screenShare {
            let expandCfg = UIImage.SymbolConfiguration(pointSize: m.expandSymbolPointSize, weight: .medium)
            expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: expandCfg), for: .normal)
        }
        let soundCfg = UIImage.SymbolConfiguration(pointSize: m.soundIconSide * 0.88, weight: .semibold)
        soundReactionIcon.image = UIImage(systemName: "speaker.wave.2.fill", withConfiguration: soundCfg)
        let raiseCfg = UIImage.SymbolConfiguration(pointSize: m.raiseHandIconSide * 0.9, weight: .semibold)
        raiseHandIcon.image = UIImage(systemName: "hand.raised.fill", withConfiguration: raiseCfg)
        refreshBadgeSymbols()
    }

    private func refreshBadgeSymbols() {
        let pt = max(10, min(17, layoutMetrics.badgeIconSide * 0.82))
        let iconCfg = UIImage.SymbolConfiguration(pointSize: pt, weight: .medium)
        switch tileKind {
        case .mainVideo:
            let micName = badgeMicOn ? "mic.fill" : "mic.slash.fill"
            badgeIcon.image = UIImage(systemName: micName, withConfiguration: iconCfg)
            badgeIcon.tintColor = .white
        case .screenShare:
            badgeIcon.image = UIImage(systemName: "rectangle.on.rectangle", withConfiguration: iconCfg)
            badgeIcon.tintColor = .white
        }
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
        setSoundReactionCornerVisible(false)
        setRaiseHandCornerVisible(false)
        lastAvatarURL = nil
        lastTileVisualState = nil
    }

    func applyTheme() {
        card.backgroundColor = UIColor.theme.secondary
        card.layer.borderColor = UIColor.theme.borderDim.cgColor
    }

    func setRaiseHandCornerVisible(_ visible: Bool) {
        guard visible != raiseHandCornerVisible else { return }
        raiseHandCornerVisible = visible
        raiseHandCorner.layer.removeAllAnimations()
        raiseHandIcon.layer.removeAllAnimations()
        if visible {
            raiseHandCorner.isHidden = false
            raiseHandCorner.alpha = 0
            raiseHandCorner.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                self.raiseHandCorner.alpha = 1
                self.raiseHandCorner.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
                self.raiseHandCorner.alpha = 0
                self.raiseHandCorner.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            } completion: { _ in
                self.raiseHandCorner.isHidden = true
                self.raiseHandCorner.transform = .identity
            }
        }
        updateSoundTrailingRelativeToRaiseHand()
    }

    private func updateSoundTrailingRelativeToRaiseHand() {
        guard tileKind == .mainVideo, let stCard = soundReactionTrailingToCard, let stRaise = soundReactionTrailingToRaiseHand else { return }
        let shift = raiseHandCornerVisible
        stCard.isActive = !shift
        stRaise.isActive = shift
    }

    func setSoundReactionCornerVisible(_ visible: Bool) {
        guard visible != soundReactionCornerVisible else { return }
        soundReactionCornerVisible = visible
        soundReactionCorner.layer.removeAllAnimations()
        soundReactionIcon.layer.removeAllAnimations()
        if visible {
            soundReactionCorner.isHidden = false
            soundReactionCorner.alpha = 0
            soundReactionCorner.transform = CGAffineTransform(scaleX: 0.65, y: 0.65)
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
                self.soundReactionCorner.alpha = 1
                self.soundReactionCorner.transform = .identity
            }
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 1
            pulse.toValue = 1.12
            pulse.duration = 0.45
            pulse.autoreverses = true
            pulse.repeatCount = .greatestFiniteMagnitude
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            soundReactionIcon.layer.add(pulse, forKey: "soundPulse")
        } else {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn]) {
                self.soundReactionCorner.alpha = 0
                self.soundReactionCorner.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            } completion: { _ in
                self.soundReactionCorner.isHidden = true
                self.soundReactionCorner.transform = .identity
            }
        }
    }

    func configure(
        displayName: String,
        micOn: Bool,
        speaking: Bool,
        avatarURL: String?,
        videoTrack: VideoTrack?,
        mirrorVideo: Bool
    ) {
        if let s = lastTileVisualState,
           s.displayName == displayName,
           s.micOn == micOn,
           s.speaking == speaking,
           s.mirrorVideo == mirrorVideo,
           s.track === videoTrack,
           s.avatarURL == avatarURL {
            return
        }
        badgeMicOn = micOn
        switch tileKind {
        case .mainVideo:
            badgeLabel.text = displayName
        case .screenShare:
            badgeLabel.text = "\(displayName) Share Screen"
        }
        refreshBadgeSymbols()

        if let track = videoTrack {
            avatarView.isHidden = true
            initialLabel.isHidden = true
            videoView.mirrorMode = mirrorVideo ? .auto : .off
            if videoView.track !== track {
                videoView.track = track
            }
            videoView.isHidden = false
        } else {
            videoView.isHidden = true
            videoView.track = nil
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
                let proxy = ImgproxyURL.create(from: raw, width: 150, height: 150)
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
        lastTileVisualState = (displayName, micOn, speaking, mirrorVideo, videoTrack, avatarURL)
    }
}
