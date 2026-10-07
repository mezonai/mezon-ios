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
            attachAVPlayer(request)
            return
        }
        CDNSigner.shared.requestURL(for: url) { [weak self] request in
            DispatchQueue.main.async {
                self?.attachAVPlayer(request)
            }
        }
    }

    private func attachAVPlayer(_ request: CDNRequestURL) {
        guard avPlayerNode == nil, vlcPlayerNode == nil else { return }
        avRequest = request
        let avNode = MezonVideoPlayerNode(url: request.url, posterURL: posterURL)
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
            vlcNode.play()
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
