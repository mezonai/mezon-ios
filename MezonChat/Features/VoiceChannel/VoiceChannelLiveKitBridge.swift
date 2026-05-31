import AVFoundation
import Foundation
import LiveKit
import LiveKitWebRTC

final class VoiceChannelLiveKitBridge: NSObject, RoomDelegate {

    private(set) var room: Room!
    private var didEndSession = false

    var onConnectionState: ((ConnectionState) -> Void)?
    var onConnectFailed: ((Error) -> Void)?
    var onDisconnected: ((LiveKitError?) -> Void)?
    var onRoomParticipantsChanged: (() -> Void)?
    var onParticipantStateUpdated: (() -> Void)?

    override init() {
        super.init()
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        AudioManager.shared.audioSession.isAutomaticDeactivationEnabled = false
        Self.primeWebRTCAudioConfigForMixIfNeeded()
        Self.applyEchoCancellationConfiguration()
        room = Room(delegate: self, roomOptions: RoomOptions(adaptiveStream: true, dynacast: true))
    }

    private static func primeWebRTCAudioConfigForMixIfNeeded() {
        let cfg = LKRTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        var opts: AVAudioSession.CategoryOptions = [
            .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay, .defaultToSpeaker,
        ]
        if VoiceChannelAudioPreferences.mixWithOthersEnabled {
            opts.insert(.mixWithOthers)
        }
        cfg.categoryOptions = opts
        cfg.mode = AVAudioSession.Mode.default.rawValue
        LKRTCAudioSessionConfiguration.setWebRTC(cfg)
    }

    static func applyEchoCancellationConfiguration() {
        AudioManager.shared.isVoiceProcessingBypassed = false
        if #available(iOS 17, *) {
            AudioManager.shared.duckingLevel = VoiceChannelAudioPreferences.mixWithOthersEnabled ? .min : .default
        }
    }

    func connect(url: String, token: String) async throws {
        didEndSession = false
        try await room.connect(url: url, token: token, connectOptions: nil, roomOptions: nil)
    }

    func clearCallbacks() {
        onConnectionState = nil
        onConnectFailed = nil
        onDisconnected = nil
        onRoomParticipantsChanged = nil
        onParticipantStateUpdated = nil
    }

    private func notifyParticipantsChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.onRoomParticipantsChanged?()
        }
    }

    private func notifyStateUpdated() {
        DispatchQueue.main.async { [weak self] in
            self?.onParticipantStateUpdated?()
        }
    }

    private func publicationLooksLikeRemoteScreenShareVideo(_ publication: RemoteTrackPublication) -> Bool {
        publication.source == .screenShareVideo
            || (publication.kind == .video && publication.name == Track.screenShareVideoName)
    }

    func disconnect() async {
        guard !didEndSession else { return }
        didEndSession = true
        await room.disconnect()
        AudioManager.shared.isVoiceProcessingBypassed = false
    }

    func setMicrophoneEnabled(_ enabled: Bool) async throws {
        try await room.localParticipant.setMicrophone(enabled: enabled)
    }

    func isMicrophoneEnabled() -> Bool {
        room.localParticipant.isMicrophoneEnabled()
    }

    func setCameraEnabled(_ enabled: Bool) async throws {
        if enabled {
            try await room.localParticipant.setCamera(
                enabled: true,
                captureOptions: CameraCaptureOptions(position: .front),
                publishOptions: nil
            )
        } else {
            try await room.localParticipant.setCamera(enabled: false)
        }
        syncFrontCameraVideoProcessor()
    }

    func isCameraEnabled() -> Bool {
        room.localParticipant.isCameraEnabled()
    }

    func switchCameraPosition() async throws {
        guard let track = room.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer else { return }
        _ = try await capturer.switchCameraPosition()
        syncFrontCameraVideoProcessor()
    }

    func currentCameraCapturePosition() -> AVCaptureDevice.Position? {
        guard let track = room.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer else { return nil }
        return capturer.position
    }

    private func syncFrontCameraVideoProcessor() {
        guard let track = room.localParticipant.firstCameraVideoTrack as? LocalVideoTrack,
              let capturer = track.capturer as? CameraCapturer
        else { return }
        if capturer.position == .front {
            track.processor = VoiceFrontCameraPublishFlipProcessor.shared
        } else {
            track.processor = nil
        }
    }

    func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionState?(connectionState)
        }
    }

    func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
        DispatchQueue.main.async { [weak self] in
            self?.onConnectFailed?(error ?? NSError(domain: "LiveKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect"]))
        }
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.didEndSession = true
            self.onDisconnected?(error)
        }
    }

    func roomDidConnect(_ room: Room) {
        notifyParticipantsChanged()
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        notifyParticipantsChanged()
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        notifyParticipantsChanged()
    }

    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        notifyStateUpdated()
    }

    func room(_ room: Room, participant: Participant, trackPublication: TrackPublication, didUpdateIsMuted isMuted: Bool) {
        notifyStateUpdated()
    }

    func room(
        _ room: Room,
        participant: RemoteParticipant,
        trackPublication: RemoteTrackPublication,
        didUpdateStreamState streamState: StreamState
    ) {
        notifyParticipantsChanged()
        if publicationLooksLikeRemoteScreenShareVideo(trackPublication) {
            notifyStateUpdated()
        }
    }

    func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        if publication.track is LocalVideoTrack {
            syncFrontCameraVideoProcessor()
        }
        notifyParticipantsChanged()
    }

    func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) {
        notifyParticipantsChanged()
    }

    func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication) {
        notifyParticipantsChanged()
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnpublishTrack publication: RemoteTrackPublication) {
        notifyParticipantsChanged()
        if publicationLooksLikeRemoteScreenShareVideo(publication) {
            notifyStateUpdated()
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        notifyParticipantsChanged()
    }

    func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        notifyParticipantsChanged()
        if publicationLooksLikeRemoteScreenShareVideo(publication) {
            notifyStateUpdated()
        }
    }
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
