import AVFoundation
import Foundation
import LiveKitWebRTC

private enum StreamingWebRTCDebug {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[StreamingWebRTC] \(message())")
        #endif
    }

    static func iceConnectionStateLabel(_ state: LKRTCIceConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }

    static func transceiverDirectionLabel(_ direction: LKRTCRtpTransceiverDirection?) -> String {
        guard let direction else { return "nil" }
        switch direction {
        case .sendRecv: return "sendRecv"
        case .sendOnly: return "sendOnly"
        case .recvOnly: return "recvOnly"
        case .inactive: return "inactive"
        case .stopped: return "stopped"
        @unknown default: return "unknown"
        }
    }

    static func redactedWSURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            guard item.name == "token" else { return item }
            let value = item.value ?? ""
            let suffix = value.count > 6 ? String(value.suffix(6)) : value
            return URLQueryItem(name: item.name, value: "<redacted:\(suffix)>")
        }
        return components.string ?? url.absoluteString
    }
}

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

    private override init() {
        super.init()
    }

    private static func log(_ message: @autoclosure () -> String) {
        StreamingWebRTCDebug.log(message())
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
            Self.log("join skipped: already connected streamId=\(streamId)")
            return
        }
        Self.log("join start clanId=\(clanId) channelId=\(channelId) streamId=\(streamId) userId=\(userId) username=\(username)")
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
        let audioTransceiver = pc.addTransceiver(of: .audio, init: audioInit)
        Self.log("audio transceiver direction=\(StreamingWebRTCDebug.transceiverDirectionLabel(audioTransceiver?.direction))")

        guard let wsURL = Self.makeWebSocketURL(username: username, token: token) else {
            Self.log("join failed: invalid websocket url base=\(MezonConfig.streamWebSocketURLString)")
            return
        }
        Self.log("websocket connect \(StreamingWebRTCDebug.redactedWSURL(wsURL))")
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
            Self.log("local offer created type=\(offer.type.rawValue) sdpLen=\(offer.sdp.count)")
            try await Self.setLocalDescription(offer, on: pc)
            sendJSON([
                "Key": "session_subscriber",
                "ClanId": "\(clanId)",
                "ChannelId": "\(channelId)",
                "UserId": userId,
                "Value": Self.sessionDescriptionPayload(offer),
            ], label: "session_subscriber")
            sendJSON(["Key": "get_channels"], label: "get_channels")
        } catch {
            Self.log("join failed during offer/localDescription: \(error.localizedDescription)")
            disconnect()
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
        Self.log("disconnect streamId=\(activeStreamChannelId.map(String.init) ?? "nil") isStreaming=\(isStreaming)")
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
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
    }

    private static func ensureSSL() {
        guard !sslInitialized else { return }
        LKRTCInitializeSSL()
        sslInitialized = true
    }

    private func attachRemoteAudioTrack(_ track: LKRTCAudioTrack?) {
        remoteAudioTrack = track
        guard let track else {
            Self.log("remote audio track cleared")
            return
        }
        track.isEnabled = true
        Self.log("remote audio track attached id=\(track.trackId) enabled=\(track.isEnabled) state=\(track.readyState.rawValue)")
        logAudioSessionState(prefix: "after audio track")
    }

    private func setRemoteVideoTrack(_ track: LKRTCVideoTrack?) {
        guard remoteVideoTrack !== track else { return }
        remoteVideoTrack = track
        if let track {
            track.isEnabled = true
            Self.log("remote video track attached id=\(track.trackId) enabled=\(track.isEnabled) state=\(track.readyState.rawValue)")
        } else {
            Self.log("remote video track cleared")
        }
        onRemoteVideoTrackChanged?(track)
    }

    private func setStreaming(_ value: Bool) {
        guard isStreaming != value else { return }
        isStreaming = value
        Self.log("isStreaming=\(value) streamId=\(pendingStreamId)")
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
            Self.log("webrtc audio session configured category=playback")
        } catch {
            Self.log("webrtc audio session configure failed: \(error.localizedDescription)")
        }
        logAudioSessionState(prefix: "after configure")
    }

    private func deactivateWebRTCAudio() {
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        rtc.isAudioEnabled = false
        try? rtc.setActive(false)
    }

    private func scanRemoteTracks(source: String) {
        guard let pc = peerConnection else { return }
        let transceivers = pc.transceivers
        Self.log("\(source): transceivers=\(transceivers.count)")
        for (index, transceiver) in transceivers.enumerated() {
            Self.log("\(source): transceiver[\(index)] media=\(transceiver.mediaType.rawValue) dir=\(StreamingWebRTCDebug.transceiverDirectionLabel(transceiver.direction)) mid=\(transceiver.mid ?? "nil")")
            if let track = transceiver.receiver.track {
                handleRemoteTrack(track, source: "\(source).scan")
            }
        }
    }

    private static func sdpMediaLineSummary(_ sdp: String) -> String {
        let lines = sdp.split(separator: "\n", omittingEmptySubsequences: false)
        let audio = lines.filter { $0.hasPrefix("m=audio") }.count
        let video = lines.filter { $0.hasPrefix("m=video") }.count
        return "audioM=\(audio) videoM=\(video)"
    }

    private func logAudioSessionState(prefix: String) {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        Self.log("\(prefix): category=\(session.category.rawValue) mode=\(session.mode.rawValue) otherAudio=\(session.isOtherAudioPlaying) outputRoute=[\(route)] volume=\(session.outputVolume)")
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

    private func sendJSON(_ object: [String: Any], label: String? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            Self.log("sendJSON failed to encode label=\(label ?? "unknown")")
            return
        }
        let key = (object["Key"] as? String) ?? label ?? "?"
        webSocketTask?.send(.string(text)) { error in
            if let error {
                StreamingWebRTCDebug.log("ws send failed key=\(key): \(error.localizedDescription)")
            } else {
                StreamingWebRTCDebug.log("ws send ok key=\(key)")
            }
        }
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
                    } else {
                        Self.log("ws received binary data len=\(data.count)")
                    }
                @unknown default:
                    break
                }
            } catch {
                Self.log("ws receive loop ended: \(error.localizedDescription)")
                break
            }
        }
    }

    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["Key"] as? String else {
            Self.log("ws message parse failed: \(text.prefix(200))")
            return
        }

        switch key {
        case "channels":
            Self.log("ws message key=channels value=\(String(describing: json["Value"]))")
            handleChannelsMessage(json)
        case "sd_answer":
            Self.log("ws message key=sd_answer")
            handleAnswerMessage(json)
        case "ice_candidate":
            Self.log("ws message key=ice_candidate")
            handleRemoteIceCandidate(json)
        case "session_received":
            Self.log("ws message key=session_received")
        case "error":
            Self.log("ws message key=error value=\(String(describing: json["Value"]))")
            setStreaming(false)
        default:
            Self.log("ws message key=\(key) value=\(String(describing: json["Value"]))")
        }
    }

    private func handleChannelsMessage(_ json: [String: Any]) {
        guard let values = json["Value"] as? [Any] else {
            Self.log("channels missing Value array")
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
        Self.log("channels contains streamId=\(streamIdString): \(containsStream) available=\(values)")
        guard containsStream else {
            setStreaming(false)
            return
        }
        sendJSON([
            "Key": "connect_subscriber",
            "ClanId": "\(pendingClanId)",
            "ChannelId": "\(pendingChannelId)",
            "UserId": pendingUserId,
            "Value": ["ChannelId": streamIdString],
        ], label: "connect_subscriber")
        setStreaming(true)
    }

    private func handleAnswerMessage(_ json: [String: Any]) {
        guard let pc = peerConnection else {
            Self.log("sd_answer ignored: no peerConnection")
            return
        }
        if let sdp = json["Value"] as? String {
            let answer = LKRTCSessionDescription(type: .answer, sdp: sdp)
            pc.setRemoteDescription(answer) { [weak self] error in
                if let error {
                    Self.log("setRemoteDescription failed: \(error.localizedDescription)")
                } else {
                    Self.log("setRemoteDescription ok sdpLen=\(sdp.count) \(Self.sdpMediaLineSummary(sdp))")
                    Task { @MainActor [weak self] in
                        self?.scanRemoteTracks(source: "after sd_answer")
                    }
                }
            }
            return
        }
        if let payload = json["Value"] as? [String: Any],
           let sdp = payload["sdp"] as? String {
            let answer = LKRTCSessionDescription(type: .answer, sdp: sdp)
            pc.setRemoteDescription(answer) { [weak self] error in
                if let error {
                    Self.log("setRemoteDescription failed: \(error.localizedDescription)")
                } else {
                    Self.log("setRemoteDescription ok sdpLen=\(sdp.count) \(Self.sdpMediaLineSummary(sdp))")
                    Task { @MainActor [weak self] in
                        self?.scanRemoteTracks(source: "after sd_answer")
                    }
                }
            }
            return
        }
        Self.log("sd_answer missing sdp payload")
    }

    private func handleRemoteIceCandidate(_ json: [String: Any]) {
        guard let pc = peerConnection else { return }
        if let candidateJSON = json["Value"] as? [String: Any] {
            if let candidate = Self.iceCandidate(from: candidateJSON) {
                pc.add(candidate) { error in
                    if let error {
                        Self.log("addIceCandidate failed: \(error.localizedDescription)")
                    } else {
                        Self.log("addIceCandidate ok mid=\(candidateJSON["sdpMid"] as? String ?? "")")
                    }
                }
            } else {
                Self.log("addIceCandidate parse failed dict=\(candidateJSON)")
            }
            return
        }
        if let candidateJSON = json["Value"] as? String,
           let data = candidateJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidate = Self.iceCandidate(from: object) {
            pc.add(candidate) { error in
                if let error {
                    Self.log("addIceCandidate failed: \(error.localizedDescription)")
                } else {
                    Self.log("addIceCandidate ok from string payload")
                }
            }
            return
        }
        Self.log("ice_candidate unsupported payload=\(String(describing: json["Value"]))")
    }

    private func handleRemoteTrack(_ track: LKRTCMediaStreamTrack, source: String) {
        if let video = track as? LKRTCVideoTrack {
            Self.log("\(source): video track id=\(video.trackId)")
            setRemoteVideoTrack(video)
            return
        }
        if let audio = track as? LKRTCAudioTrack {
            Self.log("\(source): audio track id=\(audio.trackId) enabled=\(audio.isEnabled) state=\(audio.readyState.rawValue)")
            attachRemoteAudioTrack(audio)
            return
        }
        Self.log("\(source): unknown track kind=\(track.kind)")
    }

    private static func iceCandidate(from json: [String: Any]) -> LKRTCIceCandidate? {
        guard let sdp = json["candidate"] as? String else { return nil }
        let sdpMid = json["sdpMid"] as? String
        let sdpMLineIndex = json["sdpMLineIndex"] as? Int32 ?? (json["sdpMLineIndex"] as? Int).map { Int32($0) } ?? 0
        return LKRTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}

extension StreamingWebRTCSession: LKRTCPeerConnectionDelegate {
    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange state: LKRTCSignalingState) {
        StreamingWebRTCDebug.log("signalingState=\(state.rawValue)")
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd stream: LKRTCMediaStream) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            Self.log("didAdd stream id=\(stream.streamId) audioTracks=\(stream.audioTracks.count) videoTracks=\(stream.videoTracks.count)")
            for track in stream.audioTracks {
                self.handleRemoteTrack(track, source: "didAddStream.audio")
            }
            for track in stream.videoTracks {
                self.handleRemoteTrack(track, source: "didAddStream.video")
            }
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: LKRTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_: LKRTCPeerConnection) {
        StreamingWebRTCDebug.log("negotiation needed")
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange state: LKRTCIceConnectionState) {
        StreamingWebRTCDebug.log("iceConnectionState=\(StreamingWebRTCDebug.iceConnectionStateLabel(state))")
        if state == .connected || state == .completed {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let rtc = LKRTCAudioSession.sharedInstance()
                rtc.lockForConfiguration()
                rtc.isAudioEnabled = true
                rtc.unlockForConfiguration()
                self.logAudioSessionState(prefix: "ice connected")
                self.scanRemoteTracks(source: "ice connected")
            }
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didChange state: LKRTCIceGatheringState) {
        StreamingWebRTCDebug.log("iceGatheringState=\(state.rawValue)")
    }

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
            ], label: "ice_candidate")
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: [LKRTCIceCandidate]) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didOpen _: LKRTCDataChannel) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didAdd rtpReceiver: LKRTCRtpReceiver, streams _: [LKRTCMediaStream]) {
        Task { @MainActor [weak self] in
            guard let self, let track = rtpReceiver.track else { return }
            self.handleRemoteTrack(track, source: "didAddRtpReceiver")
        }
    }

    nonisolated func peerConnection(_: LKRTCPeerConnection, didRemove _: LKRTCRtpReceiver) {}

    nonisolated func peerConnection(_: LKRTCPeerConnection, didStartReceivingOn transceiver: LKRTCRtpTransceiver) {
        Task { @MainActor [weak self] in
            guard let self, let track = transceiver.receiver.track else { return }
            self.handleRemoteTrack(track, source: "didStartReceivingOn")
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
