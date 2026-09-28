import AVFoundation
import CallKit
import Foundation
import Network
import UIKit
import WebRTC

private struct SfuInboundAudioCounters: Sendable {
    var packetsReceived: Double
    var samplesReceived: Double
}

private struct SfuAudioFlow: Sendable {
    var inbound: [String: SfuInboundAudioCounters]
    var outboundPacketsSent: Double
}

private struct SfuScreenKeyframeRequest {
    let trackId: String
    let trackIdentity: ObjectIdentifier
    let activeSince: TimeInterval
    let firstSeenAt: TimeInterval
    var attempts: Int
    var lastSentAt: TimeInterval
    var satisfied: Bool
}

private struct SfuVideoRecoveryCheck {
    let track: RTCVideoTrack
    let kind: String
    let publisherId: UInt32
    let startedAt: TimeInterval
    let checkAt: TimeInterval
}

private struct SfuVideoExposure {
    let track: RTCVideoTrack
    let focused: Bool
}

private struct SfuQueuedKeyframe {
    let track: RTCVideoTrack
    let kind: String
    let publisherId: UInt32
    var readyAt: TimeInterval
    var frameSince: TimeInterval
}

private struct SfuPeerConnectionBox: @unchecked Sendable {
    let peerConnection: RTCPeerConnection
}

private struct SfuTransceiverBatch: @unchecked Sendable {
    let transceivers: [RTCRtpTransceiver]
}

private struct SfuUncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

private let sfuWebRTCQueue = DispatchQueue(label: "com.mezon.sfu.webrtc", qos: .userInitiated)

private struct SfuRemoteTransceiverSnapshot: @unchecked Sendable {
    let mid: String
    let direction: RTCRtpTransceiverDirection
    let track: RTCMediaStreamTrack?
    let trackId: String?
}

private struct SfuMsidOwner: Sendable {
    let mid: String
    let userId: String
    let peerId: String?
}

private struct SfuPreparedOffer: Sendable {
    let sdp: String
    let msidOwners: [SfuMsidOwner]
}

private enum SfuSdp {
    private static let msidUserRegex = try? NSRegularExpression(pattern: "(?:^|-)u(\\d+)(?:-|$)")
    private static let msidPeerRegex = try? NSRegularExpression(pattern: "(?:^|-)p(\\d+)(?:-|$)")

    static func prepareOffer(_ offerSdp: String, currentRemoteSdp: String?) -> SfuPreparedOffer {
        SfuPreparedOffer(
            sdp: stabilizingInactiveVideoSections(offerSdp: offerSdp, currentRemoteSdp: currentRemoteSdp),
            msidOwners: msidOwners(in: offerSdp)
        )
    }

    static func msidOwners(in sdp: String) -> [SfuMsidOwner] {
        guard let userRegex = msidUserRegex, let peerRegex = msidPeerRegex else { return [] }
        var owners: [SfuMsidOwner] = []
        var currentMid: String?
        for rawLine in splitLines(sdp) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("m=") {
                currentMid = nil
            } else if line.hasPrefix("a=mid:") {
                currentMid = String(line.dropFirst("a=mid:".count)).trimmingCharacters(in: .whitespaces)
            } else if let mid = currentMid, line.hasPrefix("a=msid:") {
                let payload = String(line.dropFirst("a=msid:".count)).trimmingCharacters(in: .whitespaces)
                let tokens = payload.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard let uid = tokens.compactMap({ firstCapture(userRegex, in: $0) }).first else { continue }
                let pid = tokens.compactMap({ firstCapture(peerRegex, in: $0) }).first
                owners.append(SfuMsidOwner(mid: mid, userId: uid, peerId: pid == "0" ? nil : pid))
            }
        }
        return owners
    }

    static func patchingAudienceAnswer(_ sdp: String) -> String {
        var lines = splitLines(sdp).filter { !$0.isEmpty }
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

    static func stabilizingInactiveVideoSections(offerSdp: String, currentRemoteSdp: String?) -> String {
        guard let currentRemoteSdp, !currentRemoteSdp.isEmpty else { return offerSdp }

        func splitSections(_ sdp: String) -> ([String], [[String]]) {
            var sessionLines: [String] = []
            var mediaSections: [[String]] = []
            for line in splitLines(sdp) {
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

    private static func firstCapture(_ regex: NSRegularExpression, in token: String) -> String? {
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = regex.firstMatch(in: token, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: token) else {
            return nil
        }
        return String(token[groupRange])
    }

    private static func splitLines(_ sdp: String) -> [String] {
        sdp.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }
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
    private static let largeRoomSpeakingPollNanos: UInt64 = 1_000_000_000
    private static let largeRoomRemoteCount = 16
    private static let reconnectPollNanos: UInt64 = 3_000_000_000
    private static let maxReconnectAttempts = 4
    private static let maxInitialConnectAttempts = 3
    private static let healthySessionNanos: UInt64 = 30_000_000_000
    private static let joinConnectDeadlineNanos: UInt64 = 12_000_000_000
    private static let maxTokenRefreshes = 3
    private static let tokenExpiryMarginSeconds: TimeInterval = 60
    private static let minSessionRestartSpacingSeconds: TimeInterval = 5
    private static let retiringPeerConnectionGraceNanos: UInt64 = 10_000_000_000
    private static let iceRecoveryGraceNanos: UInt64 = 4_000_000_000
    private static let offerReissueNanos: UInt64 = 8_000_000_000
    private static let dtlsConnectDeadlineNanos: UInt64 = 15_000_000_000
    private static let dtlsFailureCloseCode = 4013 // SFU_DISCONNECT_DTLS_FAILED
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
    private static let keyframeRequestErrors: Set<String> = ["must_join_room_first", "session_not_found"]
    private static let keyframeRequestErrorWindow: TimeInterval = 5
    private static let screenKeyframeFirstRequestGrace: TimeInterval = 0.35
    private static let keyframeGlobalSpacing: TimeInterval = 0.25
    private static let screenKeyframeRetryDelays: [TimeInterval] = [3, 6, 12, 24]
    private static let keyframeMinimumInterval: TimeInterval = 1.5
    private static let foregroundVideoGrace: TimeInterval = 1.5
    private static let shortVideoBackground: TimeInterval = 5

    private static var sslInitialized = false
    // Keep native audio-device state within one call. Leaving and joining again
    // must not reuse a device that was stuck in an earlier call.
    private var _factory: RTCPeerConnectionFactory?
    private static weak var liveSession: MezonSfuSession?

    static var hasLiveSession: Bool {
        liveSession != nil
    }

    static func restoreLiveAudioSession(restartAudio: Bool) {
        liveSession?.restoreAudioSession(restartAudio: restartAudio)
    }

    private var factory: RTCPeerConnectionFactory {
        if let f = _factory { return f }
        Self.ensureSSL()
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
        case 1000: return .disconnected
        case 4006: return .kicked
        case 4011: return .aloneTimeout
        case 4012: return .duplicateSession
        default: return nil
        }
    }

    private static func closeReasonText(_ reason: Data?) -> String? {
        let text = reason.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
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

    // A session belongs to one call, including token refreshes and PiP transfers.
    let channelId: Int64
    let clanId: Int64
    private let userId: String
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
    private var transportRecoveryTask: Task<Void, Never>?
    private var healthySessionResetTask: Task<Void, Never>?
    private var tokenRefreshes = 0
    private var tokenRejected = false
    private var lastConnectionOpenedUptime: TimeInterval?
    private var deferredRestartTask: Task<Void, Never>?
    private var joinWatchdogTask: Task<Void, Never>?
    private var postConnectAudioRecoveryTask: Task<Void, Never>?
    private var lastPostConnectAudioRecoveryGeneration = -1
    private var screenTraceStates: [String: String] = [:]
    private var screenTraceRequestSequence = 0
    private var screenTraceStatsRemaining = 0
    private var nextScreenTraceStatsAt: TimeInterval = 0
    private var screenKeyframeRequests: [String: SfuScreenKeyframeRequest] = [:]
    private var screenKeyframeCheckTask: Task<Void, Never>?
    private var lastKeyframeRequestUptime: TimeInterval?
    private var lastVideoKeyframeRequests: [String: TimeInterval] = [:]
    private var videoRecoveryChecks: [String: SfuVideoRecoveryCheck] = [:]
    private var videoExposures: [String: SfuVideoExposure] = [:]
    private var queuedVideoKeyframes: [String: SfuQueuedKeyframe] = [:]
    private var nextVideoKeyframeSendAt: TimeInterval = 0
    private var screenRecoveryStartedAt: [String: TimeInterval] = [:]
    private var videoBackgroundedAt: TimeInterval?
    private var retiringCloseTask: Task<Void, Never>?

    private var negotiating = false
    private var pendingOffer: (Int64, String)?
    private var offerReissueTask: Task<Void, Never>?

    private var retiringPeerConnection: RTCPeerConnection?
    private var iceRecoveryTask: Task<Void, Never>?
    private var transportWatchdogTask: Task<Void, Never>?
    private var lastInboundAudioCounters: [String: SfuInboundAudioCounters] = [:]
    private var lastOutboundAudioPackets: Double?
    private var audioWatchdogGeneration = -1
    private var stalledPlayoutTicks = 0
    private var playoutRestarts = 0
    private var silentInboundTicks = 0
    private var audioStuckReported = false
    private var inboundSilenceReported = false
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.mezon.sfu.path")
    private var lastPathSignature: String?
    private var pathWasUnsatisfied = false
    private var pathSatisfied = true

    private var transceiverCache: [RTCRtpTransceiver] = []
    private var remoteSnapshot: [SfuRemoteTransceiverSnapshot] = []
    private var remoteMediaSyncScheduled = false
    private var remoteMediaSyncRunning = false
    private var remoteMediaRevision = 0
    private var audioRecoveryObservers: [NSObjectProtocol] = []
    private var audioRecoveryOwnsActivation = false
    private var audioInterrupted = false
    private var audioResumeRecoveryTask: Task<Void, Never>?

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
        var audioTrackId: String?
        var videoTrackId: String?
        var screenTrackId: String?
        var screenActive = false
        var screenActiveSince: TimeInterval = 0
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

    init(channelId: Int64, clanId: Int64, userId: String) {
        self.channelId = channelId
        self.clanId = clanId
        self.userId = userId
        super.init()
    }

    func join(token: String, role: SfuRole) {
        leave()
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
        installAudioRecoveryObservers()
        resetPlayoutWatchdog()
        Self.ensureSSL()

        guard buildWsUrl(token: token) != nil else {
            emitState(.failed)
            return
        }
        // Prepare the OS session before constructing this call's audio device.
        // Configuration can fail during a permission/inactive transition; retry
        // through the lifecycle recovery task instead of assuming success.
        let audioReady = restoreAudioSession(restartAudio: true)
        createLocalAudioTrack()
        openConnection(initial: true)
        if !audioReady { scheduleAudioResumeRecovery() }

        let speakingTask = Task { [weak self] in
            while !Task.isCancelled {
                let delayNanos = self?.speakingPollDelayNanos() ?? Self.speakingPollNanos
                try? await Task.sleep(nanoseconds: delayNanos)
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
                guard self.active, !self.socketOpen, !self.connecting, self.transportRecoveryTask == nil else { continue }
                guard self.pathSatisfied else { continue }
                self.recoverTransport(gen: self.connectionGen)
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
        pollTasks = [speakingTask, reconnectTask, playoutWatchdogTask]
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
            // availableInterfaces includes idle radios; only the route in use matters here.
            let signature: String
            if path.usesInterfaceType(.wifi) {
                signature = "wifi"
            } else if path.usesInterfaceType(.cellular) {
                signature = "cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                signature = "wired"
            } else {
                signature = "other"
            }
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
        // Continual ICE gathering can migrate media without replacing the call.
        // A healthy connection must not be torn down just because the route changed.
        scheduleIceRecovery()
    }

    private func scheduleIceRecovery() {
        guard active, joined, iceRecoveryTask == nil, transportRecoveryTask == nil else { return }
        let gen = connectionGen
        iceRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.iceRecoveryGraceNanos)
            guard !Task.isCancelled, let self, self.connectionGen == gen else { return }
            self.iceRecoveryTask = nil
            guard self.active, self.pathSatisfied, !self.connecting else { return }
            if let pc = self.peerConnection, self.socketOpen,
               pc.connectionState == .connected,
               pc.iceConnectionState == .connected || pc.iceConnectionState == .completed {
                return
            }
            self.recoverTransport(gen: gen)
        }
    }

    private func restartSession() {
        guard active, joined, !connecting, transportRecoveryTask == nil else { return }
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
            recoverTransport(gen: connectionGen)
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

    /// Equal jitter: 0.5–1s, 1–2s, 2–4s, 4–8s; capped at 8s.
    private nonisolated static func reconnectDelay(attempt: Int, jitter: Double) -> TimeInterval {
        let ceiling = Double(1 << min(max(attempt, 0), 3))
        return ceiling * (0.5 + 0.5 * min(max(jitter, 0), 1))
    }

    private func recoverTransport(gen: Int) {
        guard active, gen == connectionGen, transportRecoveryTask == nil else { return }
        discardFailedTransport()
        let maxAttempts = joined ? Self.maxReconnectAttempts : Self.maxInitialConnectAttempts
        guard reconnectAttempts < maxAttempts else {
            leave()
            emitState(.failed)
            return
        }
        let retryGen = connectionGen
        let delay = Self.reconnectDelay(attempt: reconnectAttempts, jitter: Double.random(in: 0...1))
        transportRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.active, self.connectionGen == retryGen else { return }
            // If offline, the ordinary path monitor/poller resumes once online.
            // The failed transport has already been discarded and backoff elapsed.
            guard self.pathSatisfied else {
                self.transportRecoveryTask = nil
                return
            }
            if self.tokenNeedsRefresh(), self.tokenRefreshes < Self.maxTokenRefreshes {
                let fresh = await self.tokenProvider?()
                guard !Task.isCancelled, self.active, self.connectionGen == retryGen else { return }
                self.tokenRefreshes += 1
                if let fresh, !fresh.isEmpty {
                    self.token = fresh
                    self.tokenRejected = false
                }
            }
            // Never reconnect with a token the server has explicitly rejected.
            guard !self.tokenRejected else {
                self.leave()
                self.emitState(.failed)
                return
            }
            self.transportRecoveryTask = nil
            guard self.pathSatisfied else { return }
            self.openConnection(initial: false)
        }
        emitState(.disconnected)
        guard active, connectionGen == retryGen else { return }
        emitParticipants()
        onSpeaking?([])
        onPushToTalkActive?(false)
    }

    private func discardFailedTransport() {
        // Invalidate callbacks before closing: no old SDP/candidate/receiver
        // callback may mutate the replacement connection during backoff.
        connectionGen += 1
        socketOpen = false
        connecting = false
        isConnected = false
        stateRestored = false
        admitted = false
        selfPeerId = nil
        negotiating = false
        pendingOffer = nil
        localTracksAdded = false
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        clearJoinWatchdog()
        clearTransportWatchdog()
        clearOfferReissueDeadline()
        clearDeferredRestart()
        cancelAudioResumeRecovery()
        postConnectAudioRecoveryTask?.cancel()
        postConnectAudioRecoveryTask = nil
        iceRecoveryTask?.cancel()
        iceRecoveryTask = nil
        healthySessionResetTask?.cancel()
        healthySessionResetTask = nil
        moderatorMuteTask?.cancel()
        moderatorMuteTask = nil
        cameraTierTask?.cancel()
        cameraTierTask = nil
        retiringCloseTask?.cancel()
        retiringCloseTask = nil
        let failed = peerConnection
        let retiring = retiringPeerConnection
        peerConnection = nil
        retiringPeerConnection = nil
        // Every signaling recovery starts fresh, including fatal DTLS failures.
        // Closing the PC discards its SDP, ICE credentials and candidate pairs.
        Self.closeOffMain(failed)
        Self.closeOffMain(retiring)
        discardTransceiverState()
        resetScreenKeyframeRequests()
        videoExposures.removeAll()
        resetPlayoutWatchdog()
        userIdByMid.removeAll()
        peerIdByMid.removeAll()
        roleByMid.removeAll()
        memberByPeerId.removeAll()
        remote.removeAll()
        remoteOrder.removeAll()
        participants = []
        speakingIds = []
        // Keep device tracks and user intent; attachLocalTracks + room_snapshot
        // republish them on the new PC and restore mute/camera/PTT signaling.
        localAudioTrack?.isEnabled = false
        pttActive = false
    }

    private func scheduleHealthyConnectionReset() {
        guard healthySessionResetTask == nil else { return }
        let gen = connectionGen
        healthySessionResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.healthySessionNanos)
            guard !Task.isCancelled, let self, self.connectionGen == gen else { return }
            self.healthySessionResetTask = nil
            // ICE connected alone is not enough to reset the DTLS retry budget.
            if self.active, self.isConnected, self.socketOpen, self.peerConnection?.connectionState == .connected {
                self.reconnectAttempts = 0
            }
        }
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
            Self.closeOffMain(current)
        }
    }

    private func releaseRetiringPeerConnection() {
        guard !remote.isEmpty, let previous = retiringPeerConnection else { return }
        retiringPeerConnection = nil
        retiringCloseTask?.cancel()
        retiringCloseTask = nil
        Self.closeOffMain(previous)
    }

    func leave() {
        transportRecoveryTask?.cancel()
        transportRecoveryTask = nil
        cancelAudioResumeRecovery()
        audioRecoveryObservers.forEach(NotificationCenter.default.removeObserver)
        audioRecoveryObservers.removeAll()
        if Self.liveSession === self {
            Self.liveSession = nil
        }
        let hadConnection = peerConnection != nil || webSocketTask != nil
        active = false
        audioInterrupted = false
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
        clearJoinWatchdog()
        postConnectAudioRecoveryTask?.cancel()
        postConnectAudioRecoveryTask = nil
        resetScreenKeyframeRequests()
        videoExposures.removeAll()
        clearDeferredRestart()
        retiringCloseTask?.cancel()
        retiringCloseTask = nil
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
        discardTransceiverState()
        iceRecoveryTask?.cancel()
        iceRecoveryTask = nil
        healthySessionResetTask?.cancel()
        healthySessionResetTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        let closingPeerConnection = peerConnection
        let closingRetiringPeerConnection = retiringPeerConnection
        peerConnection = nil
        retiringPeerConnection = nil
        Self.closeOffMain(closingPeerConnection)
        Self.closeOffMain(closingRetiringPeerConnection)
        if let retiredFactory = _factory {
            _factory = nil
            Self.releaseOffMain([retiredFactory])
        }
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
        if hadConnection || audioRecoveryOwnsActivation {
            disableAudioIfIdle()
        }
        releaseAudioRecoveryActivation()
    }

    func setMicEnabled(_ on: Bool) {
        guard active, role == .speaker else { return }
        micEnabled = on
        let attached = synchronizeLocalAudioTrack()
        if on { restoreAudioSession(restartAudio: false) }
        if localTracksAdded && !attached {
            recoverTransport(gen: connectionGen)
            return
        }
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
        pttActive = false
        localAudioTrack?.isEnabled = false
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
        guard active, transportRecoveryTask == nil else { return }
        cancelAudioResumeRecovery()
        if !initial {
            let maxAttempts = joined ? Self.maxReconnectAttempts : Self.maxInitialConnectAttempts
            guard reconnectAttempts < maxAttempts else {
                active = false
                emitState(.failed)
                return
            }
            reconnectAttempts += 1
        }
        healthySessionResetTask?.cancel()
        healthySessionResetTask = nil
        connecting = true
        isConnected = false
        connectionGen += 1
        let gen = connectionGen
        stateRestored = false
        admitted = false
        selfPeerId = nil
        moderatorMuteTask?.cancel()
        moderatorMuteTask = nil
        clearOfferReissueDeadline()
        clearTransportWatchdog()
        clearJoinWatchdog()
        postConnectAudioRecoveryTask?.cancel()
        postConnectAudioRecoveryTask = nil
        clearDeferredRestart()
        lastConnectionOpenedUptime = ProcessInfo.processInfo.systemUptime
        resetPlayoutWatchdog()
        resetScreenKeyframeRequests()
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
                Self.closeOffMain(retiringPeerConnection)
                retiringPeerConnection = previous
                scheduleRetiringPeerConnectionClose()
            }
            peerConnection = nil
            negotiating = false
            pendingOffer = nil
            localTracksAdded = false
            userIdByMid.removeAll()
            peerIdByMid.removeAll()
            roleByMid.removeAll()
            memberByPeerId.removeAll()
            remote.removeAll()
            remoteOrder.removeAll()
            emitParticipants()
        }
        discardTransceiverState()
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
        armJoinWatchdog(gen: gen)
    }

    private func sendJoin(gen: Int) {
        ScreenShareTrace.log("flow_active", ["revision": "ios-screen-trace-v1", "generation": gen,
            "maxInitialRequests": Self.screenKeyframeRetryDelays.count + 1,
            "retryDelaysSeconds": Self.screenKeyframeRetryDelays])
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
                guard let self, gen == self.connectionGen, self.webSocketTask === task else { return }
                if error != nil {
                    self.handleSocketClosed(gen: gen)
                } else {
                    self.socketOpen = true
                    self.connecting = false
                    self.emitState(.joining)
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
                let current = !Task.isCancelled && gen == connectionGen && webSocketTask === task
                if current {
                    let failure = error as NSError
                    ScreenShareTrace.log("sfu_socket_receive_failed", ["generation": gen,
                        "errorDomain": failure.domain, "errorCode": failure.code])
                    handleSocketClosed(gen: gen)
                }
                return
            }
        }
    }

    private func handleSocketClosed(gen: Int) {
        guard active, gen == connectionGen else { return }
        // URLSession can report .invalid (0) when the connection drops without
        // a close frame. Treat it like 1006, along with other recoverable codes.
        let closeCode = webSocketTask?.closeCode.rawValue ?? 0
        if let cause = Self.removalCause(for: closeCode) {
            handleRemoved(gen: gen, cause: cause, reason: webSocketTask?.closeReason)
            return
        }
        switch closeCode {
        case 4003, 4004, 4005:
            tokenRejected = true
        case Self.dtlsFailureCloseCode:
            break // Fatal DTLS: recoverTransport fully discards the old PC.
        default:
            break
        }
        recoverTransport(gen: gen)
    }

    private func handleRemoved(gen: Int, cause: SfuRemovalCause, reason: Data?) {
        let text = Self.closeReasonText(reason)
        guard gen == connectionGen, active else { return }
        leave()
        onRemoved?(cause, text)
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
            tokenRefreshes = 0
            tokenRejected = false
            if !stateRestored {
                stateRestored = true
                let attached = synchronizeLocalAudioTrack()
                if localTracksAdded && !attached {
                    recoverTransport(gen: connectionGen)
                    return
                }
                let resumePushToTalk = role == .audience && pttRequested
                send(["type": "mute", "is_mute": role == .speaker ? !micEnabled : !resumePushToTalk])
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
            // A delayed grant must not reopen the microphone after release.
            guard role == .audience else { break }
            let isActive = (boolValue(msg["active"]) ?? false) && pttRequested
            pttActive = isActive
            let attached = synchronizeLocalAudioTrack()
            if localTracksAdded && !attached {
                recoverTransport(gen: connectionGen)
                return
            }
            if isActive { restoreAudioSession(restartAudio: false) }
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
            if !admitted && (detail == "invalid_token" || detail == "missing_token") {
                tokenRejected = true
                recoverTransport(gen: connectionGen)
                return
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
            } else if Self.keyframeRequestErrors.contains(detail),
                      let requestedAt = lastKeyframeRequestUptime,
                      ProcessInfo.processInfo.systemUptime - requestedAt < Self.keyframeRequestErrorWindow {
                ScreenShareTrace.log("request_rejected", ["generation": connectionGen, "code": detail])
                break
            } else {
                onError?(detail, detail)
                handleRemoved(gen: connectionGen, cause: .disconnected, reason: nil)
            }
        case "keyframe_requested":
            ScreenShareTrace.log("server_ack", ["generation": connectionGen,
                "success": msg["success"] as? Bool ?? false, "cached": msg["cached"] as? Bool ?? false,
                "kind": msg["kind"] as? String ?? "unknown", "publisherIdAvailable": false])
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
            self.recoverTransport(gen: gen)
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
            self.recoverTransport(gen: gen)
        }
    }

    private func clearTransportWatchdog() {
        transportWatchdogTask?.cancel()
        transportWatchdogTask = nil
    }

    private func armJoinWatchdog(gen: Int) {
        clearJoinWatchdog()
        joinWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.joinConnectDeadlineNanos)
            guard !Task.isCancelled, let self else { return }
            self.joinWatchdogTask = nil
            guard gen == self.connectionGen, self.active, !self.isConnected else { return }
            self.recoverTransport(gen: gen)
        }
    }

    private func clearJoinWatchdog() {
        joinWatchdogTask?.cancel()
        joinWatchdogTask = nil
    }

    private func schedulePostConnectAudioRecovery(gen: Int) {
        guard lastPostConnectAudioRecoveryGeneration != gen else { return }
        lastPostConnectAudioRecoveryGeneration = gen
        postConnectAudioRecoveryTask?.cancel()
        postConnectAudioRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled, let self else { return }
            self.postConnectAudioRecoveryTask = nil
            guard gen == self.connectionGen, self.active, self.joined, self.isConnected,
                  Self.liveSession === self else { return }
            self.restoreAudioSession(restartAudio: true)
        }
    }

    private func resetPlayoutWatchdog() {
        lastInboundAudioCounters = [:]
        lastOutboundAudioPackets = nil
        audioWatchdogGeneration = -1
        stalledPlayoutTicks = 0
        playoutRestarts = 0
        silentInboundTicks = 0
        audioStuckReported = false
        inboundSilenceReported = false
    }

    private func cancelAudioResumeRecovery() {
        audioResumeRecoveryTask?.cancel()
        audioResumeRecoveryTask = nil
    }

    private func scheduleAudioResumeRecovery() {
        cancelAudioResumeRecovery()
        guard active else { return }
        // Failures while suspended must not exhaust recovery for the next
        // foreground session. Discard pre-suspension statistics as well.
        resetPlayoutWatchdog()
        let gen = connectionGen
        audioResumeRecoveryTask = Task { @MainActor [weak self] in
            // Let AVAudioSession/WebRTC finish processing lifecycle callbacks.
            // Retry only configuration/activation failures, not healthy audio.
            for delay: UInt64 in [250_000_000, 750_000_000, 1_500_000_000] {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self else { return }
                guard self.active, self.connectionGen == gen, Self.liveSession === self,
                      self.audioOwnerBlockingRestore == nil else {
                    self.audioResumeRecoveryTask = nil
                    return
                }
                if self.restoreAudioSession(restartAudio: true) {
                    self.audioResumeRecoveryTask = nil
                    return
                }
            }
            self?.audioResumeRecoveryTask = nil
        }
    }

    /// Each renderer owns a source token, so hiding a tile cannot hide its focused/PiP view.
    func setVideoTrackVisible(_ track: RTCVideoTrack, visible: Bool, source: String, focused: Bool = false) {
        let previousExposure = videoExposures[source]
        if remote.values.contains(where: { $0.screen === track }),
           (visible ? previousExposure?.track !== track || previousExposure?.focused != focused : previousExposure?.track === track) {
            ScreenShareTrace.log("renderer_visibility", ["generation": connectionGen, "source": source,
                "trackId": track.trackId, "trackObject": String(describing: ObjectIdentifier(track)),
                "visible": visible, "focused": focused])
            if visible { screenTraceStatsRemaining = 3 }
        }
        if visible {
            let previous = videoExposures[source]
            videoExposures[source] = SfuVideoExposure(track: track, focused: focused)
            if previous?.track !== track || previous?.focused != focused {
                requestVideoKeyframeIfNeeded(for: track)
            }
        } else if videoExposures[source]?.track === track {
            videoExposures[source] = nil
            if videoPriority(track) == nil {
                queuedVideoKeyframes = queuedVideoKeyframes.filter { $0.value.track !== track }
                videoRecoveryChecks = videoRecoveryChecks.filter { $0.value.track !== track }
            }
        }
        requestMissingScreenKeyframes()
    }

    private func videoPriority(_ track: RTCVideoTrack) -> Int? {
        let exposures = videoExposures.values.filter { $0.track === track }
        guard !exposures.isEmpty else { return nil }
        return exposures.contains(where: { $0.focused }) ? 0 : 1
    }

    /// Explicit watch/expand still respects the shared queue and skips a usable local frame.
    func requestVideoKeyframe(for track: RTCVideoTrack) {
        guard active, videoPriority(track) != nil, let check = videoRecoveryCheck(for: track) else { return }
        let since = videoFrameRequiredSince(check)
        guard (VideoTrackLastFrameStore.observe(track).lastFrameUptime ?? -.infinity) < since else { return }
        enqueueVideoKeyframe(check, readyAt: ProcessInfo.processInfo.systemUptime, frameSince: since)
        requestMissingScreenKeyframes()
    }

    func requestVideoKeyframeIfNeeded(for track: RTCVideoTrack) {
        guard active, let priority = videoPriority(track), let check = videoRecoveryCheck(for: track) else { return }
        let since = videoFrameRequiredSince(check)
        guard (VideoTrackLastFrameStore.observe(track).lastFrameUptime ?? -.infinity) < since else { return }
        let key = "\(check.kind)|\(check.publisherId)"
        if let previous = videoRecoveryChecks[key], previous.track !== track { videoRecoveryChecks[key] = nil }
        if priority == 0, (videoRecoveryChecks[key]?.startedAt ?? since) <= since {
            videoRecoveryChecks[key] = nil
            enqueueVideoKeyframe(check, readyAt: ProcessInfo.processInfo.systemUptime, frameSince: since)
        } else if videoRecoveryChecks[key] == nil {
            let now = ProcessInfo.processInfo.systemUptime
            videoRecoveryChecks[key] = SfuVideoRecoveryCheck(track: track, kind: check.kind, publisherId: check.publisherId,
                startedAt: since, checkAt: now + Self.screenKeyframeFirstRequestGrace + Double.random(in: 0...0.15))
        }
        requestMissingScreenKeyframes()
    }

    private func videoFrameRequiredSince(_ check: SfuVideoRecoveryCheck) -> TimeInterval {
        let entry = remote.values.first { $0.peerId == String(check.publisherId) }
        return max(lastConnectionOpenedUptime ?? 0, check.kind == "screen" ? (entry?.screenActiveSince ?? 0) : 0)
    }

    private func enqueueVideoKeyframe(_ check: SfuVideoRecoveryCheck, readyAt: TimeInterval, frameSince: TimeInterval) {
        let key = "\(check.kind)|\(check.publisherId)"
        if var queued = queuedVideoKeyframes[key], queued.track === check.track {
            queued.readyAt = min(queued.readyAt, readyAt)
            queued.frameSince = max(queued.frameSince, frameSince)
            queuedVideoKeyframes[key] = queued
        } else {
            queuedVideoKeyframes[key] = SfuQueuedKeyframe(track: check.track, kind: check.kind,
                publisherId: check.publisherId, readyAt: readyAt, frameSince: frameSince)
        }
    }

    private func videoRecoveryCheck(for track: RTCVideoTrack) -> SfuVideoRecoveryCheck? {
        guard let entry = remote.values.first(where: { $0.screen === track || $0.video === track }),
              let peerId = entry.peerId, let publisherId = UInt32(peerId), publisherId != 0 else { return nil }
        guard entry.screen === track ? entry.screenActive : entry.cameraActive else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        return SfuVideoRecoveryCheck(track: track, kind: entry.screen === track ? "screen" : "camera",
                                     publisherId: publisherId, startedAt: now, checkAt: now + Self.foregroundVideoGrace)
    }

    private func checkVideoAfterForeground() {
        guard active, let backgroundedAt = videoBackgroundedAt else { return }
        videoBackgroundedAt = nil
        queuedVideoKeyframes.removeAll()
        videoRecoveryChecks.removeAll()
        let now = ProcessInfo.processInfo.systemUptime
        let briefBackground = now - backgroundedAt < Self.shortVideoBackground
        for entry in remote.values {
            let tracks = [entry.screenActive ? entry.screen : nil, entry.cameraActive ? entry.video : nil]
            for track in tracks.compactMap({ $0 }) {
                guard videoPriority(track) != nil, let check = videoRecoveryCheck(for: track) else { continue }
                let frameAt = VideoTrackLastFrameStore.observe(track).lastFrameUptime
                // A static share's retained frame remains valid across a brief background.
                if briefBackground, check.kind == "screen", let frameAt,
                   frameAt >= max(entry.screenActiveSince, lastConnectionOpenedUptime ?? 0) { continue }
                if let frameAt, frameAt >= backgroundedAt, now - frameAt < Self.foregroundVideoGrace { continue }
                videoRecoveryChecks["\(check.kind)|\(check.publisherId)"] = check
            }
        }
    }

    private var canRequestVideoKeyframes: Bool {
        active && joined && socketOpen && webSocketTask != nil && isConnected && !negotiating
            && UIApplication.shared.applicationState == .active
    }

    private func sendVideoKeyframeRequest(kind: String, publisherId: UInt32) -> Bool {
        guard canRequestVideoKeyframes, let socket = webSocketTask else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        let key = "\(kind)|\(publisherId)"
        guard now - (lastVideoKeyframeRequests[key] ?? -.infinity) >= Self.keyframeMinimumInterval else { return false }
        let payload: [String: Any] = ["type": "request_keyframe", "kind": kind,
                                      "publisher_id": NSNumber(value: publisherId)]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return false }
        let previousSentAt = lastVideoKeyframeRequests[key]
        lastVideoKeyframeRequests[key] = now
        lastKeyframeRequestUptime = now
        let gen = connectionGen
        screenTraceRequestSequence += 1
        let traceId = screenTraceRequestSequence
        if kind == "screen" {
            screenTraceStatsRemaining = 3
            ScreenShareTrace.log("request_dispatched", ["generation": gen, "localRequestId": traceId,
                "publisherId": publisherId, "kind": kind,
                "attempt": (screenKeyframeRequests[String(publisherId)]?.attempts ?? 0) + 1,
                "sincePreviousMs": previousSentAt.map { Int((now - $0) * 1000) } ?? -1])
        }
        socket.send(.string(text)) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, gen == self.connectionGen, socket === self.webSocketTask else { return }
                if kind == "screen" {
                    let failure = error as NSError?
                    ScreenShareTrace.log(error == nil ? "request_send_completed" : "request_send_failed",
                        ["generation": gen, "localRequestId": traceId, "publisherId": publisherId,
                         "errorDomain": failure?.domain ?? "", "errorCode": failure?.code ?? 0])
                }
                guard error != nil else { return }
                // Keep the send timestamp as backoff even if enqueue fails.
                if let track = self.remote.values.first(where: { $0.peerId == String(publisherId) })
                    .flatMap({ kind == "screen" ? $0.screen : $0.video }),
                   let check = self.videoRecoveryCheck(for: track), self.videoPriority(track) != nil {
                    self.enqueueVideoKeyframe(check, readyAt: ProcessInfo.processInfo.systemUptime + Self.keyframeMinimumInterval,
                                              frameSince: check.startedAt)
                }
                self.scheduleScreenKeyframeCheck(after: Self.keyframeMinimumInterval)
            }
        }
        return true
    }

    /// A foreground check keeps its longer grace even when the renderer reattaches.
    private func recoverVideoIfNeeded() -> TimeInterval? {
        let now = ProcessInfo.processInfo.systemUptime
        var nextCheckAt: TimeInterval?
        for (key, check) in videoRecoveryChecks {
            guard videoPriority(check.track) != nil,
                  let current = videoRecoveryCheck(for: check.track), current.publisherId == check.publisherId,
                  current.kind == check.kind else {
                videoRecoveryChecks[key] = nil
                continue
            }
            if let frameAt = VideoTrackLastFrameStore.observe(check.track).lastFrameUptime, frameAt >= check.startedAt {
                videoRecoveryChecks[key] = nil
                continue
            }
            if now >= check.checkAt {
                enqueueVideoKeyframe(check, readyAt: check.checkAt, frameSince: check.startedAt)
                videoRecoveryChecks[key] = nil
                if check.kind == "screen" { screenRecoveryStartedAt[String(check.publisherId)] = check.startedAt }
            } else {
                nextCheckAt = min(nextCheckAt ?? check.checkAt, check.checkAt)
            }
        }
        return nextCheckAt
    }

    /// Drain one request at a time; priorities are evaluated at dispatch, not enqueue.
    private func drainVideoKeyframes() -> TimeInterval? {
        let now = ProcessInfo.processInfo.systemUptime
        for (key, queued) in queuedVideoKeyframes {
            guard videoPriority(queued.track) != nil,
                  let current = videoRecoveryCheck(for: queued.track), current.publisherId == queued.publisherId,
                  current.kind == queued.kind,
                  (VideoTrackLastFrameStore.observe(queued.track).lastFrameUptime ?? -.infinity) < queued.frameSince else {
                queuedVideoKeyframes[key] = nil
                continue
            }
        }
        queuedVideoKeyframes = queuedVideoKeyframes.filter { _, queued in
            guard queued.kind == "screen", let request = screenKeyframeRequests[String(queued.publisherId)],
                  request.trackIdentity == ObjectIdentifier(queued.track) else { return true }
            return request.satisfied || request.attempts <= Self.screenKeyframeRetryDelays.count
        }
        let ordered = queuedVideoKeyframes.sorted { lhs, rhs in
            let left = videoPriority(lhs.value.track) ?? 2
            let right = videoPriority(rhs.value.track) ?? 2
            if left != right { return left < right }
            if lhs.value.readyAt != rhs.value.readyAt { return lhs.value.readyAt < rhs.value.readyAt }
            return lhs.key < rhs.key
        }
        var nextAt: TimeInterval?
        for (key, queued) in ordered {
            let dueAt = max(queued.readyAt, max(nextVideoKeyframeSendAt,
                (lastVideoKeyframeRequests[key] ?? -.infinity) + Self.keyframeMinimumInterval))
            if now >= dueAt, sendVideoKeyframeRequest(kind: queued.kind, publisherId: queued.publisherId) {
                queuedVideoKeyframes[key] = nil
                nextVideoKeyframeSendAt = now + Self.keyframeGlobalSpacing + Double.random(in: 0...0.075)
                if queued.kind == "screen", var request = screenKeyframeRequests[String(queued.publisherId)],
                   request.trackIdentity == ObjectIdentifier(queued.track), !request.satisfied {
                    request.attempts += 1
                    request.lastSentAt = now
                    screenKeyframeRequests[String(queued.publisherId)] = request
                }
            } else {
                // Failed enqueue and per-track throttling must also back off the timer.
                let next = max(dueAt, (lastVideoKeyframeRequests[key] ?? -.infinity) + Self.keyframeMinimumInterval)
                nextAt = min(nextAt ?? next, next)
            }
        }
        return nextAt
    }

    private func requestMissingScreenKeyframes() {
        defer { traceScreenRecoveryState() }
        guard canRequestVideoKeyframes else { return }
        let recoveryCheckAt = recoverVideoIfNeeded()
        let now = ProcessInfo.processInfo.systemUptime
        let retryDelays = Self.screenKeyframeRetryDelays
        let connectionOpenedAt = lastConnectionOpenedUptime ?? 0
        var sharingPeerIds: Set<String> = []
        var nextCheckAt = recoveryCheckAt
        for entry in remote.values {
            guard entry.screenActive,
                  let screen = entry.screen,
                  let peerId = entry.peerId,
                  let publisherId = UInt32(peerId), publisherId != 0 else { continue }
            sharingPeerIds.insert(peerId)
            let trackId = entry.screenTrackId ?? screen.trackId
            let activeSince = max(entry.screenActiveSince, max(connectionOpenedAt, screenRecoveryStartedAt[peerId] ?? 0))
            var request = screenKeyframeRequests[peerId]
                ?? SfuScreenKeyframeRequest(trackId: trackId, trackIdentity: ObjectIdentifier(screen), activeSince: activeSince, firstSeenAt: now, attempts: 0, lastSentAt: 0, satisfied: false)
            if request.trackId != trackId || request.trackIdentity != ObjectIdentifier(screen) || request.activeSince != activeSince {
                request = SfuScreenKeyframeRequest(trackId: trackId, trackIdentity: ObjectIdentifier(screen), activeSince: activeSince, firstSeenAt: now, attempts: 0, lastSentAt: 0, satisfied: false)
            }
            if videoPriority(screen) != nil, let arrivedAt = VideoTrackLastFrameStore.observe(screen).lastFrameUptime, arrivedAt >= request.activeSince {
                request.satisfied = true
            }
            if videoPriority(screen) != nil, !request.satisfied, request.attempts <= retryDelays.count {
                let previousSend = lastVideoKeyframeRequests["screen|\(publisherId)"] ?? -.infinity
                let recoveryGrace = videoRecoveryChecks["screen|\(publisherId)"]?.checkAt ?? 0
                let dueAt = max(request.attempts == 0
                    ? request.firstSeenAt + Self.screenKeyframeFirstRequestGrace
                    : request.lastSentAt + retryDelays[request.attempts - 1],
                    max(previousSend + Self.keyframeMinimumInterval, recoveryGrace))
                if dueAt <= now, let check = videoRecoveryCheck(for: screen) {
                    enqueueVideoKeyframe(check, readyAt: dueAt, frameSince: request.activeSince)
                }
                if request.attempts <= retryDelays.count {
                    let nextAt = request.attempts == 0
                        ? request.firstSeenAt + Self.screenKeyframeFirstRequestGrace
                        : request.lastSentAt + retryDelays[request.attempts - 1]
                    let throttledNextAt = max(nextAt, max(previousSend + Self.keyframeMinimumInterval, recoveryGrace))
                    if throttledNextAt > now { nextCheckAt = min(nextCheckAt ?? throttledNextAt, throttledNextAt) }
                }
            }
            screenKeyframeRequests[peerId] = request
        }
        screenKeyframeRequests = screenKeyframeRequests.filter { sharingPeerIds.contains($0.key) }
        lastVideoKeyframeRequests = lastVideoKeyframeRequests.filter { key, _ in
            memberByPeerId[String(key.split(separator: "|").last ?? "")] != nil
        }
        screenRecoveryStartedAt = screenRecoveryStartedAt.filter { sharingPeerIds.contains($0.key) }
        if let queuedAt = drainVideoKeyframes() { nextCheckAt = min(nextCheckAt ?? queuedAt, queuedAt) }
        // Retry deadlines depend on actual dispatch, including requests sent from the queue.
        for entry in remote.values {
            guard let track = entry.screen, videoPriority(track) != nil, let peer = entry.peerId,
                  let request = screenKeyframeRequests[peer], !request.satisfied,
                  request.attempts > 0, request.attempts <= retryDelays.count else { continue }
            let due = request.lastSentAt + retryDelays[request.attempts - 1]
            if due > now { nextCheckAt = min(nextCheckAt ?? due, due) }
        }
        if let nextCheckAt {
            scheduleScreenKeyframeCheck(after: nextCheckAt - now)
        } else {
            screenKeyframeCheckTask?.cancel()
            screenKeyframeCheckTask = nil
        }
    }

    private func traceScreenRecoveryState() {
        var currentStates: [String: String] = [:]
        for entry in remote.values {
            guard entry.screenActive, let track = entry.screen, let peer = entry.peerId else { continue }
            let request = screenKeyframeRequests[peer]
            let visible = videoPriority(track) != nil
            let frameAt = VideoTrackLastFrameStore.cachedFrameUptime(of: track)
            let since = request?.activeSince ?? max(entry.screenActiveSince, lastConnectionOpenedUptime ?? 0)
            let hasFrame = frameAt.map { $0 >= since } ?? false
            let event = hasFrame ? "frame_available" : !visible ? "view_paused"
                : !canRequestVideoKeyframes ? "transport_blocked"
                : (request?.attempts ?? 0) > Self.screenKeyframeRetryDelays.count ? "retry_budget_exhausted" : "waiting_for_frame"
            let signature = "\(ObjectIdentifier(track))|\(since)|\(event)|\(request?.attempts ?? 0)|\(visible)"
            currentStates[peer] = signature
            guard screenTraceStates[peer] != signature else { continue }
            ScreenShareTrace.log("recovery_state", ["generation": connectionGen, "publisherId": peer,
                "trackId": track.trackId, "trackObject": String(describing: ObjectIdentifier(track)),
                "state": event, "visible": visible, "attempts": request?.attempts ?? 0,
                "cachedFrameAgeMs": frameAt.map { Int((ProcessInfo.processInfo.systemUptime - $0) * 1000) } ?? -1,
                "joined": joined, "socketOpen": socketOpen, "connected": isConnected, "negotiating": negotiating,
                "applicationState": UIApplication.shared.applicationState.rawValue])
        }
        for peer in screenTraceStates.keys where currentStates[peer] == nil {
            ScreenShareTrace.log("source_removed", ["generation": connectionGen, "publisherId": peer])
        }
        screenTraceStates = currentStates
    }

    private func scheduleScreenKeyframeCheck(after delay: TimeInterval) {
        screenKeyframeCheckTask?.cancel()
        screenKeyframeCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0.2) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.screenKeyframeCheckTask = nil
            self.requestMissingScreenKeyframes()
        }
    }

    private func resetScreenKeyframeRequests() {
        ScreenShareTrace.log("transport_reset", ["generation": connectionGen, "sources": screenKeyframeRequests.count])
        screenTraceStates.removeAll()
        screenTraceStatsRemaining = 0
        nextScreenTraceStatsAt = 0
        screenKeyframeCheckTask?.cancel()
        screenKeyframeCheckTask = nil
        screenKeyframeRequests.removeAll()
        lastKeyframeRequestUptime = nil
        lastVideoKeyframeRequests.removeAll()
        videoRecoveryChecks.removeAll()
        queuedVideoKeyframes.removeAll()
        nextVideoKeyframeSendAt = 0
        screenRecoveryStartedAt.removeAll()
        videoBackgroundedAt = nil
    }

    private func checkPlayout(_ pc: RTCPeerConnection) {
        guard isConnected, joined, pc.connectionState == .connected else { return }
        requestMissingScreenKeyframes()
        let gen = connectionGen
        let now = ProcessInfo.processInfo.systemUptime
        let traceStats = screenTraceStatsRemaining > 0 && now >= nextScreenTraceStatsAt
        if traceStats {
            screenTraceStatsRemaining -= 1
            nextScreenTraceStatsAt = now + 5
        }
        Self.requestStatistics(pc) { [weak self] report in
            let flow = Self.audioFlow(in: report)
            let videoStats = traceStats ? Self.screenTraceStatistics(in: report) : []
            Task { @MainActor [weak self] in
                guard let self, self.active, self.connectionGen == gen else { return }
                for stats in videoStats { ScreenShareTrace.log("inbound_video_stats", ["generation": gen, "stats": stats]) }
                self.evaluatePlayout(flow, gen: gen)
            }
        }
    }

    private nonisolated static func screenTraceStatistics(in report: RTCStatisticsReport) -> [String] {
        let fields = ["mid", "trackIdentifier", "ssrc", "packetsReceived", "bytesReceived", "framesReceived",
                      "framesDecoded", "keyFramesDecoded", "framesDropped", "pliCount", "nackCount"]
        // One screen track per line: a room-wide JSON exceeds Xcode's log line limit.
        return report.statistics.values.compactMap { stat in
            guard stat.type == "inbound-rtp",
                  (stat.values["kind"] as? String ?? stat.values["mediaType"] as? String) == "video",
                  (stat.values["trackIdentifier"] as? String)?.hasPrefix("screen-") != false else { return nil }
            var row: [String: Any] = [:]
            for field in fields { if let value = stat.values[field] { row[field] = value } }
            guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    private nonisolated static func audioFlow(in report: RTCStatisticsReport) -> SfuAudioFlow {
        var inbound: [String: SfuInboundAudioCounters] = [:]
        var outboundPacketsSent: Double = 0
        for (id, stat) in report.statistics {
            let values = stat.values
            guard (values["kind"] as? String) == "audio" else { continue }
            if stat.type == "inbound-rtp" {
                inbound[id] = SfuInboundAudioCounters(
                    packetsReceived: (values["packetsReceived"] as? NSNumber)?.doubleValue ?? 0,
                    samplesReceived: (values["totalSamplesReceived"] as? NSNumber)?.doubleValue ?? 0
                )
            } else if stat.type == "outbound-rtp" {
                outboundPacketsSent += (values["packetsSent"] as? NSNumber)?.doubleValue ?? 0
            }
        }
        return SfuAudioFlow(inbound: inbound, outboundPacketsSent: outboundPacketsSent)
    }

    private func evaluatePlayout(_ flow: SfuAudioFlow, gen: Int) {
        guard gen == connectionGen else { return }
        let previousInbound = lastInboundAudioCounters
        let previousOutbound = lastOutboundAudioPackets
        lastInboundAudioCounters = flow.inbound
        lastOutboundAudioPackets = flow.outboundPacketsSent
        guard audioWatchdogGeneration == gen else {
            audioWatchdogGeneration = gen
            stalledPlayoutTicks = 0
            silentInboundTicks = 0
            return
        }
        guard audioOwnerBlockingRestore == nil else {
            // A real interruption is not a stalled audio device. Keep the
            // counters fresh, but don't spend retries or report a false failure.
            stalledPlayoutTicks = 0
            silentInboundTicks = 0
            return
        }
        var inboundAdvanced = false
        var playoutAdvanced = false
        var packetsWithoutPlayout = false
        for (id, now) in flow.inbound {
            guard let before = previousInbound[id] else { continue }
            if now.packetsReceived > before.packetsReceived {
                inboundAdvanced = true
            }
            if now.samplesReceived > before.samplesReceived {
                playoutAdvanced = true
            } else if now.packetsReceived > before.packetsReceived {
                packetsWithoutPlayout = true
            }
        }
        // Use intent, so a disabled/missing sender is detected as a capture stall.
        let sendsAudio = localTracksAdded && shouldSendAudio
        let captureAdvanced = previousOutbound.map { flow.outboundPacketsSent > $0 } ?? false

        if !inboundAdvanced && hasUnmutedRemoteSpeaker {
            silentInboundTicks += 1
            if silentInboundTicks >= Self.playoutStallTicksBeforeRestart {
                reportInboundSilence(flow)
            }
        } else {
            silentInboundTicks = 0
        }

        var reasons: [String] = []
        let rtc = RTCAudioSession.sharedInstance()
        let session = AVAudioSession.sharedInstance()
        if !rtc.isAudioEnabled {
            reasons.append("audio_disabled")
        }
        if !rtc.isActive {
            reasons.append("session_inactive")
        }
        if session.category != .playAndRecord || session.mode != .voiceChat {
            reasons.append("session_configuration")
        }
        if session.currentRoute.outputs.isEmpty {
            reasons.append("output_missing")
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
           session.currentRoute.inputs.isEmpty {
            reasons.append("input_missing")
        }
        if packetsWithoutPlayout && !playoutAdvanced {
            reasons.append("playout")
        }
        if sendsAudio && !captureAdvanced {
            reasons.append("capture")
        }
        guard !reasons.isEmpty else {
            stalledPlayoutTicks = 0
            if playoutAdvanced || captureAdvanced {
                playoutRestarts = 0
            }
            return
        }
        stalledPlayoutTicks += 1
        guard stalledPlayoutTicks >= Self.playoutStallTicksBeforeRestart else { return }
        stalledPlayoutTicks = 0
        let details = audioHealthDetails(flow, reasons: reasons)
        guard audioOwnerBlockingRestore == nil, playoutRestarts < Self.maxPlayoutRestarts else {
            reportAudioStuck(details)
            return
        }
        playoutRestarts += 1
        SentryLogger.addBreadcrumb(category: "voice.audio", message: "restore", data: details)
        if reasons.contains("capture") {
            // Replace a stuck source on repeated recovery, preserving mic/PTT intent.
            if playoutRestarts > 1 {
                localAudioTrack?.isEnabled = false
                localAudioTrack = nil
                audioSource = nil
            }
            guard synchronizeLocalAudioTrack() else {
                recoverTransport(gen: gen)
                return
            }
        }
        restoreAudioSession(restartAudio: true)
    }

    private var audioOwnerBlockingRestore: String? {
        // Inactive is a transition (permission UI, Control Center, app switch).
        // Background is deliberately allowed: an ongoing voice call needs audio.
        if UIApplication.shared.applicationState == .inactive { return "app_inactive" }
        if audioInterrupted { return "interruption" }
        if callKitCallOwnsAudio { return "callkit" }
        if WebRTCCallManager.shared.signalingSession != nil { return "peer_call" }
        if StreamingWebRTCSession.shared.activeStreamChannelId != nil { return "stream" }
        return nil
    }

    private var hasUnmutedRemoteSpeaker: Bool {
        memberByPeerId.contains { peerId, state in
            peerId != selfPeerId && state.role != .audience && state.muted == false
        }
    }

    private func audioHealthDetails(_ flow: SfuAudioFlow, reasons: [String]) -> [String: Any] {
        let rtc = RTCAudioSession.sharedInstance()
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        return [
            "reasons": reasons.joined(separator: ","),
            "owner": audioOwnerBlockingRestore ?? "none",
            "audio_enabled": rtc.isAudioEnabled,
            "manual_audio": rtc.useManualAudio,
            "owns_activation": audioRecoveryOwnsActivation,
            "rtc_active": rtc.isActive,
            "category": session.category.rawValue,
            "mode": session.mode.rawValue,
            "input": route.inputs.map { $0.portType.rawValue }.joined(separator: ","),
            "output": route.outputs.map { $0.portType.rawValue }.joined(separator: ","),
            "mic_permission": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
            "input_available": session.isInputAvailable,
            "sample_rate": Int(session.sampleRate),
            "other_audio": session.isOtherAudioPlaying,
            "role": role.rawValue,
            "mic": micEnabled,
            "inbound_streams": flow.inbound.count,
            "inbound_packets": Int(flow.inbound.values.reduce(0) { $0 + $1.packetsReceived }),
            "outbound_packets": Int(flow.outboundPacketsSent),
            "restarts": playoutRestarts,
            "app_state": UIApplication.shared.applicationState.rawValue,
            "generation": connectionGen,
        ]
    }

    private func reportAudioStuck(_ details: [String: Any]) {
        guard !audioStuckReported else { return }
        audioStuckReported = true
        SentryLogger.capture(message: "voice.audio_stuck", extras: details)
    }

    private func reportInboundSilence(_ flow: SfuAudioFlow) {
        guard !inboundSilenceReported else { return }
        inboundSilenceReported = true
        let details = audioHealthDetails(flow, reasons: ["inbound_silent"])
        SentryLogger.capture(message: "voice.audio_inbound_silent", extras: details)
    }

    private func onOffer(generation: Int64, sdp: String) {
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
            remoteMediaRevision += 1
            do {
                let previousRemoteSdp = await Self.remoteDescriptionSdp(pc)
                guard isCurrentConnection(pc, gen: gen) else { return }
                let prepared = await Self.preparedOffer(sdp, currentRemoteSdp: previousRemoteSdp)
                guard isCurrentConnection(pc, gen: gen) else { return }
                applyMsidOwners(prepared.msidOwners)
                try await Self.awaitSetRemote(pc, RTCSessionDescription(type: .offer, sdp: prepared.sdp))
                guard isCurrentConnection(pc, gen: gen) else { return }
                // The remote offer creates the SFU uplink transceivers. Read them
                // before attaching tracks or creating the answer, including on rejoin.
                let offeredTransceivers = await Self.fetchTransceivers(pc)
                guard isCurrentConnection(pc, gen: gen) else { return }
                let previousTransceivers = transceiverCache
                transceiverCache = offeredTransceivers
                Self.releaseOffMain(previousTransceivers)
                try attachLocalTracks(pc)
                let answer = try await Self.awaitCreateAnswer(pc)
                guard isCurrentConnection(pc, gen: gen) else { return }
                var answerSdp = answer.sdp
                if role == .audience {
                    answerSdp = await Self.patchedAudienceAnswer(answer.sdp)
                    guard isCurrentConnection(pc, gen: gen) else { return }
                }
                send([
                    "type": "answer",
                    "offer_generation": NSNumber(value: generation),
                    "sdp": answerSdp,
                ])
                try await Self.awaitSetLocal(pc, RTCSessionDescription(type: .answer, sdp: answer.sdp))
                guard isCurrentConnection(pc, gen: gen) else { return }
                let transceivers = await Self.fetchTransceivers(pc)
                guard isCurrentConnection(pc, gen: gen) else { return }
                let staleTransceivers = transceiverCache
                transceiverCache = transceivers
                Self.releaseOffMain(staleTransceivers)
                let snapshot = await Self.captureRemoteSnapshot(transceivers)
                guard isCurrentConnection(pc, gen: gen) else { return }
                let staleTracks = remoteSnapshot.compactMap { $0.track }
                remoteSnapshot = snapshot
                Self.releaseOffMain(staleTracks)
                syncRemoteMedia()
            } catch {
                guard isCurrentConnection(pc, gen: gen) else { return }
                recoverTransport(gen: gen)
                return
            }
            offer = pendingOffer
            pendingOffer = nil
            if offer != nil {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        negotiating = false
        requestMissingScreenKeyframes()
        scheduleRemoteMediaSync()
    }

    private func isCurrentConnection(_ pc: RTCPeerConnection, gen: Int) -> Bool {
        gen == connectionGen && pc === peerConnection
    }

    private var shouldSendAudio: Bool {
        role == .audience ? pttActive : micEnabled
    }

    @discardableResult
    private func synchronizeLocalAudioTrack() -> Bool {
        guard active else { return false }
        createLocalAudioTrack()
        guard let audio = localAudioTrack, audio.readyState == .live else { return false }
        audio.isEnabled = shouldSendAudio
        guard let tc = findTransceiver(mid: Self.midAudio, kind: "audio") else { return false }
        if tc.sender.track?.isEqual(audio) != true {
            tc.sender.track = audio
        }
        return tc.sender.track?.isEqual(audio) == true
    }

    private func attachLocalTracks(_ pc: RTCPeerConnection) throws {
        guard synchronizeLocalAudioTrack(), let tc = findTransceiver(mid: Self.midAudio, kind: "audio") else {
            throw NSError(domain: "MezonSfuSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "SFU audio sender unavailable"])
        }
        var directionError: NSError?
        tc.setDirection(.sendOnly, error: &directionError)
        if let directionError { throw directionError }
        if !localTracksAdded, role == .speaker {
            prepareVideoSender(addingTo: pc)
        }
        localTracksAdded = true
    }

    private func handleRoleChanged(_ newRole: SfuRole) {
        guard role != newRole else { return }
        role = newRole
        createLocalAudioTrack()
        let audio = localAudioTrack
        let tc = peerConnection != nil ? findTransceiver(mid: Self.midAudio, kind: "audio") : nil
        if newRole == .speaker {
            micEnabled = true
            audio?.isEnabled = true
            if let tc, let audio {
                tc.sender.track = audio
                setTransceiverDirection(tc, .sendOnly)
            }
            pttActive = true
            onPushToTalkActive?(true)
        } else {
            micEnabled = false
            pttRequested = false
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
        let source = factory.videoSource()
        let track = factory.videoTrack(with: source, trackId: "sfu_camera")
        track.isEnabled = cameraEnabled
        cameraSource = source
        cameraTrack = track
        localCameraTrack = track
    }

    private func prepareVideoSender(addingTo pc: RTCPeerConnection? = nil) {
        ensureCameraTrack()
        guard let cameraTrack else { return }
        if let tc = findTransceiver(mid: Self.midCamera, kind: "video") {
            if tc.sender.track !== cameraTrack {
                tc.sender.track = cameraTrack
                tc.sender.applyCameraTier(cameraTierIndex)
                setTransceiverDirection(tc, .sendOnly)
            }
            return
        }
        guard let pc, let sender = pc.add(cameraTrack, streamIds: ["sfu"]) else { return }
        sender.applyCameraTier(cameraTierIndex)
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
        guard localAudioTrack?.readyState != .live else { return }
        localAudioTrack?.isEnabled = false
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "googNoiseSuppression": "true",
                "googEchoCancellation": "true",
                "googAutoGainControl": "true"
            ],
            optionalConstraints: nil
        )
        let source = factory.audioSource(with: constraints)
        audioSource = source
        let track = factory.audioTrack(with: source, trackId: "sfu_audio")
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
        return factory.peerConnection(with: config, constraints: constraints, delegate: self)
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

    private var isLargeRoom: Bool {
        max(remote.count, max(0, remoteSnapshot.count - 3) / 3) > Self.largeRoomRemoteCount
    }

    private func speakingPollDelayNanos() -> UInt64 {
        isLargeRoom ? Self.largeRoomSpeakingPollNanos : Self.speakingPollNanos
    }

    private func pollSpeaking(_ pc: RTCPeerConnection) {
        guard onSpeaking != nil else { return }
        let localId = userId
        let localAudible = micEnabled || pttActive
        let userIdByMid = self.userIdByMid
        let threshold = Self.speakingThreshold
        Self.requestStatistics(pc) { [weak self] report in
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
            if screenActive && !entry.screenActive {
                entry.screenActiveSince = ProcessInfo.processInfo.systemUptime
                // A new share may reuse the same native receiver. Its previous
                // image must not be replayed as the new share's first frame.
                if let screen = entry.screen {
                    VideoTrackLastFrameStore.clearFrame(of: screen)
                }
            }
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

    private func scheduleRemoteMediaSync() {
        remoteMediaSyncScheduled = true
        guard !remoteMediaSyncRunning, !negotiating, active, let pc = peerConnection else { return }
        let gen = connectionGen
        remoteMediaSyncRunning = true
        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.isCurrentConnection(pc, gen: gen) {
                    self.remoteMediaSyncRunning = false
                }
            }
            while self.remoteMediaSyncScheduled, self.active, self.isCurrentConnection(pc, gen: gen) {
                guard !self.negotiating else { return }
                self.remoteMediaSyncScheduled = false
                let revision = self.remoteMediaRevision
                // Receiver callbacks can arrive after the SDP snapshot was captured.
                let transceivers = await Self.fetchTransceivers(pc)
                guard self.isCurrentConnection(pc, gen: gen) else { return }
                let snapshot = await Self.captureRemoteSnapshot(transceivers)
                guard self.isCurrentConnection(pc, gen: gen) else { return }
                guard !self.negotiating else {
                    self.remoteMediaSyncScheduled = true
                    return
                }
                guard revision == self.remoteMediaRevision else {
                    self.remoteMediaSyncScheduled = true
                    continue
                }
                let oldTransceivers = self.transceiverCache
                let oldTracks = self.remoteSnapshot.compactMap { $0.track }
                self.transceiverCache = transceivers
                self.remoteSnapshot = snapshot
                Self.releaseOffMain(oldTransceivers)
                Self.releaseOffMain(oldTracks)
                self.syncRemoteMedia()
            }
        }
    }

    private nonisolated static func fetchTransceivers(_ pc: RTCPeerConnection) async -> [RTCRtpTransceiver] {
        let box = SfuPeerConnectionBox(peerConnection: pc)
        return await Task.detached(priority: .userInitiated) {
            SfuTransceiverBatch(transceivers: box.peerConnection.transceivers)
        }.value.transceivers
    }

    private nonisolated static func captureRemoteSnapshot(_ transceivers: [RTCRtpTransceiver]) async -> [SfuRemoteTransceiverSnapshot] {
        let batch = SfuTransceiverBatch(transceivers: transceivers)
        return await Task.detached(priority: .userInitiated) {
            batch.transceivers.map { tc -> SfuRemoteTransceiverSnapshot in
                var current = RTCRtpTransceiverDirection.inactive
                let direction = tc.currentDirection(&current) ? current : tc.direction
                let receiving = direction != .inactive && direction != .stopped
                let track = receiving ? tc.receiver.track : nil
                return SfuRemoteTransceiverSnapshot(mid: tc.mid, direction: direction, track: track, trackId: track?.trackId)
            }
        }.value
    }

    private func syncRemoteMedia() {
        for item in remoteSnapshot {
            let mid = item.mid
            if mid.isEmpty { continue }
            if mid == Self.midAudio || mid == Self.midCamera || mid == Self.midScreen { continue }
            let id = remoteParticipantId(mid)
            let kind = remoteKind(mid)
            if item.direction == .inactive || item.direction == .stopped {
                clearRemoteKind(id: id, kind: kind)
                continue
            }
            guard let track = item.track else { continue }
            if kind == "screen", let video = track as? RTCVideoTrack {
                _ = VideoTrackLastFrameStore.observe(video)
            }
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
                if entry.audioTrackId != item.trackId {
                    entry.audio = audio
                    entry.audioTrackId = item.trackId
                }
            } else if kind == "camera", let video = track as? RTCVideoTrack {
                if entry.videoTrackId != item.trackId {
                    entry.video = video
                    entry.videoTrackId = item.trackId
                }
            } else if kind == "screen", let video = track as? RTCVideoTrack {
                let canonical = VideoTrackLastFrameStore.canonicalTrack(video)
                if canonical !== video {
                    ScreenShareTrace.log("track_wrapper_reused", ["generation": connectionGen,
                        "trackId": video.trackId,
                        "trackObject": String(describing: ObjectIdentifier(video)),
                        "canonicalTrackObject": String(describing: ObjectIdentifier(canonical)),
                        "hasCachedFrame": VideoTrackLastFrameStore.cachedFrame(of: canonical) != nil])
                }
                if entry.screenTrackId != item.trackId || entry.screen !== canonical {
                    entry.screen = canonical
                    entry.screenTrackId = item.trackId
                }
            }
            if entry.audio == nil && entry.video == nil && entry.screen == nil {
                removeRemoteEntry(id: id)
            }
        }
        releaseRetiringPeerConnection()
        emitParticipants()
        requestMissingScreenKeyframes()
    }

    private func clearRemoteKind(id: String, kind: String?) {
        guard let entry = remote[id] else { return }
        switch kind {
        case "audio":
            entry.audio = nil
            entry.audioTrackId = nil
        case "camera":
            entry.video = nil
            entry.videoTrackId = nil
        case "screen":
            entry.screen = nil
            entry.screenTrackId = nil
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

    private func applyMsidOwners(_ owners: [SfuMsidOwner]) {
        for owner in owners {
            userIdByMid[owner.mid] = owner.userId
            if let peerId = owner.peerId {
                claimMid(owner.mid, peerId: peerId)
            }
        }
    }

    private nonisolated static func preparedOffer(_ sdp: String, currentRemoteSdp: String?) async -> SfuPreparedOffer {
        await Task.detached(priority: .userInitiated) {
            SfuSdp.prepareOffer(sdp, currentRemoteSdp: currentRemoteSdp)
        }.value
    }

    private nonisolated static func patchedAudienceAnswer(_ sdp: String) async -> String {
        await Task.detached(priority: .userInitiated) {
            SfuSdp.patchingAudienceAnswer(sdp)
        }.value
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

    private nonisolated static func awaitSetRemote(_ pc: RTCPeerConnection, _ desc: RTCSessionDescription) async throws {
        let box = SfuPeerConnectionBox(peerConnection: pc)
        let description = SfuUncheckedBox(value: desc)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sfuWebRTCQueue.async {
                box.peerConnection.setRemoteDescription(description.value) { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: ())
                    }
                }
            }
        }
    }

    private nonisolated static func awaitSetLocal(_ pc: RTCPeerConnection, _ desc: RTCSessionDescription) async throws {
        let box = SfuPeerConnectionBox(peerConnection: pc)
        let description = SfuUncheckedBox(value: desc)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sfuWebRTCQueue.async {
                box.peerConnection.setLocalDescription(description.value) { error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: ())
                    }
                }
            }
        }
    }

    private nonisolated static func awaitCreateAnswer(_ pc: RTCPeerConnection) async throws -> RTCSessionDescription {
        let box = SfuPeerConnectionBox(peerConnection: pc)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RTCSessionDescription, Error>) in
            sfuWebRTCQueue.async {
                let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                box.peerConnection.answer(for: constraints) { sdp, error in
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
    }

    private nonisolated static func remoteDescriptionSdp(_ pc: RTCPeerConnection) async -> String? {
        let box = SfuPeerConnectionBox(peerConnection: pc)
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            sfuWebRTCQueue.async {
                cont.resume(returning: box.peerConnection.remoteDescription?.sdp)
            }
        }
    }

    private nonisolated static func signalingState(_ pc: RTCPeerConnection) async -> RTCSignalingState {
        let box = SfuPeerConnectionBox(peerConnection: pc)
        return await withCheckedContinuation { (cont: CheckedContinuation<RTCSignalingState, Never>) in
            sfuWebRTCQueue.async {
                cont.resume(returning: box.peerConnection.signalingState)
            }
        }
    }

    private nonisolated static func requestStatistics(_ pc: RTCPeerConnection, _ handler: @escaping @Sendable (RTCStatisticsReport) -> Void) {
        let box = SfuPeerConnectionBox(peerConnection: pc)
        sfuWebRTCQueue.async {
            box.peerConnection.statistics(completionHandler: handler)
        }
    }

    private nonisolated static func closeOffMain(_ pc: RTCPeerConnection?) {
        guard let pc else { return }
        let box = SfuPeerConnectionBox(peerConnection: pc)
        sfuWebRTCQueue.async {
            box.peerConnection.close()
        }
    }

    private nonisolated static func releaseOffMain(_ objects: [AnyObject]) {
        guard !objects.isEmpty else { return }
        let batch = SfuUncheckedBox(value: objects)
        sfuWebRTCQueue.async {
            withExtendedLifetime(batch) {}
        }
    }

    private func discardTransceiverState() {
        remoteMediaSyncScheduled = false
        remoteMediaSyncRunning = false
        Self.releaseOffMain(transceiverCache)
        Self.releaseOffMain(remoteSnapshot.compactMap { $0.track })
        transceiverCache = []
        remoteSnapshot = []
    }

    private func rollbackIfStuck(_ pc: RTCPeerConnection) async {
        guard await Self.signalingState(pc) == .haveRemoteOffer else { return }
        try? await Self.awaitSetLocal(pc, RTCSessionDescription(type: .rollback, sdp: ""))
    }

    private static let callKitObserver = CXCallObserver()

    private var callKitCallOwnsAudio: Bool {
        // Cellular and other apps' CallKit calls also interrupt this audio device.
        Self.callKitObserver.calls.contains { !$0.hasEnded }
    }

    private func installAudioRecoveryObservers() {
        let center = NotificationCenter.default
        audioRecoveryObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelAudioResumeRecovery()
            }
        })
        audioRecoveryObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.videoBackgroundedAt = ProcessInfo.processInfo.systemUptime
                self.queuedVideoKeyframes.removeAll()
                self.videoRecoveryChecks.removeAll()
                self.screenKeyframeCheckTask?.cancel()
                self.screenKeyframeCheckTask = nil
            }
        })
        audioRecoveryObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                // iOS can omit interruption-ended while the app is suspended.
                // WebRTC also clears its interruption state on foregrounding.
                self.audioInterrupted = false
                self.scheduleAudioResumeRecovery()
                self.checkVideoAfterForeground()
                self.requestMissingScreenKeyframes()
                if let pc = self.peerConnection {
                    if pc.iceConnectionState == .failed {
                        self.restartSession()
                    } else if pc.iceConnectionState == .disconnected {
                        self.scheduleIceRecovery()
                    }
                }
            }
        })
        audioRecoveryObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            let wasSuspended = Self.interruptionWasSuspended(notification.userInfo)
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.cancelAudioResumeRecovery()
                    // On older iOS, suspension notifications can arrive AFTER
                    // didBecomeActive. They describe a past deactivation, not
                    // another call that we must wait for to finish.
                    self.audioInterrupted = !wasSuspended
                    if wasSuspended {
                        self.scheduleAudioResumeRecovery()
                    }
                } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    self.audioInterrupted = false
                    if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        self.scheduleAudioResumeRecovery()
                    }
                }
            }
        })
        audioRecoveryObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                self.audioInterrupted = false
                self.scheduleAudioResumeRecovery()
            }
        })
    }

    private nonisolated static func interruptionWasSuspended(_ userInfo: [AnyHashable: Any]?) -> Bool {
        if #available(iOS 14.5, *),
           let reason = (userInfo?[AVAudioSessionInterruptionReasonKey] as? NSNumber)?.uintValue,
           reason == AVAudioSession.InterruptionReason.appWasSuspended.rawValue {
            return true
        }
        return (userInfo?[AVAudioSessionInterruptionWasSuspendedKey] as? NSNumber)?.boolValue == true
    }

    @discardableResult
    private func restoreAudioSession(restartAudio: Bool) -> Bool {
        guard active, audioOwnerBlockingRestore == nil else {
            return false
        }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        rtc.useManualAudio = true
        if restartAudio { rtc.isAudioEnabled = false }
        // A stale `isActive == true` does not prove audio I/O is running. On a
        // recovery, balance our activation before reacquiring it. Never release
        // references owned by CallKit, peer calls or streaming sessions.
        if audioRecoveryOwnsActivation && (restartAudio || !rtc.isActive) {
            try? rtc.setActive(false)
            audioRecoveryOwnsActivation = false
        }
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        cfg.mode = AVAudioSession.Mode.voiceChat.rawValue
        let configured = (try? rtc.setConfiguration(cfg)) != nil
        // RTCAudioSession reference-counts every successful setActive(true),
        // including calls made while already active. Own exactly one reference
        // for this SFU session; route/UI updates must not acquire more.
        if !audioRecoveryOwnsActivation, (try? rtc.setActive(true)) != nil {
            audioRecoveryOwnsActivation = true
        }
        let ready = configured && audioRecoveryOwnsActivation && rtc.isActive
        rtc.isAudioEnabled = ready
        return ready
    }

    private func releaseAudioRecoveryActivation() {
        guard audioRecoveryOwnsActivation else { return }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        // Release only our reference, even if another call now owns audio.
        try? rtc.setActive(false)
        audioRecoveryOwnsActivation = false
    }

    private func disableAudioIfIdle() {
        if callKitCallOwnsAudio { return }
        if WebRTCCallManager.shared.signalingSession != nil { return }
        if StreamingWebRTCSession.shared.activeStreamChannelId != nil { return }
        if Self.liveSession != nil && Self.liveSession !== self { return }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        rtc.isAudioEnabled = false
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
                let wasConnected = self.isConnected
                self.isConnected = true
                self.clearJoinWatchdog()
                self.restoreAudioSession(restartAudio: !wasConnected)
                self.schedulePostConnectAudioRecovery(gen: self.connectionGen)
                self.requestMissingScreenKeyframes()
                self.emitState(.connected)
                self.armTransportWatchdog(peerConnection)
            case .failed:
                self.isConnected = false
                self.healthySessionResetTask?.cancel()
                self.healthySessionResetTask = nil
                self.iceRecoveryTask?.cancel()
                self.iceRecoveryTask = nil
                if self.active && self.joined {
                    self.emitState(.disconnected)
                    self.recoverTransport(gen: self.connectionGen)
                } else if self.active {
                    self.emitState(.failed)
                }
            case .disconnected:
                self.isConnected = false
                self.healthySessionResetTask?.cancel()
                self.healthySessionResetTask = nil
                self.emitState(.disconnected)
                self.scheduleIceRecovery()
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
                self.scheduleHealthyConnectionReset()
            case .failed:
                if peerConnection.iceConnectionState == .connected || peerConnection.iceConnectionState == .completed {
                    self.recoverTransport(gen: self.connectionGen)
                    return
                }
                self.isConnected = false
                self.healthySessionResetTask?.cancel()
                self.healthySessionResetTask = nil
                self.clearTransportWatchdog()
                if self.active && self.joined {
                    self.emitState(.disconnected)
                    self.recoverTransport(gen: self.connectionGen)
                }
            case .disconnected, .closed:
                self.healthySessionResetTask?.cancel()
                self.healthySessionResetTask = nil
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        let incomingVideo = SfuUncheckedBox(value: rtpReceiver.track as? RTCVideoTrack)
        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            // Start retaining frames before negotiation/participant UI finishes.
            if let video = incomingVideo.value {
                _ = VideoTrackLastFrameStore.observe(video)
            }
            self.scheduleRemoteMediaSync()
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        let incomingVideo = SfuUncheckedBox(value: transceiver.receiver.track as? RTCVideoTrack)
        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            if let video = incomingVideo.value {
                _ = VideoTrackLastFrameStore.observe(video)
            }
            self.scheduleRemoteMediaSync()
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
