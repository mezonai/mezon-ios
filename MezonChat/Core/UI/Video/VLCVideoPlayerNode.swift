import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation
import MobileVLCKit

final class VLCVideoPlayerNode: ASDisplayNode {
    
    private let playerContainerNode: ASDisplayNode
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
    
    private var vlcPlayer: VLCMediaPlayer?
    private var vlcMedia: VLCMedia?
    private var isScrubbing = false
    private var updateTimer: Foundation.Timer?
    
    private var controlsHideTimer: Foundation.Timer?
    private var areControlsVisible = true
    
    private let seekDelta: Double = 15.0
    
    var toggleOverlayVisibility: (() -> Void)?
    
    init(url: URL, posterURL: String) {
        self.playerContainerNode = ASDisplayNode()
        self.playerContainerNode.backgroundColor = .black
        
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
        
        self.addSubnode(playerContainerNode)
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
        
        let bottomConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        bottomPlayPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: bottomConfig), for: .normal)
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
        
        setupVLCPlayer(url: url)
        
        posterNode.setSignal(videoThumbnailSignal(url: posterURL, resizeMode: .fit))
    }
    
    override func didLoad() {
        super.didLoad()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(playerTapped))
        self.view.addGestureRecognizer(tap)
        
        scrubberBarNode.view.addSubview(timeSlider)
        resetControlsTimer()
    }
    
    private func setupCenterButton(_ button: ASButtonNode, iconName: String, pointSize: CGFloat) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let image = UIImage(systemName: iconName, withConfiguration: config)
        button.setImage(image, for: .normal)
        button.imageNode.imageModificationBlock = ASImageNodeTintColorModificationBlock(.white)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.clipsToBounds = true
    }
    
    private func setupVLCPlayer(url: URL) {
        vlcMedia = VLCMedia(url: url)
        vlcPlayer = VLCMediaPlayer()
        vlcPlayer?.media = vlcMedia
        vlcPlayer?.delegate = self
        
        vlcPlayer?.drawable = playerContainerNode.view
        
        startUpdateTimer()
    }
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updatePlaybackTime()
        }
    }
    
    private func updatePlaybackTime() {
        guard !isScrubbing, let player = vlcPlayer else { return }
        
        if let media = player.media, media.length.intValue > 0 {
            let duration = Double(media.length.intValue) / 1000.0
            let currentTime = Double(player.time.intValue) / 1000.0
            
            if timeSlider.maximumValue != Float(duration) {
                timeSlider.maximumValue = Float(duration)
                durationLabel.attributedText = NSAttributedString(
                    string: formatTime(duration),
                    attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
                )
                setNeedsLayout()
            }
            
            timeSlider.value = Float(currentTime)
            currentTimeLabel.attributedText = NSAttributedString(
                string: formatTime(currentTime),
                attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
            )
            setNeedsLayout()
        }
    }
    
    deinit {
        updateTimer?.invalidate()
        vlcPlayer?.stop()
        controlsHideTimer?.invalidate()
    }
    
    public func play() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        vlcPlayer?.play()
        posterNode.isHidden = true
        updatePlayPauseIcons(isPlaying: true)
        resetControlsTimer()
    }
    
    public func pause() {
        vlcPlayer?.pause()
        updatePlayPauseIcons(isPlaying: false)
        controlsHideTimer?.invalidate()
        showControls()
    }
    
    @objc private func playPauseTapped() {
        guard let player = vlcPlayer else { return }
        if player.isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    @objc private func seekBackwardTapped() {
        guard let player = vlcPlayer else { return }
        let currentTime = Double(player.time.intValue) / 1000.0
        let newTime = max(0, currentTime - seekDelta)
        player.time = VLCTime(int: Int32(newTime * 1000))
        resetControlsTimer()
        animateButtonTap(seekBackwardButton)
    }
    
    @objc private func seekForwardTapped() {
        guard let player = vlcPlayer, let media = player.media else { return }
        let duration = Double(media.length.intValue) / 1000.0
        let currentTime = Double(player.time.intValue) / 1000.0
        let newTime = min(duration, currentTime + seekDelta)
        player.time = VLCTime(int: Int32(newTime * 1000))
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
            if vlcPlayer?.isPlaying == true {
                resetControlsTimer()
            }
        }
    }
    
    @objc private func sliderDidBeginScrubbing() {
        isScrubbing = true
        vlcPlayer?.pause()
        controlsHideTimer?.invalidate()
    }
    
    @objc private func sliderDidChange() {
        let seconds = Double(timeSlider.value)
        vlcPlayer?.time = VLCTime(int: Int32(seconds * 1000))
        
        currentTimeLabel.attributedText = NSAttributedString(
            string: formatTime(seconds),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )
        setNeedsLayout()
    }
    
    @objc private func sliderDidEndScrubbing() {
        isScrubbing = false
        let seconds = Double(timeSlider.value)
        vlcPlayer?.time = VLCTime(int: Int32(seconds * 1000))
        
        if vlcPlayer?.isPlaying == false {
            
        } else {
            resetControlsTimer()
        }
    }
    
    private func updatePlayPauseIcons(isPlaying: Bool) {
        let centerConfig = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        let centerIconName = isPlaying ? "pause.fill" : "play.fill"
        centerPlayPauseButton.setImage(UIImage(systemName: centerIconName, withConfiguration: centerConfig), for: .normal)
        
        let bottomConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let bottomIconName = isPlaying ? "pause.fill" : "play.fill"
        bottomPlayPauseButton.setImage(UIImage(systemName: bottomIconName, withConfiguration: bottomConfig), for: .normal)
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
        controlsHideTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.vlcPlayer?.isPlaying == true {
                self.hideControls()
                self.toggleOverlayVisibility?()
            }
        }
    }
    
    override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }
        
        playerContainerNode.frame = b
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

extension VLCVideoPlayerNode: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = vlcPlayer else { return }
        
        DispatchQueue.main.async { [weak self] in
            switch player.state {
            case .ended:
                self?.updatePlayPauseIcons(isPlaying: false)
                self?.showControls()
            case .playing:
                self?.updatePlayPauseIcons(isPlaying: true)
            case .paused:
                self?.updatePlayPauseIcons(isPlaying: false)
            default:
                break
            }
        }
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
