import AVFoundation
import Foundation
import WebRTC

private struct IceCandidateWire: Codable {
    var candidate: String
    var sdpMLineIndex: Int32
    var sdpMid: String?
}

private let peerCallLocalAudioStreamId = "mezon_peer_call_audio"

private final class PeerCallThreadSafeSignalingQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(Int64, Int32, String)] = []
    func append(_ item: (Int64, Int32, String)) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }
    func takeAll() -> [(Int64, Int32, String)] {
        lock.lock()
        let out = items
        items.removeAll()
        lock.unlock()
        return out
    }
}

private final class PeerCallLockFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ v: Bool) {
        lock.lock()
        value = v
        lock.unlock()
    }
}

enum PeerCallDirection {
    case outgoing
    case incoming
}

@MainActor
final class PeerWebRTCCallSession: NSObject {

    let direction: PeerCallDirection
    private let myUserId: Int64
    private let peerUserId: Int64
    private let channelId: Int64
    private let callerDisplayNameForPush: String
    private let callerAvatarURLStringForPush: String

    private var phase: PeerCallPhase
    private var wantsVideo: Bool

    private var peerConnection: RTCPeerConnection?
    private var peerFactory: RTCPeerConnectionFactory?
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?

    private var pendingOutgoingIce: [RTCIceCandidate] = []
    private var pendingRemoteIce: [RTCIceCandidate] = []
    private var pendingRemoteIceJsonBeforePc: [String] = []

    private var pendingOfferCompressed: String?

    private var outgoingRingTimer: DispatchWorkItem?
    private var incomingRingTimer: DispatchWorkItem?
    private var outgoingConnectTimeoutTimer: DispatchWorkItem?
    private var disconnectRecoveryTask: Task<Void, Never>?
    private var deferredRemoteVideoScanTask: Task<Void, Never>?
    private var rescanRemoteVideoDebounceTask: Task<Void, Never>?
    private var beginOutgoingCallTask: Task<Void, Never>?
    private var answerIncomingCallTask: Task<Void, Never>?
    private var strayPreWarmIceFollowupTask: Task<Void, Never>?
    private var isScanningTransceivers = false
    private var delegateDeliveredRemoteVideoTrackIds: [String] = []
    private var lastPublishedRemoteVideoTrackId: String?
    private var remoteVideoInboundBytesProbeTask: Task<Void, Never>?
    private var remoteVideoInboundMonitorTask: Task<Void, Never>?
    private var audioFlowVerifyTask: Task<Void, Never>?
    private var beganAudioFlowVerification = false
    private var lastEmittedRemoteVideoInboundActive = false

    private var ended = false
    private(set) var didEstablishMediaConnection = false
    private var mediaConnectedAt: Date?
    private var ringTimeoutFired = false
    private var connectTimeoutFired = false
    private var remoteQuitBeforeConnect = false
    private var didPostConnectedStatusToUI = false
    private var iceConnectedOrCompletedForUI = false
    private var peerConnectionReportedConnectedForUI = false
    private var didSendConnectedCallerCancelPush = false

    private var isAnswerPrepared = false
    private var preparedAnswerCompressed: String?
    private var isPreWarmingNoSignal = false
    private var preWarmInFlight = false
    private var deferredOutgoingSignaling: [(receiverId: Int64, dataType: Int32, jsonData: String)] = []

    nonisolated private let preWarmBackgroundIceFlag = PeerCallLockFlag()
    nonisolated(unsafe) private let threadSafePreWarmSignaling = PeerCallThreadSafeSignalingQueue()
    nonisolated private let signalingDestinationUserId: Int64

    private var incomingAnswerFlowStarted = false

    private var localMicEnabled = true
    private var localCameraEnabled = false
    private var localSpeakerEnabled = false
    private var pendingCameraRenegotiation = false
    private var preferredCameraPosition: AVCaptureDevice.Position = .front
    private var remoteMicEnabled = true
    private var remoteCameraEnabledFromSignaling = true

    nonisolated private static let sharedPeerConnectionFactory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let enc = RTCDefaultVideoEncoderFactory()
        let dec = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: enc, decoderFactory: dec)
    }()

    nonisolated static func prewarmWebRTCInfrastructure() {
        _ = sharedPeerConnectionFactory
    }

    private static func makePeerConnectionFactory() -> RTCPeerConnectionFactory {
        return sharedPeerConnectionFactory
    }

    private func applyPeerConnectionConfigCommon(_ config: RTCConfiguration) {
        config.sdpSemantics = .unifiedPlan
        config.iceCandidatePoolSize = 10
        config.continualGatheringPolicy = .gatherContinually
        config.iceServers = [
            RTCIceServer(
                urlStrings: [
                    "stun:stun.l.google.com:19302",
                    "stun:stun1.l.google.com:19302",
                ],
                username: nil,
                credential: nil
            ),
            RTCIceServer(
                urlStrings: Self.expandedTurnURLStrings(from: MezonConfig.webRTCIceServerURL),
                username: MezonConfig.webRTCIceUsername,
                credential: MezonConfig.webRTCIceCredential
            ),
        ]
    }

    private static func expandedTurnURLStrings(from base: String) -> [String] {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains("?transport=") || trimmed.hasPrefix("turns:") {
            return [trimmed]
        }
        let core: String = {
            if trimmed.hasPrefix("turn:") {
                return String(trimmed.dropFirst("turn:".count))
            }
            return trimmed
        }()
        return [
            "turn:\(core)?transport=udp",
            "turn:\(core)?transport=tcp",
            "turns:\(core)?transport=tcp",
        ]
    }

    var isVideoCallSession: Bool { wantsVideo }
    var isUsingFrontCamera: Bool { preferredCameraPosition == .front }

    var isSpeakerOn: Bool { localSpeakerEnabled }

    var onStatusLabel: ((String) -> Void)?
    var onCallMediaConnectedAt: ((Date) -> Void)?
    var onEnded: (() -> Void)?
    var onRemoteMedia: ((Bool) -> Void)?
    var onLocalMedia: ((Bool, Bool) -> Void)?
    var onNetworkBanner: ((String?) -> Void)?
    var onRemoteVideoTrack: ((RTCVideoTrack?) -> Void)?
    var onRemoteVideoInboundActive: ((Bool) -> Void)?
    var onLocalVideoTrack: ((RTCVideoTrack?) -> Void)?

    private enum PeerCallPhase {
        case ringing
        case active
    }

    init(
        direction: PeerCallDirection,
        myUserId: Int64,
        peerUserId: Int64,
        channelId: Int64,
        callerDisplayNameForPush: String,
        callerAvatarURLStringForPush: String,
        wantsVideo: Bool,
        incomingStartsRinging: Bool,
        initialCompressedOffer: String?
    ) {
        self.direction = direction
        self.myUserId = myUserId
        self.peerUserId = peerUserId
        self.channelId = channelId
        self.callerDisplayNameForPush = callerDisplayNameForPush
        self.callerAvatarURLStringForPush = callerAvatarURLStringForPush
        self.wantsVideo = wantsVideo
        self.phase = incomingStartsRinging ? .ringing : .active
        self.pendingOfferCompressed = initialCompressedOffer
        self.signalingDestinationUserId = peerUserId
        super.init()
    }


    private func setPreWarmingNoSignal(_ value: Bool) {
        isPreWarmingNoSignal = value
        preWarmBackgroundIceFlag.set(value)
    }

    private func clearPreWarmDeferralPipeline() {
        setPreWarmingNoSignal(false)
        _ = threadSafePreWarmSignaling.takeAll()
    }

    private func ensureCallStillActive() throws {
        if ended || Task.isCancelled {
            throw PeerWebRTCCallSessionError.cancelled
        }
    }

    private func mergeThreadSafePreWarmDeferredIntoDeferredOutgoing() {
        let batch = threadSafePreWarmSignaling.takeAll()
        for item in batch {
            sendRealtimePeerSignaling(receiverId: item.0, dataType: item.1, jsonData: item.2)
        }
    }

    private func flushPreWarmSignalingDirectly() {
        let batch = threadSafePreWarmSignaling.takeAll()
        for item in batch {
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: item.0,
                dataType: item.1,
                jsonData: item.2,
                channelId: channelId,
                callerId: myUserId
            )
        }
    }

    private func sendRealtimePeerSignaling(receiverId: Int64, dataType: Int32, jsonData: String) {
        if isPreWarmingNoSignal && dataType != WebRTCSignalingDataType.sdpQuit {
            deferredOutgoingSignaling.append((receiverId, dataType, jsonData))
            return
        }
        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: receiverId,
            dataType: dataType,
            jsonData: jsonData,
            channelId: channelId,
            callerId: myUserId
        )
    }

    private func flushDeferredOutgoingSignaling() {
        let queued = deferredOutgoingSignaling
        deferredOutgoingSignaling.removeAll()
        for item in queued {
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: item.receiverId,
                dataType: item.dataType,
                jsonData: item.jsonData,
                channelId: channelId,
                callerId: myUserId
            )
        }
    }

    func beginOutgoingCall() {
        onStatusLabel?(direction == .outgoing ? PeerCallLocalizedStrings.statusRinging : "")
        beginOutgoingCallTask?.cancel()
        beginOutgoingCallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let micOk = await Self.requestMicPermission()
            guard !Task.isCancelled, !ended else { return }
            guard micOk else {
                onStatusLabel?(PeerCallLocalizedStrings.errorMicrophoneDenied)
                finishCall(sendQuit: false)
                return
            }
            do {
                try ensureCallStillActive()
                try await startOutgoingPeerConnection()
                try ensureCallStillActive()
                scheduleOutgoingRingTimeout()
            } catch {
                guard !Task.isCancelled, !ended else { return }
                onStatusLabel?(PeerCallLocalizedStrings.errorCouldNotStartCall)
                finishCall(sendQuit: false)
            }
        }
    }

    func scheduleIncomingRingTimeout() {
        cancelIncomingRingTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onStatusLabel?(PeerCallLocalizedStrings.statusMissed)
            self.finishCall(sendQuit: true)
        }
        incomingRingTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
    }

    func rescanRemoteVideoAttachment() {
        rescanRemoteVideoDebounceTask?.cancel()
        rescanRemoteVideoDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, !ended else { return }
            scanTransceiversForRemoteVideo()
        }
    }

    func resyncRemoteAttachmentWithUI() {
        scanTransceiversForRemoteVideo()
    }

    func isSameIncomingPeerCall(channelId ch: Int64, callerId peer: Int64) -> Bool {
        direction == .incoming && channelId == ch && peerUserId == peer
    }

    func isRingingIncomingPeerCallMatching(channelId ch: Int64, callerId peer: Int64) -> Bool {
        direction == .incoming && channelId == ch && peerUserId == peer && phase == .ringing
    }

    func isMatchingPeerCall(channelId ch: Int64, callerId peer: Int64) -> Bool {
        return channelId == ch && peerUserId == peer
    }

    private static func waitForCallKitReadyForIncomingAnswer() async {
        let rtc = RTCAudioSession.sharedInstance()
        if rtc.isActive {
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var token: NSObjectProtocol?
            var finished = false
            let finish: () -> Void = {
                guard !finished else { return }
                finished = true
                if let token { NotificationCenter.default.removeObserver(token) }
                cont.resume()
            }
            token = NotificationCenter.default.addObserver(
                forName: .mezonCallKitAudioActivated,
                object: nil,
                queue: .main
            ) { _ in
                finish()
            }
            Task { @MainActor in
                for _ in 0..<80 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    if RTCAudioSession.sharedInstance().isActive {
                        finish()
                        return
                    }
                }
                finish()
            }
        }
    }

    private func configureAudioSessionWithIncomingRetry() async throws {
        do {
            try configureAudioSession()
        } catch {
            guard direction == .incoming else { throw error }
            try await Task.sleep(nanoseconds: 320_000_000)
            try configureAudioSession()
        }
    }

    func answerIncomingCall() {
        guard !incomingAnswerFlowStarted else { return }
        incomingAnswerFlowStarted = true
        cancelIncomingRingTimer()
        PeerCallSoundPlayer.shared.stopRinging()
        onStatusLabel?(PeerCallLocalizedStrings.statusConnecting)
        answerIncomingCallTask?.cancel()
        answerIncomingCallTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let micOk = await Self.requestMicPermission()
            guard !Task.isCancelled, !ended else { return }
            guard micOk else {
                onStatusLabel?(PeerCallLocalizedStrings.errorMicrophoneDenied)
                finishCall(sendQuit: true)
                return
            }
            do {
                try await waitForIncomingOfferIfNeeded()
                try ensureCallStillActive()
                await Self.waitForCallKitReadyForIncomingAnswer()
                try ensureCallStillActive()
                try await configureAudioSessionWithIncomingRetry()
                try ensureCallStillActive()
                await waitForPreWarmCompletionIfActive()
                try ensureCallStillActive()
                if !isAnswerPrepared, peerConnection != nil {
                    resetAfterFailedPreWarm()
                }
                if isAnswerPrepared, peerConnection != nil {
                    try sendPreparedAnswerAndGoActive()
                } else {
                    try await buildIncomingPeerConnectionAndAnswer()
                }
            } catch {
                guard !Task.isCancelled, !ended else { return }
                onStatusLabel?(PeerCallLocalizedStrings.errorCouldNotAnswerCall)
                finishCall(sendQuit: true)
            }
        }
    }

    func prepareIncomingAnswerInBackground() async throws {
        guard !ended, !isAnswerPrepared, peerConnection == nil, !preWarmInFlight else { return }
        guard direction == .incoming else { return }
        guard let offerCompressed = pendingOfferCompressed?.trimmingCharacters(in: .whitespacesAndNewlines),
              !offerCompressed.isEmpty else {
            return
        }

        preWarmInFlight = true
        setPreWarmingNoSignal(true)
        do {
            try await performPreWarmBuild(offerCompressed: offerCompressed)
            preWarmInFlight = false
        } catch {
            preWarmInFlight = false
            resetAfterFailedPreWarm()
            throw error
        }
    }

    private func performPreWarmBuild(offerCompressed: String) async throws {
        try ensureCallStillActive()
        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory

        let config = RTCConfiguration()
        applyPeerConnectionConfigCommon(config)

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        peerConnection = pc

        try buildAudioVideoTracks(factory: factory)
        try ensureCallStillActive()

        let remoteOffer = try parseRemoteSessionDescription(compressedOrPlain: offerCompressed)
        let offerHasVideo = IncomingPeerCallPayloadParser.sdpContainsVideo(remoteOffer.sdp)

        try await setPeerRemoteDescription(remoteOffer)
        try ensureCallStillActive()
        attachLocalTracksAfterRemoteOffer(offerHasVideo: offerHasVideo)

        for json in pendingRemoteIceJsonBeforePc {
            await applyRemoteIceCandidatePayload(json)
        }
        pendingRemoteIceJsonBeforePc.removeAll()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.answer(for: constraints) { sdp, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let sdp else {
                    cont.resume(throwing: PeerWebRTCCallSessionError.missingSDP)
                    return
                }
                pc.setLocalDescription(sdp) { err in
                    if let err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
        try ensureCallStillActive()

        mergeThreadSafePreWarmDeferredIntoDeferredOutgoing()

        guard let localSDP = pc.localDescription else {
            throw PeerWebRTCCallSessionError.missingSDP
        }
        let answerJson = try answerJSONString(from: localSDP)
        let compressedAnswer = try PeerWebRTCStringCompression.gzipCompressUtf8(answerJson)
        preparedAnswerCompressed = compressedAnswer
        isAnswerPrepared = true
    }

    private func resetAfterFailedPreWarm() {
        clearPreWarmDeferralPipeline()
        isAnswerPrepared = false
        preparedAnswerCompressed = nil
        deferredOutgoingSignaling.removeAll()
        peerConnection?.close()
        peerConnection = nil
        peerFactory = nil
        videoCapturer?.stopCapture(completionHandler: {})
        videoCapturer = nil
        localVideoTrack = nil
        localAudioTrack?.isEnabled = false
        localAudioTrack = nil
        pendingOutgoingIce.removeAll()
        pendingRemoteIce.removeAll()
        pendingCameraRenegotiation = false
    }

    private func sendPreparedAnswerAndGoActive() throws {
        try ensureCallStillActive()
        guard let pc = peerConnection else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        guard let compressedAnswer = preparedAnswerCompressed else {
            throw PeerWebRTCCallSessionError.missingSDP
        }
        mergeThreadSafePreWarmDeferredIntoDeferredOutgoing()
        setPreWarmingNoSignal(false)
        preparedAnswerCompressed = nil
        isAnswerPrepared = false

        sendRealtimePeerSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpAnswer,
            jsonData: compressedAnswer
        )
        flushDeferredOutgoingSignaling()
        flushPreWarmSignalingDirectly()
        forwardLocalMediaStatus()
        phase = .active
        flushPendingOutgoingIceIfPossible()
        drainPendingRemoteIce()
        bindLocalAudioForOutbound(pc: pc)
        emitLocalMediaState()
        onLocalVideoTrack?(nil)
        scanTransceiversForRemoteVideo()
        scheduleDeferredRemoteVideoScan()
        scheduleRemoteVideoPostConnectWork()
        scheduleStrayPreWarmIceFollowupFlush()
    }

    private func scheduleStrayPreWarmIceFollowupFlush() {
        strayPreWarmIceFollowupTask?.cancel()
        strayPreWarmIceFollowupTask = Task { @MainActor [weak self] in
            for delayNs in [120_000_000, 360_000_000, 900_000_000] {
                try? await Task.sleep(nanoseconds: UInt64(delayNs))
                guard let self, !self.ended else { return }
                guard !Task.isCancelled else { return }
                self.flushPreWarmSignalingDirectly()
            }
        }
    }

    private func waitForIncomingOfferIfNeeded() async throws {
        guard direction == .incoming else { return }
        for _ in 0..<100 {
            if let p = pendingOfferCompressed?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw PeerWebRTCCallSessionError.missingSDP
    }

    private func waitForPreWarmCompletionIfActive() async {
        for _ in 0..<60 {
            if !preWarmInFlight { return }
            if isAnswerPrepared { return }
            if ended { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func signalingMessageTargetsThisSession(_ msg: Mezon_Realtime_WebrtcSignalingFwd) -> Bool {
        let c = msg.callerID
        let r = msg.receiverID
        if c == myUserId { return false }
        return c == peerUserId && (r == myUserId || r == 0)
    }

    func declineIncoming() {
        cancelIncomingRingTimer()
        PeerCallSoundPlayer.shared.stopRinging()
        finishCall(sendQuit: true)
    }

    func handleIncomingSignaling(_ msg: Mezon_Realtime_WebrtcSignalingFwd) {
        guard msg.channelID == channelId else {
            return
        }
        guard signalingMessageTargetsThisSession(msg) else {
            return
        }

        switch msg.dataType {
        case WebRTCSignalingDataType.sdpOffer:
            if phase == .ringing {
                let existing = pendingOfferCompressed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if existing.isEmpty {
                    let next = msg.jsonData.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !next.isEmpty {
                        pendingOfferCompressed = next
                    }
                }
                return
            }
            Task {
                await handleRenegotiationOffer(msg.jsonData)
            }
        case WebRTCSignalingDataType.sdpAnswer:
            Task {
                await applyCompressedAnswer(msg.jsonData)
            }
        case WebRTCSignalingDataType.iceCandidate:
            Task {
                await queueOrApplyIce(msg.jsonData)
            }
        case WebRTCSignalingDataType.sdpStatusRemoteMedia:
            guard msg.callerID == peerUserId else { return }
            applyRemoteMediaWire(msg.jsonData)
        case WebRTCSignalingDataType.sdpJoinedOtherCall:
            if !didEstablishMediaConnection {
                remoteQuitBeforeConnect = true
                onStatusLabel?(PeerCallLocalizedStrings.statusBusyOnAnotherCall)
            }
            finishCall(sendQuit: false)
        case WebRTCSignalingDataType.sdpNotAvailable:
            if !didEstablishMediaConnection {
                remoteQuitBeforeConnect = true
                onStatusLabel?(PeerCallLocalizedStrings.statusUserOffline)
            }
            finishCall(sendQuit: false)
        case WebRTCSignalingDataType.sdpTimeout:
            if !didEstablishMediaConnection {
                ringTimeoutFired = true
                onStatusLabel?(PeerCallLocalizedStrings.statusNoAnswer)
            }
            finishCall(sendQuit: false)
        case WebRTCSignalingDataType.sdpQuit:
            if !didEstablishMediaConnection {
                remoteQuitBeforeConnect = true
                onStatusLabel?(PeerCallLocalizedStrings.statusRemoteDeclined)
            } else {
                onStatusLabel?(PeerCallLocalizedStrings.statusRemoteEnded)
            }
            finishCall(sendQuit: false)
        case WebRTCSignalingDataType.clearCall:
            finishCall(sendQuit: false)
        default:
            break
        }
    }

    func hangUp() {
        finishCall(sendQuit: true)
    }

    func toggleMicrophoneEnabled() {
        localMicEnabled.toggle()
        localAudioTrack?.isEnabled = localMicEnabled
        if let pc = peerConnection {
            bindLocalAudioForOutbound(pc: pc)
        }
        forwardLocalMediaStatus()
        onLocalMedia?(localMicEnabled, localCameraEnabled)
    }

    func toggleSpeaker() {
        localSpeakerEnabled.toggle()
        try? applySpeakerOutputRoute()
    }

    func switchCamera() {
        guard videoCapturer != nil, localVideoTrack != nil, localCameraEnabled else { return }
        preferredCameraPosition = preferredCameraPosition == .front ? .back : .front
        videoCapturer?.stopCapture(completionHandler: { [weak self] in
            Task { @MainActor in
                try? self?.startCameraCaptureIfNeeded()
            }
        })
    }

    func toggleCameraEnabled() {
        if localCameraEnabled {
            localCameraEnabled = false
            videoCapturer?.stopCapture(completionHandler: {})
            localVideoTrack?.isEnabled = false
            onLocalVideoTrack?(nil)
            forwardLocalMediaStatus()
            onLocalMedia?(localMicEnabled, localCameraEnabled)
            return
        }
        Task {
            let ok = await Self.requestCameraPermission()
            guard ok else {
                onStatusLabel?(PeerCallLocalizedStrings.errorCameraDenied)
                return
            }
            await enableCameraMidCall()
        }
    }

    private func enableCameraMidCall() async {
        guard let pc = peerConnection, let factory = peerFactory else {
            return
        }
        guard phase == .active else {
            return
        }
        do {
            try configureAudioSession()
            var needsRenegotiation = false
            var addedVideoTransceiver = false
            let videoTrackExistedDisabled = localVideoTrack.map { !$0.isEnabled } ?? false
            if localVideoTrack == nil {
                try setupLocalVideo(factory: factory)
                guard let vt = localVideoTrack else {
                    return
                }
                let vi = RTCRtpTransceiverInit()
                vi.direction = .sendRecv
                pc.addTransceiver(with: vt, init: vi)
                needsRenegotiation = true
                addedVideoTransceiver = true
            } else if videoTrackExistedDisabled {
                needsRenegotiation = true
            }
            localVideoTrack?.isEnabled = true
            try? configureAudioSession()
            try startCameraCaptureIfNeeded()
            localCameraEnabled = true
            if !localSpeakerEnabled && !hasExternalAudioOutputRoute {
                localSpeakerEnabled = true
                try? configureAudioSession()
            }
            bindLocalVideoForOutbound(pc: pc)
            forwardLocalMediaStatus()
            onLocalMedia?(localMicEnabled, localCameraEnabled)
            if let vt = localVideoTrack {
                onLocalVideoTrack?(vt)
            }
            if needsRenegotiation {
                if pc.remoteDescription != nil {
                    pendingCameraRenegotiation = false
                    try await createAndSendOffer()
                } else if addedVideoTransceiver {
                    pendingCameraRenegotiation = true
                }
            }
        } catch {
            videoCapturer?.stopCapture(completionHandler: {})
            localVideoTrack?.isEnabled = false
            localCameraEnabled = false
            onLocalVideoTrack?(nil)
            onLocalMedia?(localMicEnabled, false)
            onStatusLabel?(PeerCallLocalizedStrings.errorCouldNotStartCall)
        }
    }

    private func createAndSendOffer() async throws {
        guard let pc = peerConnection else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.offer(for: constraints) { sdp, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let sdp else {
                    cont.resume(throwing: PeerWebRTCCallSessionError.missingSDP)
                    return
                }
                pc.setLocalDescription(sdp) { err in
                    if let err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
        guard let localSDP = pc.localDescription else {
            throw PeerWebRTCCallSessionError.missingSDP
        }
        let json = try offerJSONString(from: localSDP)
        let compressed = try PeerWebRTCStringCompression.gzipCompressUtf8(json)
        sendRealtimePeerSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpOffer,
            jsonData: compressed
        )
        flushPendingOutgoingIceIfPossible()
        bindLocalAudioForOutbound(pc: pc)
        if localCameraEnabled {
            bindLocalVideoForOutbound(pc: pc)
        }
    }

    private func finishCall(sendQuit: Bool) {
        guard !ended else { return }
        ended = true
        clearPreWarmDeferralPipeline()
        preWarmInFlight = false
        incomingAnswerFlowStarted = false
        PeerCallSoundPlayer.shared.stopAll()
        cancelOutgoingRingTimer()
        cancelIncomingRingTimer()
        cancelOutgoingConnectTimeout()
        disconnectRecoveryTask?.cancel()
        disconnectRecoveryTask = nil
        beginOutgoingCallTask?.cancel()
        beginOutgoingCallTask = nil
        answerIncomingCallTask?.cancel()
        answerIncomingCallTask = nil
        strayPreWarmIceFollowupTask?.cancel()
        strayPreWarmIceFollowupTask = nil

        if direction == .outgoing {
            let reason: PeerCallEndReason
            let durationSeconds: Int?
            if didEstablishMediaConnection, let connectedAt = mediaConnectedAt {
                reason = .finished
                durationSeconds = max(0, Int(Date().timeIntervalSince(connectedAt)))
            } else if remoteQuitBeforeConnect {
                reason = .remoteReject
                durationSeconds = nil
            } else if ringTimeoutFired || connectTimeoutFired {
                reason = .timeout
                durationSeconds = nil
            } else {
                reason = .userCancel
                durationSeconds = nil
            }
            PeerCallLogMessage.updateCallLogForOutgoing(
                channelId: channelId,
                reason: reason,
                durationSeconds: durationSeconds
            )
        }

        if direction == .outgoing && sendQuit && !didEstablishMediaConnection {
            let body: [String: Any] = [
                "offer": "CANCEL_CALL",
                "callerId": "\(myUserId)",
                "channelId": "\(channelId)",
                "receiverId": "\(peerUserId)",
                "sentAt": "\(Int64(Date().timeIntervalSince1970 * 1000))",
            ]
            if let data = try? JSONSerialization.data(withJSONObject: body),
               let s = String(data: data, encoding: .utf8) {
                MezonSocket.shared.makeCallPush(
                    receiverId: peerUserId,
                    jsonData: s,
                    channelId: channelId,
                    callerId: myUserId
                )
            }
        }

        if sendQuit {
            sendRealtimePeerSignaling(
                receiverId: peerUserId,
                dataType: WebRTCSignalingDataType.sdpQuit,
                jsonData: ""
            )
        }
        if direction == .incoming {
            CallKitManager.shared.clearVoipQuitSnapshot()
        }
        tearDownResources()
        WebRTCCallManager.shared.detachSession(self)
        onEnded?()
    }

    private func tearDownResources() {
        deferredRemoteVideoScanTask?.cancel()
        deferredRemoteVideoScanTask = nil
        rescanRemoteVideoDebounceTask?.cancel()
        rescanRemoteVideoDebounceTask = nil
        remoteVideoInboundBytesProbeTask?.cancel()
        remoteVideoInboundBytesProbeTask = nil
        remoteVideoInboundMonitorTask?.cancel()
        remoteVideoInboundMonitorTask = nil
        audioFlowVerifyTask?.cancel()
        audioFlowVerifyTask = nil
        lastEmittedRemoteVideoInboundActive = false
        pendingCameraRenegotiation = false
        onRemoteVideoInboundActive?(false)
        isScanningTransceivers = false
        delegateDeliveredRemoteVideoTrackIds.removeAll()
        lastPublishedRemoteVideoTrackId = nil
        remoteCameraEnabledFromSignaling = true
        videoCapturer?.stopCapture(completionHandler: {})
        videoCapturer = nil
        localVideoTrack = nil
        localAudioTrack?.isEnabled = false
        localAudioTrack = nil
        pendingOutgoingIce.removeAll()
        pendingRemoteIce.removeAll()
        pendingRemoteIceJsonBeforePc.removeAll()
        peerConnection?.close()
        peerConnection = nil
        peerFactory = nil
        let rtcAudio = RTCAudioSession.sharedInstance()
        rtcAudio.lockForConfiguration()
        defer { rtcAudio.unlockForConfiguration() }
        rtcAudio.isAudioEnabled = false
        try? rtcAudio.setActive(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        onRemoteVideoTrack?(nil)
        onLocalVideoTrack?(nil)
    }

    private static func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

    private static func requestCameraPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .video) { ok in
                cont.resume(returning: ok)
            }
        }
    }

    private func configureAudioSession() throws {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        let useVideoChat = wantsVideo || localVideoTrack != nil || localCameraEnabled
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        let audioMode: AVAudioSession.Mode = {
            if localSpeakerEnabled {
                return useVideoChat ? .videoChat : .voiceChat
            }
            return .voiceChat
        }()
        cfg.mode = audioMode.rawValue
        if localSpeakerEnabled {
            cfg.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        } else {
            cfg.categoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        }
        let wasActive = rtc.isActive
        // For outgoing calls we need to activate the session ourselves.
        // For incoming calls CallKit owns activation: passing active=false here
        // would make WebRTC call setActive(NO) on the session CallKit just
        // activated, which deactivates audio I/O and leaves the call connected
        // but mute. Preserve the CallKit-activated state instead.
        let activateSelf: Bool = (direction == .outgoing) ? true : wasActive
        try rtc.setConfiguration(cfg, active: activateSelf)
        if rtc.isActive {
            rtc.isAudioEnabled = true
            let port: AVAudioSession.PortOverride = localSpeakerEnabled ? .speaker : .none
            try? rtc.overrideOutputAudioPort(port)
        }
    }

    private func applySpeakerOutputRoute() throws {
        try configureAudioSession()
    }

    private var hasExternalAudioOutputRoute: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio, .carAudio, .airPlay:
                return true
            default:
                return false
            }
        }
    }

    private func scheduleOutgoingRingTimeout() {
        cancelOutgoingRingTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.ringTimeoutFired = true
            self.onStatusLabel?(PeerCallLocalizedStrings.statusNoAnswer)
            self.finishCall(sendQuit: true)
        }
        outgoingRingTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        scheduleOutgoingConnectTimeout()
    }

    private func cancelOutgoingRingTimer() {
        outgoingRingTimer?.cancel()
        outgoingRingTimer = nil
    }

    private func scheduleOutgoingConnectTimeout() {
        cancelOutgoingConnectTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.ended, !self.didEstablishMediaConnection else { return }
            self.connectTimeoutFired = true
            self.onStatusLabel?(PeerCallLocalizedStrings.statusCouldNotConnect)
            self.finishCall(sendQuit: true)
        }
        outgoingConnectTimeoutTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 22, execute: work)
    }

    private func cancelOutgoingConnectTimeout() {
        outgoingConnectTimeoutTimer?.cancel()
        outgoingConnectTimeoutTimer = nil
    }

    private func cancelIncomingRingTimer() {
        incomingRingTimer?.cancel()
        incomingRingTimer = nil
    }

    private func buildAudioVideoTracks(factory: RTCPeerConnectionFactory) throws {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: constraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "peer_audio_\(UUID().uuidString.prefix(8))")
        localAudioTrack = audioTrack
        localMicEnabled = true
        audioTrack.isEnabled = true

        if wantsVideo {
            try setupLocalVideo(factory: factory)
        }
    }

    private func setupLocalVideo(factory: RTCPeerConnectionFactory) throws {
        let source = factory.videoSource()
        let capturer = RTCCameraVideoCapturer(delegate: source)
        videoCapturer = capturer
        let track = factory.videoTrack(with: source, trackId: "peer_video_\(UUID().uuidString.prefix(8))")
        localVideoTrack = track
        localCameraEnabled = false
        track.isEnabled = false
    }

    private func setPeerRemoteDescription(_ sd: RTCSessionDescription) async throws {
        guard let pc = peerConnection else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sd) { err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume()
                }
            }
        }
    }

    private func rtpTransceiverSetSendRecv(_ tx: RTCRtpTransceiver) {
        var err: NSError?
        tx.setDirection(.sendRecv, error: &err)
    }

    private func bindLocalAudioForOutbound(pc: RTCPeerConnection) {
        guard let at = localAudioTrack else { return }
        let aTx = pc.transceivers.filter { $0.mediaType == .audio && !$0.isStopped }
        var picked: RTCRtpTransceiver?
        for tx in aTx {
            if (tx.sender.track as? RTCAudioTrack) === at {
                picked = tx
                break
            }
        }
        if picked == nil {
            for tx in aTx where tx.sender.track == nil {
                picked = tx
                break
            }
        }
        if picked == nil {
            for tx in aTx {
                var cur = RTCRtpTransceiverDirection.inactive
                if tx.currentDirection(&cur) {
                    if cur == .sendOnly || cur == .sendRecv {
                        picked = tx
                        break
                    }
                }
            }
        }
        if picked == nil {
            picked = aTx.first
        }
        guard let tx = picked else {
            return
        }
        tx.sender.track = at
        if tx.sender.streamIds.isEmpty {
            tx.sender.streamIds = [peerCallLocalAudioStreamId]
        }
        rtpTransceiverSetSendRecv(tx)
        at.isEnabled = localMicEnabled
    }

    private func bindLocalVideoForOutbound(pc: RTCPeerConnection) {
        guard let vt = localVideoTrack else {
            return
        }
        let vTx = pc.transceivers.filter { $0.mediaType == .video && !$0.isStopped }
        guard !vTx.isEmpty else {
            return
        }
        var picked: RTCRtpTransceiver?
        for tx in vTx where (tx.sender.track as? RTCVideoTrack) === vt {
            picked = tx
            break
        }
        func currentDir(_ tx: RTCRtpTransceiver) -> RTCRtpTransceiverDirection {
            var cur = RTCRtpTransceiverDirection.inactive
            if tx.currentDirection(&cur) {
                return cur
            }
            return .inactive
        }
        func allowsOutboundSend(_ tx: RTCRtpTransceiver) -> Bool {
            currentDir(tx) != .recvOnly
        }
        if picked == nil {
            for tx in vTx.reversed() {
                guard allowsOutboundSend(tx) else { continue }
                if tx.sender.track == nil || (tx.sender.track as? RTCVideoTrack) === vt {
                    picked = tx
                    break
                }
            }
        }
        if picked == nil {
            for tx in vTx {
                guard allowsOutboundSend(tx) else { continue }
                if tx.sender.track == nil || (tx.sender.track as? RTCVideoTrack) === vt {
                    picked = tx
                    break
                }
            }
        }
        if picked == nil {
            for tx in vTx.reversed() where tx.sender.track == nil && allowsOutboundSend(tx) {
                picked = tx
                break
            }
        }
        if picked == nil {
            picked = vTx.last
        }
        guard let tx = picked else {
            return
        }
        tx.sender.track = vt
        if tx.sender.streamIds.isEmpty {
            tx.sender.streamIds = ["mezon_local_video"]
        }
        rtpTransceiverSetSendRecv(tx)
        vt.isEnabled = localCameraEnabled
    }

    private func attachLocalTracksAfterRemoteOffer(offerHasVideo: Bool) {
        guard let pc = peerConnection, localAudioTrack != nil else { return }
        bindLocalAudioForOutbound(pc: pc)
        if offerHasVideo, wantsVideo, localVideoTrack != nil {
            bindLocalVideoForOutbound(pc: pc)
        }
    }

    private func startCameraCaptureIfNeeded() throws {
        guard let capturer = videoCapturer else { return }
        guard let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == preferredCameraPosition })
                ?? RTCCameraVideoCapturer.captureDevices().first
        else {
            throw PeerWebRTCCallSessionError.captureFailed
        }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device) as [AVCaptureDevice.Format]
        guard let picked = Self.selectCaptureFormat(
            from: formats,
            maxWidth: 960,
            preferredPixelFormat: capturer.preferredOutputPixelFormat()
        ) else {
            throw PeerWebRTCCallSessionError.captureFailed
        }
        let fps = Self.selectCaptureFps(for: picked, desired: 30)
        capturer.startCapture(with: device, format: picked, fps: fps) { _ in }
    }

    private static func selectCaptureFormat(
        from formats: [AVCaptureDevice.Format],
        maxWidth: Int32,
        preferredPixelFormat: FourCharCode
    ) -> AVCaptureDevice.Format? {
        guard !formats.isEmpty else { return nil }
        var best: AVCaptureDevice.Format?
        var bestWidth: Int32 = -1
        for format in formats {
            let dim = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dim.width <= maxWidth else { continue }
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            if dim.width > bestWidth {
                best = format
                bestWidth = dim.width
            } else if dim.width == bestWidth,
                      pixelFormat == preferredPixelFormat,
                      let current = best,
                      CMFormatDescriptionGetMediaSubType(current.formatDescription) != preferredPixelFormat {
                best = format
            }
        }
        return best ?? formats.last
    }

    private static func selectCaptureFps(for format: AVCaptureDevice.Format, desired: Double) -> Int {
        var maxRate: Double = 0
        var minRate = Double.greatestFiniteMagnitude
        for range in format.videoSupportedFrameRateRanges {
            maxRate = max(maxRate, range.maxFrameRate)
            minRate = min(minRate, range.minFrameRate)
        }
        guard maxRate > 0 else { return Int(desired) }
        var fps = min(desired, maxRate)
        if minRate != .greatestFiniteMagnitude {
            fps = max(fps, minRate)
        }
        return max(1, Int(fps.rounded()))
    }

    private func startOutgoingPeerConnection() async throws {
        try ensureCallStillActive()
        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory

        let config = RTCConfiguration()
        applyPeerConnectionConfigCommon(config)

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        peerConnection = pc

        try buildAudioVideoTracks(factory: factory)
        try ensureCallStillActive()

        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = .sendRecv
        audioInit.streamIds = [peerCallLocalAudioStreamId]
        guard let at = localAudioTrack else { throw PeerWebRTCCallSessionError.peerConnectionCreateFailed }
        pc.addTransceiver(with: at, init: audioInit)

        if wantsVideo, let vt = localVideoTrack {
            let vi = RTCRtpTransceiverInit()
            vi.direction = .sendRecv
            pc.addTransceiver(with: vt, init: vi)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.offer(for: constraints) { sdp, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let sdp else {
                    cont.resume(throwing: PeerWebRTCCallSessionError.missingSDP)
                    return
                }
                pc.setLocalDescription(sdp) { err in
                    if let err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
        try ensureCallStillActive()

        guard let localSDP = pc.localDescription else {
            throw PeerWebRTCCallSessionError.missingSDP
        }

        let json = try offerJSONString(from: localSDP)
        let compressed = try PeerWebRTCStringCompression.gzipCompressUtf8(json)

        sendRealtimePeerSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpOffer,
            jsonData: compressed
        )

        let pushBody = MakeCallPushBody(
            offer: compressed,
            callerName: callerDisplayNameForPush,
            callerAvatar: callerAvatarURLStringForPush,
            callerId: "\(myUserId)",
            channelId: "\(channelId)",
            sentAt: "\(Int64(Date().timeIntervalSince1970 * 1000))"
        )
        let pushData = try JSONEncoder().encode(pushBody)
        guard let pushJson = String(data: pushData, encoding: .utf8) else {
            throw PeerWebRTCCallSessionError.encodingFailed
        }

        MezonSocket.shared.makeCallPush(
            receiverId: peerUserId,
            jsonData: pushJson,
            channelId: channelId,
            callerId: myUserId
        )

        if wantsVideo, localVideoTrack != nil {
            forwardLocalMediaStatus()
        }

        phase = .active
        flushPendingOutgoingIceIfPossible()
        drainPendingRemoteIce()
        bindLocalAudioForOutbound(pc: pc)
        emitLocalMediaState()
        onLocalVideoTrack?(nil)
        scanTransceiversForRemoteVideo()
        scheduleDeferredRemoteVideoScan()
        scheduleRemoteVideoPostConnectWork()
    }

    private func buildIncomingPeerConnectionAndAnswer() async throws {
        try ensureCallStillActive()
        guard let offerCompressed = pendingOfferCompressed, !offerCompressed.isEmpty else {
            throw PeerWebRTCCallSessionError.missingSDP
        }

        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory

        let config = RTCConfiguration()
        applyPeerConnectionConfigCommon(config)

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        peerConnection = pc

        try buildAudioVideoTracks(factory: factory)
        try ensureCallStillActive()

        let remoteOffer = try parseRemoteSessionDescription(compressedOrPlain: offerCompressed)
        let offerHasVideo = IncomingPeerCallPayloadParser.sdpContainsVideo(remoteOffer.sdp)

        try await setPeerRemoteDescription(remoteOffer)
        try ensureCallStillActive()
        attachLocalTracksAfterRemoteOffer(offerHasVideo: offerHasVideo)

        for json in pendingRemoteIceJsonBeforePc {
            await applyRemoteIceCandidatePayload(json)
        }
        pendingRemoteIceJsonBeforePc.removeAll()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.answer(for: constraints) { sdp, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let sdp else {
                    cont.resume(throwing: PeerWebRTCCallSessionError.missingSDP)
                    return
                }
                pc.setLocalDescription(sdp) { err in
                    if let err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
        }
        try ensureCallStillActive()

        guard let localSDP = pc.localDescription else {
            throw PeerWebRTCCallSessionError.missingSDP
        }

        let answerJson = try answerJSONString(from: localSDP)
        let compressedAnswer = try PeerWebRTCStringCompression.gzipCompressUtf8(answerJson)

        sendRealtimePeerSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpAnswer,
            jsonData: compressedAnswer
        )

        forwardLocalMediaStatus()

        phase = .active
        flushPendingOutgoingIceIfPossible()
        drainPendingRemoteIce()
        bindLocalAudioForOutbound(pc: pc)
        emitLocalMediaState()
        onLocalVideoTrack?(nil)
        scanTransceiversForRemoteVideo()
        scheduleDeferredRemoteVideoScan()
        scheduleRemoteVideoPostConnectWork()
    }

    private func offerJSONString(from sd: RTCSessionDescription) throws -> String {
        let typeStr: String
        switch sd.type {
        case .offer: typeStr = "offer"
        case .answer: typeStr = "answer"
        case .prAnswer: typeStr = "pranswer"
        default: typeStr = "offer"
        }
        let dict: [String: Any] = [
            "type": typeStr,
            "sdp": sd.sdp,
            "callerName": callerDisplayNameForPush,
            "callerAvatar": callerAvatarURLStringForPush,
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        guard let s = String(data: data, encoding: .utf8) else {
            throw PeerWebRTCCallSessionError.encodingFailed
        }
        return s
    }

    private func answerJSONString(from sd: RTCSessionDescription) throws -> String {
        let typeStr: String
        switch sd.type {
        case .offer: typeStr = "offer"
        case .answer: typeStr = "answer"
        case .prAnswer: typeStr = "pranswer"
        default: typeStr = "answer"
        }
        let dict: [String: Any] = ["type": typeStr, "sdp": sd.sdp]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        guard let s = String(data: data, encoding: .utf8) else {
            throw PeerWebRTCCallSessionError.encodingFailed
        }
        return s
    }

    private func parseRemoteSessionDescription(compressedOrPlain: String) throws -> RTCSessionDescription {
        let rawJson = try PeerWebRTCStringCompression.decompressSignalingJson(compressedOrPlain)
        guard let data = rawJson.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeStr = obj["type"] as? String,
              let sdp = obj["sdp"] as? String
        else {
            throw PeerWebRTCCallSessionError.badSDPJson
        }

        let type: RTCSdpType
        switch typeStr {
        case "offer": type = .offer
        case "answer": type = .answer
        case "pranswer": type = .prAnswer
        default: type = .offer
        }

        return RTCSessionDescription(type: type, sdp: sdp)
    }

    private func applyCompressedAnswer(_ payload: String) async {
        guard !ended else { return }
        guard let pc = peerConnection else { return }
        do {
            let answer = try parseRemoteSessionDescription(compressedOrPlain: payload)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                pc.setRemoteDescription(answer) { err in
                    if let err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
            guard !ended else { return }
            flushPendingOutgoingIceIfPossible()
            drainPendingRemoteIce()
            bindLocalAudioForOutbound(pc: pc)
            if localCameraEnabled {
                bindLocalVideoForOutbound(pc: pc)
            }
            scanTransceiversForRemoteVideo()
            scheduleDeferredRemoteVideoScan()
            scheduleRemoteVideoPostConnectWork()
            if pendingCameraRenegotiation {
                pendingCameraRenegotiation = false
                try? await createAndSendOffer()
                if localCameraEnabled, let vt = localVideoTrack {
                    onLocalMedia?(localMicEnabled, localCameraEnabled)
                    onLocalVideoTrack?(vt)
                }
            }
        } catch {
        }
    }

    private func handleRenegotiationOffer(_ payload: String) async {
        guard !ended else { return }
        guard let pc = peerConnection else { return }
        guard phase == .active else { return }
        do {
            let offer = try parseRemoteSessionDescription(compressedOrPlain: payload)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                pc.setRemoteDescription(offer) { err in
                    if let err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
            guard !ended else { return }
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                pc.answer(for: constraints) { sdp, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let sdp else {
                        cont.resume(throwing: PeerWebRTCCallSessionError.missingSDP)
                        return
                    }
                    pc.setLocalDescription(sdp) { err in
                        if let err {
                            cont.resume(throwing: err)
                        } else {
                            cont.resume()
                        }
                    }
                }
            }
            guard !ended else { return }
            guard let localSDP = pc.localDescription else { return }
            let json = try answerJSONString(from: localSDP)
            let compressed = try PeerWebRTCStringCompression.gzipCompressUtf8(json)
            sendRealtimePeerSignaling(
                receiverId: peerUserId,
                dataType: WebRTCSignalingDataType.sdpAnswer,
                jsonData: compressed
            )
            flushPendingOutgoingIceIfPossible()
            drainPendingRemoteIce()
            bindLocalAudioForOutbound(pc: pc)
            if localCameraEnabled {
                bindLocalVideoForOutbound(pc: pc)
            }
            scanTransceiversForRemoteVideo()
            scheduleDeferredRemoteVideoScan()
            scheduleRemoteVideoPostConnectWork()
        } catch {
        }
    }

    private func queueOrApplyIce(_ json: String) async {
        guard !ended else { return }
        if peerConnection == nil {
            pendingRemoteIceJsonBeforePc.append(json)
            return
        }
        await applyRemoteIceCandidatePayload(json)
    }

    private func applyRemoteIceCandidatePayload(_ json: String) async {
        guard !ended else { return }
        guard let pc = peerConnection else { return }
        guard let data = json.data(using: .utf8) else { return }
        do {
            let wire = try JSONDecoder().decode(IceCandidateWire.self, from: data)
            let cand = RTCIceCandidate(sdp: wire.candidate, sdpMLineIndex: wire.sdpMLineIndex, sdpMid: wire.sdpMid)
            if pc.remoteDescription == nil {
                pendingRemoteIce.append(cand)
                return
            }
            try await addIceCandidate(cand, pc: pc)
        } catch {
        }
    }

    private func addIceCandidate(_ cand: RTCIceCandidate, pc: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.add(cand) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    private func flushPendingOutgoingIceIfPossible() {
        guard let pc = peerConnection, pc.remoteDescription != nil else { return }
        let batch = pendingOutgoingIce
        pendingOutgoingIce.removeAll()
        guard !batch.isEmpty else { return }
        for cand in batch {
            guard let data = try? iceCandidateJSONData(cand),
                  let json = String(data: data, encoding: .utf8)
            else { continue }
            sendRealtimePeerSignaling(
                receiverId: peerUserId,
                dataType: WebRTCSignalingDataType.iceCandidate,
                jsonData: json
            )
        }
    }

    private func drainPendingRemoteIce() {
        guard let pc = peerConnection else { return }
        let batch = pendingRemoteIce
        pendingRemoteIce.removeAll()
        Task { @MainActor [weak self] in
            guard let self else { return }
            for cand in batch {
                guard !Task.isCancelled, !self.ended else { return }
                try? await self.addIceCandidate(cand, pc: pc)
            }
        }
    }

    nonisolated private static func iceCandidateJSONDataForWire(_ cand: RTCIceCandidate) throws -> Data {
        let wire = IceCandidateWire(candidate: cand.sdp, sdpMLineIndex: cand.sdpMLineIndex, sdpMid: cand.sdpMid)
        return try JSONEncoder().encode(wire)
    }

    private func iceCandidateJSONData(_ cand: RTCIceCandidate) throws -> Data {
        try Self.iceCandidateJSONDataForWire(cand)
    }

    private func forwardSignalingConnectedHandshake() {
        sendRealtimePeerSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpInit,
            jsonData: ""
        )
        forwardLocalMediaStatus()
    }

    private func sendConnectedOutgoingCallerCancelPushIfNeeded() {
        guard direction == .outgoing else { return }
        guard !didSendConnectedCallerCancelPush else { return }
        guard !ended else { return }
        didSendConnectedCallerCancelPush = true
        let body: [String: Any] = [
            "offer": "CANCEL_CALL",
            "isConnected": true,
            "sentAt": "\(Int64(Date().timeIntervalSince1970 * 1000))",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let jsonData = String(data: data, encoding: .utf8)
        else { return }
        MezonSocket.shared.makeCallPush(
            receiverId: peerUserId,
            jsonData: jsonData,
            channelId: channelId,
            callerId: myUserId
        )
    }

    private func postConnectedStatusToUIIfNeeded() {
        guard !didPostConnectedStatusToUI else { return }
        guard !ended else { return }
        didPostConnectedStatusToUI = true
        let mediaConnectedAt = Date()
        onCallMediaConnectedAt?(mediaConnectedAt)
        onStatusLabel?(PeerCallLocalizedStrings.statusConnected)
        NotificationCenter.default.post(
            name: .mezonPeerCallDidConnect,
            object: nil,
            userInfo: [
                "channelId": NSNumber(value: channelId),
                "callerId": NSNumber(value: peerUserId),
            ]
        )
    }

    private func tryPresentFullyConnectedCallUI() {
        guard iceConnectedOrCompletedForUI || peerConnectionReportedConnectedForUI else { return }
        guard !didPostConnectedStatusToUI else { return }
        if beganAudioFlowVerification { return }
        beganAudioFlowVerification = true
        audioFlowVerifyTask?.cancel()
        audioFlowVerifyTask = Task { @MainActor in
            let deadline = Date().addingTimeInterval(12)
            let pollNs: UInt64 = 120_000_000
            while !Task.isCancelled, !self.ended {
                if let pc = self.peerConnection, await Self.hasInboundAudioRtp(peerConnection: pc) {
                    self.postConnectedStatusToUIIfNeeded()
                    return
                }
                if Date() >= deadline {
                    self.postConnectedStatusToUIIfNeeded()
                    return
                }
                try? await Task.sleep(nanoseconds: pollNs)
            }
        }
    }

    private func forwardLocalMediaStatus() {
        let payload = "{\"cameraEnabled\":\(localCameraEnabled),\"micEnabled\":\(localMicEnabled)}"
        sendRealtimePeerSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpStatusRemoteMedia,
            jsonData: payload
        )
    }

    private func applyRemoteMediaWire(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        func boolFromKeys(_ keys: [String]) -> Bool? {
            for k in keys {
                guard let raw = obj[k] else { continue }
                if let b = raw as? Bool { return b }
                if let i = raw as? Int { return i != 0 }
                if let n = raw as? NSNumber { return n.boolValue }
                if let s = raw as? String {
                    let t = s.trimmingCharacters(in: .whitespaces).lowercased()
                    if ["1", "true", "yes", "on"].contains(t) { return true }
                    if ["0", "false", "no", "off"].contains(t) { return false }
                }
            }
            return nil
        }
        if let m = boolFromKeys(["micEnabled", "mic_enabled"]) {
            remoteMicEnabled = m
        }
        if let cam = boolFromKeys(["cameraEnabled", "camera_enabled"]) {
            remoteCameraEnabledFromSignaling = cam
            if !cam {
                lastPublishedRemoteVideoTrackId = nil
                onRemoteVideoTrack?(nil)
                emitRemoteVideoInboundActive(false)
            } else {
                scanTransceiversForRemoteVideo()
                scheduleDeferredRemoteVideoScan()
            }
        }
        onRemoteMedia?(remoteMicEnabled)
    }

    private func emitLocalMediaState() {
        onLocalMedia?(localMicEnabled, localCameraEnabled)
    }

    private func pickRemoteVideoTrack(receiver: RTCRtpReceiver, streams: [RTCMediaStream]) -> RTCVideoTrack? {
        if let vt = receiver.track as? RTCVideoTrack {
            return vt
        }
        for stream in streams {
            for i in 0..<stream.videoTracks.count {
                return stream.videoTracks[i]
            }
        }
        return nil
    }

    private func publishRemoteVideoTrack(_ track: RTCVideoTrack, fromPeerDelegate: Bool = false) {
        if let localVideoTrack, track.trackId == localVideoTrack.trackId {
            return
        }
        guard remoteCameraEnabledFromSignaling else {
            return
        }
        if fromPeerDelegate, !delegateDeliveredRemoteVideoTrackIds.contains(track.trackId) {
            delegateDeliveredRemoteVideoTrackIds.append(track.trackId)
        }
        if lastPublishedRemoteVideoTrackId == track.trackId {
            track.isEnabled = true
            return
        }
        track.isEnabled = true
        lastPublishedRemoteVideoTrackId = track.trackId
        onRemoteVideoTrack?(track)
    }

    private func scanTransceiversForRemoteVideo() {
        guard !ended else { return }
        guard let pc = peerConnection else { return }
        if isScanningTransceivers {
            return
        }
        isScanningTransceivers = true
        defer { isScanningTransceivers = false }
        let txs = pc.transceivers
        let localVideoTrackId = localVideoTrack?.trackId
        var candidates: [(tx: RTCRtpTransceiver, track: RTCVideoTrack)] = []
        for tx in txs {
            guard tx.mediaType == .video else { continue }
            guard let t = tx.receiver.track as? RTCVideoTrack else { continue }
            if let localVideoTrackId, t.trackId == localVideoTrackId {
                continue
            }
            candidates.append((tx, t))
        }
        guard !candidates.isEmpty else {
            if lastPublishedRemoteVideoTrackId != nil {
                lastPublishedRemoteVideoTrackId = nil
                onRemoteVideoTrack?(nil)
            }
            return
        }
        candidates.sort { a, b in
            let ra = delegateDeliveryRank(a.track.trackId)
            let rb = delegateDeliveryRank(b.track.trackId)
            if ra != rb { return ra < rb }
            let sa = Self.remoteVideoTransceiverPickScore(a.tx.direction)
            let sb = Self.remoteVideoTransceiverPickScore(b.tx.direction)
            if sa != sb { return sa < sb }
            return a.track.trackId < b.track.trackId
        }
        let picked = candidates[0]
        publishRemoteVideoTrack(picked.track)
    }

    private func delegateDeliveryRank(_ trackId: String) -> Int {
        delegateDeliveredRemoteVideoTrackIds.firstIndex(of: trackId) ?? 10_000
    }

    private static func remoteVideoTransceiverPickScore(_ direction: RTCRtpTransceiverDirection) -> Int {
        switch direction {
        case .recvOnly: return 0
        case .sendRecv: return 1
        case .sendOnly: return 2
        case .inactive: return 3
        case .stopped: return 4
        @unknown default: return 9
        }
    }

    private func scheduleRepublishRemoteVideoFromInboundStatsIfNeeded() {
        remoteVideoInboundBytesProbeTask?.cancel()
        remoteVideoInboundBytesProbeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, !ended, let pc = peerConnection else { return }
            typealias Pick = (track: RTCVideoTrack, bytes: UInt64)
            var picks: [Pick] = []
            for tx in pc.transceivers where tx.mediaType == .video {
                guard let vt = tx.receiver.track as? RTCVideoTrack else { continue }
                if let localVideoTrack, vt.trackId == localVideoTrack.trackId { continue }
                let report = await Self.receiverStatisticsReport(peerConnection: pc, receiver: tx.receiver)
                let b = Self.bytesReceivedVideoInbound(from: report)
                picks.append((vt, b))
            }
            guard let best = picks.max(by: { $0.bytes < $1.bytes }), best.bytes > 0 else { return }
            guard best.track.trackId != lastPublishedRemoteVideoTrackId else {
                return
            }
            publishRemoteVideoTrack(best.track, fromPeerDelegate: false)
        }
    }

    private func emitRemoteVideoInboundActive(_ active: Bool) {
        guard lastEmittedRemoteVideoInboundActive != active else { return }
        lastEmittedRemoteVideoInboundActive = active
        onRemoteVideoInboundActive?(active)
    }

    private func scheduleRemoteVideoPostConnectWork() {
        scheduleRepublishRemoteVideoFromInboundStatsIfNeeded()
        scheduleRemoteVideoInboundMonitor()
    }

    private func scheduleRemoteVideoInboundMonitor() {
        remoteVideoInboundMonitorTask?.cancel()
        remoteVideoInboundMonitorTask = Task { @MainActor in
            var prevBytes: UInt64 = 0
            var stallTicks = 0
            while !Task.isCancelled, !ended {
                guard let pc = peerConnection else { break }
                let maxB = await Self.maxVideoInboundBytesReceived(
                    peerConnection: pc,
                    excludingLocalTrackId: localVideoTrack?.trackId
                )
                let published = lastPublishedRemoteVideoTrackId != nil
                let active: Bool
                if !published {
                    prevBytes = 0
                    stallTicks = 0
                    active = false
                } else if maxB < prevBytes {
                    prevBytes = maxB
                    stallTicks = 0
                    active = maxB > 0
                } else if maxB > prevBytes {
                    prevBytes = maxB
                    stallTicks = 0
                    active = true
                } else if maxB == 0 {
                    prevBytes = 0
                    stallTicks = 0
                    active = false
                } else {
                    stallTicks += 1
                    active = stallTicks < 5
                }
                emitRemoteVideoInboundActive(active)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private nonisolated static func maxVideoInboundBytesReceived(
        peerConnection: RTCPeerConnection,
        excludingLocalTrackId: String?
    ) async -> UInt64 {
        var maxB: UInt64 = 0
        for tx in peerConnection.transceivers where tx.mediaType == .video {
            guard let vt = tx.receiver.track as? RTCVideoTrack else { continue }
            if let excludingLocalTrackId, vt.trackId == excludingLocalTrackId { continue }
            let report = await receiverStatisticsReport(peerConnection: peerConnection, receiver: tx.receiver)
            maxB = max(maxB, bytesReceivedVideoInbound(from: report))
        }
        return maxB
    }

    private nonisolated static func receiverStatisticsReport(
        peerConnection: RTCPeerConnection,
        receiver: RTCRtpReceiver
    ) async -> RTCStatisticsReport {
        await withCheckedContinuation { cont in
            peerConnection.statistics(for: receiver) { cont.resume(returning: $0) }
        }
    }

    private nonisolated static func hasInboundAudioRtp(peerConnection: RTCPeerConnection) async -> Bool {
        for tx in peerConnection.transceivers where tx.mediaType == .audio {
            let report = await receiverStatisticsReport(peerConnection: peerConnection, receiver: tx.receiver)
            if audioInboundPresent(in: report) { return true }
        }
        return await withCheckedContinuation { cont in
            peerConnection.statistics { report in
                cont.resume(returning: audioInboundPresent(in: report))
            }
        }
    }

    private nonisolated static func audioInboundPresent(in report: RTCStatisticsReport) -> Bool {
        for (_, stat) in report.statistics {
            let st = stat.type
            guard st == "inbound-rtp" || st == "remote-inbound-rtp" else { continue }
            let vals = stat.values
            guard (vals["kind"] as? String) == "audio" else { continue }
            let br = (vals["bytesReceived"] as? NSNumber)?.uint64Value ?? 0
            let pr = (vals["packetsReceived"] as? NSNumber)?.uint64Value ?? 0
            if br > 0 || pr > 0 { return true }
        }
        return false
    }

    private nonisolated static func bytesReceivedVideoInbound(from report: RTCStatisticsReport) -> UInt64 {
        var maxBytes: UInt64 = 0
        for (_, stat) in report.statistics {
            let vals = stat.values
            let t = stat.type
            guard t.contains("inbound") else { continue }
            if let kind = vals["kind"] as? String, kind == "audio" { continue }
            if let n = vals["bytesReceived"] as? NSNumber {
                maxBytes = max(maxBytes, n.uint64Value)
            }
        }
        return maxBytes
    }

    private func scheduleDeferredRemoteVideoScan() {
        deferredRemoteVideoScanTask?.cancel()
        deferredRemoteVideoScanTask = Task { @MainActor in
            let delays: [UInt64] = [800_000_000, 2_200_000_000]
            for ns in delays {
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled, !ended else { return }
                scanTransceiversForRemoteVideo()
            }
        }
    }

    private func scheduleDisconnectRecoveryIfNeeded() {
        disconnectRecoveryTask?.cancel()
        disconnectRecoveryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 22_000_000_000)
            guard !Task.isCancelled else { return }
            guard !self.ended else { return }
            guard let pc = self.peerConnection else { return }
            if pc.iceConnectionState == .disconnected || pc.iceConnectionState == .failed {
                self.finishCall(sendQuit: true)
            }
        }
    }
}

private enum PeerWebRTCCallSessionError: Error {
    case peerConnectionCreateFailed
    case missingSDP
    case encodingFailed
    case badSDPJson
    case captureFailed
    case cancelled
}

private struct MakeCallPushBody: Encodable {
    let offer: String
    let callerName: String
    let callerAvatar: String
    let callerId: String
    let channelId: String
    let sentAt: String
}

extension PeerWebRTCCallSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        if preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            switch state {
            case .connected:
                peerConnectionReportedConnectedForUI = true
                sendConnectedOutgoingCallerCancelPushIfNeeded()
                tryPresentFullyConnectedCallUI()
                scanTransceiversForRemoteVideo()
                scheduleDeferredRemoteVideoScan()
                scheduleRemoteVideoPostConnectWork()
            case .failed:
                if direction == .outgoing && !didEstablishMediaConnection {
                    onStatusLabel?(PeerCallLocalizedStrings.statusCouldNotConnect)
                    return
                }
                finishCall(sendQuit: true)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        if preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            switch state {
            case .connected, .completed:
                disconnectRecoveryTask?.cancel()
                disconnectRecoveryTask = nil
                cancelOutgoingRingTimer()
                cancelOutgoingConnectTimeout()
                PeerCallSoundPlayer.shared.stopDialTone()
                if !didEstablishMediaConnection {
                    mediaConnectedAt = Date()
                }
                didEstablishMediaConnection = true
                iceConnectedOrCompletedForUI = true
                tryPresentFullyConnectedCallUI()
                onNetworkBanner?(nil)
                forwardSignalingConnectedHandshake()
                sendConnectedOutgoingCallerCancelPushIfNeeded()
                try? configureAudioSession()
                if let pc = peerConnection {
                    bindLocalAudioForOutbound(pc: pc)
                    if localCameraEnabled {
                        bindLocalVideoForOutbound(pc: pc)
                    }
                }
                scanTransceiversForRemoteVideo()
                scheduleDeferredRemoteVideoScan()
                scheduleRemoteVideoPostConnectWork()
            case .checking:
                PeerCallSoundPlayer.shared.stopDialTone()
                onNetworkBanner?(PeerCallLocalizedStrings.statusConnecting)
            case .disconnected:
                onNetworkBanner?(PeerCallLocalizedStrings.bannerWeakNetwork)
                scheduleDisconnectRecoveryIfNeeded()
            case .failed:
                if direction == .outgoing && !didEstablishMediaConnection {
                    onStatusLabel?(PeerCallLocalizedStrings.statusCouldNotConnect)
                    return
                }
                finishCall(sendQuit: true)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        if preWarmBackgroundIceFlag.get() {
            if let data = try? Self.iceCandidateJSONDataForWire(candidate),
               let json = String(data: data, encoding: .utf8) {
                threadSafePreWarmSignaling.append((signalingDestinationUserId, WebRTCSignalingDataType.iceCandidate, json))
            }
            return
        }
        Task { @MainActor in
            guard let pc = peerConnection else { return }
            if pc.remoteDescription == nil {
                pendingOutgoingIce.append(candidate)
            } else {
                guard let data = try? iceCandidateJSONData(candidate),
                      let json = String(data: data, encoding: .utf8)
                else { return }
                sendRealtimePeerSignaling(
                    receiverId: peerUserId,
                    dataType: WebRTCSignalingDataType.iceCandidate,
                    jsonData: json
                )
            }
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        if preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            guard let vt = pickRemoteVideoTrack(receiver: rtpReceiver, streams: streams) else {
                return
            }
            publishRemoteVideoTrack(vt, fromPeerDelegate: true)
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            guard transceiver.mediaType == .video else { return }
            guard let vt = transceiver.receiver.track as? RTCVideoTrack else {
                return
            }
            publishRemoteVideoTrack(vt, fromPeerDelegate: true)
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            for i in 0..<stream.videoTracks.count {
                let vt = stream.videoTracks[i]
                publishRemoteVideoTrack(vt, fromPeerDelegate: true)
                return
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        Task { @MainActor in
            let kind = rtpReceiver.track?.kind ?? "nil"
            guard kind == "video" else { return }
            scanTransceiversForRemoteVideo()
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didOpen _: RTCDataChannel) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}
}
