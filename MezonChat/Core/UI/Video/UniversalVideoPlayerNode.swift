import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation

final class UniversalVideoPlayerNode: ASDisplayNode {
    
    private var avPlayerNode: MezonVideoPlayerNode?
    private var vlcPlayerNode: VLCVideoPlayerNode?
    private let url: URL
    private let posterURL: String
    private var didTryAVPlayer = false
    private var didTryVLCPlayer = false
    
    var toggleOverlayVisibility: (() -> Void)?
    var setPagingEnabled: ((Bool) -> Void)?
    
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
        
        let avNode = MezonVideoPlayerNode(url: url, posterURL: posterURL)
        avNode.toggleOverlayVisibility = { [weak self] in
            self?.toggleOverlayVisibility?()
        }
        avNode.setPagingEnabled = { [weak self] enabled in
            self?.setPagingEnabled?(enabled)
        }
        avNode.onPlaybackFailed = { [weak self] in
            self?.fallbackToVLC()
        }
        avPlayerNode = avNode
        addSubnode(avNode)
    }
    
    private func setupVLCPlayer() {
        guard !didTryVLCPlayer else { return }
        didTryVLCPlayer = true
        
        let vlcNode = VLCVideoPlayerNode(url: url, posterURL: posterURL)
        vlcNode.toggleOverlayVisibility = { [weak self] in
            self?.toggleOverlayVisibility?()
        }
        vlcNode.setPagingEnabled = { [weak self] enabled in
            self?.setPagingEnabled?(enabled)
        }
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
        avPlayerNode?.play()
        vlcPlayerNode?.play()
    }
    
    func pause() {
        avPlayerNode?.pause()
        vlcPlayerNode?.pause()
    }
    
    override func layout() {
        super.layout()
        avPlayerNode?.frame = bounds
        vlcPlayerNode?.frame = bounds
    }
}
