import Foundation
import UIKit
import AsyncDisplayKit

final class ChatVideoGalleryItemNode: GalleryItemNode {

    private var playerNode: MezonVideoPlayerNode?

    override init() {
        super.init()
    }

    func configure(info: GalleryItemInfo) {
        guard let url = URL(string: info.url) else { return }
        playerNode?.removeFromSupernode()
        playerNode = nil
        let node = MezonVideoPlayerNode(url: url, posterURL: info.url)
        node.toggleOverlayVisibility = { [weak self] in
            self?.toggleControlsVisibility()
        }
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
            transition.updateFrame(node: playerNode, frame: CGRect(origin: .zero, size: size))
        }
    }

    override func visibilityUpdated(isVisible: Bool) {
        if !isVisible {
            playerNode?.pause()
        }
    }
}

