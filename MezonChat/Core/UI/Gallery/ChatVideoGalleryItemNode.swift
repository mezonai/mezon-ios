import Foundation
import UIKit
import AsyncDisplayKit

final class ChatVideoGalleryItemNode: GalleryItemNode {

    private var playerNode: UniversalVideoPlayerNode?
    private let previewNode = ASImageNode()
    private var videoURL: URL?
    private var posterURL: String?
    var isPlaying: Bool { playerNode?.isPlaying == true }
    var controlsBottomInset: CGFloat = 0 {
        didSet { playerNode?.controlsBottomInset = controlsBottomInset }
    }

    override init() {
        super.init()
        previewNode.contentMode = .scaleAspectFit
        addSubnode(previewNode)
    }

    func configure(info: GalleryItemInfo) {
        playerNode?.pause()
        playerNode?.removeFromSupernode()
        playerNode = nil
        videoURL = URL(string: info.url)
        posterURL = info.url
        previewNode.image = ImageCache.shared.memoryImage(forKey: "video_thumb_\(info.url)")
        previewNode.isHidden = false
    }

    private func makePlayerIfNeeded() {
        guard playerNode == nil, let url = videoURL, let posterURL else { return }
        let node = UniversalVideoPlayerNode(url: url, posterURL: posterURL)
        node.setOverlayVisible = { [weak self] visible in
            self?.setControlsVisible(visible)
        }
        node.setPagingEnabled = { [weak self] enabled in
            self?.setPagingEnabled(enabled)
        }
        node.controlsBottomInset = controlsBottomInset
        self.playerNode = node
        self.addSubnode(node)
        node.frame = bounds
        previewNode.isHidden = true
    }

    override func centralityUpdated(isCentral: Bool) {
        if isCentral {
            play()
        } else {
            playerNode?.pause()
        }
    }

    override func containerLayoutUpdated(_ size: CGSize, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(size, navigationBarHeight: navigationBarHeight, transition: transition)
        transition.updateFrame(node: previewNode, frame: CGRect(origin: .zero, size: size))
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
        makePlayerIfNeeded()
        playerNode?.play()
    }

    func pause() {
        playerNode?.pause()
    }
}
