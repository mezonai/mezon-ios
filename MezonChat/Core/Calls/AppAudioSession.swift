import AVFoundation
import Foundation
import WebRTC

enum AppAudioSession {
    static var isHeldByLiveCall: Bool {
        RTCAudioSession.sharedInstance().isAudioEnabled
    }

    static func activateForMediaPlayback(options: AVAudioSession.CategoryOptions) {
        guard !isHeldByLiveCall else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: options)
        try? session.setActive(true)
    }

    static func activateForVoiceMessageRecording() throws {
        guard !isHeldByLiveCall else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    static func releaseAfterVoiceMessageRecording() {
        guard !isHeldByLiveCall else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
