import AVFoundation
import Foundation
import WebRTC

enum StreamingSfuLog {

    static func write(_ message: String) {
        NSLog("%@", "[stream-sfu] \(message)" as NSString)
    }

    static func writeBlock(_ label: String, _ text: String) {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        var chunk = ""
        var index = 0
        for line in lines {
            if chunk.count + line.count > 700 {
                write("\(label)[\(index)] \(chunk)")
                index += 1
                chunk = ""
            }
            chunk += chunk.isEmpty ? line : " | " + line
        }
        if !chunk.isEmpty {
            write("\(label)[\(index)] \(chunk)")
        }
    }

    static func tokenSummary(_ token: String) -> String {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return "len=\(token.count) notJwt" }
        guard let payload = decodeSegment(parts[1]),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return "len=\(token.count) jwt payloadUnreadable"
        }
        let fields = json.map { "\($0.key)=\($0.value)" }.sorted()
        return "len=\(token.count) jwt " + fields.joined(separator: " ")
    }

    private static func decodeSegment(_ segment: String) -> Data? {
        var base64 = segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        return Data(base64Encoded: base64)
    }
}

@MainActor
final class StreamingWebRTCSession: NSObject {

    static let shared = StreamingWebRTCSession()

    private static var sslInitialized = false

    private(set) var activeStreamChannelId: Int64?
    private(set) var isStreaming = false
    private(set) var remoteAudioTrack: RTCAudioTrack?

    var onStreamingStateChanged: (() -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var peerConnection: RTCPeerConnection?
    private var peerFactory: RTCPeerConnectionFactory?
    private var receiveLoopTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?
    private var tokenProvider: (() async -> String?)?
    private var token = ""
    private var sessionGeneration = 0
    private var transportGeneration = 0
    private var reconnectAttempt = 0
    private var hasActivatedAudioSession = false
    private var negotiating = false
    private var pendingOffer: (Int64, String)?

    private var messagesReceived = 0
    private var offersReceived = 0
    private var answersSent = 0
    private var localCandidatesGathered = 0
    private var didLogSdpForTransport = false
    private var lastIceState = "none"
    private var lastPeerConnectionState = "none"
    private var lastSignalingState = "none"

    private static let reconnectDelays: [UInt64] = [
        1_000_000_000,
        2_000_000_000,
        4_000_000_000,
        8_000_000_000,
        15_000_000_000,
    ]

    private struct SdpMediaSection {
        let kind: String
        let mid: String
        let direction: String?
    }

    private override init() {
        super.init()
    }

    func join(
        channelId: Int64,
        token: String,
        tokenProvider: @escaping () async -> String?
    ) async {
        guard channelId != 0, !token.isEmpty else {
            StreamingSfuLog.write("join refused channel=\(channelId) tokenEmpty=\(token.isEmpty)")
            return
        }
        if activeStreamChannelId == channelId, activeStreamChannelId != nil {
            StreamingSfuLog.write("join skipped, already active on channel=\(channelId) streaming=\(isStreaming)")
            return
        }

        StreamingSfuLog.write("join channel=\(channelId) base=\(Self.baseWebSocketURLString()) token \(StreamingSfuLog.tokenSummary(token))")

        disconnect()
        activeStreamChannelId = channelId
        self.token = token
        self.tokenProvider = tokenProvider
        reconnectAttempt = 0
        negotiating = false
        pendingOffer = nil
        messagesReceived = 0
        offersReceived = 0
        answersSent = 0

        Self.ensureSSL()
        guard configureWebRTCAudioForPlayback() else {
            StreamingSfuLog.write("join aborted, audio session configuration failed")
            disconnect()
            return
        }

        openConnection()
        startDiagnostics()
    }

    func disconnect() {
        StreamingSfuLog.write("disconnect channel=\(activeStreamChannelId.map(String.init) ?? "none") streaming=\(isStreaming) offers=\(offersReceived) answers=\(answersSent)")
        sessionGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        closeTransport()
        tokenProvider = nil
        token = ""
        activeStreamChannelId = nil
        pendingOffer = nil
        negotiating = false
        reconnectAttempt = 0
        remoteAudioTrack = nil
        setStreaming(false)
        deactivateWebRTCAudio()
    }

    func leave() {
        StreamingSfuLog.write("leave requested")
        disconnect()
    }

    private func startDiagnostics() {
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled, let self, self.activeStreamChannelId != nil else { return }
                self.logHeartbeat()
            }
        }
    }

    private func logHeartbeat() {
        let socketState: String
        if let task = webSocketTask {
            socketState = "state=\(task.state.rawValue) close=\(task.closeCode.rawValue)"
        } else {
            socketState = "none"
        }
        let fields = [
            "channel=\(activeStreamChannelId.map(String.init) ?? "none")",
            "gen=\(transportGeneration)",
            "socket(\(socketState))",
            "msgs=\(messagesReceived)",
            "offers=\(offersReceived)",
            "answers=\(answersSent)",
            "negotiating=\(negotiating)",
            "ice=\(lastIceState)",
            "pc=\(lastPeerConnectionState)",
            "signaling=\(lastSignalingState)",
            "candidates=\(localCandidatesGathered)",
            "transceivers=\(peerConnection?.transceivers.count ?? -1)",
            "audioTrack=\(remoteAudioTrack != nil)",
            "streaming=\(isStreaming)",
            "reconnectAttempt=\(reconnectAttempt)",
            "reconnectPending=\(reconnectTask != nil)",
        ]
        StreamingSfuLog.write("heartbeat " + fields.joined(separator: " "))
    }

    private func openConnection() {
        guard activeStreamChannelId != nil else {
            StreamingSfuLog.write("openConnection skipped, no active channel")
            return
        }
        closeTransport()
        transportGeneration &+= 1
        let generation = transportGeneration
        didLogSdpForTransport = false
        localCandidatesGathered = 0
        lastIceState = "none"
        lastPeerConnectionState = "none"
        lastSignalingState = "none"

        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory
        guard let pc = Self.makePeerConnection(factory: factory, delegate: self) else {
            StreamingSfuLog.write("openConnection failed, peer connection not created gen=\(generation)")
            scheduleReconnect(reason: "peer-connection-create-failed")
            return
        }
        peerConnection = pc

        guard let wsURL = Self.makeWebSocketURL(token: token) else {
            StreamingSfuLog.write("openConnection failed, websocket url invalid base=\(Self.baseWebSocketURLString()) gen=\(generation)")
            scheduleReconnect(reason: "websocket-url-invalid")
            return
        }

        StreamingSfuLog.write("openConnection gen=\(generation) host=\(wsURL.host ?? "?") path=\(wsURL.path) iceServers=\(pc.configuration.iceServers.count)")

        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: wsURL)
        webSocketTask = task
        task.resume()

        receiveLoopTask = Task { [weak self] in
            await self?.receiveMessages(from: task, transportGeneration: generation)
        }

        sendJoin(token: token, transportGeneration: generation)
    }

    private func closeTransport() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        let oldPeerConnection = peerConnection
        peerConnection = nil
        oldPeerConnection?.close()
        peerFactory = nil
        remoteAudioTrack = nil
        pendingOffer = nil
        negotiating = false
    }

    private func sendJoin(token: String, transportGeneration: Int) {
        let room = String(activeStreamChannelId ?? 0)
        StreamingSfuLog.write("send join room=\(room) role=audience gen=\(transportGeneration)")
        send(
            [
                "type": "join",
                "room": room,
                "token": token,
                "role": "audience",
            ],
            transportGeneration: transportGeneration
        ) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                guard let self, transportGeneration == self.transportGeneration else { return }
                StreamingSfuLog.write("send join failed gen=\(transportGeneration) error=\(error.localizedDescription)")
                self.scheduleReconnect(reason: "join-send-failed")
            }
        }
    }

    private func receiveMessages(from task: URLSessionWebSocketTask, transportGeneration: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard !Task.isCancelled else { return }
                guard task === webSocketTask, transportGeneration == self.transportGeneration else {
                    StreamingSfuLog.write("receive ignored, stale transport gen=\(transportGeneration) current=\(self.transportGeneration)")
                    return
                }
                switch message {
                case .string(let text):
                    handleIncomingMessage(text, transportGeneration: transportGeneration)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncomingMessage(text, transportGeneration: transportGeneration)
                    } else {
                        StreamingSfuLog.write("receive binary frame bytes=\(data.count)")
                    }
                @unknown default:
                    StreamingSfuLog.write("receive unknown frame kind")
                }
            } catch {
                guard !Task.isCancelled else { return }
                let closeCode = task.closeCode.rawValue
                let closeReason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                StreamingSfuLog.write("receive failed gen=\(transportGeneration) closeCode=\(closeCode) reason=\(closeReason.isEmpty ? "-" : closeReason) error=\(error.localizedDescription)")
                guard task === webSocketTask, transportGeneration == self.transportGeneration else { return }
                scheduleReconnect(reason: "socket-closed-\(closeCode)")
                return
            }
        }
    }

    private func handleIncomingMessage(_ text: String, transportGeneration: Int) {
        guard transportGeneration == self.transportGeneration else {
            StreamingSfuLog.write("message ignored, stale transport")
            return
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            StreamingSfuLog.write("message unparsable len=\(text.count) head=\(String(text.prefix(200)))")
            return
        }

        messagesReceived += 1

        switch type {
        case "ping":
            send(["type": "pong"], transportGeneration: transportGeneration)
        case "offer":
            guard let sdp = json["sdp"] as? String, !sdp.isEmpty else {
                StreamingSfuLog.write("offer without sdp raw=\(String(text.prefix(300)))")
                return
            }
            offersReceived += 1
            let generation = int64Value(json["offer_generation"]) ?? 0
            let sections = Self.sdpMediaSections(sdp)
            StreamingSfuLog.write("offer #\(offersReceived) generation=\(generation) sdpLen=\(sdp.count) sections=\(Self.describe(sections))")
            handleOffer(generation: generation, sdp: sdp, transportGeneration: transportGeneration)
        case "error":
            StreamingSfuLog.write("server error raw=\(String(text.prefix(400)))")
            scheduleReconnect(reason: "server-error")
        case "joined":
            StreamingSfuLog.write("joined raw=\(String(text.prefix(400)))")
        case "pong":
            break
        default:
            StreamingSfuLog.write("message type=\(type) raw=\(String(text.prefix(400)))")
        }
    }

    private func handleOffer(generation: Int64, sdp: String, transportGeneration: Int) {
        guard transportGeneration == self.transportGeneration else { return }
        guard !negotiating else {
            StreamingSfuLog.write("offer generation=\(generation) queued, negotiation in progress")
            pendingOffer = (generation, sdp)
            return
        }
        Task { @MainActor [weak self] in
            await self?.negotiate(
                generation: generation,
                sdp: sdp,
                transportGeneration: transportGeneration
            )
        }
    }

    private func negotiate(generation: Int64, sdp: String, transportGeneration: Int) async {
        guard transportGeneration == self.transportGeneration,
              let pc = peerConnection else {
            StreamingSfuLog.write("negotiate skipped generation=\(generation) staleTransport=\(transportGeneration != self.transportGeneration) peerConnection=\(peerConnection != nil)")
            return
        }
        if negotiating {
            pendingOffer = (generation, sdp)
            return
        }

        negotiating = true
        var nextOffer: (Int64, String)? = (generation, sdp)
        while let currentOffer = nextOffer {
            guard transportGeneration == self.transportGeneration,
                  let currentPeerConnection = peerConnection,
                  currentPeerConnection === pc else {
                StreamingSfuLog.write("negotiate aborted before setRemote generation=\(currentOffer.0)")
                negotiating = false
                return
            }

            do {
                let offerDescription = RTCSessionDescription(type: .offer, sdp: currentOffer.1)
                let offerSections = Self.sdpMediaSections(currentOffer.1)
                if !didLogSdpForTransport {
                    StreamingSfuLog.writeBlock("offer-sdp", currentOffer.1)
                }
                try await Self.setRemoteDescription(offerDescription, on: currentPeerConnection)
                StreamingSfuLog.write("setRemoteDescription ok generation=\(currentOffer.0) transceivers=\(currentPeerConnection.transceivers.count)")
                StreamingSfuLog.write("transceivers after remote: \(Self.describeTransceivers(currentPeerConnection))")

                guard transportGeneration == self.transportGeneration,
                      currentPeerConnection === self.peerConnection else {
                    StreamingSfuLog.write("negotiate aborted after setRemote generation=\(currentOffer.0)")
                    negotiating = false
                    return
                }

                try Self.validateOfferLayout(offerSections, peerConnection: currentPeerConnection)
                Self.configureAudienceTransceivers(
                    currentPeerConnection,
                    sections: offerSections
                )
                StreamingSfuLog.write("transceivers after direction: \(Self.describeTransceivers(currentPeerConnection))")
                let answer = try await Self.createAnswer(on: currentPeerConnection)
                try await Self.setLocalDescription(answer, on: currentPeerConnection)

                guard transportGeneration == self.transportGeneration,
                      currentPeerConnection === self.peerConnection,
                      let localDescription = currentPeerConnection.localDescription else {
                    StreamingSfuLog.write("negotiate aborted after setLocal generation=\(currentOffer.0)")
                    negotiating = false
                    return
                }
                let answerSections = Self.sdpMediaSections(localDescription.sdp)
                StreamingSfuLog.write("answer generation=\(currentOffer.0) sdpLen=\(localDescription.sdp.count) sections=\(Self.describe(answerSections))")
                if !didLogSdpForTransport {
                    StreamingSfuLog.writeBlock("answer-sdp", localDescription.sdp)
                    didLogSdpForTransport = true
                }
                try Self.validateAnswerLayout(
                    offerSections: offerSections,
                    answerSections: answerSections
                )

                scanRemoteAudioTrack()
                answersSent += 1
                send(
                    [
                        "type": "answer",
                        "offer_generation": NSNumber(value: currentOffer.0),
                        "sdp": localDescription.sdp,
                    ],
                    transportGeneration: transportGeneration
                ) { error in
                    guard let error else { return }
                    StreamingSfuLog.write("send answer failed generation=\(currentOffer.0) error=\(error.localizedDescription)")
                }
                StreamingSfuLog.write("answer sent generation=\(currentOffer.0)")
            } catch {
                StreamingSfuLog.write("negotiate failed generation=\(currentOffer.0) error=\(Self.describe(error))")
                negotiating = false
                scheduleReconnect(reason: "negotiate-failed")
                return
            }

            nextOffer = pendingOffer
            pendingOffer = nil
            if nextOffer != nil {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        negotiating = false
    }

    private func scheduleReconnect(reason: String) {
        guard activeStreamChannelId != nil else {
            StreamingSfuLog.write("reconnect skipped (\(reason)), no active channel")
            return
        }
        guard reconnectTask == nil else {
            StreamingSfuLog.write("reconnect skipped (\(reason)), already scheduled")
            return
        }

        closeTransport()
        setStreaming(false)
        let generation = sessionGeneration
        let delayIndex = min(reconnectAttempt, Self.reconnectDelays.count - 1)
        let delay = Self.reconnectDelays[delayIndex]
        reconnectAttempt = min(reconnectAttempt + 1, Self.reconnectDelays.count - 1)
        StreamingSfuLog.write("reconnect scheduled reason=\(reason) attempt=\(reconnectAttempt) delay=\(delay / 1_000_000)ms")

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard generation == self.sessionGeneration, self.activeStreamChannelId != nil else {
                StreamingSfuLog.write("reconnect cancelled, session changed")
                return
            }
            guard let freshToken = await self.tokenProvider?(), !freshToken.isEmpty else {
                StreamingSfuLog.write("reconnect token refresh failed")
                self.scheduleReconnect(reason: "token-refresh-failed")
                return
            }
            guard generation == self.sessionGeneration, self.activeStreamChannelId != nil else { return }
            StreamingSfuLog.write("reconnect token refreshed \(StreamingSfuLog.tokenSummary(freshToken))")
            self.token = freshToken
            self.openConnection()
        }
    }

    private static func ensureSSL() {
        guard !sslInitialized else { return }
        RTCInitializeSSL()
        sslInitialized = true
    }

    private func configureWebRTCAudioForPlayback() -> Bool {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        cfg.mode = AVAudioSession.Mode.default.rawValue
        cfg.categoryOptions = [.mixWithOthers, .defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        RTCAudioSessionConfiguration.setWebRTC(cfg)
        do {
            try rtc.setConfiguration(cfg)
            try rtc.setActive(true)
            hasActivatedAudioSession = true
            rtc.isAudioEnabled = true
            StreamingSfuLog.write("audio session active category=\(cfg.category) mode=\(cfg.mode)")
            return true
        } catch {
            StreamingSfuLog.write("audio session failed error=\(Self.describe(error))")
            return false
        }
    }

    private func deactivateWebRTCAudio() {
        let rtc = RTCAudioSession.sharedInstance()
        guard hasActivatedAudioSession else { return }
        hasActivatedAudioSession = false
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        rtc.isAudioEnabled = false
        try? rtc.setActive(false)
    }

    private func setStreaming(_ value: Bool) {
        guard isStreaming != value else { return }
        isStreaming = value
        StreamingSfuLog.write("streaming=\(value)")
        onStreamingStateChanged?()
    }

    private func scanRemoteAudioTrack() {
        guard let pc = peerConnection else { return }
        for transceiver in pc.transceivers {
            guard let track = transceiver.receiver.track else { continue }
            if track.kind == "audio", let audio = track as? RTCAudioTrack {
                remoteAudioTrack = audio
                audio.isEnabled = true
            } else if track.kind == "video" {
                track.isEnabled = false
            }
        }
        StreamingSfuLog.write("scanRemoteAudioTrack audioTrack=\(remoteAudioTrack?.trackId ?? "none")")
    }

    private static func makePeerConnectionFactory() -> RTCPeerConnectionFactory {
        let enc = RTCDefaultVideoEncoderFactory()
        let dec = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: enc, decoderFactory: dec)
    }

    private static func makePeerConnection(
        factory: RTCPeerConnectionFactory,
        delegate: RTCPeerConnectionDelegate
    ) -> RTCPeerConnection? {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = []
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        return factory.peerConnection(with: config, constraints: constraints, delegate: delegate)
    }

    private static func baseWebSocketURLString() -> String {
        let base = MezonConfig.sfuWebSocketURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? "<empty>" : base
    }

    private static func makeWebSocketURL(token: String) -> URL? {
        let base = MezonConfig.sfuWebSocketURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "access_token" }
        items.append(URLQueryItem(name: "access_token", value: token))
        components.queryItems = items
        return components.url
    }

    private static func configureAudienceTransceivers(
        _ peerConnection: RTCPeerConnection,
        sections: [SdpMediaSection]
    ) {
        for (index, transceiver) in peerConnection.transceivers.enumerated() {
            guard index < sections.count else { continue }
            if sections[index].kind == "video" || transceiver.mediaType == .video {
                transceiver.setDirection(.inactive, error: nil)
            } else {
                transceiver.setDirection(.recvOnly, error: nil)
            }
        }
    }

    private static func validateOfferLayout(
        _ sections: [SdpMediaSection],
        peerConnection: RTCPeerConnection
    ) throws {
        guard !sections.isEmpty,
              sections.first?.kind == "audio",
              sections.first?.mid == "0",
              sections.count == peerConnection.transceivers.count else {
            StreamingSfuLog.write("offer layout rejected code=1 sections=\(describe(sections)) transceivers=\(peerConnection.transceivers.count)")
            throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 1)
        }
        guard Set(sections.map(\.mid)).count == sections.count else {
            StreamingSfuLog.write("offer layout rejected code=2 duplicate mid sections=\(describe(sections))")
            throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 2)
        }
        for (section, transceiver) in zip(sections, peerConnection.transceivers) {
            guard section.mid == transceiver.mid else {
                StreamingSfuLog.write("offer layout rejected code=3 mid mismatch section=\(section.mid) transceiver=\(transceiver.mid)")
                throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 3)
            }
        }
    }

    private static func validateAnswerLayout(
        offerSections: [SdpMediaSection],
        answerSections: [SdpMediaSection]
    ) throws {
        guard offerSections.count == answerSections.count else {
            StreamingSfuLog.write("answer layout rejected code=4 offer=\(offerSections.count) answer=\(answerSections.count)")
            throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 4)
        }
        for (offer, answer) in zip(offerSections, answerSections) {
            guard offer.kind == answer.kind, offer.mid == answer.mid else {
                StreamingSfuLog.write("answer layout rejected code=5 offer=\(offer.kind)/\(offer.mid) answer=\(answer.kind)/\(answer.mid)")
                throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 5)
            }
            if answer.kind == "video" {
                guard answer.direction == "inactive" else {
                    StreamingSfuLog.write("answer layout rejected code=6 mid=\(answer.mid) direction=\(answer.direction ?? "none")")
                    throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 6)
                }
            } else {
                guard answer.direction == "recvonly" || answer.direction == "inactive" else {
                    StreamingSfuLog.write("answer layout rejected code=7 mid=\(answer.mid) direction=\(answer.direction ?? "none")")
                    throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 7)
                }
            }
        }
    }

    private static func sdpMediaSections(_ sdp: String) -> [SdpMediaSection] {
        var sections: [(kind: String, mid: String, direction: String?)] = []
        var currentKind: String?
        var currentMid = ""
        var currentDirection: String?

        func appendCurrent() {
            guard let currentKind else { return }
            sections.append((currentKind, currentMid, currentDirection))
        }

        let normalized = sdp.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("m=") {
                appendCurrent()
                let parts = line.split(separator: " ")
                currentKind = parts.first.map { String($0.dropFirst(2)) }
                currentMid = ""
                currentDirection = nil
            } else if line.hasPrefix("a=mid:") {
                currentMid = String(line.dropFirst("a=mid:".count))
            } else if ["a=sendrecv", "a=sendonly", "a=recvonly", "a=inactive"].contains(line) {
                currentDirection = String(line.dropFirst(2))
            }
        }
        appendCurrent()
        return sections.map { SdpMediaSection(kind: $0.kind, mid: $0.mid, direction: $0.direction) }
    }

    private static func describe(_ sections: [SdpMediaSection]) -> String {
        guard !sections.isEmpty else { return "<none>" }
        return sections
            .map { "\($0.kind)/mid:\($0.mid.isEmpty ? "-" : $0.mid)/\($0.direction ?? "-")" }
            .joined(separator: ",")
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code) \(nsError.localizedDescription)"
    }

    private static func describe(_ direction: RTCRtpTransceiverDirection) -> String {
        switch direction {
        case .sendRecv: return "sendrecv"
        case .sendOnly: return "sendonly"
        case .recvOnly: return "recvonly"
        case .inactive: return "inactive"
        case .stopped: return "stopped"
        default: return "raw\(direction.rawValue)"
        }
    }

    private static func describe(_ mediaType: RTCRtpMediaType) -> String {
        switch mediaType {
        case .audio: return "audio"
        case .video: return "video"
        case .data: return "data"
        default: return "raw\(mediaType.rawValue)"
        }
    }

    private static func describeTransceivers(_ peerConnection: RTCPeerConnection) -> String {
        let rows = peerConnection.transceivers.enumerated().map { index, transceiver -> String in
            var current = RTCRtpTransceiverDirection.inactive
            let hasCurrent = transceiver.currentDirection(&current)
            let direction = hasCurrent ? current : transceiver.direction
            let track = transceiver.receiver.track
            let mid = transceiver.mid.isEmpty ? "-" : transceiver.mid
            return "#\(index) mid=\(mid) type=\(describe(transceiver.mediaType)) dir=\(describe(direction)) track=\(track?.kind ?? "none")"
        }
        return rows.isEmpty ? "<none>" : rows.joined(separator: " ; ")
    }

    private static func createAnswer(on pc: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.answer(for: constraints) { sdp, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: NSError(domain: "Mezon.StreamingWebRTCSession", code: 8))
                }
            }
        }
    }

    private static func setRemoteDescription(_ description: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func setLocalDescription(_ description: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
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

    private func send(
        _ object: [String: Any],
        transportGeneration: Int,
        completion: ((Error?) -> Void)? = nil
    ) {
        guard transportGeneration == self.transportGeneration,
              let task = webSocketTask,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            StreamingSfuLog.write("send dropped type=\(object["type"] as? String ?? "?") staleTransport=\(transportGeneration != self.transportGeneration) socket=\(webSocketTask != nil)")
            completion?(NSError(domain: "Mezon.StreamingWebRTCSession", code: 9))
            return
        }
        task.send(.string(text)) { error in
            completion?(error)
        }
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}

extension StreamingWebRTCSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        let name: String
        switch state {
        case .stable: name = "stable"
        case .haveLocalOffer: name = "haveLocalOffer"
        case .haveLocalPrAnswer: name = "haveLocalPrAnswer"
        case .haveRemoteOffer: name = "haveRemoteOffer"
        case .haveRemotePrAnswer: name = "haveRemotePrAnswer"
        case .closed: name = "closed"
        @unknown default: name = "raw\(state.rawValue)"
        }
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            self.lastSignalingState = name
            StreamingSfuLog.write("signaling state=\(name)")
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            StreamingSfuLog.write("stream added id=\(stream.streamId) audio=\(stream.audioTracks.count) video=\(stream.videoTracks.count)")
            for track in stream.audioTracks {
                self.remoteAudioTrack = track
                track.isEnabled = true
            }
            for track in stream.videoTracks {
                track.isEnabled = false
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        let name: String
        switch state {
        case .new: name = "new"
        case .checking: name = "checking"
        case .connected: name = "connected"
        case .completed: name = "completed"
        case .failed: name = "failed"
        case .disconnected: name = "disconnected"
        case .closed: name = "closed"
        default: name = "raw\(state.rawValue)"
        }
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            self.lastIceState = name
            StreamingSfuLog.write("ice state=\(name) candidates=\(self.localCandidatesGathered)")
            switch state {
            case .connected, .completed:
                self.reconnectTask?.cancel()
                self.reconnectTask = nil
                self.reconnectAttempt = 0
                self.scanRemoteAudioTrack()
                if self.hasActivatedAudioSession {
                    let rtc = RTCAudioSession.sharedInstance()
                    rtc.lockForConfiguration()
                    rtc.isAudioEnabled = true
                    rtc.unlockForConfiguration()
                }
                self.setStreaming(true)
            case .disconnected, .failed:
                self.scheduleReconnect(reason: "ice-\(name)")
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        let name: String
        switch newState {
        case .new: name = "new"
        case .connecting: name = "connecting"
        case .connected: name = "connected"
        case .disconnected: name = "disconnected"
        case .failed: name = "failed"
        case .closed: name = "closed"
        @unknown default: name = "raw\(newState.rawValue)"
        }
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            self.lastPeerConnectionState = name
            StreamingSfuLog.write("peerConnection state=\(name)")
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didChange state: RTCIceGatheringState) {
        let name: String
        switch state {
        case .new: name = "new"
        case .gathering: name = "gathering"
        case .complete: name = "complete"
        @unknown default: name = "raw\(state.rawValue)"
        }
        StreamingSfuLog.write("iceGathering state=\(name)")
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candidateSdp = candidate.sdp
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.localCandidatesGathered += 1
            if self.localCandidatesGathered <= 6 {
                StreamingSfuLog.write("local candidate #\(self.localCandidatesGathered) \(candidateSdp)")
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didOpen _: RTCDataChannel) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams _: [RTCMediaStream]) {
        Task { @MainActor [weak self] in
            guard let self, let track = rtpReceiver.track else { return }
            StreamingSfuLog.write("receiver added kind=\(track.kind) id=\(track.trackId)")
            if track.kind == "audio", let audio = track as? RTCAudioTrack {
                self.remoteAudioTrack = audio
                audio.isEnabled = true
            } else if track.kind == "video" {
                track.isEnabled = false
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCRtpReceiver) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        Task { @MainActor [weak self] in
            guard let self, let track = transceiver.receiver.track else { return }
            StreamingSfuLog.write("started receiving mid=\(transceiver.mid) kind=\(track.kind)")
            if track.kind == "audio", let audio = track as? RTCAudioTrack {
                self.remoteAudioTrack = audio
                audio.isEnabled = true
            } else if track.kind == "video" {
                track.isEnabled = false
            }
        }
    }
}
