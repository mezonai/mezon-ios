import AVFoundation
import Foundation
import WebRTC

@available(iOS 13.0, *)
final class MezonSfuSession: NSObject {

    private static let midAudio = "0"
    private static let midCamera = "1"
    private static let midScreen = "2"
    private static let captureWidth: Int32 = 640
    private static let captureHeight: Int32 = 360
    private static let captureFps = 24
    private static let speakingPollNanos: UInt64 = 300_000_000
    private static let reconnectPollNanos: UInt64 = 3_000_000_000
    private static let maxReconnectAttempts = 40
    private static let speakingThreshold = 0.02

    private static var sslInitialized = false
    private static var _factory: RTCPeerConnectionFactory?

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

    var onConnectionState: ((SfuConnectionState) -> Void)?
    var onParticipants: (([SfuParticipant]) -> Void)?
    var onRoleChanged: ((SfuRole) -> Void)?
    var onError: ((String, String?) -> Void)?
    var onLocalVideoTrack: ((RTCVideoTrack?) -> Void)?
    var onSpeaking: ((Set<String>) -> Void)?
    var onPushToTalkActive: ((Bool) -> Void)?
    var tokenProvider: ((@escaping (String?) -> Void) -> Void)?

    private(set) var role: SfuRole = .speaker
    private(set) var isConnected = false
    private(set) var micEnabled = false
    private(set) var cameraEnabled = false
    private(set) var pttActive = false
    private(set) var localCameraTrack: RTCVideoTrack?
    private(set) var participants: [SfuParticipant] = []
    private(set) var speakingIds: Set<String> = []
    private(set) var cameraPosition: AVCaptureDevice.Position = .front

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var receiveTask: CancelHandle?
    private var pollTasks: [CancelHandle] = []
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

    private var active = false
    private var socketOpen = false
    private var connecting = false
    private var connectionGen = 0
    private var stateRestored = false
    private var reconnectAttempts = 0

    private var negotiating = false
    private var pendingOffer: (Int64, String)?

    private var transceiverCache: [RTCRtpTransceiver] = []

    private var userIdByMid: [String: String] = [:]
    private var peerIdByMid: [String: String] = [:]
    private var roleByMid: [String: SfuRole] = [:]
    private var leftMids: Set<String> = []
    private var remote: [String: RemoteEntry] = [:]
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

    func clearCallbacks() {
        onConnectionState = nil
        onParticipants = nil
        onRoleChanged = nil
        onError = nil
        onLocalVideoTrack = nil
        onSpeaking = nil
        onPushToTalkActive = nil
    }

    @available(iOS 13.0, *)
    @MainActor
    func join(channelId: Int64, clanId: Int64, userId: String, token: String, role: SfuRole) {
        leave()
        self.channelId = channelId
        self.userId = userId
        self.token = token
        self.role = role
        micEnabled = false
        cameraEnabled = false
        pttActive = false
        joined = false
        localTracksAdded = false
        active = true
        isConnected = false
        reconnectAttempts = 0

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
                if self.reconnectAttempts >= Self.maxReconnectAttempts {
                    self.active = false
                    self.emitState(.failed)
                    break
                }
                self.reconnectAttempts += 1
                if let provider = self.tokenProvider {
                    let fresh = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
                        provider { continuation.resume(returning: $0) }
                    }
                    if let fresh, !fresh.isEmpty {
                        self.token = fresh
                    }
                }
                self.openConnection(initial: false)
            }
        }
        pollTasks = [CancelHandle { speakingTask.cancel() }, CancelHandle { reconnectTask.cancel() }]
    }

    func leave() {
        let hadConnection = peerConnection != nil || webSocketTask != nil
        active = false
        connectionGen += 1
        socketOpen = false
        connecting = false
        stateRestored = false
        joined = false
        for handle in pollTasks {
            handle.cancel()
        }
        pollTasks = []
        receiveTask?.cancel()
        receiveTask = nil
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
        peerConnection?.close()
        peerConnection = nil
        localTracksAdded = false
        negotiating = false
        pendingOffer = nil
        userIdByMid.removeAll()
        peerIdByMid.removeAll()
        roleByMid.removeAll()
        leftMids.removeAll()
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
        send(["type": "mute", "is_mute": false])
        send(["type": "push_to_talk", "active": true])
    }

    func pttRelease() {
        guard role == .audience else { return }
        send(["type": "push_to_talk", "active": false])
        send(["type": "mute", "is_mute": true])
    }

    @available(iOS 13.0, *)
    @MainActor
    private func openConnection(initial: Bool) {
        connecting = true
        connectionGen += 1
        let gen = connectionGen
        stateRestored = false
        if !initial {
            webSocketTask?.cancel(with: .goingAway, reason: nil)
            urlSession?.invalidateAndCancel()
            peerConnection?.close()
            negotiating = false
            pendingOffer = nil
            localTracksAdded = false
            userIdByMid.removeAll()
            peerIdByMid.removeAll()
            roleByMid.removeAll()
            leftMids.removeAll()
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
        let receiveTaskWork = Task { [weak self] in
            await self?.receiveLoop(task: task, gen: gen)
        }
        receiveTask = CancelHandle { receiveTaskWork.cancel() }
        sendJoin(gen: gen)
    }

    @available(iOS 13.0, *)
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

    @available(iOS 13.0, *)
    @MainActor
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
                    handleSocketClosed(gen: gen)
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

    @available(iOS 13.0, *)
    @MainActor
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
            if let members = msg["members"] as? [[String: Any]], applyPeers(members) {
                syncRemoteMedia()
            }
            joined = true
            reconnectAttempts = 0
            if !stateRestored {
                stateRestored = true
                send(["type": "mute", "is_mute": !micEnabled])
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
            if let sdp = msg["sdp"] as? String, !sdp.isEmpty {
                let rawGeneration = msg["offer_generation"]
                let generation = (rawGeneration as? NSNumber)?.int64Value
                    ?? (rawGeneration as? String).flatMap(Int64.init)
                    ?? 0
                onOffer(generation: generation, sdp: sdp)
            }
        case "error":
            let detail = (msg["message"] as? String) ?? ""
            if detail == "invalid_push_to_talk" || detail == "push_to_talk_rejected" {
                pttActive = false
                localAudioTrack?.isEnabled = false
                onPushToTalkActive?(false)
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

    @available(iOS 13.0, *)
    @MainActor
    private func onOffer(generation: Int64, sdp: String) {
        parseMsids(sdp)
        let gen = connectionGen
        Task { [weak self] in
            await self?.negotiate(firstGeneration: generation, firstSdp: sdp, gen: gen)
        }
    }

    @available(iOS 13.0, *)
    @MainActor
    private func negotiate(firstGeneration: Int64, firstSdp: String, gen: Int) async {
        if negotiating {
            pendingOffer = (firstGeneration, firstSdp)
            return
        }
        negotiating = true
        var offer: (Int64, String)? = (firstGeneration, firstSdp)
        while let current = offer {
            guard gen == connectionGen, let pc = peerConnection else { break }
            let (generation, sdp) = current
            do {
                let stableSdp = stabilizeInactiveVideoSections(offerSdp: sdp, currentRemoteSdp: pc.remoteDescription?.sdp)
                try await awaitSetRemote(pc, RTCSessionDescription(type: .offer, sdp: stableSdp))
                transceiverCache = pc.transceivers
                attachLocalTracks(pc)
                let answer = try await awaitCreateAnswer(pc)
                try await awaitSetLocal(pc, RTCSessionDescription(type: .answer, sdp: answer.sdp))
                syncRemoteMedia()
                if let local = pc.localDescription {
                    send([
                        "type": "answer",
                        "offer_generation": NSNumber(value: generation),
                        "sdp": patchAnswerForSfu(local.sdp),
                    ])
                }
            } catch {
                await rollbackIfStuck(pc)
            }
            offer = pendingOffer
            pendingOffer = nil
            if offer != nil {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        negotiating = false
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
        let source = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
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

    @available(iOS 13.0, *)
    private func pollSpeaking(_ pc: RTCPeerConnection) {
        pc.statistics { [weak self] report in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var speaking = Set<String>()
                for stat in report.statistics.values {
                    guard let kind = stat.values["kind"] as? String, kind == "audio" else { continue }
                    guard let level = (stat.values["audioLevel"] as? NSNumber)?.doubleValue,
                          level > Self.speakingThreshold else { continue }
                    if stat.type == "media-source" {
                        if self.micEnabled || self.pttActive {
                            speaking.insert(self.userId)
                        }
                    } else if stat.type == "inbound-rtp" {
                        if let mid = stat.values["mid"] as? String, let uid = self.userIdByMid[mid] {
                            speaking.insert(uid)
                        }
                    }
                }
                if speaking != self.speakingIds {
                    self.speakingIds = speaking
                    self.onSpeaking?(speaking)
                }
            }
        }
    }

    private func applyPeers(_ members: [[String: Any]]) -> Bool {
        var revivedMids = false
        for peer in members {
            guard let peerId = stringValue(peer["peer_id"]), !peerId.isEmpty else { continue }
            let userIdValue = stringValue(peer["user_id"]).flatMap { $0.isEmpty ? nil : $0 }
            let peerRole: SfuRole? = peer["role"] != nil ? SfuRole.fromWire(stringValue(peer["role"])) : nil
            var mids: [String] = []
            for key in ["mid_audio", "mid_video", "mid_screen"] {
                if let mid = stringValue(peer[key]), !mid.isEmpty, mid != "0" {
                    mids.append(mid)
                }
            }
            for mid in mids {
                if leftMids.remove(mid) != nil {
                    revivedMids = true
                }
                peerIdByMid[mid] = peerId
                if let userIdValue {
                    userIdByMid[mid] = userIdValue
                }
                if let peerRole {
                    roleByMid[mid] = peerRole
                }
            }
            let existing = remoteOrder.first(where: { remote[$0]?.peerId == peerId })
            guard let participantId = existing ?? mids.first.map({ remoteParticipantId($0) }) else { continue }
            let entry = remoteEntry(id: participantId)
            entry.peerId = peerId
            if let userIdValue {
                entry.userId = userIdValue
            }
            if let peerRole {
                entry.role = peerRole
            }
            if let muted = boolValue(peer["is_mute"]) {
                entry.muted = muted
            }
            if let cameraActive = boolValue(peer["camera_active"]) {
                entry.cameraActive = cameraActive
            }
            if let screenActive = boolValue(peer["screen_active"]) {
                entry.screenActive = screenActive
            }
        }
        return revivedMids
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
        for key in ["mid_audio", "mid_video", "mid_screen"] {
            guard let mid = stringValue(msg[key]), !mid.isEmpty, mid != "0" else { continue }
            leftMids.insert(mid)
            removeRemoteEntry(id: remoteParticipantId(mid))
        }
    }

    private func syncRemoteMedia() {
        for tc in transceiverCache {
            let mid = tc.mid
            if mid.isEmpty { continue }
            if mid == Self.midAudio || mid == Self.midCamera || mid == Self.midScreen { continue }
            if leftMids.contains(mid) { continue }
            var current = RTCRtpTransceiverDirection.inactive
            let hasCurrent = tc.currentDirection(&current)
            let direction = hasCurrent ? current : tc.direction
            let id = remoteParticipantId(mid)
            let kind = remoteKind(mid)
            if direction == .inactive || direction == .stopped {
                guard let entry = remote[id] else { continue }
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
                continue
            }
            guard let track = tc.receiver.track else { continue }
            let entry = remoteEntry(id: id)
            if let uid = userIdByMid[mid] {
                entry.userId = uid
            }
            if let pid = peerIdByMid[mid] {
                entry.peerId = pid
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
        emitParticipants()
    }

    private func emitParticipants() {
        let list = remoteOrder.compactMap { remote[$0] }.map { entry in
            SfuParticipant(
                id: entry.id,
                userId: entry.userId,
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

    private func parseMsids(_ sdp: String) {
        guard let regex = Self.msidUserRegex else { return }
        var currentMid: String?
        for rawLine in sdpLines(sdp) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("m=") {
                currentMid = nil
            } else if line.hasPrefix("a=mid:") {
                currentMid = String(line.dropFirst("a=mid:".count)).trimmingCharacters(in: .whitespaces)
            } else if let mid = currentMid, line.hasPrefix("a=msid:") {
                let payload = String(line.dropFirst("a=msid:".count)).trimmingCharacters(in: .whitespaces)
                let parts = payload.split(whereSeparator: { $0 == " " || $0 == "\t" })
                for part in parts {
                    let token = String(part)
                    let range = NSRange(token.startIndex..<token.endIndex, in: token)
                    if let match = regex.firstMatch(in: token, options: [], range: range),
                       match.numberOfRanges > 1,
                       let groupRange = Range(match.range(at: 1), in: token) {
                        userIdByMid[mid] = String(token[groupRange])
                        break
                    }
                }
            }
        }
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

    @available(iOS 13.0, *)
    @MainActor
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

    @available(iOS 13.0, *)
    @MainActor
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

    @available(iOS 13.0, *)
    @MainActor
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

    @available(iOS 13.0, *)
    @MainActor
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

@available(iOS 13.0, *)
extension MezonSfuSession: RTCPeerConnectionDelegate {
    @available(iOS 13.0, *)
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            switch newState {
            case .connected, .completed:
                self.isConnected = true
                let rtc = RTCAudioSession.sharedInstance()
                rtc.lockForConfiguration()
                rtc.isAudioEnabled = true
                rtc.unlockForConfiguration()
                self.emitState(.connected)
            case .failed:
                if self.active && self.joined {
                    self.emitState(.disconnected)
                    self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
                    self.handleSocketClosed(gen: self.connectionGen)
                } else if self.active {
                    self.emitState(.failed)
                }
            case .disconnected:
                self.emitState(.disconnected)
            default:
                break
            }
        }
    }

    @available(iOS 13.0, *)
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        Task { @MainActor [weak self] in
            guard let self, peerConnection === self.peerConnection else { return }
            self.syncRemoteMedia()
        }
    }

    @available(iOS 13.0, *)
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
    @available(iOS 13.0, *)
    @MainActor
    static func requestIfNeeded() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }
}

enum VoiceChannelCameraPermission {
    @available(iOS 13.0, *)
    @MainActor
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
