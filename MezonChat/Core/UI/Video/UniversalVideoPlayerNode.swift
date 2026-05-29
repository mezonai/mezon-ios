import Foundation
import UIKit
import AsyncDisplayKit
import AVFoundation

final class UniversalVideoPlayerNode: ASDisplayNode {
    
    private var avPlayerNode: MezonVideoPlayerNode?
    private var vlcPlayerNode: VLCVideoPlayerNode?
    private let url: URL
    private let posterURL: String
    
    var toggleOverlayVisibility: (() -> Void)?
    
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
            let vlcNode = VLCVideoPlayerNode(url: url, posterURL: posterURL)
            vlcNode.toggleOverlayVisibility = { [weak self] in
                self?.toggleOverlayVisibility?()
            }
            vlcPlayerNode = vlcNode
            addSubnode(vlcNode)
        } else {
            let avNode = MezonVideoPlayerNode(url: url, posterURL: posterURL)
            avNode.toggleOverlayVisibility = { [weak self] in
                self?.toggleOverlayVisibility?()
            }
            avPlayerNode = avNode
            addSubnode(avNode)
        }
    }
    
    private func shouldUseVLCPlayer(for fileExtension: String) -> Bool {
        let vlcOnlyFormats = ["webm", "ogv", "ogg", "mkv", "avi", "flv", "wmv", "3gp"]
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
