import Foundation
import UIKit
import AsyncDisplayKit

final class ChatVideoGalleryItemNode: GalleryItemNode {

    private var playerNode: UniversalVideoPlayerNode?
    var isPlaying: Bool { playerNode?.isPlaying == true }
    var controlsBottomInset: CGFloat = 0 {
        didSet { playerNode?.controlsBottomInset = controlsBottomInset }
    }

    override init() {
        super.init()
    }

    func configure(info: GalleryItemInfo) {
        guard let url = URL(string: info.url) else { return }
        playerNode?.removeFromSupernode()
        playerNode = nil
        let node = UniversalVideoPlayerNode(url: url, posterURL: info.url)
        node.setOverlayVisible = { [weak self] visible in
            self?.setControlsVisible(visible)
        }
        node.setPagingEnabled = { [weak self] enabled in
            self?.setPagingEnabled(enabled)
        }
        node.controlsBottomInset = controlsBottomInset
        self.playerNode = node
        self.addSubnode(node)
    }

    override func centralityUpdated(isCentral: Bool) {
        if isCentral {
            playerNode?.play()
        } else {
            playerNode?.pause()
        }
    }

    override func containerLayoutUpdated(_ size: CGSize, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(size, navigationBarHeight: navigationBarHeight, transition: transition)
        if let playerNode = playerNode {
            playerNode.controlsBottomInset = controlsBottomInset
            transition.updateFrame(node: playerNode, frame: CGRect(origin: .zero, size: size))
        }
    }

    override func visibilityUpdated(isVisible: Bool) {
        if !isVisible {
            playerNode?.pause()
        }
    }

    func play() {
        playerNode?.play()
    }

    func pause() {
        playerNode?.pause()
    }
}
