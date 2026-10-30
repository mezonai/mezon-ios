import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation

private final class ChunkedVideoResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private static let session = URLSession(configuration: .ephemeral)
    private static let firstChunkSize = 64 * 1024
    private static let maxChunkSize = 1024 * 1024

    let queue = DispatchQueue(label: "mezon.video.chunked-loader")
    let assetURL: URL?
    private let remoteURL: URL
    private var tasks: [ObjectIdentifier: URLSessionTask] = [:]

    init(remoteURL: URL) {
        self.remoteURL = remoteURL
        var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)
        components?.scheme = "mezon-stream"
        self.assetURL = components?.url
        super.init()
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let offset = loadingRequest.dataRequest.map { Int($0.requestedOffset) } ?? 0
        load(loadingRequest, offset: offset, chunkSize: Self.firstChunkSize)
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
    }

    private func load(_ loadingRequest: AVAssetResourceLoadingRequest, offset: Int, chunkSize: Int, retriesLeft: Int = 2) {
        var end = offset + chunkSize - 1
        if let dataRequest = loadingRequest.dataRequest, !dataRequest.requestsAllDataToEndOfResource {
            end = min(end, Int(dataRequest.requestedOffset) + dataRequest.requestedLength - 1)
        }
        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
        let key = ObjectIdentifier(loadingRequest)
        let task = Self.session.dataTask(with: request) { [weak self] data, response, error in
            self?.queue.async {
                guard let self, !loadingRequest.isCancelled else { return }
                self.tasks[key] = nil
                if (error as? URLError)?.code == .networkConnectionLost, retriesLeft > 0 {
                    self.load(loadingRequest, offset: offset, chunkSize: chunkSize, retriesLeft: retriesLeft - 1)
                    return
                }
                let http = response as? HTTPURLResponse
                guard let data, error == nil, http?.statusCode == 206,
                      let contentRange = http?.value(forHTTPHeaderField: "Content-Range"),
                      let totalBytes = contentRange.split(separator: "/").last.flatMap({ Int64($0) }) else {
                    loadingRequest.finishLoading(with: error ?? NSError(domain: "ChunkedVideoResourceLoader", code: http?.statusCode ?? -1))
                    return
                }
                if let info = loadingRequest.contentInformationRequest {
                    info.contentType = self.remoteURL.pathExtension.lowercased() == "mov" ? "com.apple.quicktime-movie" : "public.mpeg-4"
                    info.contentLength = totalBytes
                    info.isByteRangeAccessSupported = true
                }
                guard let dataRequest = loadingRequest.dataRequest else {
                    loadingRequest.finishLoading()
                    return
                }
                dataRequest.respond(with: data)
                let nextOffset = offset + data.count
                let requestedEnd = dataRequest.requestsAllDataToEndOfResource
                    ? totalBytes
                    : min(totalBytes, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
                if Int64(nextOffset) >= requestedEnd || data.isEmpty {
                    loadingRequest.finishLoading()
                } else {
                    self.load(loadingRequest, offset: nextOffset, chunkSize: min(chunkSize * 2, Self.maxChunkSize))
                }
            }
        }
        tasks[key] = task
        task.resume()
    }
}

final class MezonVideoPlayerNode: ASDisplayNode {

    private let playerNode: ASDisplayNode
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

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    private var isScrubbing = false
    private var scrubGeneration = 0
    private let bufferingSpinner = UIActivityIndicatorView(style: .large)
    private var isBuffering = false

    private var controlsHideTimer: Foundation.Timer?
    private var areControlsVisible = true

    private let seekDelta: Double = 15.0
    
    private var sourceURL: URL?
    private var chunkedLoader: ChunkedVideoResourceLoader?
    private var errorOverlayNode: ASDisplayNode?

    var setOverlayVisible: ((Bool) -> Void)?
    var onPlaybackFailed: (() -> Void)?
    var setPagingEnabled: ((Bool) -> Void)?
    var isPlaying: Bool {
        guard let player else { return false }
        return player.rate != 0 || player.timeControlStatus != .paused
    }
    var controlsBottomInset: CGFloat = 0 {
        didSet {
            guard oldValue != controlsBottomInset else { return }
            setNeedsLayout()
        }
    }

    convenience init(url: URL, posterURL: String, usesChunkedLoading: Bool = false) {
        let loader = usesChunkedLoading ? ChunkedVideoResourceLoader(remoteURL: url) : nil
        let asset = AVURLAsset(url: loader?.assetURL ?? url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        if let loader {
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        }
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable", "tracks"])
        self.init(playerItem: item, posterURL: posterURL)
        self.chunkedLoader = loader
        self.sourceURL = url
    }

    init(playerItem: AVPlayerItem, posterURL: String) {

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

        let bottomConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        bottomPlayPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: bottomConfig), for: .normal)
        bottomPlayPauseButton.imageNode.installSafeWhiteTint()
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


        setupPlayer(playerItem: playerItem)


        posterNode.setSignal(videoThumbnailSignal(url: posterURL, resizeMode: .fit))
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(playerTapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        self.view.addGestureRecognizer(tap)

        scrubberBarNode.view.addSubview(timeSlider)
        bufferingSpinner.color = .white
        bufferingSpinner.hidesWhenStopped = true
        view.addSubview(bufferingSpinner)
        updateBufferingIndicator()
        resetControlsTimer()
    }


    private func setupCenterButton(_ button: ASButtonNode, iconName: String, pointSize: CGFloat) {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let image = UIImage(systemName: iconName, withConfiguration: config)
        button.setImage(image, for: .normal)
        button.imageNode.installSafeWhiteTint()
        button.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        button.clipsToBounds = true
    }


    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var readyForDisplayObserver: NSKeyValueObservation?
    private var loadedRangesObserver: NSKeyValueObservation?
    private let minimumBufferToStart: Double = 3.0

    private func setupPlayer(playerItem: AVPlayerItem) {
        if #available(iOS 14.5, *) {
            playerItem.startsOnFirstEligibleVariant = true
        }
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.player = avPlayer

        if let layer = playerNode.layer as? AVPlayerLayer {
            layer.player = avPlayer
            self.playerLayer = layer
            readyForDisplayObserver = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                DispatchQueue.main.async { self?.posterNode.isHidden = true }
            }
        }


        timeControlObserver = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBuffering = isBuffering
                if self.isNodeLoaded { self.updateBufferingIndicator() }
                self.startPlaybackIfBuffered()
            }
        }

        loadedRangesObserver = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.startPlaybackIfBuffered()
            }
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
            } else if item.status == .failed {
                DispatchQueue.main.async {
                    self?.showErrorOverlay(error: item.error)
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
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
        readyForDisplayObserver?.invalidate()
        loadedRangesObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func showErrorOverlay(error: Error?) {
        guard errorOverlayNode == nil else { return }

        isScrubbing = false
        isBuffering = false
        if isNodeLoaded { updateBufferingIndicator() }
        onPlaybackFailed?()
        
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
        let errorMessage = error?.localizedDescription ?? "This video format may not be supported"
        messageNode.attributedText = NSAttributedString(
            string: errorMessage,
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

    public func play() {
        AppAudioSession.activateForMediaPlayback(options: [])
        player?.play()
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
        if p.timeControlStatus == .paused {
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
        scrubGeneration += 1
        isScrubbing = true
        setPagingEnabled?(false)
        controlsHideTimer?.invalidate()
    }

    @objc private func sliderDidChange() {
        let seconds = Double(timeSlider.value)
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: seekTime)

        currentTimeLabel.attributedText = NSAttributedString(
            string: formatTime(seconds),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )
        setNeedsLayout()
    }

    @objc private func sliderDidEndScrubbing() {
        setPagingEnabled?(true)
        guard let player = player else {
            isScrubbing = false
            return
        }
        let generation = scrubGeneration
        let seconds = Double(timeSlider.value)
        let seekTime = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: seekTime) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.scrubGeneration == generation else { return }
                self.isScrubbing = false
            }
        }
        if player.timeControlStatus != .paused {
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

    private func startPlaybackIfBuffered() {
        guard !isScrubbing,
              let player,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
              let reason = player.reasonForWaitingToPlay,
              reason == .toMinimizeStalls || reason == .evaluatingBufferingRate,
              let item = player.currentItem,
              item.status == .readyToPlay else { return }
        let now = item.currentTime()
        guard let range = item.loadedTimeRanges.map(\.timeRangeValue).first(where: { $0.containsTime(now) }),
              range.end.seconds - now.seconds >= minimumBufferToStart else { return }
        player.playImmediately(atRate: 1)
    }

    private func updateBufferingIndicator() {
        if isBuffering {
            bufferingSpinner.startAnimating()
        } else {
            bufferingSpinner.stopAnimating()
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
            if self.player?.rate != 0 {
                self.hideControls()
            }
        }
    }


    override func layout() {
        super.layout()
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }

        playerNode.frame = b
        posterNode.frame = b
        bufferingSpinner.sizeToFit()
        bufferingSpinner.center = CGPoint(x: b.midX, y: b.midY + 60)
        
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


        let safeBottom = max(view.safeAreaInsets.bottom, view.window?.safeAreaInsets.bottom ?? 0)
        let minBottomPadding: CGFloat = 44
        let barBottomPadding = controlsBottomInset > 0 ? 0 : max(safeBottom, minBottomPadding)
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

extension MezonVideoPlayerNode: UIGestureRecognizerDelegate {
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
