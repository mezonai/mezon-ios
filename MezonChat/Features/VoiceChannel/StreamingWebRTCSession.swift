import AVFoundation
import Foundation
import LiveKitWebRTC

@MainActor
final class StreamingWebRTCSession: NSObject {

    static let shared = StreamingWebRTCSession()

    private static var sslInitialized = false

    private(set) var activeStreamChannelId: Int64?
    private(set) var isStreaming = false
    private(set) var remoteVideoTrack: LKRTCVideoTrack?
    private(set) var remoteAudioTrack: LKRTCAudioTrack?

    var isRemoteVideoStream: Bool { remoteVideoTrack != nil }

    var onStreamingStateChanged: (() -> Void)?
    var onRemoteVideoTrackChanged: ((LKRTCVideoTrack?) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var peerConnection: LKRTCPeerConnection?
    private var peerFactory: LKRTCPeerConnectionFactory?
    private var pendingClanId: Int64 = 0
    private var pendingChannelId: Int64 = 0
    private var pendingStreamId: Int64 = 0
    private var pendingUserId: String = ""
    private var receiveLoopTask: Task<Void, Never>?
    private var availabilityPollTask: Task<Void, Never>?
    private var hasSubscribedToStream = false

    private static let availabilityPollIntervalNanos: UInt64 = 3_000_000_000

    private override init() {
        super.init()
    }

    func join(
        clanId: Int64,
        channelId: Int64,
        streamId: Int64,
        userId: String,
        username: String,
        token: String
    ) async {
        if activeStreamChannelId == streamId, isStreaming, peerConnection != nil {
            return
        }
        disconnect()
        pendingClanId = clanId
        pendingChannelId = channelId
        pendingStreamId = streamId
        pendingUserId = userId
        activeStreamChannelId = streamId

        Self.ensureSSL()
        configureWebRTCAudioForPlayback()

        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory
        let pc = Self.makePeerConnection(factory: factory, delegate: self)
        peerConnection = pc

        let audioInit = LKRTCRtpTransceiverInit()
        audioInit.direction = .recvOnly
        pc.addTransceiver(of: .audio, init: audioInit)

        guard let wsURL = Self.makeWebSocketURL(username: username, token: token) else {
            return
        }
        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: wsURL)
        webSocketTask = task
        task.resume()
        receiveLoopTask = Task { [weak self] in
            await self?.receiveMessages(from: task)
        }

        do {
            let offer = try await Self.createOffer(on: pc)
            try await Self.setLocalDescription(offer, on: pc)
            sendJSON([
                "Key": "session_subscriber",
                "ClanId": "\(clanId)",
                "ChannelId": "\(channelId)",
                "UserId": userId,
                "Value": Self.sessionDescriptionPayload(offer),
            ])
            sendJSON(["Key": "get_channels"])
            startAvailabilityPolling()
        } catch {
            disconnect()
        }
    }

    private func startAvailabilityPolling() {
        availabilityPollTask?.cancel()
        availabilityPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.availabilityPollIntervalNanos)
                guard !Task.isCancelled, let self else { return }
                guard !self.isStreaming, self.webSocketTask != nil else { return }
                self.sendJSON(["Key": "get_channels"])
            }
        }
    }

    private static func createOffer(on pc: LKRTCPeerConnection) async throws -> LKRTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.offer(for: constraints) { sdp, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: MezonError.httpError(statusCode: 0, message: "Missing stream offer"))
                }
            }
        }
    }

    private static func setLocalDescription(_ description: LKRTCSessionDescription, on pc: LKRTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        availabilityPollTask?.cancel()
        availabilityPollTask = nil
        hasSubscribedToStream = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        peerConnection?.close()
        peerConnection = nil
        peerFactory = nil
        deactivateWebRTCAudio()
        activeStreamChannelId = nil
        isStreaming = false
        remoteAudioTrack = nil
        setRemoteVideoTrack(nil)
        pendingClanId = 0
        pendingChannelId = 0
        pendingStreamId = 0
        pendingUserId = ""
    }

    func leave() {
        disconnect()
    }

    private static func ensureSSL() {
        guard !sslInitialized else { return }
        LKRTCInitializeSSL()
        sslInitialized = true
    }

    private func attachRemoteAudioTrack(_ track: LKRTCAudioTrack?) {
        remoteAudioTrack = track
        guard let track else {
            return
        }
        track.isEnabled = true
    }

    private func setRemoteVideoTrack(_ track: LKRTCVideoTrack?) {
        guard remoteVideoTrack !== track else { return }
        remoteVideoTrack = track
        if let track {
            track.isEnabled = true
        }
        onRemoteVideoTrackChanged?(track)
    }

    private func setStreaming(_ value: Bool) {
        guard isStreaming != value else { return }
        isStreaming = value
        if value {
            availabilityPollTask?.cancel()
            availabilityPollTask = nil
        }
        onStreamingStateChanged?()
    }

    private func configureWebRTCAudioForPlayback() {
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        let cfg = LKRTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playback.rawValue
        cfg.mode = AVAudioSession.Mode.moviePlayback.rawValue
        cfg.categoryOptions = [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
        do {
            try rtc.setConfiguration(cfg, active: true)
            rtc.isAudioEnabled = true
        } catch {
        }
    }

    private func deactivateWebRTCAudio() {
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        rtc.isAudioEnabled = false
        try? rtc.setActive(false)
    }

    private func scanRemoteTracks() {
        guard let pc = peerConnection else { return }
        for transceiver in pc.transceivers {
            if let track = transceiver.receiver.track {
                handleRemoteTrack(track)
            }
        }
    }

    private static func makePeerConnectionFactory() -> LKRTCPeerConnectionFactory {
        let enc = LKRTCDefaultVideoEncoderFactory()
        let dec = LKRTCDefaultVideoDecoderFactory()
        return LKRTCPeerConnectionFactory(encoderFactory: enc, decoderFactory: dec)
    }

    private static func makePeerConnection(
        factory: LKRTCPeerConnectionFactory,
        delegate: LKRTCPeerConnectionDelegate
    ) -> LKRTCPeerConnection {
        let config = LKRTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [
            LKRTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"], username: nil, credential: nil),
        ]
        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return factory.peerConnection(with: config, constraints: constraints, delegate: delegate)!
    }

    private static func makeWebSocketURL(username: String, token: String) -> URL? {
        let base = MezonConfig.streamWebSocketURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        var components = URLComponents(string: base.hasSuffix("/ws") ? base : "\(base)/ws")
        components?.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "token", value: token),
        ]
        return components?.url
    }

    private static func sessionDescriptionPayload(_ description: LKRTCSessionDescription) -> [String: String] {
        [
            "type": description.type.canonicalString,
            "sdp": description.sdp,
        ]
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(text)) { _ in }
    }

    private func receiveMessages(from task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleIncomingMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncomingMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                break
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["Key"] as? String else {
            return
        }

        switch key {
        case "channels":
            handleChannelsMessage(json)
        case "sd_answer":
            handleAnswerMessage(json)
        case "ice_candidate":
            handleRemoteIceCandidate(json)
        case "session_received":
            break
        case "error":
            setStreaming(false)
        default:
            break
        }
    }

    private func handleChannelsMessage(_ json: [String: Any]) {
        guard let values = json["Value"] as? [Any] else {
            setStreaming(false)
            return
        }
        let streamIdString = "\(pendingStreamId)"
        let containsStream = values.contains { value in
            if let id = value as? String { return id == streamIdString }
            if let id = value as? NSNumber { return id.stringValue == streamIdString }
            if let id = value as? Int64 { return "\(id)" == streamIdString }
            return false
        }
        guard containsStream else {
            setStreaming(false)
            return
        }
        if !hasSubscribedToStream {
            hasSubscribedToStream = true
            sendJSON([
                "Key": "connect_subscriber",
                "ClanId": "\(pendingClanId)",
                "ChannelId": "\(pendingChannelId)",
                "UserId": pendingUserId,
                "Value": ["ChannelId": streamIdString],
            ])
        }
        setStreaming(true)
    }

    private func handleAnswerMessage(_ json: [String: Any]) {
        guard let pc = peerConnection else {
            return
        }
        if let sdp = json["Value"] as? String {
            let answer = LKRTCSessionDescription(type: .answer, sdp: sdp)
            pc.setRemoteDescription(answer) { [weak self] error in
                if error == nil {
                    Task { @MainActor [weak self] in
                        self?.scanRemoteTracks()
                    }
                }
            }
            return
        }
        if let payload = json["Value"] as? [String: Any],
           let sdp = payload["sdp"] as? String {
            let answer = LKRTCSessionDescription(type: .answer, sdp: sdp)
            pc.setRemoteDescription(answer) { [weak self] error in
                if error == nil {
                    Task { @MainActor [weak self] in
                        self?.scanRemoteTracks()
                    }
                }
            }
            return
        }
    }

    private func handleRemoteIceCandidate(_ json: [String: Any]) {
        guard let pc = peerConnection else { return }
        if let candidateJSON = json["Value"] as? [String: Any] {
            if let candidate = Self.iceCandidate(from: candidateJSON) {
                pc.add(candidate) { _ in }
            }
            return
        }
        if let candidateJSON = json["Value"] as? String,
           let data = candidateJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidate = Self.iceCandidate(from: object) {
            pc.add(candidate) { _ in }
            return
        }
    }

    private func handleRemoteTrack(_ track: LKRTCMediaStreamTrack) {
        if let video = track as? LKRTCVideoTrack {
            setRemoteVideoTrack(video)
            return
        }
        if let audio = track as? LKRTCAudioTrack {
            attachRemoteAudioTrack(audio)
            return
        }
    }

    private static func iceCandidate(from json: [String: Any]) -> LKRTCIceCandidate? {
        guard let sdp = json["candidate"] as? String else { return nil }
        let sdpMid = json["sdpMid"] as? String
        let sdpMLineIndex = json["sdpMLineIndex"] as? Int32 ?? (json["sdpMLineIndex"] as? Int).map { Int32($0) } ?? 0
        return LKRTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}

extension StreamingWebRTCSession: LKRTCPeerConnectionDelegate {
    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange _: LKRTCSignalingState) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for track in stream.audioTracks {
                self.handleRemoteTrack(track)
            }
            for track in stream.videoTracks {
                self.handleRemoteTrack(track)
            }
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: LKRTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_: LKRTCPeerConnection) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange state: LKRTCIceConnectionState) {
        if state == .connected || state == .completed {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let rtc = LKRTCAudioSession.sharedInstance()
                rtc.lockForConfiguration()
                rtc.isAudioEnabled = true
                rtc.unlockForConfiguration()
                self.scanRemoteTracks()
            }
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange _: LKRTCIceGatheringState) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didGenerate candidate: LKRTCIceCandidate) {
        guard !candidate.sdp.isEmpty else { return }
        let payload: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex,
        ]
        Task { @MainActor [weak self] in
            self?.sendJSON([
                "Key": "ice_candidate",
                "Value": payload,
            ])
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: [LKRTCIceCandidate]) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didOpen _: LKRTCDataChannel) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver, streams _: [LKRTCMediaStream]) {
        Task { @MainActor [weak self] in
            guard let self, let track = rtpReceiver.track else { return }
            self.handleRemoteTrack(track)
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: LKRTCRtpReceiver) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didStartReceivingOn transceiver: LKRTCRtpTransceiver) {
        Task { @MainActor [weak self] in
            guard let self, let track = transceiver.receiver.track else { return }
            self.handleRemoteTrack(track)
        }
    }
}

private extension LKRTCSdpType {
    var canonicalString: String {
        switch self {
        case .offer: return "offer"
        case .prAnswer: return "pranswer"
        case .answer: return "answer"
        case .rollback: return "rollback"
        @unknown default: return "offer"
        }
    }
}
