import AVFoundation
import Foundation

final class VoiceJoinSound {

    private static let minimumInterval: TimeInterval = 5

    private var player: AVAudioPlayer?
    private var lastPlayedAt: TimeInterval?

    func play() {
        guard AppAudioSession.isHeldByLiveCall else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPlayedAt, now - lastPlayedAt < Self.minimumInterval { return }
        guard let player = player ?? makePlayer(), !player.isPlaying else { return }
        player.currentTime = 0
        if player.play() { lastPlayedAt = ProcessInfo.processInfo.systemUptime }
    }

    private func makePlayer() -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: "joincallsound", withExtension: "mp3", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: "joincallsound", withExtension: "mp3"),
              let created = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player = created
        return created
    }
}
