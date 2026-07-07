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
    private let timeSlider = SeekSlider()
    private let currentTimeLabel: ASTextNode
    private let durationLabel: ASTextNode
    
    private var vlcPlayer: VLCMediaPlayer?
    private var vlcMedia: VLCMedia?
    private var isScrubbing = false
    private var scrubIdleTicks = 0
    private var updateTimer: Foundation.Timer?
    
    private var controlsHideTimer: Foundation.Timer?
    private var areControlsVisible = true
    
    private let seekDelta: Double = 15.0
    
    private var sourceURL: URL?
    private var errorOverlayNode: ASDisplayNode?
    private var loadingTimeoutTimer: Foundation.Timer?
    
    var setOverlayVisible: ((Bool) -> Void)?
    var setPagingEnabled: ((Bool) -> Void)?
    var controlsBottomInset: CGFloat = 0 {
        didSet {
            guard oldValue != controlsBottomInset else { return }
            setNeedsLayout()
        }
    }
    
    init(url: URL, posterURL: String) {
        self.sourceURL = url
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
        
        let thumbImage = makeCircleImage(radius: 9, color: .white)
        self.timeSlider.setThumbImage(thumbImage, for: .normal)
        self.timeSlider.setThumbImage(thumbImage, for: .highlighted)
        
        self.timeSlider.addTarget(self, action: #selector(sliderDidBeginScrubbing), for: .touchDown)
        self.timeSlider.addTarget(self, action: #selector(sliderDidChange), for: .valueChanged)
        self.timeSlider.addTarget(self, action: #selector(sliderDidEndScrubbing), for: .touchUpInside)
        self.timeSlider.addTarget(self, action: #selector(sliderDidEndScrubbing), for: .touchUpOutside)
        self.timeSlider.addTarget(self, action: #selector(sliderDidEndScrubbing), for: .touchCancel)
        
        updatePlayPauseIcons(isPlaying: false)
        
        setupVLCPlayer(url: url)
        
        posterNode.setSignal(videoThumbnailSignal(url: posterURL, resizeMode: .fit))
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.isUserInteractionEnabled = true
        playerContainerNode.view.isUserInteractionEnabled = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(playerTapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        playerContainerNode.view.addGestureRecognizer(tap)
        
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
        scrubIdleTicks += 1
        if isScrubbing && (!timeSlider.isTracking || scrubIdleTicks > 8) {
            isScrubbing = false
        }
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
        loadingTimeoutTimer?.invalidate()
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
        
        loadingTimeoutTimer?.invalidate()
        loadingTimeoutTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.vlcPlayer?.state == .error {
                self.showErrorOverlay(message: "Video failed to load. The format may not be supported or the connection timed out.")
            }
        }
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
        setPagingEnabled?(false)
        controlsHideTimer?.invalidate()
    }
    
    @objc private func sliderDidChange() {
        scrubIdleTicks = 0
        guard let player = vlcPlayer, let media = player.media else { return }
        let duration = Double(media.length.intValue) / 1000.0
        guard duration > 0 else { return }
        
        let seconds = Double(timeSlider.value)
        let clampedSeconds = max(0, min(seconds, duration))
        
        currentTimeLabel.attributedText = NSAttributedString(
            string: formatTime(clampedSeconds),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )
        setNeedsLayout()
    }
    
    @objc private func sliderDidEndScrubbing() {
        isScrubbing = false
        setPagingEnabled?(true)
        guard let player = vlcPlayer, let media = player.media else { return }
        let duration = Double(media.length.intValue) / 1000.0
        guard duration > 0 else { return }

        let seconds = Double(timeSlider.value)
        let clampedSeconds = max(0, min(seconds, duration))

        player.time = VLCTime(int: Int32(clampedSeconds * 1000))

        if player.isPlaying {
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
        setOverlayVisible?(true)
        UIView.animate(withDuration: 0.25) {
            self.centerOverlayNode.alpha = 1.0
            self.scrubberBarNode.alpha = 1.0
        }
    }
    
    private func hideControls() {
        areControlsVisible = false
        setOverlayVisible?(false)
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
            }
        }
    }
    
    override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }
        
        playerContainerNode.frame = b
        posterNode.frame = b
        
        if let errorNode = errorOverlayNode {
            errorNode.frame = b
        }
        
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
        let barBottomPadding = controlsBottomInset > 0 ? 0 : safeBottom
        let barHeight: CGFloat = 50 + barBottomPadding
        scrubberBarNode.frame = CGRect(x: 0, y: b.height - controlsBottomInset - barHeight, width: b.width, height: barHeight)
        
        let playSize = CGSize(width: 44, height: 44)
        bottomPlayPauseButton.frame = CGRect(x: 8, y: 3, width: playSize.width, height: playSize.height)
        
        let currentSize = currentTimeLabel.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: 100, height: 20))).size
        currentTimeLabel.frame = CGRect(x: bottomPlayPauseButton.frame.maxX + 4, y: 15, width: currentSize.width, height: currentSize.height)
        
        let durationSize = durationLabel.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: 100, height: 20))).size
        durationLabel.frame = CGRect(x: b.width - durationSize.width - 16, y: 15, width: durationSize.width, height: durationSize.height)
        
        let sliderX = currentTimeLabel.frame.maxX + 12
        let sliderW = durationLabel.frame.minX - 12 - sliderX
        timeSlider.frame = CGRect(x: sliderX, y: 3, width: sliderW, height: 44)
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let errorNode = errorOverlayNode, errorNode.supernode != nil {
            let errorPoint = self.view.convert(point, to: errorNode.view)
            if let hitView = errorNode.view.hitTest(errorPoint, with: event) {
                return hitView
            }
        }
        
        if areControlsVisible {
            let centerPoint = self.view.convert(point, to: centerOverlayNode.view)
            if let hitView = centerOverlayNode.view.hitTest(centerPoint, with: event), hitView != centerOverlayNode.view {
                return hitView
            }
            
            let scrubberPoint = self.view.convert(point, to: scrubberBarNode.view)
            if let hitView = scrubberBarNode.view.hitTest(scrubberPoint, with: event), hitView != scrubberBarNode.view {
                return hitView
            }
        }
        
        return playerContainerNode.view
    }
}

extension VLCVideoPlayerNode: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = vlcPlayer else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch player.state {
            case .ended:
                self.loadingTimeoutTimer?.invalidate()
                self.updatePlayPauseIcons(isPlaying: false)
                self.showControls()
            case .playing:
                self.loadingTimeoutTimer?.invalidate()
                self.updatePlayPauseIcons(isPlaying: true)
            case .paused:
                self.loadingTimeoutTimer?.invalidate()
                self.updatePlayPauseIcons(isPlaying: false)
            case .error:
                self.loadingTimeoutTimer?.invalidate()
                self.showErrorOverlay(message: "An error occurred while playing this video.")
            case .stopped:
                self.loadingTimeoutTimer?.invalidate()
            case .opening, .buffering:
                break
            default:
                break
            }
        }
    }
    
    private func showErrorOverlay(message: String) {
        guard errorOverlayNode == nil else { return }
        
        centerOverlayNode.isHidden = true
        scrubberBarNode.isHidden = true
        
        let overlayNode = ASDisplayNode()
        overlayNode.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        overlayNode.automaticallyManagesSubnodes = true
        
        let iconNode = ASImageNode()
        let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        iconNode.image = UIImage(systemName: "exclamationmark.triangle", withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit
        
        let titleNode = ASTextNode()
        titleNode.attributedText = NSAttributedString(
            string: "Cannot Play Video",
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
        )
        titleNode.maximumNumberOfLines = 1
        
        let messageNode = ASTextNode()
        messageNode.attributedText = NSAttributedString(
            string: message,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
        )
        messageNode.maximumNumberOfLines = 0
        
        let openButton = ASButtonNode()
        openButton.setTitle("Open in Browser", with: UIFont.systemFont(ofSize: 16, weight: .medium), with: .white, for: .normal)
        openButton.backgroundColor = UIColor.systemBlue
        openButton.cornerRadius = 8
        openButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        openButton.addTarget(self, action: #selector(openInBrowserTapped), forControlEvents: .touchUpInside)
        
        let closeButton = ASButtonNode()
        closeButton.setTitle("Close", with: UIFont.systemFont(ofSize: 16, weight: .medium), with: UIColor.white.withAlphaComponent(0.8), for: .normal)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        closeButton.cornerRadius = 8
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        closeButton.addTarget(self, action: #selector(closeErrorOverlay), forControlEvents: .touchUpInside)
        
        overlayNode.layoutSpecBlock = { _, constrainedSize in
            iconNode.style.preferredSize = CGSize(width: 48, height: 48)
            let iconSpec = ASCenterLayoutSpec(centeringOptions: .X, sizingOptions: [], child: iconNode)
            
            let titleSpec = ASCenterLayoutSpec(centeringOptions: .X, sizingOptions: [], child: titleNode)
            
            messageNode.style.maxWidth = ASDimension(unit: .points, value: min(constrainedSize.max.width - 64, 320))
            let messageSpec = ASCenterLayoutSpec(centeringOptions: .X, sizingOptions: [], child: messageNode)
            
            openButton.style.preferredSize = CGSize(width: 200, height: 44)
            closeButton.style.preferredSize = CGSize(width: 200, height: 44)
            
            let buttonsStack = ASStackLayoutSpec.vertical()
            buttonsStack.spacing = 12
            buttonsStack.children = [openButton, closeButton]
            let buttonsSpec = ASCenterLayoutSpec(centeringOptions: .X, sizingOptions: [], child: buttonsStack)
            
            let stack = ASStackLayoutSpec.vertical()
            stack.spacing = 16
            stack.children = [iconSpec, titleSpec, messageSpec, buttonsSpec]
            
            return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: stack)
        }
        
        errorOverlayNode = overlayNode
        addSubnode(overlayNode)
        setNeedsLayout()
    }
    
    @objc private func closeErrorOverlay() {
        errorOverlayNode?.removeFromSupernode()
        errorOverlayNode = nil
        
        centerOverlayNode.isHidden = false
        scrubberBarNode.isHidden = false
        showControls()
    }
    
    @objc private func openInBrowserTapped() {
        guard let url = sourceURL else { return }
        UIApplication.shared.open(url)
    }
}

extension VLCVideoPlayerNode: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UISlider { return false }
            view = v.superview
        }
        return true
    }
}

private final class SeekSlider: UISlider {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let width = bounds.width
        guard width > 0 else { return super.beginTracking(touch, with: event) }
        let ratio = Float(min(max(0, touch.location(in: self).x / width), 1))
        setValue(minimumValue + ratio * (maximumValue - minimumValue), animated: false)
        sendActions(for: .valueChanged)
        return true
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: 0, dy: -12).contains(point)
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
