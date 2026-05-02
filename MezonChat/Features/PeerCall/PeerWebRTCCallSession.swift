import AVFoundation
import Foundation
import LiveKitWebRTC

private struct IceCandidateWire: Codable {
    var candidate: String
    var sdpMLineIndex: Int32
    var sdpMid: String?
}

private let peerCallLocalAudioStreamId = "mezon_peer_call_audio"

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
    private var lastEmittedRemoteVideoInboundActive = false

    private var ended = false
    private var didEstablishMediaConnection = false

    private var localMicEnabled = true
    private var localCameraEnabled = false
    private var localSpeakerEnabled = false
    private var preferredCameraPosition: AVCaptureDevice.Position = .front
    private var remoteMicEnabled = true

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
        super.init()
    }

    func beginOutgoingCall() {
        onStatusLabel?(direction == .outgoing ? "Calling…" : "")
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
        peerCallVideoLog("rescanRemoteVideoAttachment debounce 120ms")
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

    func answerIncomingCall() {
        cancelIncomingRingTimer()
        PeerCallSoundPlayer.shared.stopRinging()
        onStatusLabel?("Connecting…")
        Task {
            let micOk = await Self.requestMicPermission()
            guard micOk else {
                onStatusLabel?("Microphone access denied")
                finishCall(sendQuit: true)
                return
            }
            do {
                try configureAudioSession()
                try await buildIncomingPeerConnectionAndAnswer()
            } catch {
                onStatusLabel?("Could not answer call")
                finishCall(sendQuit: true)
            }
        }
    }

    func declineIncoming() {
        cancelIncomingRingTimer()
        PeerCallSoundPlayer.shared.stopRinging()
        finishCall(sendQuit: true)
    }

    func handleIncomingSignaling(_ msg: Mezon_Realtime_WebrtcSignalingFwd) {
        guard msg.channelID == channelId else { return }
        let pair = Set([msg.callerID, msg.receiverID])
        guard pair.contains(myUserId), pair.contains(peerUserId) else { return }

        switch msg.dataType {
        case WebRTCSignalingDataType.sdpOffer:
            if phase == .ringing {
                pendingOfferCompressed = msg.jsonData
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
        peerCallDebug(
            "toggleCamera enabled=\(localCameraEnabled) hasLocalVideoTrack=\(localVideoTrack != nil) wantsVideo=\(wantsVideo) phase=\(phase)"
        )
        if localCameraEnabled {
            localCameraEnabled = false
            videoCapturer?.stopCapture(completionHandler: {})
            localVideoTrack?.isEnabled = false
            onLocalVideoTrack?(nil)
            forwardLocalMediaStatus()
            onLocalMedia?(localMicEnabled, localCameraEnabled)
            peerCallDebug("toggleCamera -> OFF, onLocalVideoTrack(nil)")
            return
        }
        Task {
            let ok = await Self.requestCameraPermission()
            guard ok else {
                peerCallDebug("toggleCamera permission denied")
                onStatusLabel?("Camera access denied")
                return
            }
            await enableCameraMidCall()
        }
    }

    private func enableCameraMidCall() async {
        peerCallDebug(
            "enableCameraMidCall enter phase=\(phase) pc=\(peerConnection != nil) factory=\(peerFactory != nil) trackNil=\(localVideoTrack == nil)"
        )
        guard let pc = peerConnection, let factory = peerFactory else {
            peerCallDebug("enableCameraMidCall abort: missing pc or factory")
            return
        }
        guard phase == .active else {
            peerCallDebug("enableCameraMidCall abort: phase not active")
            return
        }
        do {
            try configureAudioSession()
            peerCallDebug("enableCameraMidCall configureAudioSession ok")
            var needsRenegotiation = false
            var addedVideoTransceiver = false
            let videoTrackExistedDisabled = localVideoTrack.map { !$0.isEnabled } ?? false
            if localVideoTrack == nil {
                try setupLocalVideo(factory: factory)
                guard let vt = localVideoTrack else {
                    peerCallDebug("enableCameraMidCall setupLocalVideo left no track")
                    return
                }
                let vi = LKRTCRtpTransceiverInit()
                vi.direction = .sendRecv
                pc.addTransceiver(with: vt, init: vi)
                needsRenegotiation = true
                addedVideoTransceiver = true
                peerCallDebug("enableCameraMidCall new transceiver + track \(vt.trackId)")
            } else if videoTrackExistedDisabled {
                needsRenegotiation = true
                peerCallDebug(
                    "enableCameraMidCall existing disabled track needsRenegotiation id=\(localVideoTrack?.trackId ?? "?")"
                )
            }
            localVideoTrack?.isEnabled = true
            localCameraEnabled = true
            try? configureAudioSession()
            try startCameraCaptureIfNeeded()
            peerCallDebug("enableCameraMidCall capture started")
            bindLocalVideoForOutbound(pc: pc)
            forwardLocalMediaStatus()
            onLocalMedia?(localMicEnabled, localCameraEnabled)
            if let vt = localVideoTrack {
                onLocalVideoTrack?(vt)
                peerCallDebug("enableCameraMidCall onLocalVideoTrack id=\(vt.trackId) en=\(vt.isEnabled)")
            }
            if needsRenegotiation {
                let remoteReady = pc.remoteDescription != nil
                let canOffer = remoteReady || addedVideoTransceiver
                peerCallDebug(
                    "reoffer needs=\(needsRenegotiation) remoteSDP=\(remoteReady) addedTx=\(addedVideoTransceiver) canOffer=\(canOffer) signaling=\(pc.signalingState)"
                )
                if canOffer {
                    try await createAndSendOffer()
                    peerCallDebug("enableCameraMidCall createAndSendOffer done")
                } else {
                    peerCallDebug("reoffer skipped: in-flight initial offer already has video m-line")
                }
            }
        } catch {
            peerCallDebug("enableCameraMidCall FAILED: \(error)")
        }
    }

    private func createAndSendOffer() async throws {
        guard let pc = peerConnection else { return }
        peerCallDebug(
            "createAndSendOffer signaling=\(pc.signalingState) ice=\(pc.iceConnectionState) conn=\(pc.connectionState)"
        )
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
        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpOffer,
            jsonData: compressed,
            channelId: channelId,
            callerId: myUserId
        )
        flushPendingOutgoingIceIfPossible()
    }

    private func finishCall(sendQuit: Bool) {
        guard !ended else { return }
        ended = true
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
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: peerUserId,
                dataType: WebRTCSignalingDataType.sdpQuit,
                jsonData: "",
                channelId: channelId,
                callerId: myUserId
            )
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
        lastEmittedRemoteVideoInboundActive = false
        onRemoteVideoInboundActive?(false)
        isScanningTransceivers = false
        delegateDeliveredRemoteVideoTrackIds.removeAll()
        lastPublishedRemoteVideoTrackId = nil
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
        rtc.useManualAudio = false
        rtc.isAudioEnabled = true
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
        try rtc.setConfiguration(cfg, active: true)
        let port: AVAudioSession.PortOverride = localSpeakerEnabled ? .speaker : .none
        try rtc.overrideOutputAudioPort(port)
        peerCallDebug(
            "configureAudioSession mode=\(localSpeakerEnabled ? (useVideoChat ? "videoChat" : "voiceChat") : "voiceChat(earpiece)")"
        )
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
        if let e = err {
            peerCallDebug("setSendRecv error: \(e)")
        }
    }

    private func bindLocalAudioForOutbound(pc: LKRTCPeerConnection) {
        guard let at = localAudioTrack else {
            peerCallDebug("bindLocalAudio skip: no localAudioTrack")
            return
        }
        let aTx = pc.transceivers.filter { $0.mediaType == .audio && !$0.isStopped }
        peerCallDebug("bindLocalAudio audioTx.count=\(aTx.count) senders=\(pc.senders.count)")
        var picked: LKRTCRtpTransceiver?
        for tx in aTx {
            var cur = LKRTCRtpTransceiverDirection.inactive
            if tx.currentDirection(&cur) {
                if cur == .sendOnly || cur == .sendRecv {
                    picked = tx
                    break
                }
            }
        }
        if picked == nil {
            picked = aTx.first
        }
        guard let tx = picked else {
            peerCallDebug("bindLocalAudio WARNING: no audio transceiver")
            return
        }
        tx.sender.track = at
        if tx.sender.streamIds.isEmpty {
            tx.sender.streamIds = [peerCallLocalAudioStreamId]
        }
        rtpTransceiverSetSendRecv(tx)
        at.isEnabled = localMicEnabled
        peerCallDebug(
            "bindLocalAudio track=\(at.trackId) mid=\(tx.mid) micEn=\(localMicEnabled) streamIds=\(tx.sender.streamIds)"
        )
    }

    private func bindLocalVideoForOutbound(pc: LKRTCPeerConnection) {
        guard let vt = localVideoTrack else {
            peerCallDebug("bindLocalVideo skip: no localVideoTrack")
            return
        }
        let vTx = pc.transceivers.filter { $0.mediaType == .video && !$0.isStopped }
        guard let tx = vTx.first else {
            peerCallDebug("bindLocalVideo WARNING: no video transceiver")
            return
        }
        tx.sender.track = vt
        if tx.sender.streamIds.isEmpty {
            tx.sender.streamIds = ["mezon_local_video"]
        }
        rtpTransceiverSetSendRecv(tx)
        peerCallDebug(
            "bindLocalVideo track=\(vt.trackId) mid=\(tx.mid) streamIds=\(tx.sender.streamIds)"
        )
    }

    private func attachLocalTracksAfterRemoteOffer(offerHasVideo: Bool) {
        guard let pc = peerConnection, localAudioTrack != nil else { return }
        bindLocalAudioForOutbound(pc: pc)
        if offerHasVideo, wantsVideo, localVideoTrack != nil {
            bindLocalVideoForOutbound(pc: pc)
            peerCallVideoLog("answer attach video via bindLocalVideo")
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

        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpOffer,
            jsonData: compressed,
            channelId: channelId,
            callerId: myUserId
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
        peerCallDebug("startOutgoingPeerConnection onLocalVideoTrack(nil) after connect (preview until user enables camera)")
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

        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpAnswer,
            jsonData: compressedAnswer,
            channelId: channelId,
            callerId: myUserId
        )

        forwardLocalMediaStatus()

        phase = .active
        flushPendingOutgoingIceIfPossible()
        drainPendingRemoteIce()
        bindLocalAudioForOutbound(pc: pc)
        emitLocalMediaState()
        peerCallDebug("buildIncomingPeerConnectionAndAnswer onLocalVideoTrack(nil) after answer (preview until user enables camera)")
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
            peerCallDebug("applyCompressedAnswer failed: \(error)")
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
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: peerUserId,
                dataType: WebRTCSignalingDataType.sdpAnswer,
                jsonData: compressed,
                channelId: channelId,
                callerId: myUserId
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
            peerCallDebug("handleRenegotiationOffer failed: \(error)")
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
        } catch {}
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
        for cand in batch {
            guard let data = try? iceCandidateJSONData(cand),
                  let json = String(data: data, encoding: .utf8)
            else { continue }
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: peerUserId,
                dataType: WebRTCSignalingDataType.iceCandidate,
                jsonData: json,
                channelId: channelId,
                callerId: myUserId
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

    private func iceCandidateJSONData(_ cand: LKRTCIceCandidate) throws -> Data {
        let wire = IceCandidateWire(candidate: cand.sdp, sdpMLineIndex: cand.sdpMLineIndex, sdpMid: cand.sdpMid)
        return try JSONEncoder().encode(wire)
    }

    private func forwardSignalingConnectedHandshake() {
        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpInit,
            jsonData: "",
            channelId: channelId,
            callerId: myUserId
        )
        forwardLocalMediaStatus()
    }

    private func forwardLocalMediaStatus() {
        let payload = "{\"cameraEnabled\":\(localCameraEnabled),\"micEnabled\":\(localMicEnabled)}"
        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: peerUserId,
            dataType: WebRTCSignalingDataType.sdpStatusRemoteMedia,
            jsonData: payload,
            channelId: channelId,
            callerId: myUserId
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
        peerCallVideoLog("applyRemoteMediaWire json=\(json) -> mic=\(remoteMicEnabled)")
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
            peerCallVideoLog("publishRemoteVideoTrack skip local trackId=\(track.trackId)")
            return
        }
        if fromPeerDelegate, !delegateDeliveredRemoteVideoTrackIds.contains(track.trackId) {
            delegateDeliveredRemoteVideoTrackIds.append(track.trackId)
        }
        if lastPublishedRemoteVideoTrackId == track.trackId {
            peerCallVideoLog("publishRemoteVideoTrack redispatch id=\(track.trackId)")
            track.isEnabled = true
            track.shouldReceive = true
            return
        }
        track.isEnabled = true
        track.shouldReceive = true
        peerCallVideoLog(
            "publishRemoteVideoTrack \(peerCallVideoTrackLabel(track)) delegateHint=\(delegateDeliveredRemoteVideoTrackIds)"
        )
        lastPublishedRemoteVideoTrackId = track.trackId
        onRemoteVideoTrack?(track)
    }

    private func scanTransceiversForRemoteVideo() {
        guard !ended else { return }
        guard let pc = peerConnection else { return }
        if isScanningTransceivers {
            peerCallVideoLog("scanTransceivers skip (reentrant)")
            return
        }
        isScanningTransceivers = true
        defer { isScanningTransceivers = false }
        let txs = pc.transceivers
        peerCallVideoLog("scanTransceivers txs.count=\(txs.count)")
        let localVideoTrackId = localVideoTrack?.trackId
        var candidates: [(tx: LKRTCRtpTransceiver, track: LKRTCVideoTrack)] = []
        for tx in txs {
            guard tx.mediaType == .video else { continue }
            guard let t = tx.receiver.track as? LKRTCVideoTrack else { continue }
            if let localVideoTrackId, t.trackId == localVideoTrackId {
                peerCallVideoLog("scanTransceivers skip receiver trackId matches localVideoTrack")
                continue
            }
            candidates.append((tx, t))
        }
        guard !candidates.isEmpty else {
            peerCallVideoLog("scanTransceivers no remote-shaped video receiver track")
            if lastPublishedRemoteVideoTrackId != nil {
                peerCallVideoLog("scanTransceivers clear published remote video")
                lastPublishedRemoteVideoTrackId = nil
                onRemoteVideoTrack?(nil)
            }
            return
        }
        for (idx, c) in candidates.enumerated() {
            peerCallVideoLog(
                "scanTransceivers candidate[\(idx)] dir=\(c.tx.direction) \(peerCallVideoTrackLabel(c.track))"
            )
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
        peerCallVideoLog(
            "scanTransceivers picked dir=\(picked.tx.direction) track=\(peerCallVideoTrackLabel(picked.track)) among \(candidates.count) candidate(s) delegateOrder=\(delegateDeliveredRemoteVideoTrackIds)"
        )
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
                let line = Self.summarizedStatsLine(report: report)
                peerCallVideoLog("inboundProbe receiver track=\(vt.trackId.prefix(8))... stats=\(line)")
                let b = Self.bytesReceivedVideoInbound(from: report)
                picks.append((vt, b))
            }
            let summary = picks.map { "\($0.track.trackId.prefix(8)):\($0.bytes)" }.joined(separator: ",")
            peerCallVideoLog("inboundProbe bytesByTrack=[\(summary)] published=\(lastPublishedRemoteVideoTrackId ?? "nil")")
            guard let best = picks.max(by: { $0.bytes < $1.bytes }), best.bytes > 0 else { return }
            guard best.track.trackId != lastPublishedRemoteVideoTrackId else {
                peerCallVideoLog("inboundProbe keep track=\(best.track.trackId.prefix(8))... bytes=\(best.bytes)")
                return
            }
            peerCallVideoLog("inboundProbe republish track=\(best.track.trackId) bytes=\(best.bytes)")
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

    private nonisolated static func summarizedStatsLine(report: LKRTCStatisticsReport) -> String {
        report.statistics
            .map { _, s in
                let v = s.values
                let br = (v["bytesReceived"] as? NSNumber)?.uint64Value ?? 0
                let fd = (v["framesDecoded"] as? NSNumber)?.intValue ?? -1
                let kind = v["kind"] as? String ?? "."
                return "\(s.type)(\(kind) b=\(br) dec=\(fd))"
            }
            .joined(separator: ";")
    }

    private func scheduleAudioOutboundDiagnostics() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !ended, let pc = peerConnection else { return }
            pc.statistics { [weak self] report in
                guard let self else { return }
                Task { @MainActor in
                    var found = false
                    for (_, stat) in report.statistics {
                        guard stat.type == "outbound-rtp" else { continue }
                        let vals = stat.values
                        guard (vals["kind"] as? String) == "audio" else { continue }
                        let bytes = (vals["bytesSent"] as? NSNumber)?.uint64Value ?? 0
                        let packets = (vals["packetsSent"] as? NSNumber)?.uint64Value ?? 0
                        self.peerCallDebug("audioOutboundStats bytesSent=\(bytes) packetsSent=\(packets)")
                        found = true
                    }
                    if !found {
                        self.peerCallDebug("audioOutboundStats: no outbound-rtp audio (check session + transceiver)")
                    }
                }
            }
        }
    }

    private func peerCallVideoLog(_: String) {
    }

    private func peerCallDebug(_: String) {
    }

    private func peerCallVideoTrackLabel(_ track: LKRTCVideoTrack) -> String {
        let st = String(describing: track.readyState)
        return "id=\(track.trackId) enabled=\(track.isEnabled) readyState=\(st) shouldReceive=\(track.shouldReceive)"
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
        Task { @MainActor in
            switch state {
            case .connected:
                peerCallVideoLog("PC RTCPeerConnectionState connected -> scan")
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
        Task { @MainActor in
            switch state {
            case .connected, .completed:
                disconnectRecoveryTask?.cancel()
                disconnectRecoveryTask = nil
                cancelOutgoingRingTimer()
                PeerCallSoundPlayer.shared.stopDialTone()
                didEstablishMediaConnection = true
                onNetworkBanner?(nil)
                onStatusLabel?("Connected")
                forwardSignalingConnectedHandshake()
                peerCallVideoLog("ICE connected/completed -> scan + deferred scan")
                try? configureAudioSession()
                if let pc = peerConnection {
                    bindLocalAudioForOutbound(pc: pc)
                    if localCameraEnabled {
                        bindLocalVideoForOutbound(pc: pc)
                    }
                }
                scheduleAudioOutboundDiagnostics()
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
        Task { @MainActor in
            guard let pc = peerConnection else { return }
            if pc.remoteDescription == nil {
                pendingOutgoingIce.append(candidate)
            } else {
                guard let data = try? iceCandidateJSONData(candidate),
                      let json = String(data: data, encoding: .utf8)
                else { return }
                MezonSocket.shared.forwardWebrtcSignaling(
                    receiverId: peerUserId,
                    dataType: WebRTCSignalingDataType.iceCandidate,
                    jsonData: json,
                    channelId: channelId,
                    callerId: myUserId
                )
            }
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_: LKRTCPeerConnection) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver, streams: [LKRTCMediaStream]) {
        Task { @MainActor in
            let kind = rtpReceiver.track?.kind ?? "nil"
            peerCallVideoLog("delegate didAdd receiver kind=\(kind) streamCount=\(streams.count)")
            guard let vt = pickRemoteVideoTrack(receiver: rtpReceiver, streams: streams) else {
                peerCallVideoLog("delegate didAdd receiver pickRemoteVideoTrack -> nil")
                return
            }
            publishRemoteVideoTrack(vt, fromPeerDelegate: true)
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didStartReceivingOn transceiver: LKRTCRtpTransceiver) {
        Task { @MainActor in
            peerCallVideoLog("delegate didStartReceivingOn media=\(transceiver.mediaType)")
            guard transceiver.mediaType == .video else { return }
            guard let vt = transceiver.receiver.track as? LKRTCVideoTrack else {
                peerCallVideoLog("delegate didStartReceivingOn video transceiver but no LKRTCVideoTrack")
                return
            }
            publishRemoteVideoTrack(vt, fromPeerDelegate: true)
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        Task { @MainActor in
            peerCallVideoLog("delegate didAdd stream videoTracks=\(stream.videoTracks.count)")
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
            peerCallVideoLog("delegate didRemove video receiver")
            scanTransceiversForRemoteVideo()
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didOpen _: LKRTCDataChannel) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: LKRTCMediaStream) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange _: LKRTCSignalingState) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange _: LKRTCIceGatheringState) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: [LKRTCIceCandidate]) {}
}
