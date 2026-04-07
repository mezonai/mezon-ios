import AsyncDisplayKit
import AVFoundation
import UIKit

final class MessageAudioAttachmentNode: ASDisplayNode {

    private var attachments: [ParsedAttachment] = []
    private var messageId: String = ""
    private var playerViews: [MessageAudioPlayerView] = []

    static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 6
    static let maxChipWidth: CGFloat = 140

    override init() {
        super.init()
        automaticallyManagesSubnodes = false
    }

    func configure(audio: [ParsedAttachment], messageId: String) {
        attachments = audio
        self.messageId = messageId
        if isNodeLoaded {
            rebuildPlayerViews()
        }
    }

    override func didLoad() {
        super.didLoad()
        rebuildPlayerViews()
    }

    private func rebuildPlayerViews() {
        playerViews.forEach { $0.removeFromSuperview() }
        playerViews.removeAll()
        for (idx, att) in attachments.enumerated() {
            let id = "\(messageId)-audio-\(idx)"
            let v = MessageAudioPlayerView(attachment: att, playbackId: id)
            view.addSubview(v)
            playerViews.append(v)
        }
        setNeedsLayout()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard !attachments.isEmpty else { return .zero }
        let n = attachments.count
        let h = CGFloat(n) * Self.rowHeight + CGFloat(max(0, n - 1)) * Self.rowSpacing
        let w = min(maxWidth, Self.maxChipWidth)
        return CGSize(width: w, height: h)
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for v in playerViews {
            v.frame = CGRect(x: 0, y: y, width: bounds.width, height: Self.rowHeight)
            y += Self.rowHeight + Self.rowSpacing
        }
    }
}

final class MessageAudioPlayerView: UIView, ChatAudioPlaybackProgressSink {

    private let attachment: ParsedAttachment
    private let playbackId: String

    private let bubble = UIView()
    private let playButton = UIButton(type: .system)
    private let waveContainer = UIView()
    private var barViews: [UIView] = []
    private let barHeights: [CGFloat]
    private let timeLabel = UILabel()

    private var isPlayingUI = false
    private let apiDuration: TimeInterval
    private var fallbackTotalFromPlayer: TimeInterval = 0
    private var didCaptureDurationFromPlayer = false
    private var resolvedAssetDuration: TimeInterval = 0
    private var lockedDisplayTotalSeconds: Int = 0
    private var lastProgressFraction: CGFloat = 0

    private static let barCount = 10
    private static let probedDurationCache = NSCache<NSString, NSNumber>()
    private var themeObserver: NSObjectProtocol?

    init(attachment: ParsedAttachment, playbackId: String) {
        self.attachment = attachment
        self.playbackId = playbackId
        if let d = attachment.durationSeconds, d > 0 {
            self.apiDuration = TimeInterval(d)
        } else {
            self.apiDuration = 0
        }
        self.barHeights = Self.normalizedBarHeights(seed: attachment.url.isEmpty ? playbackId : attachment.url)
        super.init(frame: .zero)
        setup()
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeManager.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
        ChatAudioPlaybackCoordinator.shared.cancelIfCurrent(playbackId: playbackId)
    }

    private func setup() {
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.layer.cornerRadius = 22
        bubble.clipsToBounds = true
        addSubview(bubble)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.layer.cornerRadius = 18
        playButton.clipsToBounds = true
        let playCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playCfg), for: .normal)
        playButton.isUserInteractionEnabled = false
        bubble.addSubview(playButton)

        waveContainer.translatesAutoresizingMaskIntoConstraints = false
        waveContainer.clipsToBounds = true
        bubble.addSubview(waveContainer)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textAlignment = .right
        bubble.addSubview(timeLabel)

        let barW: CGFloat = 3
        for _ in barHeights {
            let b = UIView()
            b.backgroundColor = .clear
            b.layer.cornerRadius = barW / 2
            b.clipsToBounds = true
            waveContainer.addSubview(b)
            barViews.append(b)
        }

        let bubbleTap = UITapGestureRecognizer(target: self, action: #selector(bubbleTapped))
        bubbleTap.cancelsTouchesInView = true
        bubble.addGestureRecognizer(bubbleTap)
        bubble.isAccessibilityElement = true
        bubble.accessibilityTraits = .button
        bubble.accessibilityLabel = L(L10n.ChannelMessages.voiceMessageA11y)

        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),

            playButton.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8),
            playButton.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 36),
            playButton.heightAnchor.constraint(equalToConstant: 36),

            timeLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            waveContainer.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 10),
            waveContainer.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -10),
            waveContainer.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            waveContainer.heightAnchor.constraint(equalToConstant: 24),
        ])

        refreshTimeLabel()
        applyTheme()
        loadDurationFromAssetIfNeeded()
        isUserInteractionEnabled = !attachment.url.isEmpty
        alpha = attachment.url.isEmpty ? 0.55 : 1
    }

    private func loadDurationFromAssetIfNeeded() {
        guard apiDuration <= 0, !attachment.url.isEmpty else { return }
        let key = attachment.url as NSString
        if let cached = Self.probedDurationCache.object(forKey: key) {
            let d = cached.doubleValue
            guard d > 0 else { return }
            resolvedAssetDuration = d
            refreshTimeLabel()
            return
        }
        guard let url = ChatAudioPlaybackCoordinator.resolvePlaybackURL(from: attachment.url) else { return }
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
            guard let self else { return }
            var err: NSError?
            guard asset.statusOfValue(forKey: "duration", error: &err) == .loaded else { return }
            let sec = CMTimeGetSeconds(asset.duration)
            guard sec.isFinite, sec > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resolvedAssetDuration = sec
                Self.probedDurationCache.setObject(NSNumber(value: sec), forKey: key)
                self.refreshTimeLabel()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutWaveBars()
    }

    private func layoutWaveBars() {
        let spacing: CGFloat = 2
        let barW: CGFloat = 3
        let w = waveContainer.bounds.width
        let hC = waveContainer.bounds.height
        guard w > 1, hC > 1, !barViews.isEmpty else { return }
        let totalW = CGFloat(barViews.count) * barW + CGFloat(max(0, barViews.count - 1)) * spacing
        var x = max(0, (w - totalW) / 2)
        for (i, b) in barViews.enumerated() {
            let norm = i < barHeights.count ? barHeights[i] : 0.5
            let barH = max(4, min(hC - 2, (hC - 4) * norm))
            b.frame = CGRect(x: x, y: hC - barH, width: barW, height: barH)
            x += barW + spacing
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        bubble.backgroundColor = t.secondaryWeight
        timeLabel.textColor = t.textStrong
        playButton.backgroundColor = t.bgViolet
        playButton.tintColor = .white
        let barColor = t.textDisabled.withAlphaComponent(0.55)
        barViews.forEach { $0.backgroundColor = barColor }
    }

    @objc private func bubbleTapped() {
        playTapped()
    }

    private func playTapped() {
        guard !attachment.url.isEmpty else { return }
        ChatAudioPlaybackCoordinator.shared.toggle(urlString: attachment.url, playbackId: playbackId, sink: self)
    }

    func playbackDidReset() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPlayingUI = false
            self.lastProgressFraction = 0
            self.syncPlayIcon()
            self.refreshTimeLabel()
        }
    }

    func playbackProgress(_ fraction: CGFloat, playing: Bool, duration: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastProgressFraction = fraction
            self.isPlayingUI = playing
            if duration > 0 {
                self.lockedDisplayTotalSeconds = max(self.lockedDisplayTotalSeconds, Int(ceil(duration)))
            }
            if duration > 0, self.apiDuration <= 0, self.resolvedAssetDuration <= 0, !self.didCaptureDurationFromPlayer {
                self.didCaptureDurationFromPlayer = true
                self.fallbackTotalFromPlayer = duration
            }
            self.syncPlayIcon()
            self.refreshTimeLabel()
        }
    }

    private func syncPlayIcon() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let name = isPlayingUI ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
    }

    private func refreshTimeLabel() {
        let raw = max(apiDuration, resolvedAssetDuration, fallbackTotalFromPlayer)
        if raw > 0 {
            lockedDisplayTotalSeconds = max(lockedDisplayTotalSeconds, Int(ceil(raw)))
        }
        let total = max(
            raw,
            lockedDisplayTotalSeconds > 0 ? TimeInterval(lockedDisplayTotalSeconds) : 0
        )
        guard total > 0 else {
            timeLabel.text = "--:--"
            return
        }
        if isPlayingUI || lastProgressFraction > 0.001 {
            let elapsed = TimeInterval(lastProgressFraction) * total
            let remaining = max(0, total - elapsed)
            timeLabel.text = Self.formatClock(Int(ceil(remaining)))
        } else {
            timeLabel.text = Self.formatClock(Int(ceil(total)))
        }
    }

    private static func formatClock(_ totalSeconds: Int) -> String {
        let s = max(0, totalSeconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }

    private static func normalizedBarHeights(seed: String) -> [CGFloat] {
        var state = FNV1a64.hash(seed)
        return (0..<barCount).map { _ in
            state = state &* 1_099_515_211 + 1_234_567
            let u = Double(state % 10_000) / 10_000.0
            return CGFloat(0.35 + u * 0.65)
        }
    }
}

private enum FNV1a64 {
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 14_695_981_869_709_697_377
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 1_099_515_211_294_991_221
        }
        return h == 0 ? 1 : h
    }
}
