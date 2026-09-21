import AVFoundation
import Foundation
import WebRTC

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
    private var tokenProvider: (() async -> String?)?
    private var token = ""
    private var sessionGeneration = 0
    private var transportGeneration = 0
    private var reconnectAttempt = 0
    private var hasActivatedAudioSession = false
    private var negotiating = false
    private var pendingOffer: (Int64, String)?

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
        guard channelId != 0, !token.isEmpty else { return }
        if activeStreamChannelId == channelId, activeStreamChannelId != nil {
            return
        }

        disconnect()
        activeStreamChannelId = channelId
        self.token = token
        self.tokenProvider = tokenProvider
        reconnectAttempt = 0
        negotiating = false
        pendingOffer = nil

        Self.ensureSSL()
        guard configureWebRTCAudioForPlayback() else {
            disconnect()
            return
        }

        openConnection()
    }

    func disconnect() {
        sessionGeneration &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
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
        disconnect()
    }

    private func openConnection() {
        guard activeStreamChannelId != nil else { return }
        closeTransport()
        transportGeneration &+= 1
        let generation = transportGeneration

        let factory = Self.makePeerConnectionFactory()
        peerFactory = factory
        guard let pc = Self.makePeerConnection(factory: factory, delegate: self) else {
            scheduleReconnect()
            return
        }
        peerConnection = pc

        guard let wsURL = Self.makeWebSocketURL(token: token) else {
            scheduleReconnect()
            return
        }

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
        send(
            [
                "type": "join",
                "room": String(activeStreamChannelId ?? 0),
                "token": token,
                "role": "audience",
            ],
            transportGeneration: transportGeneration
        ) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, transportGeneration == self.transportGeneration else { return }
                self.scheduleReconnect()
            }
        }
    }

    private func receiveMessages(from task: URLSessionWebSocketTask, transportGeneration: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard !Task.isCancelled else { return }
                guard task === webSocketTask, transportGeneration == self.transportGeneration else { return }
                switch message {
                case .string(let text):
                    handleIncomingMessage(text, transportGeneration: transportGeneration)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncomingMessage(text, transportGeneration: transportGeneration)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard task === webSocketTask, transportGeneration == self.transportGeneration else { return }
                scheduleReconnect()
                return
            }
        }
    }

    private func handleIncomingMessage(_ text: String, transportGeneration: Int) {
        guard transportGeneration == self.transportGeneration,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "ping":
            send(["type": "pong"], transportGeneration: transportGeneration)
        case "offer":
            guard let sdp = json["sdp"] as? String, !sdp.isEmpty else { return }
            let generation = int64Value(json["offer_generation"]) ?? 0
            handleOffer(generation: generation, sdp: sdp, transportGeneration: transportGeneration)
        case "error":
            scheduleReconnect()
        case "joined", "pong":
            break
        default:
            break
        }
    }

    private func handleOffer(generation: Int64, sdp: String, transportGeneration: Int) {
        guard transportGeneration == self.transportGeneration else { return }
        guard !negotiating else {
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
              let pc = peerConnection else { return }
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
                negotiating = false
                return
            }

            do {
                let offerDescription = RTCSessionDescription(type: .offer, sdp: currentOffer.1)
                let offerSections = Self.sdpMediaSections(currentOffer.1)
                try await Self.setRemoteDescription(offerDescription, on: currentPeerConnection)

                guard transportGeneration == self.transportGeneration,
                      currentPeerConnection === self.peerConnection else {
                    negotiating = false
                    return
                }

                try Self.validateOfferLayout(offerSections, peerConnection: currentPeerConnection)
                Self.configureAudienceTransceivers(
                    currentPeerConnection,
                    sections: offerSections
                )
                let answer = try await Self.createAnswer(on: currentPeerConnection)
                try await Self.setLocalDescription(answer, on: currentPeerConnection)

                guard transportGeneration == self.transportGeneration,
                      currentPeerConnection === self.peerConnection,
                      let localDescription = currentPeerConnection.localDescription else {
                    negotiating = false
                    return
                }
                let answerSections = Self.sdpMediaSections(localDescription.sdp)
                try Self.validateAnswerLayout(
                    offerSections: offerSections,
                    answerSections: answerSections
                )

                scanRemoteAudioTrack()
                send(
                    [
                        "type": "answer",
                        "offer_generation": NSNumber(value: currentOffer.0),
                        "sdp": localDescription.sdp,
                    ],
                    transportGeneration: transportGeneration
                )
            } catch {
                negotiating = false
                scheduleReconnect()
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

    private func scheduleReconnect() {
        guard activeStreamChannelId != nil else { return }
        guard reconnectTask == nil else { return }

        closeTransport()
        setStreaming(false)
        let generation = sessionGeneration
        let delayIndex = min(reconnectAttempt, Self.reconnectDelays.count - 1)
        let delay = Self.reconnectDelays[delayIndex]
        reconnectAttempt = min(reconnectAttempt + 1, Self.reconnectDelays.count - 1)

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard generation == self.sessionGeneration, self.activeStreamChannelId != nil else { return }
            guard let freshToken = await self.tokenProvider?(), !freshToken.isEmpty else {
                self.scheduleReconnect()
                return
            }
            guard generation == self.sessionGeneration, self.activeStreamChannelId != nil else { return }
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
            return true
        } catch {
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
            throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 1)
        }
        guard Set(sections.map(\.mid)).count == sections.count else {
            throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 2)
        }
        for (section, transceiver) in zip(sections, peerConnection.transceivers) {
            guard section.mid == transceiver.mid else {
                throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 3)
            }
        }
    }

    private static func validateAnswerLayout(
        offerSections: [SdpMediaSection],
        answerSections: [SdpMediaSection]
    ) throws {
        guard offerSections.count == answerSections.count else {
            throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 4)
        }
        for (offer, answer) in zip(offerSections, answerSections) {
            guard offer.kind == answer.kind, offer.mid == answer.mid else {
                throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 5)
            }
            if answer.kind == "video" {
                guard answer.direction == "inactive" else {
                    throw NSError(domain: "Mezon.StreamingWebRTCSession", code: 6)
                }
            } else {
                guard answer.direction == "recvonly" || answer.direction == "inactive" else {
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

        for rawLine in sdp.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
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
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Task { @MainActor [weak self] in
            guard let self else { return }
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
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
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
                self.scheduleReconnect()
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didGenerate _: RTCIceCandidate) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didOpen _: RTCDataChannel) {}

    nonisolated func peerConnection(_: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams _: [RTCMediaStream]) {
        Task { @MainActor [weak self] in
            guard let self, let track = rtpReceiver.track else { return }
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
            if track.kind == "audio", let audio = track as? RTCAudioTrack {
                self.remoteAudioTrack = audio
                audio.isEnabled = true
            } else if track.kind == "video" {
                track.isEnabled = false
            }
        }
    }
}
