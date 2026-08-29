import AsyncDisplayKit
import AVFoundation
import UIKit

final class MessageAudioAttachmentNode: ASDisplayNode {

    private var attachments: [ParsedAttachment] = []
    private var messageId: String = ""
    private var playerViews: [MessageAudioPlayerView] = []
    private var pendingConfigureKey: String?

    static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 6
    static let maxChipWidth: CGFloat = 150

    override init() {
        super.init()
        automaticallyManagesSubnodes = false
        isOpaque = false
    }

    func configure(audio: [ParsedAttachment], messageId: String) {
        let key = "\(messageId)#\(audio.count)#\(audio.first?.url ?? "")"
        if pendingConfigureKey == key { return }
        pendingConfigureKey = key
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
        let w = bounds.width
        for v in playerViews {
            v.frame = CGRect(x: 0, y: y, width: w, height: Self.rowHeight)
            y += Self.rowHeight + Self.rowSpacing
        }
    }
}

final class MessageAudioPlayerView: UIView, ChatAudioPlaybackProgressSink {

    private let attachment: ParsedAttachment
    private let playbackId: String

    private let bubble = UIView()
    private let playIconView = UIImageView()
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

    private static let barCount = 22
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2
    private static let buttonSize: CGFloat = 36
    private static let timeLabelMinWidth: CGFloat = 50
    private static let waveHeight: CGFloat = 24

    private static let probedDurationCache = NSCache<NSString, NSNumber>()
    private static let durationProbeQueue = DispatchQueue(
        label: "mezon.audio.duration.probe",
        qos: .utility,
        attributes: .concurrent
    )

    private static let playSymbolConfig = MezonSymbolConfiguration(pointSize: 14, weight: .semibold)
    private static let playIcon: UIImage? = UIImage.mezonSystemImage("play.fill", withConfiguration: playSymbolConfig)?
        .withRenderingMode(.alwaysTemplate)
    private static let pauseIcon: UIImage? = UIImage.mezonSystemImage("pause.fill", withConfiguration: playSymbolConfig)?
        .withRenderingMode(.alwaysTemplate)

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
        bubble.layer.cornerRadius = 22
        bubble.layer.setMezonCornerCurveContinuous()
        bubble.isUserInteractionEnabled = false
        addSubview(bubble)

        playIconView.image = Self.playIcon
        playIconView.contentMode = .center
        playIconView.layer.cornerRadius = Self.buttonSize / 2
        playIconView.layer.setMezonCornerCurveContinuous()
        playIconView.clipsToBounds = true
        playIconView.isUserInteractionEnabled = false
        bubble.addSubview(playIconView)

        waveContainer.isUserInteractionEnabled = false
        waveContainer.clipsToBounds = true
        bubble.addSubview(waveContainer)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textAlignment = .right
        timeLabel.isUserInteractionEnabled = false
        bubble.addSubview(timeLabel)

        let barW = Self.barWidth
        for _ in barHeights {
            let b = UIView()
            b.layer.cornerRadius = barW / 2
            waveContainer.addSubview(b)
            barViews.append(b)
        }

        let bubbleTap = UITapGestureRecognizer(target: self, action: #selector(bubbleTapped))
        bubbleTap.cancelsTouchesInView = true
        bubble.addGestureRecognizer(bubbleTap)
        bubble.isUserInteractionEnabled = true
        bubble.isAccessibilityElement = true
        bubble.accessibilityTraits = .button
        bubble.accessibilityLabel = L(L10n.ChannelMessages.voiceMessageA11y)

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
        let urlStr = attachment.url
        Self.durationProbeQueue.async { [weak self] in
            guard let url = ChatAudioPlaybackCoordinator.resolvePlaybackURL(from: urlStr) else { return }
            let asset = AVURLAsset(url: url)
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                var err: NSError?
                guard asset.statusOfValue(forKey: "duration", error: &err) == .loaded else { return }
                let sec = CMTimeGetSeconds(asset.duration)
                guard sec.isFinite, sec > 0 else { return }
                Self.probedDurationCache.setObject(NSNumber(value: sec), forKey: key)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.resolvedAssetDuration = sec
                    self.refreshTimeLabel()
                }
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }

        bubble.frame = b

        let buttonSize = Self.buttonSize
        let buttonY = (b.height - buttonSize) / 2
        playIconView.frame = CGRect(x: 8, y: buttonY, width: buttonSize, height: buttonSize)

        let timeWidth = Self.timeLabelMinWidth
        timeLabel.frame = CGRect(
            x: b.width - 12 - timeWidth,
            y: 0,
            width: timeWidth,
            height: b.height
        )

        let waveX = playIconView.frame.maxX + 10
        let waveMaxX = timeLabel.frame.minX - 10
        let waveW = max(0, waveMaxX - waveX)
        let waveH = Self.waveHeight
        waveContainer.frame = CGRect(
            x: waveX,
            y: (b.height - waveH) / 2,
            width: waveW,
            height: waveH
        )

        layoutWaveBars()
    }

    private func layoutWaveBars() {
        let barW = Self.barWidth
        let w = waveContainer.bounds.width
        let hC = waveContainer.bounds.height
        guard w > 1, hC > 1, !barViews.isEmpty else { return }
        let n = barViews.count
        var spacing = Self.barSpacing
        if n > 1 {
            let minGap: CGFloat = 1
            let needed = CGFloat(n) * barW + CGFloat(n - 1) * minGap
            if w >= needed {
                spacing = max(minGap, (w - CGFloat(n) * barW) / CGFloat(n - 1))
            }
        }
        let totalW = CGFloat(n) * barW + CGFloat(max(0, n - 1)) * spacing
        var x = max(0, (w - totalW) / 2)
        let usableHeight = hC - 4
        for (i, b) in barViews.enumerated() {
            let norm = i < barHeights.count ? barHeights[i] : 0.5
            let barH = max(4, min(hC - 2, usableHeight * norm))
            b.frame = CGRect(x: x, y: hC - barH, width: barW, height: barH)
            x += barW + spacing
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        bubble.backgroundColor = t.secondaryWeight
        timeLabel.textColor = t.textStrong
        playIconView.backgroundColor = t.bgViolet
        playIconView.tintColor = .white
        let barColor = t.textDisabled.withAlphaComponent(0.55)
        for b in barViews { b.backgroundColor = barColor }
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
            if self.isPlayingUI != playing {
                self.isPlayingUI = playing
                self.syncPlayIcon()
            }
            if duration > 0 {
                self.lockedDisplayTotalSeconds = max(self.lockedDisplayTotalSeconds, Int(ceil(duration)))
            }
            if duration > 0, self.apiDuration <= 0, self.resolvedAssetDuration <= 0, !self.didCaptureDurationFromPlayer {
                self.didCaptureDurationFromPlayer = true
                self.fallbackTotalFromPlayer = duration
            }
            self.refreshTimeLabel()
        }
    }

    private func syncPlayIcon() {
        playIconView.image = isPlayingUI ? Self.pauseIcon : Self.playIcon
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
