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
            attachPlayerMatchingContainer(request)
            return
        }
        CDNSigner.shared.requestURL(for: url) { [weak self] request in
            DispatchQueue.main.async {
                self?.attachPlayerMatchingContainer(request)
            }
        }
    }

    private func attachPlayerMatchingContainer(_ request: CDNRequestURL) {
        guard request.isSigned else {
            attachAVPlayer(request)
            return
        }
        var probe = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        probe.setValue("bytes=0-8191", forHTTPHeaderField: "Range")
        URLSession.shared.dataTask(with: probe) { [weak self] data, _, _ in
            let isFragmented = data.map(UniversalVideoPlayerNode.isFragmentedMP4) ?? false
            DispatchQueue.main.async {
                guard let self else { return }
                self.usesChunkedLoading = isFragmented
                self.attachAVPlayer(request)
            }
        }.resume()
    }

    private static func isFragmentedMP4(_ data: Data) -> Bool {
        var offset = 0
        while offset + 8 <= data.count {
            let size = data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            if data[offset + 4..<offset + 8] == Data("moov".utf8) {
                let end = min(offset + size, data.count)
                guard end > offset else { return false }
                return data.range(of: Data("mvex".utf8), options: [], in: offset..<end) != nil
            }
            guard size >= 8 else { return false }
            offset += size
        }
        return false
    }

    private func attachAVPlayer(_ request: CDNRequestURL) {
        guard avPlayerNode == nil, vlcPlayerNode == nil else { return }
        avRequest = request
        let avNode = MezonVideoPlayerNode(url: request.url, posterURL: posterURL, usesChunkedLoading: usesChunkedLoading)
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
        guard !didResignAVPlayer,
              let request = avRequest,
              CDNSigner.shared.invalidate(request) else {
            fallbackToVLC()
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
                    self.fallbackToVLC()
                }
            }
        }
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
}
