import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation

private enum VideoPlaybackBufferPolicy {
    // Track timestamps may begin slightly after zero or differ by a few frames.
    // Count only contiguous ranges near the playhead, never a distant seek target.
    static func bufferedAhead(at position: Double, ranges: [CMTimeRange]) -> Double {
        guard position.isFinite else { return 0 }
        let ranges = ranges.compactMap { range -> (start: Double, end: Double)? in
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite, end > start else { return nil }
            return (start, end)
        }.sorted { $0.start < $1.start }
        var end = position
        for range in ranges {
            if range.end <= end { continue }
            guard range.start <= end + 0.1 else { break }
            end = range.end
        }
        return max(0, end - position)
    }

    static func shouldStart(bufferedAhead: Double, remaining: Double?, hasStarted: Bool, waitingDuration: Double, bufferGrowthRate: Double? = nil) -> Bool {
        guard bufferedAhead.isFinite, bufferedAhead > 0 else { return false }
        if let remaining, remaining.isFinite, remaining > 0,
           bufferedAhead >= remaining - 0.05 { return true }
        // If loading adds less than one second of playable media per second,
        // forcing playback just drains the buffer and repeats the stall.
        if waitingDuration >= 2, let rate = bufferGrowthRate, rate.isFinite, rate < 1 {
            return false
        }
        return bufferedAhead >= (hasStarted ? 2.0 : 1.0)
    }
}

private final class ChunkedVideoResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    // Larger HTTP ranges avoid repeated round trips; delegate callbacks still
    // deliver the first bytes immediately, without waiting for a whole chunk.
    private static let chunkSize = VideoRangeCache.chunkSize
    private static let cacheLimit = 4 * 1024 * 1024
    private static let maxConcurrentTransfers = 2
    static let httpErrorDomain = "MezonVideoRangeHTTP"

    private final class Transfer {
        let offset: Int64
        var end: Int64
        var data: Data
        var task: URLSessionDataTask?
        var responseEnd: Int64?
        var retriesLeft = 2
        var isPrefetch = false
        var priority = URLSessionTask.highPriority

        var nextOffset: Int64 { offset + Int64(data.count) }

        init(offset: Int64, end: Int64, data: Data) {
            self.offset = offset
            self.end = end
            self.data = data
        }
    }

    // URLSession retains its delegate. A weak owner lets closing the player
    // release this loader and cancel all transfers, even during a slow response.
    private final class SessionDelegate: VideoRangeTaskHandler {
        weak var owner: ChunkedVideoResourceLoader?

        func videoRangeTask(_ task: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let owner else { completionHandler(.cancel); return }
            owner.receive(response, for: task, completionHandler: completionHandler)
        }

        func videoRangeTask(_ task: URLSessionDataTask, didReceive data: Data) {
            owner?.receive(data, for: task)
        }

        func videoRangeTask(_ task: URLSessionTask, didCompleteWithError error: Error?) {
            owner?.complete(task, error: error)
        }
    }

    let queue = DispatchQueue(label: "mezon.video.chunked-loader", qos: .userInitiated)
    let assetURL: URL?
    private let remoteURL: URL
    private let cacheKey: String
    private let sessionDelegate = SessionDelegate()
    private var requests: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private var transfers: [Int64: Transfer] = [:]
    private var tasks: [Int: Transfer] = [:]
    private var contentLength: Int64?
    private var cache: [Int64: Data] = [:]
    private var cacheOrder: [Int64] = []
    private var cachedBytes = 0
    private var usesDiskCache = true
    private var failedPrefetchOffsets = Set<Int64>()
    private let receivedBytesLock = NSLock()
    private var receivedBytes: Int64 = 0

    var receivedByteCount: Int64 {
        receivedBytesLock.lock()
        defer { receivedBytesLock.unlock() }
        return receivedBytes
    }

    init(remoteURL: URL, cacheKey: String) {
        self.remoteURL = remoteURL
        self.cacheKey = cacheKey
        var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)
        components?.scheme = "mezon-stream"
        self.assetURL = components?.url
        super.init()
        sessionDelegate.owner = self
        queue.async { [self] in
            VideoRangeCache.shared.retain(cacheKey)
            contentLength = VideoRangeCache.shared.contentLength(for: cacheKey)
        }
    }

    deinit {
        transfers.values.forEach { $0.task?.cancel() }
        VideoRangeCache.shared.release(cacheKey)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if let data = loadingRequest.dataRequest {
            let (_, overflow) = data.requestedOffset.addingReportingOverflow(Int64(data.requestedLength))
            guard data.requestedOffset >= 0, data.requestedLength >= 0,
                  !overflow || data.requestsAllDataToEndOfResource else {
                loadingRequest.finishLoading(with: URLError(.badURL))
                return true
            }
        }
        requests[ObjectIdentifier(loadingRequest)] = loadingRequest
        processRequests()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        requests.removeValue(forKey: ObjectIdentifier(loadingRequest))
        processRequests()
    }

    private func chunkOffset(for offset: Int64) -> Int64 {
        offset / Int64(Self.chunkSize) * Int64(Self.chunkSize)
    }

    private func processRequests() {
        var needed = Set<Int64>()
        var readAhead = Set<Int64>()
        for (key, request) in Array(requests) {
            guard !request.isCancelled else { requests[key] = nil; continue }
            if let length = contentLength, let info = request.contentInformationRequest {
                info.contentType = remoteURL.pathExtension.lowercased() == "mov" ? "com.apple.quicktime-movie" : "public.mpeg-4"
                info.contentLength = length
                info.isByteRangeAccessSupported = true
            }
            guard let dataRequest = request.dataRequest else {
                if contentLength != nil {
                    requests[key] = nil
                    request.finishLoading()
                } else {
                    needed.insert(0)
                }
                continue
            }
            let requestedEnd = dataRequest.requestsAllDataToEndOfResource
                ? Int64.max : dataRequest.requestedOffset + Int64(dataRequest.requestedLength)
            let end = min(requestedEnd, contentLength ?? Int64.max)
            var offset = max(dataRequest.requestedOffset, dataRequest.currentOffset)
            while offset < end {
                let start = chunkOffset(for: offset)
                guard let bytes = transfers[start]?.data ?? cachedData(at: start),
                      offset - start < Int64(bytes.count) else { break }
                let lower = Int(offset - start)
                let count = Int(min(Int64(bytes.count - lower), end - offset))
                dataRequest.respond(with: bytes.subdata(in: lower..<lower + count))
                if cache[start] != nil { touchCache(start) }
                offset += Int64(count)
            }
            if offset >= end, contentLength != nil {
                requests[key] = nil
                request.finishLoading()
            } else {
                let start = chunkOffset(for: offset)
                needed.insert(start)
                if let length = contentLength,
                   start <= Int64.max - Int64(Self.chunkSize) {
                    let next = start + Int64(Self.chunkSize)
                    if next < min(end, length), !isChunkCached(at: next), !failedPrefetchOffsets.contains(next) {
                        readAhead.insert(next)
                    }
                }
            }
        }

        for transfer in Array(transfers.values) {
            // Finish the current HTTP range across gaps between small AVPlayer
            // reads. Keep unused responses at low priority until a required
            // read actually needs their slot; read-ahead alone cannot evict them.
            transfer.isPrefetch = !needed.contains(transfer.offset)
            transfer.priority = needed.contains(transfer.offset) ? URLSessionTask.highPriority
                : (readAhead.contains(transfer.offset) ? URLSessionTask.defaultPriority : URLSessionTask.lowPriority)
            transfer.task?.priority = transfer.priority
        }

        // Metadata and seeks take precedence over speculative read-ahead.
        for offset in needed.sorted() where transfers[offset] == nil {
            if transfers.count >= Self.maxConcurrentTransfers {
                // Never interrupt an active read or a fully received response.
                // Reclaim an unused range first, then speculative read-ahead.
                let candidate = transfers.values.filter {
                    !needed.contains($0.offset) && $0.nextOffset <= $0.end
                }.min { lhs, rhs in
                    let lhsIsReadAhead = readAhead.contains(lhs.offset)
                    let rhsIsReadAhead = readAhead.contains(rhs.offset)
                    if lhsIsReadAhead != rhsIsReadAhead { return !lhsIsReadAhead }
                    if lhs.data.count != rhs.data.count { return lhs.data.count < rhs.data.count }
                    return lhs.offset < rhs.offset
                }
                guard let candidate else { break }
                storeInCache(candidate.data, at: candidate.offset)
                removeTransfer(candidate)
            }
            guard transfers.count < Self.maxConcurrentTransfers else { break }
            addTransfer(at: offset, isPrefetch: false)
        }
        for offset in readAhead.subtracting(needed).sorted() where transfers[offset] == nil {
            guard transfers.count < Self.maxConcurrentTransfers else { break }
            addTransfer(at: offset, isPrefetch: true)
        }
    }

    private func isChunkCached(at offset: Int64) -> Bool {
        guard let length = contentLength, offset < length else { return false }
        let diskCount = usesDiskCache ? VideoRangeCache.shared.chunkLength(at: offset, for: cacheKey) : 0
        let count = max(transfers[offset]?.data.count ?? 0, max(cache[offset]?.count ?? 0, diskCount))
        return Int64(count) >= min(Int64(Self.chunkSize), length - offset)
    }

    private func addTransfer(at offset: Int64, isPrefetch: Bool) {
        let chunkEnd = offset + min(Int64(Self.chunkSize) - 1, Int64.max - offset)
        let end = min(chunkEnd, (contentLength ?? Int64.max) - 1)
        let data = cachedData(at: offset) ?? Data()
        guard offset + Int64(data.count) <= end else { return }
        let transfer = Transfer(offset: offset, end: end, data: data)
        transfer.isPrefetch = isPrefetch
        transfer.priority = isPrefetch ? URLSessionTask.defaultPriority : URLSessionTask.highPriority
        transfers[offset] = transfer
        start(transfer)
    }

    private func start(_ transfer: Transfer) {
        var request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("bytes=\(transfer.nextOffset)-\(transfer.end)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        transfer.responseEnd = nil
        let task = VideoRangeSession.shared.dataTask(with: request, handler: sessionDelegate, queue: queue)
        task.priority = transfer.priority
        transfer.task = task
        tasks[task.taskIdentifier] = transfer
        task.resume()
    }

    private func receive(_ response: URLResponse, for task: URLSessionDataTask, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let transfer = tasks[task.taskIdentifier] else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206,
              let header = http.value(forHTTPHeaderField: "Content-Range"),
              let range = VideoRangeCache.parseContentRange(header),
              range.start == transfer.nextOffset, range.end <= transfer.end,
              contentLength == nil || contentLength == range.total,
              response.expectedContentLength < 0 || response.expectedContentLength == range.end - range.start + 1 else {
            completionHandler(.cancel)
            if let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
               let total = VideoRangeCache.parseContentRange(header)?.total,
               let contentLength, total != contentLength {
                usesDiskCache = false
                VideoRangeCache.shared.remove(cacheKey)
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                fail(transfer, error: NSError(domain: Self.httpErrorDomain, code: http.statusCode))
            } else {
                fail(transfer, error: URLError(.badServerResponse))
            }
            return
        }
        contentLength = range.total
        transfer.end = min(transfer.end, range.total - 1)
        transfer.responseEnd = range.end
        completionHandler(.allow)
        processRequests()
    }

    private func receive(_ data: Data, for task: URLSessionDataTask) {
        guard let transfer = tasks[task.taskIdentifier], let responseEnd = transfer.responseEnd else { return }
        guard Int64(data.count) <= responseEnd - transfer.nextOffset + 1 else {
            fail(transfer, error: URLError(.badServerResponse))
            return
        }
        transfer.data.append(data)
        receivedBytesLock.lock()
        receivedBytes += Int64(data.count)
        receivedBytesLock.unlock()
        processRequests()
    }

    private func complete(_ task: URLSessionTask, error: Error?) {
        guard let transfer = tasks.removeValue(forKey: task.taskIdentifier) else { return }
        transfer.task = nil
        if transfer.nextOffset > transfer.end {
            storeInCache(transfer.data, at: transfer.offset)
            transfers[transfer.offset] = nil
            processRequests()
            return
        }
        let isTruncated = error == nil && transfer.nextOffset != transfer.responseEnd.map { $0 + 1 }
        if error != nil || isTruncated {
            let code = (error as? URLError)?.code
            let canRetry = isTruncated || code == .networkConnectionLost || code == .timedOut
            guard canRetry, transfer.retriesLeft > 0 else {
                fail(transfer, error: error ?? URLError(.networkConnectionLost))
                return
            }
            transfer.retriesLeft -= 1
        }
        // Resume after bytes already delivered, including on a transient failure.
        start(transfer)
    }

    private func fail(_ transfer: Transfer, error: Error) {
        if transfer.isPrefetch { failedPrefetchOffsets.insert(transfer.offset) }
        storeInCache(transfer.data, at: transfer.offset)
        removeTransfer(transfer)
        for (key, request) in Array(requests) {
            let offset = request.dataRequest.map { max($0.requestedOffset, $0.currentOffset) } ?? 0
            if chunkOffset(for: offset) == transfer.offset {
                requests[key] = nil
                if !request.isCancelled { request.finishLoading(with: error) }
            }
        }
        processRequests()
    }

    private func removeTransfer(_ transfer: Transfer) {
        if let task = transfer.task {
            tasks[task.taskIdentifier] = nil
            task.cancel()
        }
        transfers[transfer.offset] = nil
    }

    private func touchCache(_ offset: Int64) {
        cacheOrder.removeAll { $0 == offset }
        cacheOrder.append(offset)
    }

    private func storeInCache(_ data: Data, at offset: Int64) {
        persistToDisk(data, at: offset)
        guard !data.isEmpty, data.count > (cache[offset]?.count ?? 0) else { return }
        cachedBytes -= cache[offset]?.count ?? 0
        cache[offset] = data
        cachedBytes += data.count
        touchCache(offset)
        while cachedBytes > Self.cacheLimit, let oldest = cacheOrder.first(where: { $0 != 0 }) {
            cachedBytes -= cache.removeValue(forKey: oldest)?.count ?? 0
            cacheOrder.removeAll { $0 == oldest }
        }
    }

    private func cachedData(at offset: Int64) -> Data? {
        if let data = cache[offset] { return data }
        guard usesDiskCache, let data = VideoRangeCache.shared.data(at: offset, for: cacheKey) else { return nil }
        storeInCache(data, at: offset)
        return data
    }

    private func persistToDisk(_ data: Data, at offset: Int64) {
        guard usesDiskCache, let contentLength else { return }
        VideoRangeCache.shared.store(data, at: offset, contentLength: contentLength, for: cacheKey)
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
    private let bufferingProgressLabel = UILabel()
    private var isBuffering = false
    private var wantsPlayback = false {
        didSet { updatePrefetchPause() }
    }
    private var holdsPrefetchPause = false
    private var hasStartedPlayback = false
    private var readyWaitingSince: TimeInterval?
    private var bufferBaseline: (time: TimeInterval, seconds: Double)?
    private var lastImmediatePlaybackAttempt: TimeInterval?
    private var bufferingMonitor: Foundation.Timer?
    private var stallWatchdog: Foundation.Timer?
    private var playbackWatchdog: VideoPlaybackWatchdog?
    private var didReloadStalledPlaylist = false

    private var controlsHideTimer: Foundation.Timer?
    private var areControlsVisible = true

    private let seekDelta: Double = 15.0
    private static let endStallTolerance: Double = 1.0
    private static let endStallGrace: TimeInterval = 1.0
    private static let endStallTimeout: TimeInterval = 3.0
    private static let loadedToEndTolerance: Double = 0.5

    private var sourceURL: URL?
    private var attachedCacheFile: URL?
    private var chunkedLoader: ChunkedVideoResourceLoader?
    private var errorOverlayNode: ASDisplayNode?
    private var growingPlaylistURL: URL?
    private var playlistMonitor: Foundation.Timer?
    private var lastPlaylistReloadAt: TimeInterval?
    private var didReloadEndedPlaylist = false
    private var didApplyGrowingPlaylistStart = false
    private var growingListedDuration: Double = 0
    private var playlistEndedSeenAt: TimeInterval?
    private var starvingSince: TimeInterval?

    var setOverlayVisible: ((Bool) -> Void)?
    var onPlaybackFailed: ((Error?) -> Bool)?
    var setPagingEnabled: ((Bool) -> Void)?
    var startPosition: Double = 0
    var isPlaying: Bool { wantsPlayback }
    var localFileURL: URL? { sourceURL?.isFileURL == true ? sourceURL : nil }
    var hasRenderedVideo: Bool { playerLayer?.isReadyForDisplay == true }
    var playbackPosition: Double {
        if startPosition > 0 { return startPosition }
        return currentPosition
    }

    private var currentPosition: Double {
        let seconds = player?.currentTime().seconds ?? 0
        return seconds.isFinite ? max(0, seconds) : 0
    }

    var isCDNAccessDenied: Bool { failed(withCDNStatus: 403) }

    var isCDNFileMissing: Bool { failed(withCDNStatus: 404) }

    private func failed(withCDNStatus status: Int) -> Bool {
        let item = player?.currentItem
        if item?.errorLog()?.events.last?.errorStatusCode == status { return true }
        var error = item?.error as NSError?
        while let current = error {
            if current.domain == ChunkedVideoResourceLoader.httpErrorDomain, current.code == status { return true }
            error = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
    var controlsBottomInset: CGFloat = 0 {
        didSet {
            guard oldValue != controlsBottomInset else { return }
            setNeedsLayout()
        }
    }

    convenience init(url: URL, posterURL: String, cacheKey: String? = nil, usesChunkedLoading: Bool = false) {
        let loader = usesChunkedLoading ? ChunkedVideoResourceLoader(remoteURL: url, cacheKey: cacheKey ?? url.absoluteString) : nil
        let asset = AVURLAsset(url: loader?.assetURL ?? url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        if let loader {
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        }
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        self.init(playerItem: item, posterURL: posterURL)
        self.chunkedLoader = loader
        self.sourceURL = url
        if url.isFileURL, VLCVideoPlayerNode.retainCachedFile(url) { attachedCacheFile = url }
    }

    convenience init(growingPlaylistURL: URL, posterURL: String) {
        let item = AVPlayerItem(asset: AVURLAsset(url: growingPlaylistURL), automaticallyLoadedAssetKeys: ["playable"])
        self.init(playerItem: item, posterURL: posterURL)
        self.sourceURL = growingPlaylistURL
        self.growingPlaylistURL = growingPlaylistURL
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


        setupPlayer(playerItem: playerItem)


        posterNode.setSignal(videoThumbnailSignal(url: posterURL, resizeMode: .fit, allowRemoteGeneration: false))
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(playerTapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        self.view.addGestureRecognizer(tap)

        scrubberBarNode.view.addSubview(timeSlider)
        bufferingSpinner.accessibilityIdentifier = AccessibilityID.Video.loading
        bufferingSpinner.accessibilityLabel = "Loading video"
        bufferingSpinner.isAccessibilityElement = true
        bufferingProgressLabel.accessibilityIdentifier = AccessibilityID.Video.progress
        bufferingSpinner.color = .white
        bufferingSpinner.hidesWhenStopped = true
        view.addSubview(bufferingSpinner)
        bufferingProgressLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        bufferingProgressLabel.textColor = .white
        bufferingProgressLabel.textAlignment = .center
        bufferingProgressLabel.layer.shadowColor = UIColor.black.cgColor
        bufferingProgressLabel.layer.shadowOpacity = 0.6
        bufferingProgressLabel.layer.shadowRadius = 2
        bufferingProgressLabel.layer.shadowOffset = .zero
        bufferingProgressLabel.isHidden = true
        view.addSubview(bufferingProgressLabel)
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
                DispatchQueue.main.async {
                    self?.posterNode.isHidden = true
                    self?.refreshBufferingIndicator()
                    self?.startPlaybackIfBuffered()
                }
            }
        }


        timeControlObserver = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if player.timeControlStatus == .playing { self.hasStartedPlayback = true }
                self.refreshBufferingIndicator()
                self.startPlaybackIfBuffered()
            }
        }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateTime(time)
        }

        observe(playerItem)
    }

    private func observe(_ playerItem: AVPlayerItem) {
        loadedRangesObserver = playerItem.observe(\.loadedTimeRanges, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateBufferingProgress()
                self?.updatePrefetchPause()
                self?.startPlaybackIfBuffered()
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinishPlaying(_:)), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(playerItemFailedToPlayToEnd(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)


        statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    let duration = item.duration.seconds
                    if duration.isFinite {
                        self.timeSlider.maximumValue = Float(duration)
                        self.durationLabel.attributedText = NSAttributedString(
                            string: self.formatTime(duration),
                            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
                        )
                        self.setNeedsLayout()
                    }
                    self.applyStartPosition(to: item)
                    self.growingPlaylistBecameReady()
                    self.startPlaybackIfBuffered()
                case .failed:
                    self.showErrorOverlay(error: item.error)
                default:
                    break
                }
            }
        }
    }

    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        if let attachedCacheFile { VLCVideoPlayerNode.releaseCachedFile(attachedCacheFile) }
        controlsHideTimer?.invalidate()
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
        readyForDisplayObserver?.invalidate()
        loadedRangesObserver?.invalidate()
        bufferingMonitor?.invalidate()
        stallWatchdog?.invalidate()
        playlistMonitor?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if holdsPrefetchPause {
            VideoRangePrefetcher.shared.resume()
        }
    }
    
    private func showErrorOverlay(error: Error?) {
        guard errorOverlayNode == nil else { return }

        if onPlaybackFailed?(error) == true { return }
        if isScrubbing { setPagingEnabled?(true) }
        isScrubbing = false
        pause()
        
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
        let unsupportedMessage = "This video format may not be supported"
        let errorMessage = error?.userMessage(fallback: unsupportedMessage) ?? unsupportedMessage
        messageNode.attributedText = NSAttributedString(
            string: errorMessage,
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
        UIApplication.shared.open(url)
    }

    public func play() {
        guard errorOverlayNode == nil else { return }
        wantsPlayback = true
        AppAudioSession.activateForMediaPlayback(options: [])
        player?.play()
        startPlaybackIfBuffered()
        startStallWatchdog()
        refreshBufferingIndicator()
        updatePlayPauseIcons(isPlaying: true)
        resetControlsTimer()
    }

    public func pause() {
        wantsPlayback = false
        stopBufferingMonitor()
        stopStallWatchdog()
        player?.pause()
        refreshBufferingIndicator()
        updatePlayPauseIcons(isPlaying: false)
        controlsHideTimer?.invalidate()
        showControls()
    }


    @objc private func playPauseTapped() {
        guard let p = player else { return }
        if !wantsPlayback {
            if let duration = p.currentItem?.duration.seconds, duration.isFinite,
               duration - p.currentTime().seconds <= Self.endStallTolerance {
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
        let itemDuration = p.currentItem?.duration.seconds ?? currentTime
        let duration = itemDuration.isFinite ? itemDuration : Double(timeSlider.maximumValue)
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

    private func finishStalledEnd() {
        player?.pause()
        finishPlayback()
    }

    @objc private func playerDidFinishPlaying(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player?.currentItem === item else { return }
            self.finishPlayback()
        }
    }

    private func finishPlayback() {
        guard wantsPlayback else { return }
        guard playerLayer?.isReadyForDisplay == true else {
            showErrorOverlay(error: AVError(.decodeFailed))
            return
        }
        hasStartedPlayback = false
        pause()
    }

    @objc private func sliderDidBeginScrubbing() {
        scrubGeneration += 1
        isScrubbing = true
        stopBufferingMonitor()
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
                self.startPlaybackIfBuffered()
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
        updateGrowingDuration()
        timeSlider.value = Float(seconds)

        let label = formatTime(seconds)
        guard currentTimeLabel.attributedText?.string != label else { return }
        currentTimeLabel.attributedText = NSAttributedString(
            string: label,
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )
        setNeedsLayout()
    }

    private func startPlaybackIfBuffered() {
        guard wantsPlayback, !isScrubbing,
              let player,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
              let reason = player.reasonForWaitingToPlay,
              reason == .toMinimizeStalls || reason == .evaluatingBufferingRate,
              let item = player.currentItem,
              item.status == .readyToPlay else {
            stopBufferingMonitor()
            return
        }
        let clock = ProcessInfo.processInfo.systemUptime
        if readyWaitingSince == nil { readyWaitingSince = clock }
        if bufferingMonitor == nil {
            // AVPlayer's periodic time observer may stop while the media clock
            // is waiting. A wall-clock timer also handles unchanged buffer KVO.
            bufferingMonitor = Foundation.Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.startPlaybackIfBuffered()
            }
        }
        let position = item.currentTime().seconds
        let ranges = item.loadedTimeRanges.map(\.timeRangeValue)
        let bufferedAhead = VideoPlaybackBufferPolicy.bufferedAhead(at: position, ranges: ranges)
        if bufferBaseline == nil { bufferBaseline = (clock, bufferedAhead) }
        let sampleDuration = clock - (bufferBaseline?.time ?? clock)
        let growthRate = sampleDuration >= 2 ? max(0, bufferedAhead - (bufferBaseline?.seconds ?? bufferedAhead)) / sampleDuration : nil
        let duration = item.duration.seconds
        let remaining = duration.isFinite && position.isFinite ? duration - position : nil
        let waitingDuration = clock - (readyWaitingSince ?? clock)
        if hasStartedPlayback, position > 0, let remaining, remaining <= Self.endStallTolerance,
           waitingDuration >= (bufferedAhead >= remaining - 0.05 ? Self.endStallGrace : Self.endStallTimeout) {
            finishStalledEnd()
            return
        }
        guard VideoPlaybackBufferPolicy.shouldStart(bufferedAhead: bufferedAhead, remaining: remaining, hasStarted: hasStartedPlayback, waitingDuration: waitingDuration, bufferGrowthRate: growthRate),
              lastImmediatePlaybackAttempt.map({ clock - $0 >= 1 }) ?? true else { return }
        lastImmediatePlaybackAttempt = clock
        player.playImmediately(atRate: 1)
    }

    private func growingPlaylistBecameReady() {
        guard growingPlaylistURL != nil, let player else { return }
        if !didApplyGrowingPlaylistStart {
            didApplyGrowingPlaylistStart = true
            if player.currentTime().seconds > 0.5 {
                player.seek(to: .zero)
            }
        }
        updateGrowingDuration()
        guard playlistMonitor == nil else { return }
        playlistMonitor = Foundation.Timer.scheduledTimer(
            withTimeInterval: FileIngestPlaylist.probeInterval,
            repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.checkGrowingPlaylist()
        }
        checkGrowingPlaylist()
    }

    private func checkGrowingPlaylist() {
        guard let playlist = growingPlaylistURL, let item = player?.currentItem else { return }
        if item.duration.seconds.isFinite {
            playlistMonitor?.invalidate()
            playlistMonitor = nil
            return
        }
        FileIngestPlaylist.fetchSnapshot(playlist: playlist) { [weak self] snapshot in
            guard let snapshot else { return }
            DispatchQueue.main.async {
                self?.applyPlaylistSnapshot(snapshot)
            }
        }
    }

    private func applyPlaylistSnapshot(_ snapshot: FileIngestPlaylist.Snapshot) {
        guard let player, let item = player.currentItem else { return }
        growingListedDuration = max(growingListedDuration, snapshot.listedDuration)
        updateGrowingDuration()
        guard item.status == .readyToPlay,
              !isScrubbing,
              !item.duration.seconds.isFinite else { return }
        let clock = ProcessInfo.processInfo.systemUptime
        let position = item.currentTime().seconds
        let bufferedEnd = position + VideoPlaybackBufferPolicy.bufferedAhead(at: position, ranges: item.loadedTimeRanges.map(\.timeRangeValue))
        let targetDuration = max(snapshot.targetDuration, 4)
        if snapshot.ended, playlistEndedSeenAt == nil {
            playlistEndedSeenAt = clock
        }
        let endedUnseen = snapshot.ended
            && !didReloadEndedPlaylist
            && clock - (playlistEndedSeenAt ?? clock) >= targetDuration * 1.5
        let starving = wantsPlayback
            && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            && bufferedEnd - position < 1
            && snapshot.listedDuration - bufferedEnd > targetDuration
        if starving {
            if starvingSince == nil { starvingSince = clock }
        } else {
            starvingSince = nil
        }
        let stuck = starvingSince.map { clock - $0 >= targetDuration * 2 } ?? false
        guard endedUnseen || (stuck && !didReloadStalledPlaylist),
              lastPlaylistReloadAt.map({ clock - $0 >= 10 }) ?? true else { return }
        lastPlaylistReloadAt = clock
        starvingSince = nil
        if snapshot.ended { didReloadEndedPlaylist = true }
        if stuck { didReloadStalledPlaylist = true }
        reloadPlayerItem(snapshot.url)
    }

    private func reloadPlayerItem(_ url: URL) {
        guard let player, let oldItem = player.currentItem else { return }
        let position = oldItem.currentTime()
        let item = AVPlayerItem(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: ["playable"])
        if #available(iOS 14.5, *) {
            item.startsOnFirstEligibleVariant = true
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: oldItem)
        observe(item)
        player.replaceCurrentItem(with: item)
        if position.isNumeric {
            player.seek(to: position)
        }
        if wantsPlayback {
            player.play()
        }
    }

    private func updateGrowingDuration() {
        guard growingPlaylistURL != nil, let item = player?.currentItem else { return }
        let seekableEnd = item.seekableTimeRanges.last.map { $0.timeRangeValue.end.seconds } ?? 0
        let duration = item.duration.seconds.isFinite
            ? item.duration.seconds
            : max(growingListedDuration, seekableEnd)
        guard duration.isFinite, duration > 0, Float(duration) != timeSlider.maximumValue else { return }
        timeSlider.maximumValue = Float(duration)
        durationLabel.attributedText = NSAttributedString(
            string: formatTime(duration),
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.white]
        )
        setNeedsLayout()
    }

    private func stopBufferingMonitor() {
        bufferingMonitor?.invalidate()
        bufferingMonitor = nil
        readyWaitingSince = nil
        bufferBaseline = nil
        lastImmediatePlaybackAttempt = nil
    }

    private func startStallWatchdog() {
        guard stallWatchdog == nil else { return }
        playbackWatchdog = VideoPlaybackWatchdog(position: currentPosition)
        stallWatchdog = Foundation.Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkForStall()
        }
    }

    private func stopStallWatchdog() {
        stallWatchdog?.invalidate()
        stallWatchdog = nil
        playbackWatchdog = nil
    }

    private func checkForStall() {
        guard wantsPlayback, let player, let item = player.currentItem else {
            stopStallWatchdog()
            return
        }
        let position = currentPosition
        guard !isScrubbing, UIApplication.shared.applicationState == .active else {
            playbackWatchdog = VideoPlaybackWatchdog(position: position)
            return
        }

        let bufferedEnd = position + VideoPlaybackBufferPolicy.bufferedAhead(at: position, ranges: item.loadedTimeRanges.map(\.timeRangeValue))
        let receivedBytes = chunkedLoader?.receivedByteCount ?? item.accessLog()?.events.last?.numberOfBytesTransferred ?? 0
        guard playbackWatchdog?.hasStalled(
            position: position,
            hasVideo: hasRenderedVideo,
            bufferedEnd: bufferedEnd,
            receivedBytes: receivedBytes,
            idleTimeout: growingPlaylistURL == nil ? 10 : 15,
            playbackTimeout: growingPlaylistURL == nil ? 25 : 35
        ) == true else { return }

        if let playlist = growingPlaylistURL, hasRenderedVideo, !didReloadStalledPlaylist {
            didReloadStalledPlaylist = true
            playbackWatchdog = VideoPlaybackWatchdog(position: position)
            reloadPlayerItem(playlist)
        } else {
            showErrorOverlay(error: URLError(.timedOut))
        }
    }

    private func applyStartPosition(to item: AVPlayerItem) {
        guard startPosition > 0, let player else { return }
        let duration = item.duration.seconds
        let seconds = duration.isFinite ? min(startPosition, max(0, duration - 0.1)) : startPosition
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.player?.currentItem === item else { return }
                self.startPosition = 0
            }
        }
    }

    @objc private func playerItemFailedToPlayToEnd(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player?.currentItem === item else { return }
            self.showErrorOverlay(error: error)
        }
    }

    private func refreshBufferingIndicator() {
        isBuffering = wantsPlayback && (player?.timeControlStatus != .playing || !hasRenderedVideo)
        if isNodeLoaded { updateBufferingIndicator() }
    }

    private func updateBufferingIndicator() {
        centerPlayPauseButton.isHidden = isBuffering
        if isBuffering {
            bufferingSpinner.startAnimating()
        } else {
            bufferingSpinner.stopAnimating()
        }
        updateBufferingProgress()
    }

    private func updateBufferingProgress() {
        guard isNodeLoaded else { return }
        guard isBuffering, let progress = loadedProgress(), progress.end < progress.duration else {
            bufferingProgressLabel.isHidden = true
            return
        }
        bufferingProgressLabel.text = "\(Int(progress.end / progress.duration * 100))%"
        bufferingProgressLabel.isHidden = false
        layoutBufferingProgressLabel()
    }

    private func layoutBufferingProgressLabel() {
        bufferingProgressLabel.sizeToFit()
        bufferingProgressLabel.center = CGPoint(
            x: bufferingSpinner.center.x,
            y: bufferingSpinner.frame.maxY + 8 + bufferingProgressLabel.bounds.height / 2
        )
    }

    private func loadedProgress() -> (end: Double, duration: Double)? {
        guard let item = player?.currentItem else { return nil }
        let duration = item.duration.seconds
        let position = item.currentTime().seconds
        guard duration.isFinite, duration > 0, position.isFinite else { return nil }
        let ranges = item.loadedTimeRanges.map(\.timeRangeValue)
        return (position + VideoPlaybackBufferPolicy.bufferedAhead(at: position, ranges: ranges), duration)
    }

    private func updatePrefetchPause() {
        let isLoadedToEnd = loadedProgress().map { $0.end >= $0.duration - Self.loadedToEndTolerance } ?? false
        let shouldPause = wantsPlayback && !isLoadedToEnd
        guard shouldPause != holdsPrefetchPause else { return }
        holdsPrefetchPause = shouldPause
        if shouldPause {
            VideoRangePrefetcher.shared.pause()
        } else {
            VideoRangePrefetcher.shared.resume()
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
        bufferingSpinner.center = CGPoint(x: b.midX, y: b.midY)
        layoutBufferingProgressLabel()
        
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
