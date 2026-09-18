import AVFoundation
import Foundation
import Network
import WebRTC

private struct SfuAudioHealth: Sendable {
    var sourceLevel = 0.0
    var packetsSent = 0.0
    var inboundStreams = 0
    var packetsReceived = 0.0
    var packetsLost = 0.0
    var samplesReceived = 0.0
    var concealedSamples = 0.0
    var playoutSynthesized = 0.0
    var playoutDuration = 0.0
    var roundTripTime = 0.0
    var dtlsState = ""
}

private struct SfuInboundAudioCounters: Sendable {
    var packetsReceived: Double
    var samplesReceived: Double
}

@MainActor
final class MezonSfuSession: NSObject {

    private static let midAudio = "0"
    private static let midCamera = "1"
    private static let midScreen = "2"
    private static let captureWidth: Int32 = 640
    private static let captureHeight: Int32 = 360
    private static let captureFps = 24
    private static let speakingPollNanos: UInt64 = 300_000_000
    private static let audioDiagnosticsNanos: UInt64 = 5_000_000_000
    private static let reconnectPollNanos: UInt64 = 3_000_000_000
    private static let maxReconnectAttempts = 40
    private static let maxTokenRefreshes = 3
    private static let tokenExpiryMarginSeconds: TimeInterval = 60
    private static let minSessionRestartSpacingSeconds: TimeInterval = 5
    private static let retiringPeerConnectionGraceNanos: UInt64 = 10_000_000_000
    private static let iceRecoveryGraceNanos: UInt64 = 4_000_000_000
    private static let offerReissueNanos: UInt64 = 8_000_000_000
    private static let dtlsConnectDeadlineNanos: UInt64 = 15_000_000_000
    private static let playoutWatchdogNanos: UInt64 = 5_000_000_000
    private static let playoutStallTicksBeforeRestart = 2
    private static let maxPlayoutRestarts = 3
    private static let speakingThreshold = 0.02
    private static let moderatorMuteGraceNanos: UInt64 = 300_000_000
    private static let participantActionErrors: Set<String> = [
        "invalid_token",
        "token_room_mismatch",
        "target_not_found",
        "invalid_participant_action",
        "unsupported_participant_action",
        "auth_not_configured",
    ]

    private static var sslInitialized = false
    private static var _factory: RTCPeerConnectionFactory?
    private static weak var liveSession: MezonSfuSession?

    static var hasLiveSession: Bool {
        liveSession != nil
    }

    private static var factory: RTCPeerConnectionFactory {
        if let f = _factory { return f }
        ensureSSL()
        let f = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        _factory = f
        return f
    }

    private static func ensureSSL() {
        guard !sslInitialized else { return }
        RTCInitializeSSL()
        sslInitialized = true
    }

    private static func removalCause(for closeCode: Int) -> SfuRemovalCause? {
        switch closeCode {
        case 4006: return .kicked
        case 4011: return .aloneTimeout
        default: return nil
        }
    }

    var onConnectionState: ((SfuConnectionState) -> Void)?
    var onParticipants: (([SfuParticipant]) -> Void)?
    var onRoleChanged: ((SfuRole) -> Void)?
    var onError: ((String, String?) -> Void)?
    var onLocalVideoTrack: ((RTCVideoTrack?) -> Void)?
    var onSpeaking: ((Set<String>) -> Void)?
    var onPushToTalkActive: ((Bool) -> Void)?
    var onParticipantActionFailed: ((String) -> Void)?
    var onMutedByModerator: (() -> Void)?
    var onRemoved: ((SfuRemovalCause, String?) -> Void)?
    var tokenProvider: (() async -> String?)?

    private(set) var role: SfuRole = .speaker
    private(set) var isConnected = false
    private(set) var micEnabled = false
    private(set) var cameraEnabled = false
    private(set) var pttActive = false
    private var pttRequested = false
    private(set) var localCameraTrack: RTCVideoTrack?
    private(set) var participants: [SfuParticipant] = []
    private(set) var speakingIds: Set<String> = []
    private(set) var cameraPosition: AVCaptureDevice.Position = .front

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveTask: Task<Void, Never>?
    private var pollTasks: [Task<Void, Never>] = []
    private var peerConnection: RTCPeerConnection?

    private var channelId: Int64 = 0
    private var userId = ""
    private var token = ""

    private var audioSource: RTCAudioSource?
    private var localAudioTrack: RTCAudioTrack?
    private var cameraCapturer: RTCCameraVideoCapturer?
    private var cameraSource: RTCVideoSource?
    private var cameraTrack: RTCVideoTrack?
    private var cameraCapturing = false

    private var joined = false
    private var localTracksAdded = false
    private var admitted = false
    private var selfPeerId: String?
    private var moderatorMuteTask: Task<Void, Never>?

    private var active = false
    private var socketOpen = false
    private var connecting = false
    private var connectionGen = 0
    private var stateRestored = false
    private var reconnectAttempts = 0
    private var tokenRefreshes = 0
    private var tokenRejected = false
    private var lastConnectionOpenedUptime: TimeInterval?
    private var deferredRestartTask: Task<Void, Never>?
    private var retiringCloseTask: Task<Void, Never>?

    private var negotiating = false
    private var pendingOffer: (Int64, String)?
    private var offerReissueTask: Task<Void, Never>?
    private var lastAudioHealth: SfuAudioHealth?
    private var audioProcessingLogger: RTCCallbackLogger?

    private var retiringPeerConnection: RTCPeerConnection?
    private var iceRecoveryTask: Task<Void, Never>?
    private var transportWatchdogTask: Task<Void, Never>?
    private var lastInboundAudioCounters: [String: SfuInboundAudioCounters] = [:]
    private var stalledPlayoutTicks = 0
    private var playoutRestarts = 0
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.mezon.sfu.path")
    private var lastPathSignature: String?
    private var pathWasUnsatisfied = false
    private var pathSatisfied = true

    private var transceiverCache: [RTCRtpTransceiver] = []

    private var userIdByMid: [String: String] = [:]
    private var peerIdByMid: [String: String] = [:]
    private var roleByMid: [String: SfuRole] = [:]
    private var memberByPeerId: [String: MemberState] = [:]
    private var remote: [String: RemoteEntry] = [:]
    private var cameraTierIndex = 0
    private var cameraTierTask: Task<Void, Never>?
    private var remoteOrder: [String] = []

    private final class RemoteEntry {
        let id: String
        var userId: String?
        var peerId: String?
        var role: SfuRole?
        var muted = false
        var audio: RTCAudioTrack?
        var video: RTCVideoTrack?
        var screen: RTCVideoTrack?
        var screenActive = false
        var cameraActive = false

        init(id: String) {
            self.id = id
        }
    }

    private final class MemberState {
        var userId: String?
        var role: SfuRole?
        var muted: Bool?
        var cameraActive: Bool?
        var screenActive: Bool?
    }

    func clearCallbacks() {
        onConnectionState = nil
        onParticipants = nil
        onRoleChanged = nil
        onError = nil
        onLocalVideoTrack = nil
        onSpeaking = nil
        onPushToTalkActive = nil
        onParticipantActionFailed = nil
        onMutedByModerator = nil
        onRemoved = nil
    }

    func join(channelId: Int64, clanId: Int64, userId: String, token: String, role: SfuRole) {
        leave()
        self.channelId = channelId
        self.userId = userId
        self.token = token
        self.role = role
        micEnabled = false
        cameraEnabled = false
        pttActive = false
        pttRequested = false
        joined = false
        localTracksAdded = false
        active = true
        isConnected = false
        reconnectAttempts = 0
        tokenRefreshes = 0
        tokenRejected = false
        Self.liveSession = self
        resetPlayoutWatchdog()

        lastAudioHealth = nil
        if audioProcessingLogger == nil {
            audioProcessingLogger = Self.makeAudioProcessingLogger()
        }
        Self.ensureSSL()
        createLocalAudioTrack()

        guard buildWsUrl(token: token) != nil else {
            emitState(.failed)
            return
        }
        openConnection(initial: true)

        let speakingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.speakingPollNanos)
                guard !Task.isCancelled, let self else { break }
                if let pc = self.peerConnection {
                    self.pollSpeaking(pc)
                }
            }
        }
        let reconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.reconnectPollNanos)
                guard !Task.isCancelled, let self else { break }
                guard self.active, self.joined, !self.socketOpen, !self.connecting else { continue }
                guard self.pathSatisfied else { continue }
                if self.reconnectAttempts >= Self.maxReconnectAttempts {
                    self.active = false
                    self.emitState(.failed)
                    break
                }
                self.reconnectAttempts += 1
                if self.tokenNeedsRefresh(), self.tokenRefreshes < Self.maxTokenRefreshes {
                    if let fresh = await self.tokenProvider?(), !fresh.isEmpty {
                        self.tokenRefreshes += 1
                        self.token = fresh
                        self.tokenRejected = false
                    }
                }
                guard !Task.isCancelled, self.active, self.joined, !self.socketOpen, !self.connecting else { continue }
                self.openConnection(initial: false)
            }
        }
        let audioDiagnosticsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.audioDiagnosticsNanos)
                guard !Task.isCancelled, let self else { break }
                if let pc = self.peerConnection {
                    self.logAudioHealth(pc)
                }
            }
        }
        let playoutWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.playoutWatchdogNanos)
                guard !Task.isCancelled, let self else { break }
                if let pc = self.peerConnection {
                    self.checkPlayout(pc)
                }
            }
        }
        pollTasks = [speakingTask, reconnectTask, audioDiagnosticsTask, playoutWatchdogTask]
        startPathMonitor()
    }

    private func startPathMonitor() {
        pathMonitor?.cancel()
        lastPathSignature = nil
        pathWasUnsatisfied = false
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let signature = path.availableInterfaces.first?.name ?? ""
            guard let self else { return }
            Task { @MainActor in
                self.handlePathUpdate(satisfied: satisfied, signature: signature)
            }
        }
        monitor.start(queue: pathMonitorQueue)
    }

    private func handlePathUpdate(satisfied: Bool, signature: String) {
        pathSatisfied = satisfied
        guard active else { return }
        guard satisfied else {
            pathWasUnsatisfied = true
            return
        }
        let changed = pathWasUnsatisfied || (lastPathSignature != nil && lastPathSignature != signature)
        lastPathSignature = signature
        pathWasUnsatisfied = false
        guard changed, joined else { return }
        restartSession()
    }

    private func restartSession() {
        guard active, joined, !connecting else { return }
        if let openedAt = lastConnectionOpenedUptime {
            let wait = Self.minSessionRestartSpacingSeconds - (ProcessInfo.processInfo.systemUptime - openedAt)
            if wait > 0 {
                deferRestart(after: wait)
                return
            }
        }
        iceRecoveryTask?.cancel()
        iceRecoveryTask = nil
        if tokenNeedsRefresh() {
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            handleSocketClosed(gen: connectionGen)
            return
        }
        openConnection(initial: false)
    }

    private func deferRestart(after seconds: TimeInterval) {
        guard deferredRestartTask == nil else { return }
        let gen = connectionGen
        deferredRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.deferredRestartTask = nil
            guard gen == self.connectionGen else { return }
            self.restartSession()
        }
    }

    private func clearDeferredRestart() {
        deferredRestartTask?.cancel()
        deferredRestartTask = nil
    }

    private func tokenNeedsRefresh() -> Bool {
        if tokenRejected {
            return true
        }
        guard let secondsLeft = Self.tokenSecondsLeft(token) else {
            return true
        }
        return secondsLeft <= Self.tokenExpiryMarginSeconds
    }

    private nonisolated static func tokenSecondsLeft(_ token: String) -> TimeInterval? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            return nil
        }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let exp = (claims["exp"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return exp - Date().timeIntervalSince1970
    }

    private func scheduleRetiringPeerConnectionClose() {
        retiringCloseTask?.cancel()
        guard let retiring = retiringPeerConnection else {
            retiringCloseTask = nil
            return
        }
        let retiringId = ObjectIdentifier(retiring)
        retiringCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.retiringPeerConnectionGraceNanos)
            guard !Task.isCancelled, let self else { return }
            self.retiringCloseTask = nil
            guard let current = self.retiringPeerConnection, ObjectIdentifier(current) == retiringId else { return }
            self.retiringPeerConnection = nil
            current.close()
        }
    }

    private func releaseRetiringPeerConnection() {
        guard !remote.isEmpty, let previous = retiringPeerConnection else { return }
        retiringPeerConnection = nil
        retiringCloseTask?.cancel()
        retiringCloseTask = nil
        previous.close()
    }

    func leave() {
        if Self.liveSession === self {
            Self.liveSession = nil
        }
        let hadConnection = peerConnection != nil || webSocketTask != nil
        active = false
        connectionGen += 1
        socketOpen = false
        connecting = false
        stateRestored = false
        pttRequested = false
        joined = false
        admitted = false
        selfPeerId = nil
        moderatorMuteTask?.cancel()
        moderatorMuteTask = nil
        for task in pollTasks {
            task.cancel()
        }
        pollTasks = []
        receiveTask?.cancel()
        receiveTask = nil
        clearOfferReissueDeadline()
        clearTransportWatchdog()
        clearDeferredRestart()
        retiringCloseTask?.cancel()
        retiringCloseTask = nil
        audioProcessingLogger?.stop()
        audioProcessingLogger = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        stopCameraCapture()
        cameraCapturer = nil
        cameraTrack = nil
        cameraSource = nil
        localCameraTrack = nil
        localAudioTrack = nil
        audioSource = nil
        transceiverCache = []
        iceRecoveryTask?.cancel()
        iceRecoveryTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        peerConnection?.close()
        retiringPeerConnection?.close()
        peerConnection = nil
        retiringPeerConnection = nil
        localTracksAdded = false
        negotiating = false
        pendingOffer = nil
        userIdByMid.removeAll()
        peerIdByMid.removeAll()
        roleByMid.removeAll()
        memberByPeerId.removeAll()
        remote.removeAll()
        remoteOrder.removeAll()
        participants = []
        speakingIds = []
        pttActive = false
        isConnected = false
        if hadConnection {
            deactivateAudioIfIdle()
        }
    }

    func setMicEnabled(_ on: Bool) {
        micEnabled = on
        localAudioTrack?.isEnabled = on
        send(["type": "mute", "is_mute": !on])
    }

    func setCameraEnabled(_ on: Bool) {
        cameraEnabled = on
        scheduleCameraTier()
        if on {
            if peerConnection != nil {
                prepareVideoSender()
            }
            ensureCameraCapturer()
            startCameraCapture()
            cameraTrack?.isEnabled = true
            if let track = cameraTrack {
                localCameraTrack = track
                onLocalVideoTrack?(track)
            }
        } else {
            stopCameraCapture()
            cameraTrack?.isEnabled = false
        }
        send(["type": "camera", "active": on])
    }

    func switchCamera() {
        cameraPosition = cameraPosition == .front ? .back : .front
        guard cameraCapturing, let capturer = cameraCapturer else { return }
        beginCapture(on: capturer)
    }

    func pttPress() {
        guard role == .audience else { return }
        pttRequested = true
        send(["type": "mute", "is_mute": false])
        send(["type": "push_to_talk", "active": true])
    }

    func pttRelease() {
        guard role == .audience else { return }
        pttRequested = false
        send(["type": "push_to_talk", "active": false])
        send(["type": "mute", "is_mute": true])
    }

    func sendParticipantAction(token actionToken: String) -> Bool {
        guard active, socketOpen, admitted, webSocketTask != nil else { return false }
        send(["type": "participant_action", "token": actionToken])
        return true
    }

    private func noteSelfPeerUpdate(_ peer: [String: Any]) {
        guard let selfPeerId, stringValue(peer["peer_id"]) == selfPeerId else { return }
        guard boolValue(peer["is_mute"]) == true, micEnabled || (pttActive && pttRequested) else { return }
        guard moderatorMuteTask == nil else { return }
        let gen = connectionGen
        moderatorMuteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.moderatorMuteGraceNanos)
            guard let self, !Task.isCancelled else { return }
            self.moderatorMuteTask = nil
            guard gen == self.connectionGen, self.micEnabled || (self.pttActive && self.pttRequested) else { return }
            if self.micEnabled {
                self.setMicEnabled(false)
            } else {
                self.pttRelease()
            }
            self.onMutedByModerator?()
        }
    }

    private func openConnection(initial: Bool) {
        connecting = true
        connectionGen += 1
        let gen = connectionGen
        stateRestored = false
        admitted = false
        selfPeerId = nil
        moderatorMuteTask?.cancel()
        moderatorMuteTask = nil
        clearOfferReissueDeadline()
        clearTransportWatchdog()
        clearDeferredRestart()
        lastConnectionOpenedUptime = ProcessInfo.processInfo.systemUptime
        resetPlayoutWatchdog()
        if !initial {
            if pttActive {
                pttActive = false
                localAudioTrack?.isEnabled = false
                onPushToTalkActive?(false)
            }
            socketOpen = false
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            urlSession?.invalidateAndCancel()
            if let previous = peerConnection {
                retiringPeerConnection?.close()
                retiringPeerConnection = previous
                scheduleRetiringPeerConnectionClose()
            }
            peerConnection = nil
            negotiating = false
            pendingOffer = nil
            localTracksAdded = false
            lastAudioHealth = nil
            userIdByMid.removeAll()
            peerIdByMid.removeAll()
            roleByMid.removeAll()
            memberByPeerId.removeAll()
            remote.removeAll()
            remoteOrder.removeAll()
            emitParticipants()
        }
        transceiverCache = []
        guard let pc = createPeerConnection() else {
            connecting = false
            emitState(.failed)
            return
        }
        peerConnection = pc
        emitState(initial ? .connecting : .disconnected)
        guard let url = buildWsUrl(token: token) else {
            connecting = false
            emitState(.failed)
            return
        }
        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task, gen: gen)
        }
        sendJoin(gen: gen)
    }

    private func sendJoin(gen: Int) {
        let payload: [String: Any] = [
            "type": "join",
            "room": String(channelId),
            "token": token,
            "role": role.rawValue,
        ]
        guard let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            handleSocketClosed(gen: gen)
            return
        }
        task.send(.string(text)) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, gen == self.connectionGen else { return }
                if error == nil {
                    self.socketOpen = true
                    self.connecting = false
                    self.emitState(.joining)
                } else {
                    self.handleSocketClosed(gen: gen)
                }
            }
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, gen: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard gen == connectionGen else { return }
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    if let cause = Self.removalCause(for: task.closeCode.rawValue) {
                        handleRemoved(gen: gen, cause: cause, reason: task.closeReason)
                    } else {
                        handleSocketClosed(gen: gen)
                    }
                }
                return
            }
        }
    }

    private func handleSocketClosed(gen: Int) {
        guard gen == connectionGen else { return }
        socketOpen = false
        connecting = false
        if active && joined {
            emitState(.disconnected)
        } else if active {
            emitState(.failed)
        }
    }

    private func handleRemoved(gen: Int, cause: SfuRemovalCause, reason: Data?) {
        guard gen == connectionGen, active else { return }
        active = false
        socketOpen = false
        connecting = false
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        onRemoved?(cause, text.isEmpty ? nil : text)
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return
        }
        switch msg["type"] as? String {
        case "ping":
            send(["type": "pong"])
        case "pong":
            break
        case "joined":
            emitState(.awaitingOffer)
        case "room_snapshot":
            admitted = true
            selfPeerId = stringValue(msg["self_peer_id"])
            if let members = msg["members"] as? [[String: Any]], applyPeers(members) {
                syncRemoteMedia()
            }
            joined = true
            reconnectAttempts = 0
            tokenRefreshes = 0
            tokenRejected = false
            if !stateRestored {
                stateRestored = true
                let resumePushToTalk = role == .audience && pttRequested
                send(["type": "mute", "is_mute": !micEnabled && !resumePushToTalk])
                if resumePushToTalk {
                    send(["type": "push_to_talk", "active": true])
                }
                if role == .speaker {
                    send(["type": "camera", "active": cameraEnabled])
                }
                send(["type": "visibility", "visible": true])
            }
            emitParticipants()
        case "peer_joined", "peer_updated":
            if let peer = msg["peer"] as? [String: Any], applyPeers([peer]) {
                syncRemoteMedia()
            }
            if (msg["type"] as? String) == "peer_updated", let peer = msg["peer"] as? [String: Any] {
                noteSelfPeerUpdate(peer)
            }
            emitParticipants()
        case "peer_left":
            handlePeerLeft(msg)
            emitParticipants()
        case "push_to_talk_changed":
            let isActive = boolValue(msg["active"]) ?? false
            pttActive = isActive
            localAudioTrack?.isEnabled = isActive
            onPushToTalkActive?(isActive)
        case "role_changed":
            handleRoleChanged(SfuRole.fromWire(msg["role"] as? String))
        case "offer":
            clearOfferReissueDeadline()
            if let sdp = msg["sdp"] as? String, !sdp.isEmpty {
                let rawGeneration = msg["offer_generation"]
                let generation = (rawGeneration as? NSNumber)?.int64Value
                    ?? (rawGeneration as? String).flatMap(Int64.init)
                    ?? 0
                onOffer(generation: generation, sdp: sdp)
            }
        case "mute_changed":
            moderatorMuteTask?.cancel()
            moderatorMuteTask = nil
        case "error":
            let detail = (msg["message"] as? String) ?? ""
            if detail == "invalid_token" || detail == "missing_token" {
                tokenRejected = true
            }
            if detail == "invalid_push_to_talk" || detail == "push_to_talk_rejected" {
                pttActive = false
                pttRequested = false
                localAudioTrack?.isEnabled = false
                onPushToTalkActive?(false)
            } else if detail == "stale_offer_generation" || detail == "future_offer_generation" {
                if !negotiating && pendingOffer == nil {
                    armOfferReissueDeadline()
                }
            } else if admitted && Self.participantActionErrors.contains(detail) {
                onParticipantActionFailed?(detail)
            } else if (detail == "invalid_token" || detail == "missing_token") && active && joined && tokenRefreshes >= Self.maxTokenRefreshes {
                active = false
                webSocketTask?.cancel(with: .normalClosure, reason: nil)
                onError?(detail, detail)
                emitState(.failed)
            } else if active && joined {
                webSocketTask?.cancel(with: .normalClosure, reason: nil)
                handleSocketClosed(gen: connectionGen)
            } else {
                onError?(detail, detail)
                emitState(.failed)
            }
        default:
            break
        }
    }

    private func armOfferReissueDeadline() {
        guard offerReissueTask == nil else { return }
        let gen = connectionGen
        offerReissueTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.offerReissueNanos)
            guard let self, !Task.isCancelled else { return }
            self.offerReissueTask = nil
            guard gen == self.connectionGen, self.active, self.joined else { return }
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.handleSocketClosed(gen: gen)
        }
    }

    private func clearOfferReissueDeadline() {
        offerReissueTask?.cancel()
        offerReissueTask = nil
    }

    private func armTransportWatchdog(_ pc: RTCPeerConnection) {
        guard transportWatchdogTask == nil, pc.connectionState != .connected else { return }
        let gen = connectionGen
        transportWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.dtlsConnectDeadlineNanos)
            guard !Task.isCancelled, let self else { return }
            self.transportWatchdogTask = nil
            guard gen == self.connectionGen, let current = self.peerConnection, self.active, self.joined else { return }
            guard current.connectionState != .connected else { return }
            NSLog("%@", "[sfu-audio] dtls never completed after ice connected; restarting the session" as NSString)
            self.restartSession()
        }
    }

    private func clearTransportWatchdog() {
        transportWatchdogTask?.cancel()
        transportWatchdogTask = nil
    }

    private func resetPlayoutWatchdog() {
        lastInboundAudioCounters = [:]
        stalledPlayoutTicks = 0
        playoutRestarts = 0
    }

    private func checkPlayout(_ pc: RTCPeerConnection) {
        guard isConnected, joined else { return }
        let gen = connectionGen
        pc.statistics { [weak self] report in
            let counters = Self.inboundAudioCounters(in: report)
            Task { @MainActor [weak self] in
                self?.evaluatePlayout(counters, gen: gen)
            }
        }
    }

    private nonisolated static func inboundAudioCounters(in report: RTCStatisticsReport) -> [String: SfuInboundAudioCounters] {
        var counters: [String: SfuInboundAudioCounters] = [:]
        for (id, stat) in report.statistics where stat.type == "inbound-rtp" {
            let values = stat.values
            guard (values["kind"] as? String) == "audio" else { continue }
            counters[id] = SfuInboundAudioCounters(
                packetsReceived: (values["packetsReceived"] as? NSNumber)?.doubleValue ?? 0,
                samplesReceived: (values["totalSamplesReceived"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        return counters
    }

    private func evaluatePlayout(_ counters: [String: SfuInboundAudioCounters], gen: Int) {
        guard gen == connectionGen else { return }
        let previous = lastInboundAudioCounters
        lastInboundAudioCounters = counters
        var playoutAdvanced = false
        var packetsWithoutPlayout = false
        for (id, now) in counters {
            guard let before = previous[id] else { continue }
            if now.samplesReceived > before.samplesReceived {
                playoutAdvanced = true
            } else if before.samplesReceived > 0, now.packetsReceived > before.packetsReceived {
                packetsWithoutPlayout = true
            }
        }
        if playoutAdvanced || !packetsWithoutPlayout {
            stalledPlayoutTicks = 0
            if playoutAdvanced {
                playoutRestarts = 0
            }
            return
        }
        stalledPlayoutTicks += 1
        guard stalledPlayoutTicks >= Self.playoutStallTicksBeforeRestart, playoutRestarts < Self.maxPlayoutRestarts else { return }
        guard !CallKitManager.shared.hasTrackedActiveCall,
              WebRTCCallManager.shared.signalingSession == nil,
              StreamingWebRTCSession.shared.activeStreamChannelId == nil else { return }
        stalledPlayoutTicks = 0
        playoutRestarts += 1
        NSLog("%@", "[sfu-audio] remote audio arrives but nothing is played; restarting the audio unit, attempt \(playoutRestarts)" as NSString)
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        rtc.isAudioEnabled = false
        rtc.isAudioEnabled = true
        rtc.unlockForConfiguration()
    }

    private func onOffer(generation: Int64, sdp: String) {
        parseMsids(sdp)
        let gen = connectionGen
        Task { [weak self] in
            await self?.negotiate(firstGeneration: generation, firstSdp: sdp, gen: gen)
        }
    }

    private func negotiate(firstGeneration: Int64, firstSdp: String, gen: Int) async {
        guard gen == connectionGen else { return }
        if negotiating {
            pendingOffer = (firstGeneration, firstSdp)
            return
        }
        negotiating = true
        var offer: (Int64, String)? = (firstGeneration, firstSdp)
        while let current = offer {
            guard gen == connectionGen else { return }
            guard let pc = peerConnection else { break }
            let (generation, sdp) = current
            do {
                let stableSdp = stabilizeInactiveVideoSections(offerSdp: sdp, currentRemoteSdp: pc.remoteDescription?.sdp)
                try await awaitSetRemote(pc, RTCSessionDescription(type: .offer, sdp: stableSdp))
                guard isCurrentConnection(pc, gen: gen) else { return }
                transceiverCache = pc.transceivers
                attachLocalTracks(pc)
                let answer = try await awaitCreateAnswer(pc)
                guard isCurrentConnection(pc, gen: gen) else { return }
                try await awaitSetLocal(pc, RTCSessionDescription(type: .answer, sdp: answer.sdp))
                guard isCurrentConnection(pc, gen: gen) else { return }
                syncRemoteMedia()
                if let local = pc.localDescription {
                    send([
                        "type": "answer",
                        "offer_generation": NSNumber(value: generation),
                        "sdp": patchAnswerForSfu(local.sdp),
                    ])
                }
            } catch {
                guard isCurrentConnection(pc, gen: gen) else { return }
                await rollbackIfStuck(pc)
                guard isCurrentConnection(pc, gen: gen) else { return }
            }
            offer = pendingOffer
            pendingOffer = nil
            if offer != nil {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        negotiating = false
    }

    private func isCurrentConnection(_ pc: RTCPeerConnection, gen: Int) -> Bool {
        gen == connectionGen && pc === peerConnection
    }

    private func attachLocalTracks(_ pc: RTCPeerConnection) {
        if localTracksAdded {
            return
        }
        if let audio = localAudioTrack {
            audio.isEnabled = role == .audience ? pttActive : micEnabled
            if let tc = findTransceiver(mid: Self.midAudio, kind: "audio") {
                tc.sender.track = audio
                setTransceiverDirection(tc, .sendOnly)
            } else {
                pc.add(audio, streamIds: ["sfu"])
            }
        }
        if role == .speaker {
            prepareVideoSender()
        }
        localTracksAdded = true
    }

    private func handleRoleChanged(_ newRole: SfuRole) {
        role = newRole
        let audio = localAudioTrack
        let tc = peerConnection != nil ? findTransceiver(mid: Self.midAudio, kind: "audio") : nil
        if newRole == .speaker {
            audio?.isEnabled = true
            if let tc, let audio {
                tc.sender.track = audio
                setTransceiverDirection(tc, .sendOnly)
            }
            pttActive = true
            onPushToTalkActive?(true)
        } else {
            audio?.isEnabled = false
            if let tc {
                tc.sender.track = nil
                setTransceiverDirection(tc, .inactive)
            }
            pttActive = false
            onPushToTalkActive?(false)
        }
        onRoleChanged?(newRole)
    }

    private func setTransceiverDirection(_ tc: RTCRtpTransceiver, _ direction: RTCRtpTransceiverDirection) {
        tc.setDirection(direction, error: nil)
    }

    private func findTransceiver(mid: String, kind: String) -> RTCRtpTransceiver? {
        let tcs = transceiverCache
        if let exact = tcs.first(where: { $0.mid == mid }) {
            return exact
        }
        return tcs.first(where: { tc in
            guard tc.mid.isEmpty else { return false }
            guard let track = tc.receiver.track else { return false }
            return track.kind == kind
        })
    }

    private func ensureCameraTrack() {
        guard cameraTrack == nil else { return }
        let source = Self.factory.videoSource()
        let track = Self.factory.videoTrack(with: source, trackId: "sfu_camera")
        track.isEnabled = cameraEnabled
        cameraSource = source
        cameraTrack = track
        localCameraTrack = track
    }

    private func prepareVideoSender() {
        ensureCameraTrack()
        guard let tc = findTransceiver(mid: Self.midCamera, kind: "video") else { return }
        if tc.sender.track !== cameraTrack {
            tc.sender.track = cameraTrack
            tc.sender.applyCameraTier(cameraTierIndex)
            setTransceiverDirection(tc, .sendOnly)
        }
    }

    private func ensureCameraCapturer() {
        guard cameraCapturer == nil else { return }
        ensureCameraTrack()
        guard let source = cameraSource else { return }
        cameraCapturer = RTCCameraVideoCapturer(delegate: source)
    }

    private func captureDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = RTCCameraVideoCapturer.captureDevices()
        return devices.first(where: { $0.position == position }) ?? devices.first
    }

    private func selectFormat(device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        var best: AVCaptureDevice.Format?
        var bestDiff = Int32.max
        for format in formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let diff = abs(dims.width - Self.captureWidth) + abs(dims.height - Self.captureHeight)
            if diff < bestDiff {
                bestDiff = diff
                best = format
            }
        }
        return best
    }

    private func beginCapture(on capturer: RTCCameraVideoCapturer) {
        guard let device = captureDevice(position: cameraPosition),
              let format = selectFormat(device: device) else { return }
        let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? Double(Self.captureFps)
        let fps = min(Self.captureFps, Int(maxRate))
        capturer.startCapture(with: device, format: format, fps: fps)
    }

    private func startCameraCapture() {
        guard !cameraCapturing, let capturer = cameraCapturer else { return }
        beginCapture(on: capturer)
        cameraCapturing = true
    }

    private func stopCameraCapture() {
        guard cameraCapturing else { return }
        cameraCapturer?.stopCapture()
        cameraCapturing = false
    }

    private func createLocalAudioTrack() {
        guard localAudioTrack == nil else { return }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "googNoiseSuppression": "true",
                "googEchoCancellation": "true",
                "googAutoGainControl": "true"
            ],
            optionalConstraints: nil
        )
        let source = Self.factory.audioSource(with: constraints)
        audioSource = source
        let track = Self.factory.audioTrack(with: source, trackId: "sfu_audio")
        track.isEnabled = false
        localAudioTrack = track
    }

    private func createPeerConnection() -> RTCPeerConnection? {
        var iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"], username: nil, credential: nil)]
        let iceURL = MezonConfig.webRTCIceServerURL
        if !iceURL.isEmpty {
            iceServers.append(
                RTCIceServer(
                    urlStrings: [iceURL],
                    username: MezonConfig.webRTCIceUsername,
                    credential: MezonConfig.webRTCIceCredential
                )
            )
        }
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return Self.factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    private func buildWsUrl(token: String) -> URL? {
        let base = MezonConfig.sfuWebSocketURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        guard var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "access_token", value: token))
        components.queryItems = items
        return components.url
    }

    private nonisolated static func makeAudioProcessingLogger() -> RTCCallbackLogger {
        let logger = RTCCallbackLogger()
        logger.severity = .info
        logger.start { @Sendable message in
            guard Self.isAudioProcessingLogLine(message) else { return }
            let line = message.trimmingCharacters(in: .whitespacesAndNewlines)
            NSLog("%@", "[sfu-audio] webrtc \(line)" as NSString)
        }
        return logger
    }

    private nonisolated static func isAudioProcessingLogLine(_ message: String) -> Bool {
        let markers = [
            "WebRtcVoiceEngine::ApplyOptions",
            "AudioProcessing::ApplyConfig",
            "Voice Processing I/O",
            "voice processing",
            "bypass_voice_processing",
            "Always disable",
            "built-in NS",
            "audio unit",
            "interruption",
            "Interruption",
            "CanPlayOrRecord",
            "setActive",
            "activations",
            "Media services",
            "sample rate change",
            "VPAU state",
            "Audio route changed",
        ]
        return markers.contains { message.contains($0) }
    }

    private func logAudioHealth(_ pc: RTCPeerConnection) {
        pc.statistics { [weak self] report in
            let health = Self.audioHealth(in: report)
            Task { @MainActor [weak self] in
                self?.emitAudioHealth(health)
            }
        }
    }

    private nonisolated static func audioHealth(in report: RTCStatisticsReport) -> SfuAudioHealth {
        var health = SfuAudioHealth()
        for stat in report.statistics.values {
            let values = stat.values
            let kind = values["kind"] as? String
            func number(_ key: String) -> Double {
                (values[key] as? NSNumber)?.doubleValue ?? 0
            }
            switch stat.type {
            case "media-source" where kind == "audio":
                health.sourceLevel = number("audioLevel")
            case "outbound-rtp" where kind == "audio":
                health.packetsSent += number("packetsSent")
            case "inbound-rtp" where kind == "audio":
                health.inboundStreams += 1
                health.packetsReceived += number("packetsReceived")
                health.packetsLost += number("packetsLost")
                health.samplesReceived += number("totalSamplesReceived")
                health.concealedSamples += number("concealedSamples")
            case "media-playout":
                health.playoutSynthesized += number("synthesizedSamplesDuration")
                health.playoutDuration += number("totalSamplesDuration")
            case "transport":
                health.dtlsState = (values["dtlsState"] as? String) ?? ""
            case "candidate-pair" where (values["nominated"] as? NSNumber)?.boolValue == true:
                health.roundTripTime = number("currentRoundTripTime")
            default:
                break
            }
        }
        return health
    }

    private func emitAudioHealth(_ health: SfuAudioHealth) {
        let previous = lastAudioHealth ?? health
        lastAudioHealth = health
        let received = health.samplesReceived - previous.samplesReceived
        let concealed = health.concealedSamples - previous.concealedSamples
        let concealedPercent = received > 0 ? concealed / received * 100 : 0
        let session = AVAudioSession.sharedInstance()
        let rtc = RTCAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        let fields: [String] = [
            "mic=\(micEnabled)",
            "ptt=\(pttActive)",
            "audioEnabled=\(rtc.isAudioEnabled)",
            "active=\(rtc.isActive)",
            "mode=\(session.mode.rawValue)",
            "in=\(inputs)",
            "out=\(outputs)",
            "rate=\(Int(session.sampleRate))",
            "io=\(String(format: "%.4f", session.ioBufferDuration))",
            "srcLevel=\(String(format: "%.3f", health.sourceLevel))",
            "sent=+\(Int(health.packetsSent - previous.packetsSent))",
            "inStreams=\(health.inboundStreams)",
            "recv=+\(Int(health.packetsReceived - previous.packetsReceived))",
            "lost=+\(Int(health.packetsLost - previous.packetsLost))",
            "concealed=\(String(format: "%.1f", concealedPercent))%",
            "synth=+\(String(format: "%.3f", health.playoutSynthesized - previous.playoutSynthesized))s",
            "played=+\(String(format: "%.1f", health.playoutDuration - previous.playoutDuration))s",
            "rtt=\(Int(health.roundTripTime * 1000))ms",
            "dtls=\(health.dtlsState.isEmpty ? "none" : health.dtlsState)",
        ]
        NSLog("%@", ("[sfu-audio] " + fields.joined(separator: " ")) as NSString)
    }

    private func pollSpeaking(_ pc: RTCPeerConnection) {
        guard onSpeaking != nil else { return }
        let localId = userId
        let localAudible = micEnabled || pttActive
        let userIdByMid = self.userIdByMid
        let threshold = Self.speakingThreshold
        pc.statistics { [weak self] report in
            let speaking = Self.speakingUserIds(
                in: report,
                localId: localId,
                localAudible: localAudible,
                userIdByMid: userIdByMid,
                threshold: threshold
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                if speaking != self.speakingIds {
                    self.speakingIds = speaking
                    self.onSpeaking?(speaking)
                }
            }
        }
    }

    private nonisolated static func speakingUserIds(
        in report: RTCStatisticsReport,
        localId: String,
        localAudible: Bool,
        userIdByMid: [String: String],
        threshold: Double
    ) -> Set<String> {
        var speaking = Set<String>()
        for stat in report.statistics.values {
            let type = stat.type
            guard type == "media-source" || type == "inbound-rtp" else { continue }
            let values = stat.values
            guard let kind = values["kind"] as? String, kind == "audio" else { continue }
            guard let level = (values["audioLevel"] as? NSNumber)?.doubleValue, level > threshold else { continue }
            if type == "media-source" {
                if localAudible {
                    speaking.insert(localId)
                }
            } else if let mid = values["mid"] as? String, let uid = userIdByMid[mid] {
                speaking.insert(uid)
            }
        }
        return speaking
    }

    private func applyPeers(_ members: [[String: Any]]) -> Bool {
        var revivedMids = false
        for peer in members {
            guard let peerId = stringValue(peer["peer_id"]), !peerId.isEmpty else { continue }
            let state = memberState(peerId: peerId)
            if let userIdValue = stringValue(peer["user_id"]), !userIdValue.isEmpty {
                state.userId = userIdValue
            }
            if peer["role"] != nil {
                state.role = SfuRole.fromWire(stringValue(peer["role"]))
            }
            if let muted = boolValue(peer["is_mute"]) {
                state.muted = muted
            }
            if let cameraActive = boolValue(peer["camera_active"]) {
                state.cameraActive = cameraActive
            }
            if let screenActive = boolValue(peer["screen_active"]) {
                state.screenActive = screenActive
            }
            var mids: [String] = []
            for key in ["mid_audio", "mid_video", "mid_screen"] {
                if let mid = stringValue(peer[key]), !mid.isEmpty, mid != "0" {
                    mids.append(mid)
                }
            }
            for mid in mids {
                if claimMid(mid, peerId: peerId) {
                    revivedMids = true
                }
            }
            let existing = remoteOrder.first(where: { remote[$0]?.peerId == peerId })
            guard let participantId = existing ?? mids.first.map({ remoteParticipantId($0) }) else { continue }
            applyMemberState(to: remoteEntry(id: participantId), peerId: peerId)
        }
        scheduleCameraTier()
        return revivedMids
    }

    private func activeCameraCount() -> Int {
        remote.values.filter { $0.cameraActive }.count + (cameraEnabled ? 1 : 0)
    }

    private func scheduleCameraTier() {
        let next = resolveCameraTier(activeCameraCount(), current: cameraTierIndex)
        guard next != cameraTierIndex else { return }
        let delayNanos: UInt64 = next > cameraTierIndex ? 1_500_000_000 : 6_000_000_000
        cameraTierTask?.cancel()
        cameraTierTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            self.cameraTierIndex = next
            self.findTransceiver(mid: Self.midCamera, kind: "video")?.sender.applyCameraTier(next)
        }
    }

    private func memberState(peerId: String) -> MemberState {
        if let state = memberByPeerId[peerId] {
            return state
        }
        let state = MemberState()
        memberByPeerId[peerId] = state
        return state
    }

    @discardableResult
    private func claimMid(_ mid: String, peerId: String) -> Bool {
        let changed = peerIdByMid.updateValue(peerId, forKey: mid) != peerId
        if let state = memberByPeerId[peerId] {
            if let userId = state.userId {
                userIdByMid[mid] = userId
            }
            if let role = state.role {
                roleByMid[mid] = role
            }
        }
        return changed
    }

    private func applyMemberState(to entry: RemoteEntry, peerId: String) {
        entry.peerId = peerId
        guard let state = memberByPeerId[peerId] else { return }
        if let userId = state.userId {
            entry.userId = userId
        }
        if let role = state.role {
            entry.role = role
        }
        if let muted = state.muted {
            entry.muted = muted
        }
        if let cameraActive = state.cameraActive {
            entry.cameraActive = cameraActive
        }
        if let screenActive = state.screenActive {
            entry.screenActive = screenActive
        }
    }

    private func remoteEntry(id: String) -> RemoteEntry {
        if let entry = remote[id] {
            return entry
        }
        let entry = RemoteEntry(id: id)
        remote[id] = entry
        remoteOrder.append(id)
        return entry
    }

    private func removeRemoteEntry(id: String) {
        remote.removeValue(forKey: id)
        remoteOrder.removeAll(where: { $0 == id })
    }

    private func handlePeerLeft(_ msg: [String: Any]) {
        let peerId = stringValue(msg["peer_id"])
        if let peerId {
            memberByPeerId.removeValue(forKey: peerId)
        }
        for key in ["mid_audio", "mid_video", "mid_screen"] {
            guard let mid = stringValue(msg[key]), !mid.isEmpty, mid != "0" else { continue }
            if let owner = peerIdByMid[mid], let peerId, owner != peerId {
                continue
            }
            peerIdByMid.removeValue(forKey: mid)
            userIdByMid.removeValue(forKey: mid)
            roleByMid.removeValue(forKey: mid)
            removeRemoteEntry(id: remoteParticipantId(mid))
        }
    }

    private func syncRemoteMedia() {
        for tc in transceiverCache {
            let mid = tc.mid
            if mid.isEmpty { continue }
            if mid == Self.midAudio || mid == Self.midCamera || mid == Self.midScreen { continue }
            var current = RTCRtpTransceiverDirection.inactive
            let hasCurrent = tc.currentDirection(&current)
            let direction = hasCurrent ? current : tc.direction
            let id = remoteParticipantId(mid)
            let kind = remoteKind(mid)
            if direction == .inactive || direction == .stopped {
                clearRemoteKind(id: id, kind: kind)
                continue
            }
            guard let track = tc.receiver.track else { continue }
            let ownerUserId = userIdByMid[mid]
            let ownerPeerId = peerIdByMid[mid]
            if ownerUserId == nil && ownerPeerId == nil {
                clearRemoteKind(id: id, kind: kind)
                continue
            }
            let entry = remoteEntry(id: id)
            if let uid = ownerUserId {
                entry.userId = uid
            }
            if let pid = ownerPeerId {
                applyMemberState(to: entry, peerId: pid)
            }
            if let peerRole = roleByMid[mid] {
                entry.role = peerRole
            }
            if let audio = track as? RTCAudioTrack {
                if entry.audio?.trackId != audio.trackId {
                    entry.audio = audio
                }
            } else if kind == "camera", let video = track as? RTCVideoTrack {
                if entry.video?.trackId != video.trackId {
                    entry.video = video
                }
            } else if kind == "screen", let video = track as? RTCVideoTrack {
                if entry.screen?.trackId != video.trackId {
                    entry.screen = video
                }
            }
            if entry.audio == nil && entry.video == nil && entry.screen == nil {
                removeRemoteEntry(id: id)
            }
        }
        releaseRetiringPeerConnection()
        emitParticipants()
    }

    private func clearRemoteKind(id: String, kind: String?) {
        guard let entry = remote[id] else { return }
        switch kind {
        case "audio":
            entry.audio = nil
        case "camera":
            entry.video = nil
        case "screen":
            entry.screen = nil
        default:
            break
        }
        if entry.audio == nil && entry.video == nil && entry.screen == nil {
            removeRemoteEntry(id: id)
        }
    }

    private func emitParticipants() {
        let list = remoteOrder.compactMap { remote[$0] }.map { entry in
            SfuParticipant(
                id: entry.id,
                userId: entry.userId,
                peerId: entry.peerId,
                role: entry.role,
                muted: entry.muted,
                audio: entry.audio,
                video: entry.video,
                screen: entry.screen,
                screenActive: entry.screenActive,
                cameraActive: entry.cameraActive
            )
        }
        participants = list
        onParticipants?(list)
    }

    private func remoteParticipantId(_ mid: String) -> String {
        if let n = Int(mid), n >= 3 {
            return "peer-\((n - 3) / 3)"
        }
        return "mid-\(mid)"
    }

    private func remoteKind(_ mid: String) -> String? {
        guard let n = Int(mid), n >= 3 else { return nil }
        switch (n - 3) % 3 {
        case 0:
            return "audio"
        case 1:
            return "camera"
        default:
            return "screen"
        }
    }

    private static let msidUserRegex = try? NSRegularExpression(pattern: "(?:^|-)u(\\d+)(?:-|$)")
    private static let msidPeerRegex = try? NSRegularExpression(pattern: "(?:^|-)p(\\d+)(?:-|$)")

    private func parseMsids(_ sdp: String) {
        guard let userRegex = Self.msidUserRegex, let peerRegex = Self.msidPeerRegex else { return }
        var currentMid: String?
        for rawLine in sdpLines(sdp) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("m=") {
                currentMid = nil
            } else if line.hasPrefix("a=mid:") {
                currentMid = String(line.dropFirst("a=mid:".count)).trimmingCharacters(in: .whitespaces)
            } else if let mid = currentMid, line.hasPrefix("a=msid:") {
                let payload = String(line.dropFirst("a=msid:".count)).trimmingCharacters(in: .whitespaces)
                let tokens = payload.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard let uid = tokens.compactMap({ Self.firstCapture(userRegex, in: $0) }).first else { continue }
                userIdByMid[mid] = uid
                if let pid = tokens.compactMap({ Self.firstCapture(peerRegex, in: $0) }).first, pid != "0" {
                    claimMid(mid, peerId: pid)
                }
            }
        }
    }

    private static func firstCapture(_ regex: NSRegularExpression, in token: String) -> String? {
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = regex.firstMatch(in: token, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: token) else {
            return nil
        }
        return String(token[groupRange])
    }

    private func sdpLines(_ sdp: String) -> [String] {
        sdp.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    private func patchAnswerForSfu(_ sdp: String) -> String {
        guard role == .audience else { return sdp }
        var lines = sdpLines(sdp).filter { !$0.isEmpty }
        var currentIsVideo = false
        var sectionHasMid1 = false
        var inactiveIdx = -1
        var changed = false
        func applySection() {
            if sectionHasMid1, inactiveIdx >= 0 {
                lines[inactiveIdx] = "a=sendonly"
                changed = true
            }
            sectionHasMid1 = false
            inactiveIdx = -1
        }
        for i in lines.indices {
            let line = lines[i]
            if line.hasPrefix("m=") {
                applySection()
                currentIsVideo = line.hasPrefix("m=video")
            } else if currentIsVideo {
                if line == "a=mid:1" {
                    sectionHasMid1 = true
                } else if line == "a=inactive" {
                    inactiveIdx = i
                }
            }
        }
        applySection()
        guard changed else { return sdp }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func stabilizeInactiveVideoSections(offerSdp: String, currentRemoteSdp: String?) -> String {
        guard let currentRemoteSdp, !currentRemoteSdp.isEmpty else { return offerSdp }

        func splitSections(_ sdp: String) -> ([String], [[String]]) {
            var sessionLines: [String] = []
            var mediaSections: [[String]] = []
            for line in sdpLines(sdp) {
                if line.isEmpty { continue }
                if line.hasPrefix("m=") {
                    mediaSections.append([line])
                } else if !mediaSections.isEmpty {
                    mediaSections[mediaSections.count - 1].append(line)
                } else {
                    sessionLines.append(line)
                }
            }
            return (sessionLines, mediaSections)
        }
        func midOf(_ section: [String]) -> String? {
            section.first(where: { $0.hasPrefix("a=mid:") }).map { String($0.dropFirst("a=mid:".count)) }
        }
        func isCodecLine(_ line: String) -> Bool {
            line.hasPrefix("a=rtpmap:") || line.hasPrefix("a=fmtp:") || line.hasPrefix("a=rtcp-fb:")
        }

        var previousByMid: [String: [String]] = [:]
        for section in splitSections(currentRemoteSdp).1 {
            if let mid = midOf(section) {
                previousByMid[mid] = section
            }
        }

        let (nextSession, nextSections) = splitSections(offerSdp)
        var changed = false
        let stabilized: [[String]] = nextSections.map { section in
            guard section[0].hasPrefix("m=video "), section.contains("a=inactive") else { return section }
            guard let mid = midOf(section) else { return section }
            guard (Int(mid) ?? 0) >= 3 else { return section }
            guard let prev = previousByMid[mid], !prev.isEmpty, prev[0].hasPrefix("m=video ") else { return section }
            let prevCodecLines = prev.filter { isCodecLine($0) }
            guard !prevCodecLines.isEmpty else { return section }
            var out = section.filter { !isCodecLine($0) }
            out[0] = prev[0]
            if let insertIdx = out.firstIndex(of: "a=rtcp-mux") {
                out.insert(contentsOf: prevCodecLines, at: insertIdx + 1)
            } else {
                out.append(contentsOf: prevCodecLines)
            }
            changed = true
            return out
        }
        guard changed else { return offerSdp }
        var result = nextSession
        for section in stabilized {
            result.append(contentsOf: section)
        }
        return result.joined(separator: "\r\n") + "\r\n"
    }

    private func send(_ object: [String: Any]) {
        guard let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        task.send(.string(text)) { _ in }
    }

    private func emitState(_ state: SfuConnectionState) {
        onConnectionState?(state)
    }

    private func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private func boolValue(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return nil
    }

    private func awaitSetRemote(_ pc: RTCPeerConnection, _ desc: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(desc) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func awaitSetLocal(_ pc: RTCPeerConnection, _ desc: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(desc) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    private func awaitCreateAnswer(_ pc: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RTCSessionDescription, Error>) in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.answer(for: constraints) { sdp, error in
                if let sdp {
                    cont.resume(returning: sdp)
                } else {
                    cont.resume(throwing: error ?? NSError(
                        domain: "MezonSfuSession",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "createAnswer returned nil"]
                    ))
                }
            }
        }
    }

    private func rollbackIfStuck(_ pc: RTCPeerConnection) async {
        guard pc.signalingState == .haveRemoteOffer else { return }
        try? await awaitSetLocal(pc, RTCSessionDescription(type: .rollback, sdp: ""))
    }

    private func deactivateAudioIfIdle() {
        if CallKitManager.shared.hasTrackedActiveCall { return }
        if StreamingWebRTCSession.shared.activeStreamChannelId != nil { return }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        rtc.isAudioEnabled = false
        try? rtc.setActive(false)
        rtc.unlockForConfiguration()
    }
}

extension MezonSfuSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            switch newState {
            case .connected, .completed:
                self.iceRecoveryTask?.cancel()
                self.iceRecoveryTask = nil
                self.isConnected = true
                let rtc = RTCAudioSession.sharedInstance()
                rtc.lockForConfiguration()
                rtc.isAudioEnabled = true
                rtc.unlockForConfiguration()
                self.emitState(.connected)
                self.armTransportWatchdog(peerConnection)
            case .failed:
                self.iceRecoveryTask?.cancel()
                self.iceRecoveryTask = nil
                if self.active && self.joined {
                    self.emitState(.disconnected)
                    self.restartSession()
                } else if self.active {
                    self.emitState(.failed)
                }
            case .disconnected:
                self.emitState(.disconnected)
                if self.active, self.joined, self.iceRecoveryTask == nil {
                    self.iceRecoveryTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: Self.iceRecoveryGraceNanos)
                        guard !Task.isCancelled, let self else { return }
                        self.iceRecoveryTask = nil
                        self.restartSession()
                    }
                }
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            switch newState {
            case .connected:
                self.clearTransportWatchdog()
            case .failed:
                self.clearTransportWatchdog()
                if self.active && self.joined {
                    self.emitState(.disconnected)
                    self.restartSession()
                }
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            self.syncRemoteMedia()
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            self.syncRemoteMedia()
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didAdd _: RTCMediaStream) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didGenerate _: RTCIceCandidate) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didOpen _: RTCDataChannel) {}
}

enum VoiceChannelMicPermission {
    static func requestIfNeeded() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}

enum VoiceChannelCameraPermission {
    static func requestIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
            }
        default:
            return false
        }
    }
}

private struct CameraTier {
    let maxCameras: Int
    let scaleDown: Double
    let maxBitrateBps: Int
    let maxFps: Int
    let uncapped: Bool
}

private let cameraTiers: [CameraTier] = [
    CameraTier(maxCameras: 2, scaleDown: 1.0, maxBitrateBps: 1_000_000, maxFps: 30, uncapped: true),
    CameraTier(maxCameras: 4, scaleDown: 1.333, maxBitrateBps: 500_000, maxFps: 24, uncapped: false),
    CameraTier(maxCameras: 8, scaleDown: 2.0, maxBitrateBps: 300_000, maxFps: 20, uncapped: false),
    CameraTier(maxCameras: Int.max, scaleDown: 2.0, maxBitrateBps: 200_000, maxFps: 15, uncapped: false)
]

private func cameraTierIndexFor(_ cameras: Int, margin: Int = 0) -> Int {
    cameraTiers.firstIndex(where: { cameras <= $0.maxCameras - margin }) ?? cameraTiers.count - 1
}

func resolveCameraTier(_ cameras: Int, current: Int) -> Int {
    let target = cameraTierIndexFor(cameras)
    return target >= current ? target : min(current, cameraTierIndexFor(cameras, margin: 1))
}

extension RTCRtpSender {
    func preferMaintainFramerate() {
        let parameters = self.parameters
        parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainFramerate.rawValue)
        self.parameters = parameters
    }

    func applyCameraTier(_ index: Int) {
        let tier = cameraTiers.indices.contains(index) ? cameraTiers[index] : cameraTiers[0]
        let parameters = self.parameters
        parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainFramerate.rawValue)
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = tier.uncapped ? nil : NSNumber(value: tier.maxBitrateBps)
            encoding.maxFramerate = tier.uncapped ? nil : NSNumber(value: tier.maxFps)
            encoding.scaleResolutionDownBy = tier.uncapped ? nil : NSNumber(value: tier.scaleDown)
        }
        self.parameters = parameters
    }
}
