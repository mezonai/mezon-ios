import AVFoundation
import UIKit

final class ChatAudioPlaybackCoordinator: NSObject {

    static let shared = ChatAudioPlaybackCoordinator()


    static func resolvePlaybackURL(from string: String) -> URL? {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let u = URL(string: s), u.scheme != nil { return u }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
        return URL(string: s)
    }

    private weak var sink: ChatAudioPlaybackProgressSink?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private(set) var currentPlaybackId: String?
    private var stableItemDuration: TimeInterval = 0

    private override init() {
        super.init()
    }

    func cancelIfCurrent(playbackId: String) {
        guard currentPlaybackId == playbackId else { return }
        sink?.playbackDidReset()
        sink = nil
        tearDownPlayer()
    }

    func toggle(urlString: String, playbackId: String, sink: ChatAudioPlaybackProgressSink) {
        guard !urlString.isEmpty else { return }
        guard let url = Self.resolvePlaybackURL(from: urlString) else {
            return
        }

        if currentPlaybackId == playbackId, player != nil {
            self.sink = sink
            if player?.rate != 0 {
                player?.pause()
                emitProgress(playing: false)
            } else {
                ensureSession()
                player?.play()
                emitProgress(playing: true)
            }
            return
        }

        self.sink?.playbackDidReset()
        self.sink = nil
        tearDownPlayer()

        ensureSession()
        currentPlaybackId = playbackId
        self.sink = sink

        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        player = p

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.onPlaybackFinished()
        }

        let interval = CMTime(seconds: 0.12, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.emitProgress(playing: self?.player?.rate != 0)
        }

        p.play()
        emitProgress(playing: true)
    }

    private func onPlaybackFinished() {
        player?.seek(to: .zero)
        player?.pause()
        emitProgress(playing: false)
    }

    private func emitProgress(playing: Bool) {
        guard let item = player?.currentItem else {
            sink?.playbackProgress(0, playing: playing, duration: 0)
            return
        }
        let d = CMTimeGetSeconds(item.duration)
        if d.isFinite, d > 0 {
            stableItemDuration = max(stableItemDuration, d)
        }
        let total = stableItemDuration > 0 ? stableItemDuration : ((d.isFinite && d > 0) ? d : 0)
        let t = CMTimeGetSeconds(item.currentTime())
        let time = t.isFinite ? t : 0
        let fraction: CGFloat = total > 0 ? CGFloat(max(0, min(1, time / total))) : 0
        sink?.playbackProgress(fraction, playing: playing, duration: total)
    }

    private func tearDownPlayer() {
        if let obs = timeObserver, let p = player {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        currentPlaybackId = nil
        stableItemDuration = 0
    }

    private func ensureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}

protocol ChatAudioPlaybackProgressSink: AnyObject {
    func playbackDidReset()
    func playbackProgress(_ fraction: CGFloat, playing: Bool, duration: TimeInterval)
}
