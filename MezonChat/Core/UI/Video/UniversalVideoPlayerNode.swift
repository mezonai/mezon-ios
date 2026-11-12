import Foundation
import UIKit
import AsyncDisplayKit

extension ASImageNode {
    func installSafeWhiteTint() {
        let tintBlock = ASImageNodeTintColorModificationBlock(.white)
        imageModificationBlock = { image, traitCollection in
            let size = image.size
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0, image.scale > 0 else { return nil }
            return tintBlock(image, traitCollection)
        }
    }
}

enum VideoRangeLoadingPolicy {
    static func shouldProbe(_ url: URL) -> Bool {
        !url.isFileURL && ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }
}

struct VideoPlaybackWatchdog {
    private var lastPlaybackProgress: TimeInterval
    private var lastLoadingProgress: TimeInterval
    private var position: Double
    private var bufferedEnd: Double = 0
    private var receivedBytes: Int64 = 0

    init(position: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.position = position
        lastPlaybackProgress = now
        lastLoadingProgress = now
    }

    mutating func hasStalled(
        position: Double,
        hasVideo: Bool,
        bufferedEnd: Double = 0,
        receivedBytes: Int64 = 0,
        idleTimeout: TimeInterval = 10,
        playbackTimeout: TimeInterval = 25,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        if hasVideo, abs(position - self.position) >= 0.1 {
            self = VideoPlaybackWatchdog(position: position, now: now)
        }
        if bufferedEnd > self.bufferedEnd + 0.1 || receivedBytes > self.receivedBytes {
            self.bufferedEnd = max(bufferedEnd, self.bufferedEnd)
            self.receivedBytes = max(receivedBytes, self.receivedBytes)
            lastLoadingProgress = now
        }
        return now - lastLoadingProgress >= idleTimeout || now - lastPlaybackProgress >= playbackTimeout
    }
}

final class UniversalVideoPlayerNode: ASDisplayNode {
    private enum AVSource: String {
        case ingest
        case chunked
        case direct
        case local
    }

    private var avPlayerNode: MezonVideoPlayerNode?
    private var vlcPlayerNode: VLCVideoPlayerNode?
    private let url: URL
    private let posterURL: String
    private var wantsPlay = false
    private var isResolvingIngest = false
    private var didRefreshSignature = false
    private var didDownloadFile = false
    private var didTryFinishedHLS = false
    private var isOriginalMissing = false
    private let prefersVLC: Bool
    private var resumePosition: Double = 0

    var setOverlayVisible: ((Bool) -> Void)?
    var setPagingEnabled: ((Bool) -> Void)?
    var isPlaying: Bool { avPlayerNode?.isPlaying ?? vlcPlayerNode?.isPlaying ?? wantsPlay }
    var controlsBottomInset: CGFloat = 0 {
        didSet {
            avPlayerNode?.controlsBottomInset = controlsBottomInset
            vlcPlayerNode?.controlsBottomInset = controlsBottomInset
        }
    }

    init(url: URL, posterURL: String) {
        self.url = url
        self.posterURL = posterURL
        self.prefersVLC = ["webm", "ogv", "ogg", "mkv", "avi", "flv", "wmv", "3gp", "3g2", "mpg", "mpeg", "ts", "vob"]
            .contains(url.pathExtension.lowercased())
        super.init()

        VideoRangePrefetcher.shared.cancel(url)
        if !prefersVLC, let localFile = VLCVideoPlayerNode.cachedFile(for: url) {
            attachLocalAVPlayer(localFile)
        } else if FileIngestPlaylist.isMarked(url.absoluteString) {
            resolveIngestPlaylist()
        } else {
            setupOriginalPlayer()
        }
    }

    private func resolveIngestPlaylist() {
        if case let .playable(playlist) = FileIngestPlaylist.state(for: url.absoluteString) {
            attachIngestPlayer(playlist)
            return
        }
        isResolvingIngest = true
        FileIngestPlaylist.resolve(attachmentURL: url.absoluteString) { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.isResolvingIngest else { return }
                self.isResolvingIngest = false
                if case let .playable(playlist) = state {
                    self.attachIngestPlayer(playlist)
                } else {
                    self.setupOriginalPlayer()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isResolvingIngest else { return }
            self.isResolvingIngest = false
            self.setupOriginalPlayer()
        }
    }

    private func attachIngestPlayer(_ playlist: URL) {
        didTryFinishedHLS = true
        let node = MezonVideoPlayerNode(growingPlaylistURL: playlist, posterURL: posterURL)
        attachAVPlayer(node, source: .ingest)
    }

    private func playFinishedHLS() {
        didTryFinishedHLS = true
        FileIngestPlaylist.resolve(attachmentURL: url.absoluteString) { [weak self] state in
            DispatchQueue.main.async {
                guard let self, self.avPlayerNode == nil, self.vlcPlayerNode == nil else { return }
                if case let .playable(playlist) = state {
                    self.attachIngestPlayer(playlist)
                } else {
                    self.attachVLCPlayer(downloadsFirst: true)
                }
            }
        }
    }

    private func setupOriginalPlayer() {
        guard !prefersVLC else {
            attachVLCPlayer()
            return
        }
        if url.isFileURL {
            attachLocalAVPlayer(url)
            return
        }
        // Use prefetched bytes when available. Cold playback can open the URL
        // immediately and let AVFoundation handle HTTP range requests.
        let cacheKey = url.absoluteString
        let attach: (CDNRequestURL) -> Void = { [weak self] request in
            DispatchQueue.global(qos: .userInitiated).async {
                let hasPrefetchedRanges = VideoRangeLoadingPolicy.shouldProbe(request.url)
                    && VideoRangeCache.shared.cachedContentLength(for: cacheKey) != nil
                DispatchQueue.main.async {
                    self?.attachRemoteAVPlayer(request, source: hasPrefetchedRanges ? .chunked : .direct)
                }
            }
        }
        if let request = CDNSigner.shared.readyRequestURL(for: url) {
            attach(request)
        } else {
            CDNSigner.shared.requestURL(for: url, completion: attach)
        }
    }

    private func attachRemoteAVPlayer(_ request: CDNRequestURL, source: AVSource) {
        let node = MezonVideoPlayerNode(
            url: request.url,
            posterURL: posterURL,
            cacheKey: url.absoluteString,
            usesChunkedLoading: source == .chunked
        )
        attachAVPlayer(node, source: source, request: request)
    }

    private func attachLocalAVPlayer(_ fileURL: URL) {
        let node = MezonVideoPlayerNode(url: fileURL, posterURL: posterURL)
        attachAVPlayer(node, source: .local)
    }

    private func attachAVPlayer(_ node: MezonVideoPlayerNode, source: AVSource, request: CDNRequestURL? = nil) {
        node.backgroundColor = .black
        node.startPosition = resumePosition
        node.setOverlayVisible = { [weak self] visible in self?.setOverlayVisible?(visible) }
        node.setPagingEnabled = { [weak self] enabled in self?.setPagingEnabled?(enabled) }
        node.onPlaybackFailed = { [weak self, weak node] error in
            guard let self, let node, self.avPlayerNode === node else { return false }
            self.recoverFromAVFailure(node, source: source, request: request, error: error)
            return true
        }
        node.controlsBottomInset = controlsBottomInset
        avPlayerNode = node
        addSubnode(node)
        node.frame = bounds
        if wantsPlay { node.play() }
    }

    private func recoverFromAVFailure(_ node: MezonVideoPlayerNode, source: AVSource, request: CDNRequestURL?, error: Error?) {
        wantsPlay = node.isPlaying
        if node.hasRenderedVideo { resumePosition = node.playbackPosition }
        var extras: [String: Any] = [
            "source": source.rawValue,
            "extension": url.pathExtension.lowercased(),
            "position": resumePosition
        ]
        if let error = error as NSError? {
            extras["error"] = "\(error.domain) \(error.code)"
        }
        SentryLogger.capture(message: "video.playback_fallback", extras: extras)

        let accessDenied = node.isCDNAccessDenied
        let originalMissing = (source == .chunked || source == .direct) && (accessDenied || node.isCDNFileMissing)
        avPlayerNode = nil
        node.pause()
        node.removeFromSupernode()
        setPagingEnabled?(true)

        if source == .ingest {
            if isOriginalMissing {
                attachVLCPlayer(downloadsFirst: true)
            } else {
                setupOriginalPlayer()
            }
        } else if let request, accessDenied, !didRefreshSignature, CDNSigner.shared.invalidate(request) {
            didRefreshSignature = true
            CDNSigner.shared.freshRequestURL(after: request, for: url) { [weak self] freshRequest in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let freshRequest {
                        self.attachRemoteAVPlayer(freshRequest, source: source)
                    } else {
                        self.attachVLCPlayer()
                    }
                }
            }
        } else if originalMissing, !didTryFinishedHLS {
            isOriginalMissing = true
            playFinishedHLS()
        } else if source == .chunked, let request, !accessDenied, !originalMissing {
            attachRemoteAVPlayer(request, source: .direct)
        } else {
            attachVLCPlayer(localFile: node.localFileURL, downloadsFirst: originalMissing)
        }
    }

    private func attachVLCPlayer(localFile: URL? = nil, downloadsFirst: Bool = false) {
        let node = VLCVideoPlayerNode(
            url: url,
            posterURL: posterURL,
            localFile: localFile,
            retryCachedFile: !didDownloadFile,
            downloadsFirst: downloadsFirst)
        node.startPosition = resumePosition
        node.setOverlayVisible = { [weak self] visible in self?.setOverlayVisible?(visible) }
        node.setPagingEnabled = { [weak self] enabled in self?.setPagingEnabled?(enabled) }
        node.onDownloadedFile = { [weak self, weak node] fileURL in
            guard let self, let node, self.vlcPlayerNode === node,
                  !self.prefersVLC, !self.didDownloadFile else { return false }
            self.didDownloadFile = true
            self.wantsPlay = node.isPlaying
            self.resumePosition = node.playbackPosition
            self.vlcPlayerNode = nil
            node.pause()
            node.removeFromSupernode()
            self.attachLocalAVPlayer(fileURL)
            return true
        }
        node.controlsBottomInset = controlsBottomInset
        vlcPlayerNode = node
        addSubnode(node)
        node.frame = bounds
        if wantsPlay { node.play() }
    }

    func play() {
        wantsPlay = true
        avPlayerNode?.play()
        vlcPlayerNode?.play()
    }

    func pause() {
        wantsPlay = false
        avPlayerNode?.pause()
        vlcPlayerNode?.pause()
    }

    override func layout() {
        super.layout()
        avPlayerNode?.frame = bounds
        vlcPlayerNode?.frame = bounds
    }
}
