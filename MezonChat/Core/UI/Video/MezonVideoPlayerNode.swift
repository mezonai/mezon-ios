import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation

final class MezonVideoPlayerNode: ASDisplayNode {

    private let playerNode: ASDisplayNode
    private let posterNode: TransformImageNode

    private let centerOverlayNode: ASDisplayNode
    private let centerPlayPauseButton: ASButtonNode
    private let seekBackwardButton: ASButtonNode
    private let seekForwardButton: ASButtonNode

    private let scrubberBarNode: ASDisplayNode
    private let bottomPlayPauseButton: ASButtonNode
    private let timeSlider = UISlider()
    private let currentTimeLabel: ASTextNode
    private let durationLabel: ASTextNode

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    private var isScrubbing = false

    private var controlsHideTimer: Foundation.Timer?
    private var areControlsVisible = true

    private let seekDelta: Double = 15.0

    var toggleOverlayVisibility: (() -> Void)?

    init(url: URL, posterURL: String) {

        self.playerNode = ASDisplayNode { () -> CALayer in
            let layer = AVPlayerLayer()
            layer.videoGravity = .resizeAspect
            return layer
        }


        self.posterNode = TransformImageNode()
        self.posterNode.contentAnimations = [.firstUpdate]


        self.centerOverlayNode = ASDisplayNode()
        self.centerOverlayNode.isUserInteractionEnabled = true

        self.centerPlayPauseButton = ASButtonNode()
        self.seekBackwardButton = ASButtonNode()
        self.seekForwardButton = ASButtonNode()


        self.scrubberBarNode = ASDisplayNode()
        self.scrubberBarNode.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        self.bottomPlayPauseButton = ASButtonNode()
        self.currentTimeLabel = ASTextNode()
        self.durationLabel = ASTextNode()

        super.init()


        self.addSubnode(playerNode)
        self.addSubnode(posterNode)
        self.addSubnode(centerOverlayNode)
        self.addSubnode(scrubberBarNode)


        setupCenterButton(centerPlayPauseButton, iconName: "play.fill", pointSize: 44)
        setupCenterButton(seekBackwardButton, iconName: "gobackward.15", pointSize: 28)
        setupCenterButton(seekForwardButton, iconName: "goforward.15", pointSize: 28)

        centerOverlayNode.addSubnode(seekBackwardButton)
        centerOverlayNode.addSubnode(centerPlayPauseButton)
        centerOverlayNode.addSubnode(seekForwardButton)

        centerPlayPauseButton.addTarget(self, action: #selector(playPauseTapped), forControlEvents: .touchUpInside)
        seekBackwardButton.addTarget(self, action: #selector(seekBackwardTapped), forControlEvents: .touchUpInside)
        seekForwardButton.addTarget(self, action: #selector(seekForwardTapped), forControlEvents: .touchUpInside)


        scrubberBarNode.addSubnode(bottomPlayPauseButton)
        scrubberBarNode.addSubnode(currentTimeLabel)
        scrubberBarNode.addSubnode(durationLabel)

        bottomPlayPauseButton.setImage(Self.sfSymbolImage(name: "play.fill", pointSize: 18, bold: false), for: .normal)
        bottomPlayPauseButton.imageNode.imageModificationBlock = ASImageNodeTintColorModificationBlock(.white)
        bottomPlayPauseButton.addTarget(self, action: #selector(playPauseTapped), forControlEvents: .touchUpInside)


        self.timeSlider.minimumTrackTintColor = .white
        self.timeSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        self.timeSlider.thumbTintColor = .white

        let thumbImage = makeCircleImage(radius: 6, color: .white)
        self.timeSlider.setThumbImage(thumbImage, for: .normal)
        self.timeSlider.setThumbImage(thumbImage, for: .highlighted)

        self.timeSlider.addTarget(self, action: #selector(sliderDidBeginScrubbing), for: .touchDown)
        self.timeSlider.addTarget(self, action: #selector(sliderDidChange), for: .valueChanged)
        self.timeSlider.addTarget(self, action: #selector(sliderDidEndScrubbing), for: .touchUpInside)
        self.timeSlider.addTarget(self, action: #selector(sliderDidEndScrubbing), for: .touchUpOutside)


        updatePlayPauseIcons(isPlaying: false)


        setupPlayer(url: url)


        posterNode.setSignal(videoThumbnailSignal(url: posterURL, resizeMode: .fit))
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(playerTapped))
        self.view.addGestureRecognizer(tap)

        scrubberBarNode.view.addSubview(timeSlider)
        resetControlsTimer()
    }


    private static func sfSymbolImage(name: String, pointSize: CGFloat, bold: Bool) -> UIImage? {
        if #available(iOS 13.0, *) {
            let weight: UIImage.SymbolWeight = bold ? .bold : .regular
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            return UIImage(systemName: name, withConfiguration: config)
        }
        return nil
    }

    private func setupCenterButton(_ button: ASButtonNode, iconName: String, pointSize: CGFloat) {
        let image = Self.sfSymbolImage(name: iconName, pointSize: pointSize, bold: true)
        button.setImage(image, for: .normal)
        button.imageNode.imageModificationBlock = ASImageNodeTintColorModificationBlock(.white)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.clipsToBounds = true
    }


    private var statusObserver: NSKeyValueObservation?

    private func setupPlayer(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.player = avPlayer

        if let layer = playerNode.layer as? AVPlayerLayer {
            layer.player = avPlayer
            self.playerLayer = layer
        }


        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateTime(time)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)


        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .readyToPlay {
                let duration = item.duration.seconds
                if duration.isFinite {
                    DispatchQueue.main.async {
                        self?.timeSlider.maximumValue = Float(duration)
                        self?.durationLabel.attributedText = NSAttributedString(
                            string: self?.formatTime(duration) ?? "0:00",
                            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
                        )
                        self?.setNeedsLayout()
                    }
                }
            }
        }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        controlsHideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    public func play() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        posterNode.isHidden = true
        updatePlayPauseIcons(isPlaying: true)
        resetControlsTimer()
    }

    public func pause() {
        player?.pause()
        updatePlayPauseIcons(isPlaying: false)
        controlsHideTimer?.invalidate()
        showControls()
    }


    @objc private func playPauseTapped() {
        guard let p = player else { return }
        if p.rate == 0 {
            if p.currentTime() == p.currentItem?.duration {
                p.seek(to: .zero)
            }
            play()
        } else {
            pause()
        }
    }

    @objc private func seekBackwardTapped() {
        guard let p = player else { return }
        let currentTime = p.currentTime().seconds
        let newTime = max(0, currentTime - seekDelta)
        p.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
        resetControlsTimer()


        animateButtonTap(seekBackwardButton)
    }

    @objc private func seekForwardTapped() {
        guard let p = player else { return }
        let currentTime = p.currentTime().seconds
        let duration = p.currentItem?.duration.seconds ?? currentTime
        let newTime = min(duration, currentTime + seekDelta)
        p.seek(to: CMTime(seconds: newTime, preferredTimescale: 600))
        resetControlsTimer()

        animateButtonTap(seekForwardButton)
    }

    private func animateButtonTap(_ button: ASButtonNode) {
        UIView.animate(withDuration: 0.1, animations: {
            button.view.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                button.view.transform = .identity
            }
        }
    }

    @objc private func playerTapped() {
        toggleOverlayVisibility?()

        if areControlsVisible {
            hideControls()
        } else {
            showControls()
            if player?.rate != 0 {
                resetControlsTimer()
            }
        }
    }

    @objc private func playerDidFinishPlaying() {
        updatePlayPauseIcons(isPlaying: false)
        showControls()
    }

    @objc private func sliderDidBeginScrubbing() {
        isScrubbing = true
        player?.pause()
        controlsHideTimer?.invalidate()
    }

    @objc private func sliderDidChange() {
        let seconds = Double(timeSlider.value)
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)

        currentTimeLabel.attributedText = NSAttributedString(
            string: formatTime(seconds),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )
        setNeedsLayout()
    }

    @objc private func sliderDidEndScrubbing() {
        isScrubbing = false
        let seconds = Double(timeSlider.value)
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self] _ in
            if self?.player?.rate == 0 {

            }
        }
        if player?.rate != 0 {
            resetControlsTimer()
        }
    }


    private func updateTime(_ time: CMTime) {
        guard !isScrubbing else { return }
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        timeSlider.value = Float(seconds)

        currentTimeLabel.attributedText = NSAttributedString(
            string: formatTime(seconds),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )
        setNeedsLayout()
    }

    private func updatePlayPauseIcons(isPlaying: Bool) {
        let centerIconName = isPlaying ? "pause.fill" : "play.fill"
        centerPlayPauseButton.setImage(Self.sfSymbolImage(name: centerIconName, pointSize: 44, bold: true), for: .normal)

        let bottomIconName = isPlaying ? "pause.fill" : "play.fill"
        bottomPlayPauseButton.setImage(Self.sfSymbolImage(name: bottomIconName, pointSize: 18, bold: false), for: .normal)
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }


    private func showControls() {
        areControlsVisible = true
        UIView.animate(withDuration: 0.25) {
            self.centerOverlayNode.alpha = 1.0
            self.scrubberBarNode.alpha = 1.0
        }
    }

    private func hideControls() {
        areControlsVisible = false
        UIView.animate(withDuration: 0.25) {
            self.centerOverlayNode.alpha = 0.0
            self.scrubberBarNode.alpha = 0.0
        }
    }

    private func resetControlsTimer() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = Foundation.Timer.scheduledTimer(timeInterval: 4.0, target: self, selector: #selector(timerFired), userInfo: nil, repeats: false)
    }

    @objc private func timerFired() {
        if self.player?.rate != 0 {
            self.hideControls()
            self.toggleOverlayVisibility?()
        }
    }


    override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }

        playerNode.frame = b
        posterNode.frame = b

        let args = TransformImageArguments(corners: ImageCorners(), imageSize: b.size, boundingSize: b.size, intrinsicInsets: .zero)
        let apply = posterNode.asyncLayout()(args)
        apply()


        let centerButtonSize: CGFloat = 64
        let sideButtonSize: CGFloat = 48
        let buttonSpacing: CGFloat = 48

        let totalWidth = sideButtonSize + buttonSpacing + centerButtonSize + buttonSpacing + sideButtonSize
        let overlayHeight = centerButtonSize
        let overlayX = (b.width - totalWidth) / 2
        let overlayY = (b.height - overlayHeight) / 2
        centerOverlayNode.frame = CGRect(x: overlayX, y: overlayY, width: totalWidth, height: overlayHeight)

        let sideY = (overlayHeight - sideButtonSize) / 2

        seekBackwardButton.frame = CGRect(x: 0, y: sideY, width: sideButtonSize, height: sideButtonSize)
        seekBackwardButton.cornerRadius = sideButtonSize / 2

        centerPlayPauseButton.frame = CGRect(x: sideButtonSize + buttonSpacing, y: 0, width: centerButtonSize, height: centerButtonSize)
        centerPlayPauseButton.cornerRadius = centerButtonSize / 2

        seekForwardButton.frame = CGRect(x: sideButtonSize + buttonSpacing + centerButtonSize + buttonSpacing, y: sideY, width: sideButtonSize, height: sideButtonSize)
        seekForwardButton.cornerRadius = sideButtonSize / 2


        let safeBottom = view.safeAreaInsets.bottom
        let barHeight: CGFloat = 50 + safeBottom
        scrubberBarNode.frame = CGRect(x: 0, y: b.height - barHeight, width: b.width, height: barHeight)

        let playSize = CGSize(width: 44, height: 44)
        bottomPlayPauseButton.frame = CGRect(x: 8, y: 3, width: playSize.width, height: playSize.height)

        let currentSize = currentTimeLabel.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: 100, height: 20))).size
        currentTimeLabel.frame = CGRect(x: bottomPlayPauseButton.frame.maxX + 4, y: 15, width: currentSize.width, height: currentSize.height)

        let durationSize = durationLabel.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: 100, height: 20))).size
        durationLabel.frame = CGRect(x: b.width - durationSize.width - 16, y: 15, width: durationSize.width, height: durationSize.height)

        let sliderX = currentTimeLabel.frame.maxX + 12
        let sliderW = durationLabel.frame.minX - 12 - sliderX
        timeSlider.frame = CGRect(x: sliderX, y: 10, width: sliderW, height: 30)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {

        if areControlsVisible {
            let centerPoint = self.view.convert(point, to: centerOverlayNode.view)
            if let hitView = centerOverlayNode.view.hitTest(centerPoint, with: event) {
                return hitView
            }

            let scrubberPoint = self.view.convert(point, to: scrubberBarNode.view)
            if let hitView = scrubberBarNode.view.hitTest(scrubberPoint, with: event) {
                return hitView
            }
        }

        return super.hitTest(point, with: event)
    }
}

private func makeCircleImage(radius: CGFloat, color: UIColor) -> UIImage {
    let size = CGSize(width: radius * 2, height: radius * 2)
    UIGraphicsBeginImageContextWithOptions(size, false, 0)
    let ctx = UIGraphicsGetCurrentContext()!
    ctx.setFillColor(color.cgColor)
    ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
    let img = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return img
}
