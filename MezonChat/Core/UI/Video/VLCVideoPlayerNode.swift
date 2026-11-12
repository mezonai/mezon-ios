import Foundation
import Darwin
import UIKit
import AsyncDisplayKit
import AVFoundation
import MobileVLCKit

private final class VLCDrawableHostView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            subview.frame = bounds
        }
    }
}

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
    private var pendingSeekTarget: Double?
    private var pendingSeekFrom: Double = 0
    private var pendingSeekWaitTicks = 0

    private var lastKnownTime: Double = 0
    private var updateTimer: Foundation.Timer?
    
    private var controlsHideTimer: Foundation.Timer?
    private var areControlsVisible = true
    
    private let seekDelta: Double = 15.0
    
    private var sourceURL: URL?
    private var errorOverlayNode: ASDisplayNode?
    private var playbackWatchdog: VideoPlaybackWatchdog?
    private var hasPresentedVideo = false

    private var downloadTask: CDNTaskHandle?
    private var downloadProgressObservation: NSKeyValueObservation?
    private var wantsPlay = false
    private var isPreparingDownload = false
    private var pendingRemoteURL: URL?
    private var isRequestingStreamURL = false
    private var isStreamingRemote = false
    private var canRetryCachedFile = false
    private var needsDownload = false
    private let downloadSpinner = UIActivityIndicatorView(style: .large)
    private let downloadProgressLabel = UILabel()

    var setOverlayVisible: ((Bool) -> Void)?
    var setPagingEnabled: ((Bool) -> Void)?
    var onDownloadedFile: ((URL) -> Bool)?
    var startPosition: Double = 0
    var isPlaying: Bool { wantsPlay }
    var playbackPosition: Double { startPosition > 0 ? startPosition : lastKnownTime }
    var controlsBottomInset: CGFloat = 0 {
        didSet {
            guard oldValue != controlsBottomInset else { return }
            setNeedsLayout()
        }
    }
    
    init(url: URL, posterURL: String, localFile: URL?, retryCachedFile: Bool) {
        self.sourceURL = url
        self.playerContainerNode = ASDisplayNode(viewBlock: { VLCDrawableHostView() })
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
        
        centerPlayPauseButton.accessibilityIdentifier = AccessibilityID.Video.playPause
        seekBackwardButton.accessibilityIdentifier = AccessibilityID.Video.seekBackward
        seekBackwardButton.accessibilityLabel = "Back 15 seconds"
        seekForwardButton.accessibilityIdentifier = AccessibilityID.Video.seekForward
        seekForwardButton.accessibilityLabel = "Forward 15 seconds"

        centerPlayPauseButton.addTarget(self, action: #selector(playPauseTapped), forControlEvents: .touchUpInside)
        seekBackwardButton.addTarget(self, action: #selector(seekBackwardTapped), forControlEvents: .touchUpInside)
        seekForwardButton.addTarget(self, action: #selector(seekForwardTapped), forControlEvents: .touchUpInside)
        
        scrubberBarNode.addSubnode(bottomPlayPauseButton)
        scrubberBarNode.addSubnode(currentTimeLabel)
        scrubberBarNode.addSubnode(durationLabel)
        
        let bottomConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        bottomPlayPauseButton.setImage(UIImage(systemName: "play.fill", withConfiguration: bottomConfig), for: .normal)
        bottomPlayPauseButton.imageNode.installSafeWhiteTint()
        bottomPlayPauseButton.accessibilityIdentifier = AccessibilityID.Video.scrubberPlayPause
        bottomPlayPauseButton.addTarget(self, action: #selector(playPauseTapped), forControlEvents: .touchUpInside)
        
        self.timeSlider.accessibilityIdentifier = AccessibilityID.Video.scrubber
        self.timeSlider.accessibilityLabel = "Playback position"
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
        
        setupVLCPlayer(url: url, localFile: localFile, retryCachedFile: retryCachedFile)
        
        posterNode.setSignal(videoThumbnailSignal(url: posterURL, resizeMode: .fit, allowRemoteGeneration: false))
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

        downloadSpinner.accessibilityIdentifier = AccessibilityID.Video.loading
        downloadSpinner.accessibilityLabel = "Loading video"
        downloadSpinner.isAccessibilityElement = true
        downloadProgressLabel.accessibilityIdentifier = AccessibilityID.Video.progress
        downloadSpinner.color = .white
        downloadSpinner.hidesWhenStopped = true
        view.addSubview(downloadSpinner)

        downloadProgressLabel.textColor = .white
        downloadProgressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        downloadProgressLabel.textAlignment = .center
        downloadProgressLabel.isHidden = true
        view.addSubview(downloadProgressLabel)

        if isPreparingDownload {
            showDownloadIndicator()
        } else if wantsPlay && (isRequestingStreamURL || isStreamingRemote) {
            showStreamIndicator()
        }

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
    
    private func setupVLCPlayer(url: URL, localFile: URL?, retryCachedFile: Bool) {
        if url.isFileURL {
            attachVLCPlayer(fileURL: url)
            return
        }
        pendingRemoteURL = url
        if let localURL = localFile ?? Self.cachedFile(for: url) {
            canRetryCachedFile = retryCachedFile
            attachVLCPlayer(fileURL: localURL)
        }
    }

    private func attachVLCPlayer(fileURL: URL) {
        if Self.retainCachedFile(fileURL) { attachedCacheFile = fileURL }
        isStreamingRemote = !fileURL.isFileURL
        hasPresentedVideo = false
        vlcMedia = VLCMedia(url: fileURL)
        vlcPlayer = VLCMediaPlayer(options: ["--network-caching=1000", "--no-video-title-show"])
        vlcPlayer?.media = vlcMedia
        vlcPlayer?.delegate = self
        vlcPlayer?.drawable = playerContainerNode.view
        if wantsPlay { play() }
    }

    private func startRemoteStream(_ remoteURL: URL) {
        guard !isRequestingStreamURL else { return }
        isRequestingStreamURL = true
        showStreamIndicator()
        CDNSigner.shared.requestURL(for: remoteURL) { [weak self] request in
            DispatchQueue.main.async {
                guard let self, self.isRequestingStreamURL else { return }
                self.isRequestingStreamURL = false
                self.attachVLCPlayer(fileURL: request.url)
                if !self.wantsPlay { self.hideDownloadIndicator() }
            }
        }
    }

    private func handlePlaybackFailure(_ message: String) {
        if isStreamingRemote, pendingRemoteURL?.pathExtension.lowercased() != "m3u8" {
            needsDownload = true
        } else if !canRetryCachedFile {
            showErrorOverlay(message: message)
            return
        }
        canRetryCachedFile = false
        if hasPresentedVideo { startPosition = playbackPosition }
        lastKnownTime = 0
        updateTimer?.invalidate()
        updateTimer = nil
        playbackWatchdog = nil
        if isScrubbing { setPagingEnabled?(true) }
        isScrubbing = false
        pendingSeekTarget = nil
        vlcPlayer?.delegate = nil
        vlcPlayer?.stop()
        vlcPlayer = nil
        vlcMedia = nil
        releaseAttachedCacheFile()
        posterNode.isHidden = false
        if wantsPlay { play() }
    }

    private static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 10 * 60
        return URLSession(configuration: config)
    }()

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }

    static let streamCacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VideoStreamCache", isDirectory: true)

    private static let attachedStreamCacheLock = NSLock()
    private static var attachedStreamCacheFileCounts: [String: Int] = [:]
    private var attachedCacheFile: URL?

    static func attachedStreamCacheFileNames() -> Set<String> {
        attachedStreamCacheLock.lock()
        defer { attachedStreamCacheLock.unlock() }
        return Set(attachedStreamCacheFileCounts.keys)
    }

    @discardableResult
    static func retainCachedFile(_ fileURL: URL) -> Bool {
        guard fileURL.deletingLastPathComponent().path == streamCacheDirectory.path else { return false }
        attachedStreamCacheLock.lock()
        attachedStreamCacheFileCounts[fileURL.lastPathComponent, default: 0] += 1
        attachedStreamCacheLock.unlock()
        return true
    }

    static func releaseCachedFile(_ fileURL: URL) {
        let name = fileURL.lastPathComponent
        attachedStreamCacheLock.lock()
        if let count = attachedStreamCacheFileCounts[name], count > 1 {
            attachedStreamCacheFileCounts[name] = count - 1
        } else {
            attachedStreamCacheFileCounts.removeValue(forKey: name)
        }
        attachedStreamCacheLock.unlock()
    }

    private func releaseAttachedCacheFile() {
        guard let attachedCacheFile else { return }
        Self.releaseCachedFile(attachedCacheFile)
        self.attachedCacheFile = nil
    }

    private static func cachedFileURL(for remoteURL: URL, isHLSCopy: Bool = false) -> URL {
        let ext = isHLSCopy ? "hls.mp4" : (remoteURL.pathExtension.isEmpty ? "mkv" : remoteURL.pathExtension)
        return streamCacheDirectory.appendingPathComponent("\(stableHash(remoteURL.absoluteString)).\(ext)")
    }

    static func cachedFile(for remoteURL: URL) -> URL? {
        guard !remoteURL.isFileURL else { return nil }
        for fileURL in [cachedFileURL(for: remoteURL, isHLSCopy: true), cachedFileURL(for: remoteURL)] {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { continue }
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
            return fileURL
        }
        return nil
    }

    private static func storeDownloadedFile(_ tempURL: URL, response: URLResponse?, at localURL: URL) -> Bool {
        guard let http = response as? HTTPURLResponse,
              http.mimeType?.hasPrefix("text/") != true, http.mimeType != "application/json",
              http.mimeType != "application/vnd.apple.mpegurl", http.mimeType != "application/x-mpegurl",
              let size = (try? tempURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 else { return false }
        if http.statusCode != 200 {
            guard http.statusCode == 206, let header = http.value(forHTTPHeaderField: "Content-Range"),
                  let range = VideoRangeCache.parseContentRange(header),
                  range.start == 0, range.end == range.total - 1, range.total == Int64(size) else { return false }
        }
        return storeFile(tempURL, at: localURL, size: size)
    }

    private static func storeFile(_ tempURL: URL, at localURL: URL, size: Int) -> Bool {
        let fileManager = FileManager.default
        let stagingURL = localURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        do {
            try fileManager.createDirectory(at: streamCacheDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: tempURL, to: stagingURL)
        } catch {
            return false
        }
        defer { try? fileManager.removeItem(at: stagingURL) }
        // Publish only complete files. Readers can keep using the previous file
        // if a different gallery instance has already opened it.
        let stored = stagingURL.withUnsafeFileSystemRepresentation { source in
            localURL.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return false }
                return rename(source, destination) == 0
            }
        }
        if stored {
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: localURL.path)
            StorageMaintenance.shared.noteDiskCacheWrite(byteCount: size)
        }
        return stored
    }

    private func startDownload(remote: URL) {
        guard !isPreparingDownload else { return }
        isPreparingDownload = true
        downloadProgressLabel.text = nil
        showControls()
        showDownloadIndicator()
        let localURL = Self.cachedFileURL(for: remote)
        downloadTask = CDNSigner.shared.downloadTask(with: remote, in: Self.downloadSession, onStart: { [weak self] started in
            let observation = started.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                DispatchQueue.main.async { self?.updateDownloadProgress(fraction) }
            }
            DispatchQueue.main.async {
                guard let self, self.isPreparingDownload else {
                    observation.invalidate()
                    return
                }
                self.downloadProgressObservation?.invalidate()
                self.downloadProgressObservation = observation
            }
        }) { [weak self] tempURL, response, error in
            guard self != nil else { return }
            let stored = error == nil && (tempURL.map { Self.storeDownloadedFile($0, response: response, at: localURL) } ?? false)
            let status = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let self else { return }
                self.downloadTask = nil
                self.downloadProgressObservation?.invalidate()
                self.downloadProgressObservation = nil
                if stored {
                    self.finishDownload(localURL)
                } else if error == nil, status == 403 || status == 404 {
                    self.downloadFinishedHLS(remote)
                } else {
                    self.finishDownload(nil)
                }
            }
        }
    }

    private func downloadFinishedHLS(_ remote: URL) {
        let destination = Self.cachedFileURL(for: remote, isHLSCopy: true)
        updateDownloadProgress(0)
        FileIngestHLSCopy.makeFile(
            attachmentURL: remote.absoluteString,
            shouldContinue: { [weak self] in self != nil },
            progress: { [weak self] fraction in
                DispatchQueue.main.async { self?.updateDownloadProgress(fraction) }
            }
        ) { [weak self] outcome in
            var stored = false
            if case .file(let file) = outcome {
                defer { try? FileManager.default.removeItem(at: file) }
                if self != nil, let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0 {
                    stored = Self.storeFile(file, at: destination, size: size)
                }
            }
            let file = stored ? destination : nil
            DispatchQueue.main.async { self?.finishDownload(file) }
        }
    }

    private func updateDownloadProgress(_ fraction: Double) {
        guard isPreparingDownload, fraction.isFinite, fraction >= 0 else { return }
        let percent = Int(min(fraction, 1) * 100)
        let text = "\(percent)%"
        if downloadProgressLabel.text != text { downloadProgressLabel.text = text }
    }

    private func finishDownload(_ fileURL: URL?) {
        isPreparingDownload = false
        needsDownload = false
        hideDownloadIndicator()
        guard let fileURL else {
            showErrorOverlay(message: "Unable to load this video.")
            return
        }
        if onDownloadedFile?(fileURL) != true { attachVLCPlayer(fileURL: fileURL) }
    }

    private func showDownloadIndicator() {
        downloadSpinner.startAnimating()
        centerOverlayNode.isHidden = true
        downloadProgressLabel.isHidden = false
        if downloadProgressLabel.text == nil { downloadProgressLabel.text = "0%" }
    }

    private func showStreamIndicator() {
        downloadSpinner.startAnimating()
        downloadProgressLabel.isHidden = true
        centerOverlayNode.isHidden = true
    }

    private func hideDownloadIndicator() {
        downloadSpinner.stopAnimating()
        downloadProgressLabel.isHidden = true
        centerOverlayNode.isHidden = false
    }
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        updateTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updatePlaybackTime()
        }
    }
    
    private func updatePlaybackTime() {
        guard let player = vlcPlayer, wantsPlay else { return }
        let currentTime = max(0, Double(player.time.intValue) / 1000.0)
        guard !isScrubbing, UIApplication.shared.applicationState == .active else {
            playbackWatchdog = VideoPlaybackWatchdog(position: currentTime)
            return
        }

        let hasVideo = player.hasVideoOut
        if hasVideo, currentTime > 0, currentTime != lastKnownTime {
            hasPresentedVideo = true
            posterNode.isHidden = true
            if downloadSpinner.isAnimating { hideDownloadIndicator() }
            if startPosition > 0, player.isSeekable {
                let duration = Double(player.media?.length.intValue ?? 0) / 1000
                let target = duration > 0 ? min(startPosition, max(0, duration - 0.1)) : startPosition
                if target < Double(Int32.max) / 1000 {
                    player.time = VLCTime(int: Int32(target * 1000))
                }
                startPosition = 0
            }
        }
        let receivedBytes = Int64(player.media?.statistics.readBytes ?? 0)
        if playbackWatchdog?.hasStalled(position: currentTime, hasVideo: hasVideo, receivedBytes: receivedBytes) == true {
            handlePlaybackFailure("Video playback timed out.")
            return
        }
        lastKnownTime = currentTime

        if let target = pendingSeekTarget {
            let reachedTarget = currentTime >= target && abs(currentTime - pendingSeekFrom) > 0.5
            let closeEnough = abs(currentTime - target) <= 0.35
            if reachedTarget || closeEnough {
                pendingSeekTarget = nil
                pendingSeekWaitTicks = 0
            } else {
                pendingSeekWaitTicks += 1
                if pendingSeekWaitTicks == 6 {
                    player.time = VLCTime(int: Int32(target * 1000))
                } else if pendingSeekWaitTicks >= 12 {
                    pendingSeekTarget = nil
                }
            }
            return
        }

        if let media = player.media, media.length.intValue > 0 {
            let duration = Double(media.length.intValue) / 1000.0
            if timeSlider.maximumValue != Float(duration) {
                timeSlider.maximumValue = Float(duration)
                durationLabel.attributedText = NSAttributedString(
                    string: formatTime(duration),
                    attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
                )
                setNeedsLayout()
            }
            
            timeSlider.value = Float(currentTime)
            let label = formatTime(currentTime)
            guard currentTimeLabel.attributedText?.string != label else { return }
            currentTimeLabel.attributedText = NSAttributedString(
                string: label,
                attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
            )
            setNeedsLayout()
        }
    }
    
    deinit {
        releaseAttachedCacheFile()
        downloadTask?.cancel()
        downloadProgressObservation?.invalidate()
        updateTimer?.invalidate()
        vlcPlayer?.delegate = nil
        vlcPlayer?.stop()
        controlsHideTimer?.invalidate()
    }
    
    public func play() {
        guard errorOverlayNode == nil else { return }
        wantsPlay = true
        updatePlayPauseIcons(isPlaying: true)
        guard let player = vlcPlayer else {
            guard let remote = pendingRemoteURL else { return }
            if needsDownload {
                startDownload(remote: remote)
            } else {
                startRemoteStream(remote)
            }
            return
        }
        AppAudioSession.activateForMediaPlayback(options: [])
        if updateTimer == nil {
            playbackWatchdog = VideoPlaybackWatchdog(position: max(0, Double(player.time.intValue) / 1000))
            startUpdateTimer()
        }
        if !hasPresentedVideo { showStreamIndicator() }
        player.play()
        resetControlsTimer()
    }

    public func pause() {
        wantsPlay = false
        vlcPlayer?.pause()
        updateTimer?.invalidate()
        updateTimer = nil
        playbackWatchdog = nil
        if !isPreparingDownload { hideDownloadIndicator() }
        updatePlayPauseIcons(isPlaying: false)
        controlsHideTimer?.invalidate()
        showControls()
    }

    @objc private func playPauseTapped() {
        if wantsPlay {
            pause()
        } else {
            play()
        }
    }
    
    @objc private func seekBackwardTapped() {
        guard let player = vlcPlayer else { return }
        let base = pendingSeekTarget ?? (Double(player.time.intValue) / 1000.0)
        let newTime = max(0, base - seekDelta)
        pendingSeekTarget = nil
        pendingSeekWaitTicks = 0
        player.time = VLCTime(int: Int32(newTime * 1000))
        resetControlsTimer()
        animateButtonTap(seekBackwardButton)
    }

    @objc private func seekForwardTapped() {
        guard let player = vlcPlayer, let media = player.media else { return }
        let duration = Double(media.length.intValue) / 1000.0
        let base = pendingSeekTarget ?? (Double(player.time.intValue) / 1000.0)
        let newTime = min(duration, base + seekDelta)
        pendingSeekTarget = nil
        pendingSeekWaitTicks = 0
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
        pendingSeekTarget = nil
        pendingSeekWaitTicks = 0
        setPagingEnabled?(false)
        controlsHideTimer?.invalidate()
    }

    @objc private func sliderDidChange() {
        guard let media = vlcPlayer?.media else { return }
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
        setPagingEnabled?(true)
        isScrubbing = false
        guard let player = vlcPlayer, let media = player.media else {
            pendingSeekTarget = nil
            return
        }
        let duration = Double(media.length.intValue) / 1000.0
        guard duration > 0 else {
            pendingSeekTarget = nil
            return
        }

        let seconds = Double(timeSlider.value)
        let clampedSeconds = max(0, min(seconds, duration))

        timeSlider.value = Float(clampedSeconds)
        currentTimeLabel.attributedText = NSAttributedString(
            string: formatTime(clampedSeconds),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )

        pendingSeekFrom = Double(player.time.intValue) / 1000.0
        player.time = VLCTime(int: Int32(clampedSeconds * 1000))
        pendingSeekTarget = clampedSeconds
        pendingSeekWaitTicks = 0

        if player.isPlaying {
            resetControlsTimer()
        }
    }
    
    private func updatePlayPauseIcons(isPlaying: Bool) {
        let label = isPlaying ? "Pause" : "Play"
        centerPlayPauseButton.accessibilityLabel = label
        bottomPlayPauseButton.accessibilityLabel = label
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
        
        downloadSpinner.sizeToFit()
        downloadSpinner.center = CGPoint(x: b.midX, y: b.midY)
        let progressLabelHeight = ceil(downloadProgressLabel.font.lineHeight)
        downloadProgressLabel.frame = CGRect(x: 0, y: downloadSpinner.frame.maxY + 8, width: b.width, height: progressLabelHeight)
        
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
    func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.vlcPlayer === player, self.errorOverlayNode == nil else { return }

            switch player.state {
            case .ended:
                self.pendingSeekTarget = nil
                self.pendingSeekWaitTicks = 0
                let showedVideo = self.hasPresentedVideo || player.hasVideoOut || (player.media?.statistics.displayedPictures ?? 0) > 0
                if self.playbackEndedPrematurely(player: player) || !showedVideo {
                    self.handlePlaybackFailure("This video could not be played in full.")
                    return
                }
                self.pause()
            case .playing:
                if self.wantsPlay { self.updatePlayPauseIcons(isPlaying: true) }
            case .error:
                self.handlePlaybackFailure("An error occurred while playing this video.")
            case .stopped:
                self.pendingSeekTarget = nil
                self.pendingSeekWaitTicks = 0
            case .opening, .buffering:
                if self.wantsPlay { self.showStreamIndicator() }
            default:
                break
            }
        }
    }

    private func playbackEndedPrematurely(player: VLCMediaPlayer) -> Bool {
        let declared = Double(player.media?.length.intValue ?? 0) / 1000.0
        let playedTo = max(lastKnownTime, Double(player.time.intValue) / 1000.0)
        guard declared > 5 else { return false }
        return playedTo < declared * 0.6 && (declared - playedTo) > 5
    }

    private func showErrorOverlay(message: String) {
        guard errorOverlayNode == nil else { return }
        if isScrubbing { setPagingEnabled?(true) }
        isScrubbing = false
        pause()
        hideDownloadIndicator()
        
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
        messageNode.accessibilityIdentifier = AccessibilityID.Video.error
        
        let openButton = ASButtonNode()
        openButton.setTitle("Open in Browser", with: UIFont.systemFont(ofSize: 16, weight: .medium), with: .white, for: .normal)
        openButton.backgroundColor = UIColor.systemBlue
        openButton.cornerRadius = 8
        openButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        openButton.accessibilityIdentifier = AccessibilityID.Video.openInBrowser
        openButton.addTarget(self, action: #selector(openInBrowserTapped), forControlEvents: .touchUpInside)
        
        let closeButton = ASButtonNode()
        closeButton.setTitle("Close", with: UIFont.systemFont(ofSize: 16, weight: .medium), with: UIColor.white.withAlphaComponent(0.8), for: .normal)
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        closeButton.cornerRadius = 8
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        closeButton.accessibilityIdentifier = AccessibilityID.Video.closeError
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
        CDNSigner.shared.openExternally(url)
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
