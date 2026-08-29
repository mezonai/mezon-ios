import AVFoundation
import Foundation

final class PeerCallSoundPlayer {

    static let shared = PeerCallSoundPlayer()

    private var dialTonePlayer: AVAudioPlayer?

    private init() {}

    func playDialToneLoop() {
        stopDialTone()
        guard let url = Bundle.main.url(forResource: "dialtone", withExtension: "mp3", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: "dialtone", withExtension: "mp3")
        else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.prepareToPlay()
            p.play()
            dialTonePlayer = p
        } catch {}
    }

    func stopDialTone() {
        dialTonePlayer?.stop()
        dialTonePlayer = nil
    }

    func playRingingLoop() {
        stopRinging()
    }

    func stopRinging() {}

    func stopAll() {
        stopDialTone()
        stopRinging()
    }
}
