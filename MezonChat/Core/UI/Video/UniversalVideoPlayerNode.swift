import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation

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

// FOR TEST ONLY: remove before release
enum VideoLoadDebug {
    private static var startedAt = CFAbsoluteTimeGetCurrent()

    static func begin(_ message: String) {
        startedAt = CFAbsoluteTimeGetCurrent()
        log("=== \(message)")
    }

    static func log(_ message: String) {
        print("[VideoLoad] +\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startedAt))s \(message)")
    }

    static func boxes(_ data: Data) -> String {
        var result: [String] = []
        var offset = 0
        while offset + 8 <= data.count, result.count < 6 {
            let size = data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
            result.append("\(type)@\(offset)+\(size)")
            guard size >= 8 else { break }
            offset += size
        }
        return result.joined(separator: " ")
    }
}

private enum VideoRangeLoadingPolicy {
    static func shouldProbe(_ url: URL) -> Bool {
        !url.isFileURL && ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
    }

    static func supportsChunkedLoading(data: Data?, response: URLResponse?) -> Bool {
        guard let data, !data.isEmpty,
              let response = response as? HTTPURLResponse, response.statusCode == 206,
              let header = response.value(forHTTPHeaderField: "Content-Range") else { return false }
        let fields = header.split(separator: " ")
        guard fields.count == 2, fields[0].lowercased() == "bytes" else { return false }
        let sizes = fields[1].split(separator: "/")
        guard sizes.count == 2, let total = Int64(sizes[1]), total >= Int64(data.count) else { return false }
        let bounds = sizes[0].split(separator: "-", omittingEmptySubsequences: false)
        return bounds.count == 2 && Int64(bounds[0]) == 0 && Int64(bounds[1]) == Int64(data.count) - 1
    }
}

final class UniversalVideoPlayerNode: ASDisplayNode {
    
    private var avPlayerNode: MezonVideoPlayerNode?
    private var vlcPlayerNode: VLCVideoPlayerNode?
    private let url: URL
    private let posterURL: String
    private var didTryAVPlayer = false
    private var didTryVLCPlayer = false
    private var avRequest: CDNRequestURL?
    private var didResignAVPlayer = false
    private var wantsPlay = false
    private var usesChunkedLoading = false
    private var containerProbeTask: URLSessionDataTask?
    private var isContainerProbePending = false
    private var containerProbePrefix: (data: Data, response: HTTPURLResponse)?
    
    var setOverlayVisible: ((Bool) -> Void)?
    var setPagingEnabled: ((Bool) -> Void)?
    var isPlaying: Bool { avPlayerNode?.isPlaying == true || vlcPlayerNode?.isPlaying == true }
    var controlsBottomInset: CGFloat = 0 {
        didSet {
            avPlayerNode?.controlsBottomInset = controlsBottomInset
            vlcPlayerNode?.controlsBottomInset = controlsBottomInset
        }
    }
    
    init(url: URL, posterURL: String) {
        self.url = url
        self.posterURL = posterURL
        super.init()
        VideoLoadDebug.begin("open \(url.lastPathComponent)") // FOR TEST ONLY: remove before release
        
        setupAppropriatePlayer()
    }
    
    private func setupAppropriatePlayer() {
        let fileExtension = url.pathExtension.lowercased()
        let useVLC = shouldUseVLCPlayer(for: fileExtension)

        if useVLC {
            setupVLCPlayer()
        } else {
            setupAVPlayer()
        }
    }
    
    private func setupAVPlayer() {
        guard !didTryAVPlayer else { return }
        didTryAVPlayer = true

        if let request = CDNSigner.shared.readyRequestURL(for: url) {
            VideoLoadDebug.log("signature ready signed=\(request.isSigned)") // FOR TEST ONLY: remove before release
            attachPlayerMatchingContainer(request)
            return
        }
        CDNSigner.shared.requestURL(for: url) { [weak self] request in
            DispatchQueue.main.async {
                VideoLoadDebug.log("signature fetched signed=\(request.isSigned)") // FOR TEST ONLY: remove before release
                self?.attachPlayerMatchingContainer(request)
            }
        }
    }

    private func attachPlayerMatchingContainer(_ request: CDNRequestURL) {
        guard VideoRangeLoadingPolicy.shouldProbe(request.url) else {
            attachAVPlayer(request)
            return
        }
        var probe = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        probe.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
        isContainerProbePending = true
        containerProbeTask = URLSession.shared.dataTask(with: probe) { [weak self] data, response, error in
            let supportsChunks = error == nil && VideoRangeLoadingPolicy.supportsChunkedLoading(data: data, response: response)
            let debugHTTP = response as? HTTPURLResponse // FOR TEST ONLY: remove before release
            VideoLoadDebug.log("probe status=\(debugHTTP?.statusCode ?? -1) cache=\(debugHTTP?.value(forHTTPHeaderField: "X-Cache-Status") ?? "nil") range=\(debugHTTP?.value(forHTTPHeaderField: "Content-Range") ?? "nil") chunked=\(supportsChunks) boxes=[\(data.map(VideoLoadDebug.boxes) ?? "nil")] error=\(String(describing: error))") // FOR TEST ONLY: remove before release
            DispatchQueue.main.async {
                guard let self else { return }
                let prefix = data.flatMap { data in (response as? HTTPURLResponse).map { (data, $0) } }
                self.finishContainerProbe(request, supportsChunks: supportsChunks, prefix: prefix)
            }
        }
        containerProbeTask?.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finishContainerProbe(request, supportsChunks: false)
        }
    }

    private func finishContainerProbe(_ request: CDNRequestURL, supportsChunks: Bool, prefix: (data: Data, response: HTTPURLResponse)? = nil) {
        guard isContainerProbePending else { return }
        isContainerProbePending = false
        containerProbeTask?.cancel()
        containerProbeTask = nil
        usesChunkedLoading = supportsChunks
        containerProbePrefix = supportsChunks ? prefix : nil
        attachAVPlayer(request)
    }

    private func attachAVPlayer(_ request: CDNRequestURL) {
        guard avPlayerNode == nil, vlcPlayerNode == nil else { return }
        avRequest = request
        VideoLoadDebug.log("attach AVPlayer chunked=\(usesChunkedLoading) host=\(request.url.host ?? "unknown")") // FOR TEST ONLY: remove before release
        let avNode = MezonVideoPlayerNode(url: request.url, posterURL: posterURL, usesChunkedLoading: usesChunkedLoading, initialData: containerProbePrefix?.data, initialResponse: containerProbePrefix?.response)
        containerProbePrefix = nil
        avNode.setOverlayVisible = { [weak self] visible in
            self?.setOverlayVisible?(visible)
        }
        avNode.setPagingEnabled = { [weak self] enabled in
            self?.setPagingEnabled?(enabled)
        }
        avNode.onPlaybackFailed = { [weak self] in
            self?.retryAVPlayerWithFreshSignatureOrFallback()
        }
        avNode.controlsBottomInset = controlsBottomInset
        avPlayerNode = avNode
        addSubnode(avNode)
        avNode.frame = bounds
        if wantsPlay {
            avNode.play()
        }
    }

    private func retryAVPlayerWithFreshSignatureOrFallback() {
        VideoLoadDebug.log("AVPlayer failed, retry or fallback") // FOR TEST ONLY: remove before release
        guard !didResignAVPlayer,
              let request = avRequest,
              CDNSigner.shared.invalidate(request) else {
            fallbackToNativePlayerOrVLC()
            return
        }
        didResignAVPlayer = true
        avPlayerNode?.removeFromSupernode()
        avPlayerNode = nil
        CDNSigner.shared.freshRequestURL(after: request, for: url) { [weak self] next in
            DispatchQueue.main.async {
                guard let self else { return }
                if let next {
                    self.attachAVPlayer(next)
                } else {
                    self.fallbackToNativePlayerOrVLC()
                }
            }
        }
    }

    private func fallbackToNativePlayerOrVLC() {
        guard usesChunkedLoading, let request = avRequest else {
            fallbackToVLC()
            return
        }
        VideoLoadDebug.log("range loading failed, retrying native AVPlayer") // FOR TEST ONLY: remove before release
        usesChunkedLoading = false
        avPlayerNode?.pause()
        avPlayerNode?.removeFromSupernode()
        avPlayerNode = nil
        attachAVPlayer(request)
    }
    
    private func setupVLCPlayer() {
        guard !didTryVLCPlayer else { return }
        didTryVLCPlayer = true
        
        let vlcNode = VLCVideoPlayerNode(url: url, posterURL: posterURL)
        vlcNode.setOverlayVisible = { [weak self] visible in
            self?.setOverlayVisible?(visible)
        }
        vlcNode.setPagingEnabled = { [weak self] enabled in
            self?.setPagingEnabled?(enabled)
        }
        vlcNode.controlsBottomInset = controlsBottomInset
        vlcPlayerNode = vlcNode
        addSubnode(vlcNode)
    }
    
    private func fallbackToVLC() {
        guard !didTryVLCPlayer else { return }
        VideoLoadDebug.log("fallback to VLC") // FOR TEST ONLY: remove before release

        avPlayerNode?.removeFromSupernode()
        avPlayerNode = nil
        
        setupVLCPlayer()
        
        if let vlcNode = vlcPlayerNode {
            vlcNode.frame = bounds
            if wantsPlay {
                vlcNode.play()
            }
        }
    }
    
    private func shouldUseVLCPlayer(for fileExtension: String) -> Bool {
        let vlcOnlyFormats = ["webm", "ogv", "ogg", "mkv", "avi", "flv", "wmv", "3gp", "3g2", "mpg", "mpeg", "ts", "vob"]
        return vlcOnlyFormats.contains(fileExtension)
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

    deinit {
        containerProbeTask?.cancel()
    }
}
