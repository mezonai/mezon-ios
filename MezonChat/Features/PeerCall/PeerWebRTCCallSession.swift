import AVFoundation
import Foundation
import LiveKitWebRTC

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

    private var peerConnection: LKRTCPeerConnection?
    private var peerFactory: LKRTCPeerConnectionFactory?
    private var localAudioTrack: LKRTCAudioTrack?
    private var localVideoTrack: LKRTCVideoTrack?
    private var videoCapturer: LKRTCCameraVideoCapturer?

    private var pendingOutgoingIce: [LKRTCIceCandidate] = []
    private var pendingRemoteIce: [LKRTCIceCandidate] = []
    private var pendingRemoteIceJsonBeforePc: [String] = []

    private var pendingOfferCompressed: String?

    private var outgoingRingTimer: DispatchWorkItem?
    private var incomingRingTimer: DispatchWorkItem?
    private var disconnectRecoveryTask: Task<Void, Never>?
    private var deferredRemoteVideoScanTask: Task<Void, Never>?
    private var rescanRemoteVideoDebounceTask: Task<Void, Never>?
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
    private var didPostConnectedStatusToUI = false
    private var iceConnectedOrCompletedForUI = false
    private var peerConnectionReportedConnectedForUI = false

    private var isAnswerPrepared = false
    private var preparedAnswerCompressed: String?
    private var isPreWarmingNoSignal = false
    private var deferredOutgoingSignaling: [(receiverId: Int64, dataType: Int32, jsonData: String)] = []

    nonisolated private static let preWarmBackgroundIceFlag = PeerCallLockFlag()
    nonisolated(unsafe) private let threadSafePreWarmSignaling = PeerCallThreadSafeSignalingQueue()
    nonisolated private let signalingDestinationUserId: Int64

    private var incomingAnswerFlowStarted = false

    private var localMicEnabled = true
    private var localCameraEnabled = false
    private var localSpeakerEnabled = false
    private var preferredCameraPosition: AVCaptureDevice.Position = .front
    private var remoteMicEnabled = true
    private var remoteCameraEnabledFromSignaling = true

    private static var sslStarted = false

    private static func makePeerConnectionFactory() -> LKRTCPeerConnectionFactory {
        let enc = LKRTCDefaultVideoEncoderFactory()
        let dec = LKRTCDefaultVideoDecoderFactory()
        return LKRTCPeerConnectionFactory(encoderFactory: enc, decoderFactory: dec)
    }

    private func applyPeerConnectionConfigCommon(_ config: LKRTCConfiguration) {
        config.sdpSemantics = .unifiedPlan
        config.iceCandidatePoolSize = 10
        config.continualGatheringPolicy = .gatherContinually
        config.iceServers = [
            LKRTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"], username: nil, credential: nil),
            LKRTCIceServer(
                urlStrings: [MezonConfig.webRTCIceServerURL],
                username: MezonConfig.webRTCIceUsername,
                credential: MezonConfig.webRTCIceCredential
            ),
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
    var onRemoteVideoTrack: ((LKRTCVideoTrack?) -> Void)?
    var onRemoteVideoInboundActive: ((Bool) -> Void)?
    var onLocalVideoTrack: ((LKRTCVideoTrack?) -> Void)?

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
        Self.preWarmBackgroundIceFlag.set(value)
    }

    private func clearPreWarmDeferralPipeline() {
        setPreWarmingNoSignal(false)
        _ = threadSafePreWarmSignaling.takeAll()
    }

    private func mergeThreadSafePreWarmDeferredIntoDeferredOutgoing() {
        let batch = threadSafePreWarmSignaling.takeAll()
        for item in batch {
            sendRealtimePeerSignaling(receiverId: item.0, dataType: item.1, jsonData: item.2)
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
        onStatusLabel?(direction == .outgoing ? "Ringing…" : "")
        Task {
            let micOk = await Self.requestMicPermission()
            guard micOk else {
                onStatusLabel?("Microphone access denied")
                finishCall(sendQuit: false)
                return
            }
            do {
                try configureAudioSession()
                try await startOutgoingPeerConnection()
                scheduleOutgoingRingTimeout()
            } catch {
                onStatusLabel?("Could not start call")
                finishCall(sendQuit: false)
            }
        }
    }

    func scheduleIncomingRingTimeout() {
        cancelIncomingRingTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onStatusLabel?("Missed call")
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

    private static func waitForCallKitReadyForIncomingAnswer() async {
        let rtc = LKRTCAudioSession.sharedInstance()
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
                    if LKRTCAudioSession.sharedInstance().isActive {
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
        onStatusLabel?("Connecting…")
        Task { @MainActor in
            let micOk = await Self.requestMicPermission()
            guard micOk else {
                onStatusLabel?("Microphone access denied")
                finishCall(sendQuit: true)
                return
            }
            do {
                try await waitForIncomingOfferIfNeeded()
                await Self.waitForCallKitReadyForIncomingAnswer()
                try await configureAudioSessionWithIncomingRetry()
                if isAnswerPrepared, peerConnection != nil {
                    try sendPreparedAnswerAndGoActive()
                } else {
                    try await buildIncomingPeerConnectionAndAnswer()
                }
            } catch {
                onStatusLabel?("Could not answer call")
                finishCall(sendQuit: true)
            }
        }
    }

    func prepareIncomingAnswerInBackground() async throws {
        guard !ended, !isAnswerPrepared, peerConnection == nil else { return }
        guard direction == .incoming else { return }
        guard let offerCompressed = pendingOfferCompressed?.trimmingCharacters(in: .whitespacesAndNewlines),
              !offerCompressed.isEmpty else {
            return
        }

        setPreWarmingNoSignal(true)
        do {
            try await performPreWarmBuild(offerCompressed: offerCompressed)
        } catch {
            resetAfterFailedPreWarm()
            throw error
        }
    }

    private func performPreWarmBuild(offerCompressed: String) async throws {
        Self.ensureSSL()
        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory

        let config = LKRTCConfiguration()
        applyPeerConnectionConfigCommon(config)

        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        peerConnection = pc

        try buildAudioVideoTracks(factory: factory)

        let remoteOffer = try parseRemoteSessionDescription(compressedOrPlain: offerCompressed)
        let offerHasVideo = IncomingPeerCallPayloadParser.sdpContainsVideo(remoteOffer.sdp)

        try await setPeerRemoteDescription(remoteOffer)
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
    }

    private func sendPreparedAnswerAndGoActive() throws {
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
        guard msg.channelID == channelId else { return }
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
        case WebRTCSignalingDataType.sdpQuit, WebRTCSignalingDataType.sdpTimeout, WebRTCSignalingDataType.sdpNotAvailable,
             WebRTCSignalingDataType.sdpJoinedOtherCall, WebRTCSignalingDataType.clearCall:
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
                onStatusLabel?("Camera access denied")
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
                let vi = LKRTCRtpTransceiverInit()
                vi.direction = .sendRecv
                pc.addTransceiver(with: vt, init: vi)
                needsRenegotiation = true
                addedVideoTransceiver = true
            } else if videoTrackExistedDisabled {
                needsRenegotiation = true
            }
            localVideoTrack?.isEnabled = true
            localCameraEnabled = true
            try? configureAudioSession()
            try startCameraCaptureIfNeeded()
            bindLocalVideoForOutbound(pc: pc)
            forwardLocalMediaStatus()
            onLocalMedia?(localMicEnabled, localCameraEnabled)
            if let vt = localVideoTrack {
                onLocalVideoTrack?(vt)
            }
            if needsRenegotiation {
                let remoteReady = pc.remoteDescription != nil
                let canOffer = remoteReady || addedVideoTransceiver
                if canOffer {
                    try await createAndSendOffer()
                }
            }
        } catch {
        }
    }

    private func createAndSendOffer() async throws {
        guard let pc = peerConnection else { return }
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
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
        incomingAnswerFlowStarted = false
        PeerCallSoundPlayer.shared.stopAll()
        cancelOutgoingRingTimer()
        cancelIncomingRingTimer()
        disconnectRecoveryTask?.cancel()
        disconnectRecoveryTask = nil

        if direction == .outgoing && sendQuit && !didEstablishMediaConnection {
            let body: [String: Any] = ["offer": "CANCEL_CALL"]
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
        let rtcAudio = LKRTCAudioSession.sharedInstance()
        rtcAudio.lockForConfiguration()
        defer { rtcAudio.unlockForConfiguration() }
        try? rtcAudio.setActive(false)
        onRemoteVideoTrack?(nil)
        onLocalVideoTrack?(nil)
    }

    private static func ensureSSL() {
        guard !sslStarted else { return }
        LKRTCInitializeSSL()
        sslStarted = true
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
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        let useVideoChat = wantsVideo || localVideoTrack != nil || localCameraEnabled
        let cfg = LKRTCAudioSessionConfiguration.webRTC()
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
        let activateSelf = direction == .outgoing
        rtc.isAudioEnabled = false
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

    private func scheduleOutgoingRingTimeout() {
        cancelOutgoingRingTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onStatusLabel?("No answer")
            self.finishCall(sendQuit: true)
        }
        outgoingRingTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    private func cancelOutgoingRingTimer() {
        outgoingRingTimer?.cancel()
        outgoingRingTimer = nil
    }

    private func cancelIncomingRingTimer() {
        incomingRingTimer?.cancel()
        incomingRingTimer = nil
    }

    private func buildAudioVideoTracks(factory: LKRTCPeerConnectionFactory) throws {
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = factory.audioSource(with: constraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "peer_audio_\(UUID().uuidString.prefix(8))")
        localAudioTrack = audioTrack
        localMicEnabled = true
        audioTrack.isEnabled = true

        if wantsVideo {
            try setupLocalVideo(factory: factory)
        }
    }

    private func setupLocalVideo(factory: LKRTCPeerConnectionFactory) throws {
        let source = factory.videoSource()
        let capturer = LKRTCCameraVideoCapturer(delegate: source)
        videoCapturer = capturer
        let track = factory.videoTrack(with: source, trackId: "peer_video_\(UUID().uuidString.prefix(8))")
        localVideoTrack = track
        localCameraEnabled = false
        track.isEnabled = false
    }

    private func setPeerRemoteDescription(_ sd: LKRTCSessionDescription) async throws {
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

    private func rtpTransceiverSetSendRecv(_ tx: LKRTCRtpTransceiver) {
        var err: NSError?
        tx.setDirection(.sendRecv, error: &err)
    }

    private func bindLocalAudioForOutbound(pc: LKRTCPeerConnection) {
        guard let at = localAudioTrack else {
            return
        }
        let aTx = pc.transceivers.filter { $0.mediaType == .audio && !$0.isStopped }
        var picked: LKRTCRtpTransceiver?
        for tx in aTx {
            if (tx.sender.track as? LKRTCAudioTrack) === at {
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
                var cur = LKRTCRtpTransceiverDirection.inactive
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

    private func bindLocalVideoForOutbound(pc: LKRTCPeerConnection) {
        guard let vt = localVideoTrack else {
            return
        }
        let vTx = pc.transceivers.filter { $0.mediaType == .video && !$0.isStopped }
        guard let tx = vTx.first else {
            return
        }
        tx.sender.track = vt
        if tx.sender.streamIds.isEmpty {
            tx.sender.streamIds = ["mezon_local_video"]
        }
        rtpTransceiverSetSendRecv(tx)
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
        guard let device = LKRTCCameraVideoCapturer.captureDevices().first(where: { $0.position == preferredCameraPosition })
                ?? LKRTCCameraVideoCapturer.captureDevices().first
        else {
            throw PeerWebRTCCallSessionError.captureFailed
        }
        let formatsObj = LKRTCCameraVideoCapturer.supportedFormats(for: device)
        let formats = formatsObj as [AVCaptureDevice.Format]
        let filtered = formats.filter { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= 960 }
        guard let picked = filtered.last ?? formats.last else {
            throw PeerWebRTCCallSessionError.captureFailed
        }
        capturer.startCapture(with: device, format: picked, fps: 30)
    }

    private func startOutgoingPeerConnection() async throws {
        Self.ensureSSL()
        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory

        let config = LKRTCConfiguration()
        applyPeerConnectionConfigCommon(config)

        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        peerConnection = pc

        try buildAudioVideoTracks(factory: factory)

        let audioInit = LKRTCRtpTransceiverInit()
        audioInit.direction = .sendRecv
        audioInit.streamIds = [peerCallLocalAudioStreamId]
        guard let at = localAudioTrack else { throw PeerWebRTCCallSessionError.peerConnectionCreateFailed }
        pc.addTransceiver(with: at, init: audioInit)

        if wantsVideo, let vt = localVideoTrack {
            let vi = LKRTCRtpTransceiverInit()
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
            channelId: "\(channelId)"
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
        guard let offerCompressed = pendingOfferCompressed, !offerCompressed.isEmpty else {
            throw PeerWebRTCCallSessionError.missingSDP
        }

        Self.ensureSSL()
        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory

        let config = LKRTCConfiguration()
        applyPeerConnectionConfigCommon(config)

        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw PeerWebRTCCallSessionError.peerConnectionCreateFailed
        }
        peerConnection = pc

        try buildAudioVideoTracks(factory: factory)

        let remoteOffer = try parseRemoteSessionDescription(compressedOrPlain: offerCompressed)
        let offerHasVideo = IncomingPeerCallPayloadParser.sdpContainsVideo(remoteOffer.sdp)

        try await setPeerRemoteDescription(remoteOffer)
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

    private func offerJSONString(from sd: LKRTCSessionDescription) throws -> String {
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

    private func answerJSONString(from sd: LKRTCSessionDescription) throws -> String {
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

    private func parseRemoteSessionDescription(compressedOrPlain: String) throws -> LKRTCSessionDescription {
        let rawJson = try PeerWebRTCStringCompression.decompressSignalingJson(compressedOrPlain)
        guard let data = rawJson.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeStr = obj["type"] as? String,
              let sdp = obj["sdp"] as? String
        else {
            throw PeerWebRTCCallSessionError.badSDPJson
        }

        let type: LKRTCSdpType
        switch typeStr {
        case "offer": type = .offer
        case "answer": type = .answer
        case "pranswer": type = .prAnswer
        default: type = .offer
        }

        return LKRTCSessionDescription(type: type, sdp: sdp)
    }

    private func applyCompressedAnswer(_ payload: String) async {
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

    private func handleRenegotiationOffer(_ payload: String) async {
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
            let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
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
        if peerConnection == nil {
            pendingRemoteIceJsonBeforePc.append(json)
            return
        }
        await applyRemoteIceCandidatePayload(json)
    }

    private func applyRemoteIceCandidatePayload(_ json: String) async {
        guard let pc = peerConnection else { return }
        guard let data = json.data(using: .utf8) else { return }
        do {
            let wire = try JSONDecoder().decode(IceCandidateWire.self, from: data)
            let cand = LKRTCIceCandidate(sdp: wire.candidate, sdpMLineIndex: wire.sdpMLineIndex, sdpMid: wire.sdpMid)
            if pc.remoteDescription == nil {
                pendingRemoteIce.append(cand)
                return
            }
            try await addIceCandidate(cand, pc: pc)
        } catch {
        }
    }

    private func addIceCandidate(_ cand: LKRTCIceCandidate, pc: LKRTCPeerConnection) async throws {
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
        Task {
            for cand in batch {
                try? await addIceCandidate(cand, pc: pc)
            }
        }
    }

    nonisolated private static func iceCandidateJSONDataForWire(_ cand: LKRTCIceCandidate) throws -> Data {
        let wire = IceCandidateWire(candidate: cand.sdp, sdpMLineIndex: cand.sdpMLineIndex, sdpMid: cand.sdpMid)
        return try JSONEncoder().encode(wire)
    }

    private func iceCandidateJSONData(_ cand: LKRTCIceCandidate) throws -> Data {
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

    private func postConnectedStatusToUIIfNeeded() {
        guard !didPostConnectedStatusToUI else { return }
        guard !ended else { return }
        didPostConnectedStatusToUI = true
        let mediaConnectedAt = Date()
        onCallMediaConnectedAt?(mediaConnectedAt)
        onStatusLabel?("Connected")
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
        guard iceConnectedOrCompletedForUI, peerConnectionReportedConnectedForUI else { return }
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

    private func pickRemoteVideoTrack(receiver: LKRTCRtpReceiver, streams: [LKRTCMediaStream]) -> LKRTCVideoTrack? {
        if let vt = receiver.track as? LKRTCVideoTrack {
            return vt
        }
        for stream in streams {
            for i in 0..<stream.videoTracks.count {
                return stream.videoTracks[i]
            }
        }
        return nil
    }

    private func publishRemoteVideoTrack(_ track: LKRTCVideoTrack, fromPeerDelegate: Bool = false) {
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
            track.shouldReceive = true
            return
        }
        track.isEnabled = true
        track.shouldReceive = true
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
        var candidates: [(tx: LKRTCRtpTransceiver, track: LKRTCVideoTrack)] = []
        for tx in txs {
            guard tx.mediaType == .video else { continue }
            guard let t = tx.receiver.track as? LKRTCVideoTrack else { continue }
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

    private static func remoteVideoTransceiverPickScore(_ direction: LKRTCRtpTransceiverDirection) -> Int {
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
            typealias Pick = (track: LKRTCVideoTrack, bytes: UInt64)
            var picks: [Pick] = []
            for tx in pc.transceivers where tx.mediaType == .video {
                guard let vt = tx.receiver.track as? LKRTCVideoTrack else { continue }
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
        peerConnection: LKRTCPeerConnection,
        excludingLocalTrackId: String?
    ) async -> UInt64 {
        var maxB: UInt64 = 0
        for tx in peerConnection.transceivers where tx.mediaType == .video {
            guard let vt = tx.receiver.track as? LKRTCVideoTrack else { continue }
            if let excludingLocalTrackId, vt.trackId == excludingLocalTrackId { continue }
            let report = await receiverStatisticsReport(peerConnection: peerConnection, receiver: tx.receiver)
            maxB = max(maxB, bytesReceivedVideoInbound(from: report))
        }
        return maxB
    }

    private nonisolated static func receiverStatisticsReport(
        peerConnection: LKRTCPeerConnection,
        receiver: LKRTCRtpReceiver
    ) async -> LKRTCStatisticsReport {
        await withCheckedContinuation { cont in
            peerConnection.statistics(for: receiver) { cont.resume(returning: $0) }
        }
    }

    private nonisolated static func hasInboundAudioRtp(peerConnection: LKRTCPeerConnection) async -> Bool {
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

    private nonisolated static func audioInboundPresent(in report: LKRTCStatisticsReport) -> Bool {
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

    private nonisolated static func bytesReceivedVideoInbound(from report: LKRTCStatisticsReport) -> UInt64 {
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
}

private struct MakeCallPushBody: Encodable {
    let offer: String
    let callerName: String
    let callerAvatar: String
    let callerId: String
    let channelId: String
}

extension PeerWebRTCCallSession: LKRTCPeerConnectionDelegate {
    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange state: LKRTCPeerConnectionState) {
        if Self.preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            switch state {
            case .connected:
                peerConnectionReportedConnectedForUI = true
                tryPresentFullyConnectedCallUI()
                scanTransceiversForRemoteVideo()
                scheduleDeferredRemoteVideoScan()
                scheduleRemoteVideoPostConnectWork()
            case .failed:
                finishCall(sendQuit: true)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange state: LKRTCIceConnectionState) {
        if Self.preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            switch state {
            case .connected, .completed:
                disconnectRecoveryTask?.cancel()
                disconnectRecoveryTask = nil
                cancelOutgoingRingTimer()
                PeerCallSoundPlayer.shared.stopDialTone()
                didEstablishMediaConnection = true
                iceConnectedOrCompletedForUI = true
                tryPresentFullyConnectedCallUI()
                onNetworkBanner?(nil)
                forwardSignalingConnectedHandshake()
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
                onNetworkBanner?("Connecting…")
            case .disconnected:
                onNetworkBanner?("Weak network — reconnecting…")
                scheduleDisconnectRecoveryIfNeeded()
            case .failed:
                finishCall(sendQuit: true)
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        if Self.preWarmBackgroundIceFlag.get() {
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

    nonisolated func peerConnectionShouldNegotiate(_: LKRTCPeerConnection) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver, streams: [LKRTCMediaStream]) {
        if Self.preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            guard let vt = pickRemoteVideoTrack(receiver: rtpReceiver, streams: streams) else {
                return
            }
            publishRemoteVideoTrack(vt, fromPeerDelegate: true)
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didStartReceivingOn transceiver: LKRTCRtpTransceiver) {
        if Self.preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            guard transceiver.mediaType == .video else { return }
            guard let vt = transceiver.receiver.track as? LKRTCVideoTrack else {
                return
            }
            publishRemoteVideoTrack(vt, fromPeerDelegate: true)
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        if Self.preWarmBackgroundIceFlag.get() { return }
        Task { @MainActor in
            for i in 0..<stream.videoTracks.count {
                let vt = stream.videoTracks[i]
                publishRemoteVideoTrack(vt, fromPeerDelegate: true)
                return
            }
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove rtpReceiver: LKRTCRtpReceiver) {
        Task { @MainActor in
            let kind = rtpReceiver.track?.kind ?? "nil"
            guard kind == "video" else { return }
            scanTransceiversForRemoteVideo()
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didOpen _: LKRTCDataChannel) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: LKRTCMediaStream) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange _: LKRTCSignalingState) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange _: LKRTCIceGatheringState) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: [LKRTCIceCandidate]) {}
}
