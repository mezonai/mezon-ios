import AVFoundation
import Foundation
import WebRTC

private extension RTCPeerConnection {
    func createOffer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            self.offer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "No SDP"])) }
            }
        }
    }

    func createAnswer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            self.answer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "No SDP"])) }
            }
        }
    }

    func setLocalDescriptionAsync(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setLocalDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func setRemoteDescriptionAsync(_ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.setRemoteDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func addIceCandidate(_ candidate: RTCIceCandidate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.add(candidate) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

enum CallConnectionState {
    case idle
    case ringing
    case connecting
    case connected
    case ended
}

@MainActor
final class WebRTCCallManager: NSObject {

    static let shared = WebRTCCallManager()

    private(set) var connectionState: CallConnectionState = .idle
    private(set) var isMicEnabled: Bool = true
    private(set) var isSpeakerEnabled: Bool = false
    private(set) var timeStartConnected: Date?

    var onStateChanged: ((CallConnectionState) -> Void)?
    var onCallEnded: (() -> Void)?

    private(set) var receiverId: Int64 = 0
    private(set) var channelId: Int64 = 0
    private(set) var callerId: Int64 = 0
    private(set) var isCaller: Bool = false
    private var callUUID: UUID?

    private var peerConnection: RTCPeerConnection?
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var localAudioTrack: RTCAudioTrack?
    private var pendingRemoteIceCandidates: [RTCIceCandidate] = []
    private var hasRemoteDescription = false
    private var callTimeoutTimer: Foundation.Timer?
    private var isCallCanceled = false

    private override init() {
        super.init()
        initializeFactory()
    }

    private func initializeFactory() {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }

    func startCall(
        receiverId: Int64,
        channelId: Int64,
        callerId: Int64,
        callerName: String,
        callerAvatar: String
    ) {
        guard connectionState == .idle else { return }
        self.receiverId = receiverId
        self.channelId = channelId
        self.callerId = callerId
        self.isCaller = true
        self.isCallCanceled = false
        self.callUUID = UUID()
        self.hasRemoteDescription = false

        updateState(.ringing)

        Task {
            let micGranted = await requestMicrophonePermission()
            guard micGranted else {
                endCall(sendQuit: true)
                return
            }

            guard let pc = createPeerConnection() else {
                endCall(sendQuit: true)
                return
            }
            self.peerConnection = pc

            addLocalAudioTrack(to: pc)

            do {
                let constraints = RTCMediaConstraints(
                    mandatoryConstraints: [
                        "OfferToReceiveAudio": "true",
                        "OfferToReceiveVideo": "false",
                    ],
                    optionalConstraints: nil
                )
                let offer = try await pc.createOffer(for: constraints)
                try await pc.setLocalDescriptionAsync(offer)

                guard !isCallCanceled else {
                    pc.close()
                    return
                }

                let sdpDict: [String: Any] = [
                    "type": RTCSessionDescription.string(for: offer.type),
                    "sdp": offer.sdp,
                    "callerName": callerName,
                    "callerAvatar": callerAvatar,
                ]
                let sdpJson = try JSONSerialization.data(withJSONObject: sdpDict)
                let sdpString = String(data: sdpJson, encoding: .utf8) ?? ""

                let pushBody: [String: Any] = [
                    "offer": sdpString,
                    "callerName": callerName,
                    "callerAvatar": callerAvatar,
                    "callerId": "\(callerId)",
                    "channelId": "\(channelId)",
                ]
                let pushJson = try JSONSerialization.data(withJSONObject: pushBody)
                let pushString = String(data: pushJson, encoding: .utf8) ?? ""

                MezonSocket.shared.makeCallPush(
                    receiverId: receiverId,
                    jsonData: pushString,
                    channelId: channelId,
                    callerId: callerId
                )

                MezonSocket.shared.forwardWebrtcSignaling(
                    receiverId: receiverId,
                    dataType: .sdpOffer,
                    jsonData: sdpString,
                    channelId: channelId,
                    callerId: callerId
                )

                isMicEnabled = true
                onStateChanged?(connectionState)

                callTimeoutTimer = Foundation.Timer.scheduledTimer(withTimeInterval: WebRTCConfig.callTimeoutSeconds, repeats: false) { [weak self] (_: Foundation.Timer) in
                    Task { @MainActor in
                        self?.handleCallTimeout()
                    }
                }

                if let uuid = callUUID {
                    CallKitManager.shared.startOutgoingCall(
                        uuid: uuid,
                        handle: "\(receiverId)",
                        displayName: callerName
                    )
                }
            } catch {
                endCall(sendQuit: true)
            }
        }
    }

    func answerCall(
        receiverId: Int64,
        channelId: Int64,
        callerId: Int64,
        offerSdp: String
    ) {
        guard connectionState == .idle || connectionState == .ringing else { return }
        self.receiverId = receiverId
        self.channelId = channelId
        self.callerId = callerId
        self.isCaller = false
        self.isCallCanceled = false
        self.hasRemoteDescription = false

        updateState(.connecting)

        Task {
            let micGranted = await requestMicrophonePermission()
            guard micGranted else {
                endCall(sendQuit: true)
                return
            }

            guard let pc = createPeerConnection() else {
                endCall(sendQuit: true)
                return
            }
            self.peerConnection = pc
            addLocalAudioTrack(to: pc)

            do {
                guard let offerData = offerSdp.data(using: .utf8),
                      let offerDict = try? JSONSerialization.jsonObject(with: offerData) as? [String: Any],
                      let sdpString = offerDict["sdp"] as? String else {
                    endCall(sendQuit: true)
                    return
                }

                let remoteDesc = RTCSessionDescription(type: .offer, sdp: sdpString)
                try await pc.setRemoteDescriptionAsync(remoteDesc)
                hasRemoteDescription = true

                for candidate in pendingRemoteIceCandidates {
                    try await pc.addIceCandidate(candidate)
                }
                pendingRemoteIceCandidates.removeAll()

                let answerConstraints = RTCMediaConstraints(
                    mandatoryConstraints: [
                        "OfferToReceiveAudio": "true",
                        "OfferToReceiveVideo": "false",
                    ],
                    optionalConstraints: nil
                )
                let answer = try await pc.createAnswer(for: answerConstraints)
                try await pc.setLocalDescriptionAsync(answer)

                let answerDict: [String: Any] = [
                    "type": RTCSessionDescription.string(for: answer.type),
                    "sdp": answer.sdp,
                ]
                let answerJson = try JSONSerialization.data(withJSONObject: answerDict)
                let answerString = String(data: answerJson, encoding: .utf8) ?? ""

                MezonSocket.shared.forwardWebrtcSignaling(
                    receiverId: receiverId,
                    dataType: .sdpAnswer,
                    jsonData: answerString,
                    channelId: channelId,
                    callerId: callerId
                )

                isMicEnabled = true
            } catch {
                endCall(sendQuit: true)
            }
        }
    }

    func handleSignalingMessage(_ msg: Mezon_Realtime_WebrtcSignalingFwd) {
        guard let dataType = WebRTCSignalingType(rawValue: msg.dataType) else { return }

        switch dataType {
        case .sdpOffer:
            break
        case .sdpAnswer:
            handleAnswer(msg)
        case .iceCandidate:
            handleICECandidate(msg)
        case .sdpQuit, .sdpTimeout:
            handleRemoteEndCall()
        case .sdpInit:
            break
        case .sdpStatusRemoteMedia:
            break
        case .sdpJoinedOtherCall:
            handleRemoteEndCall()
        }
    }

    private func handleAnswer(_ msg: Mezon_Realtime_WebrtcSignalingFwd) {
        guard let pc = peerConnection else { return }
        Task {
            do {
                guard let data = msg.jsonData.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sdpString = dict["sdp"] as? String else {
                    return
                }

                let remoteDesc = RTCSessionDescription(type: .answer, sdp: sdpString)
                try await pc.setRemoteDescriptionAsync(remoteDesc)
                hasRemoteDescription = true

                for candidate in pendingRemoteIceCandidates {
                    try await pc.addIceCandidate(candidate)
                }
                pendingRemoteIceCandidates.removeAll()
            } catch {
            }
        }
    }

    private func handleICECandidate(_ msg: Mezon_Realtime_WebrtcSignalingFwd) {
        guard let data = msg.jsonData.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sdp = dict["candidate"] as? String else {
            return
        }

        let sdpMid = dict["sdpMid"] as? String ?? ""
        let sdpMLineIndex = (dict["sdpMLineIndex"] as? Int32) ?? 0
        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)

        guard let pc = peerConnection else {
            pendingRemoteIceCandidates.append(candidate)
            return
        }

        if hasRemoteDescription {
            pc.add(candidate) { _ in }
        } else {
            pendingRemoteIceCandidates.append(candidate)
        }
    }

    private func handleRemoteEndCall() {
        callTimeoutTimer?.invalidate()
        callTimeoutTimer = nil
        cleanup()
        updateState(.ended)

        if let uuid = callUUID {
            CallKitManager.shared.reportCallEnded(uuid: uuid, reason: .remoteEnded)
        }
        callUUID = nil
        onCallEnded?()
    }

    private func handleCallTimeout() {
        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: receiverId,
            dataType: .sdpTimeout,
            jsonData: "",
            channelId: channelId,
            callerId: callerId
        )
        endCall(sendQuit: false)
    }

    func endCall(sendQuit: Bool = true) {
        isCallCanceled = true
        callTimeoutTimer?.invalidate()
        callTimeoutTimer = nil

        if sendQuit && receiverId != 0 {
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: receiverId,
                dataType: .sdpQuit,
                jsonData: "",
                channelId: channelId,
                callerId: callerId
            )

            if timeStartConnected == nil {
                cancelCallPush()
            }
        }

        cleanup()
        updateState(.ended)

        if let uuid = callUUID {
            CallKitManager.shared.endCall(uuid: uuid)
        }
        callUUID = nil
        onCallEnded?()
    }

    private func cancelCallPush() {
        let body: [String: Any] = ["offer": "CANCEL_CALL"]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        MezonSocket.shared.makeCallPush(
            receiverId: receiverId,
            jsonData: json,
            channelId: channelId,
            callerId: callerId
        )
    }

    private func cleanup() {
        localAudioTrack?.isEnabled = false
        localAudioTrack = nil
        peerConnection?.close()
        peerConnection = nil
        pendingRemoteIceCandidates.removeAll()
        hasRemoteDescription = false
        isMicEnabled = true
        isSpeakerEnabled = false
        timeStartConnected = nil
    }

    func toggleMic() {
        guard let track = localAudioTrack else { return }
        isMicEnabled.toggle()
        track.isEnabled = isMicEnabled

        let json = "{\"micEnabled\": \(isMicEnabled)}"
        MezonSocket.shared.forwardWebrtcSignaling(
            receiverId: receiverId,
            dataType: .sdpStatusRemoteMedia,
            jsonData: json,
            channelId: channelId,
            callerId: callerId
        )
    }

    func toggleSpeaker() {
        let session = AVAudioSession.sharedInstance()
        do {
            isSpeakerEnabled.toggle()
            try session.overrideOutputAudioPort(isSpeakerEnabled ? .speaker : .none)
        } catch {
            isSpeakerEnabled.toggle()
        }
    }

    private func addLocalAudioTrack(to pc: RTCPeerConnection) {
        guard let factory = peerConnectionFactory else { return }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        let audioSource = factory.audioSource(with: constraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        audioTrack.isEnabled = true
        self.localAudioTrack = audioTrack
        pc.add(audioTrack, streamIds: ["stream0"])
    }

    private func createPeerConnection() -> RTCPeerConnection? {
        let config = RTCConfiguration()
        let iceServer = RTCIceServer(
            urlStrings: [WebRTCConfig.iceServerURL],
            username: WebRTCConfig.iceServerUsername,
            credential: WebRTCConfig.iceServerCredential
        )
        config.iceServers = [iceServer]
        config.sdpSemantics = .unifiedPlan
        config.iceCandidatePoolSize = 10

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        return peerConnectionFactory?.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )
    }

    private func updateState(_ state: CallConnectionState) {
        connectionState = state
        onStateChanged?(state)
    }

    private func requestMicrophonePermission() async -> Bool {
        let status = AVAudioSession.sharedInstance().recordPermission
        if status == .granted { return true }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func resetToIdle() {
        cleanup()
        connectionState = .idle
        receiverId = 0
        channelId = 0
        callerId = 0
        isCaller = false
        callUUID = nil
        isCallCanceled = false
    }
}

extension WebRTCCallManager: RTCPeerConnectionDelegate {

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            switch newState {
            case .connected, .completed:
                self.timeStartConnected = Date()
                self.callTimeoutTimer?.invalidate()
                self.callTimeoutTimer = nil
                self.updateState(.connected)

                MezonSocket.shared.forwardWebrtcSignaling(
                    receiverId: self.receiverId,
                    dataType: .sdpInit,
                    jsonData: "",
                    channelId: self.channelId,
                    callerId: self.callerId
                )

                self.cancelCallPush()

                if let uuid = self.callUUID {
                    CallKitManager.shared.reportOutgoingCallConnected(uuid: uuid)
                }

                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
                try? session.setActive(true)

            case .disconnected:
                self.handleRemoteEndCall()

            case .failed:
                self.endCall(sendQuit: true)

            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let candidateDict: [String: Any] = [
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": candidate.sdpMLineIndex,
            "candidate": candidate.sdp,
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: candidateDict),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        Task { @MainActor in
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: self.receiverId,
                dataType: .iceCandidate,
                jsonData: jsonString,
                channelId: self.channelId,
                callerId: self.callerId
            )
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
