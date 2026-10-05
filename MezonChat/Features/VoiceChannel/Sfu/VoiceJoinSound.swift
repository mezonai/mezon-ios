import AVFoundation
import Foundation

final class VoiceJoinSound {

    private static let minimumInterval: TimeInterval = 1.1

    private var player: AVAudioPlayer?
    private var lastPlayedAt: TimeInterval = 0

    func play() {
        guard AppAudioSession.isHeldByLiveCall else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPlayedAt >= Self.minimumInterval, let player = player ?? makePlayer() else { return }
        lastPlayedAt = now
        player.currentTime = 0
        player.play()
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
