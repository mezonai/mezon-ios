import Foundation
import UIKit
import AsyncDisplayKit

final class ChatVideoGalleryItemNode: GalleryItemNode {

    private var playerNode: UniversalVideoPlayerNode?
    private let previewNode = ASImageNode()
    private static let neighborPrefetchDelay: TimeInterval = 2

    private var videoURL: URL?
    private var posterURL: String?
    private var didScheduleNeighborPrefetch = false
    var isPlaying: Bool { playerNode?.isPlaying == true }
    var controlsBottomInset: CGFloat = 0 {
        didSet { playerNode?.controlsBottomInset = controlsBottomInset }
    }

    override init() {
        super.init()
        accessibilityElementsHidden = true
        previewNode.contentMode = .scaleAspectFit
        addSubnode(previewNode)
    }

    func configure(info: GalleryItemInfo) {
        playerNode?.pause()
        playerNode?.removeFromSupernode()
        playerNode = nil
        videoURL = URL(string: info.url)
        posterURL = info.url
        didScheduleNeighborPrefetch = false
        previewNode.image = ImageCache.shared.memoryImage(forKey: "video_thumb_\(info.url)")
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
    }

    override func centralityUpdated(isCentral: Bool) {
        accessibilityElementsHidden = !isCentral
        if isCentral {
            play()
        } else {
            playerNode?.pause()
            scheduleNeighborPrefetch()
        }
    }

    private func scheduleNeighborPrefetch() {
        guard !didScheduleNeighborPrefetch, playerNode == nil, let url = videoURL else { return }
        didScheduleNeighborPrefetch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.neighborPrefetchDelay) { [weak self] in
            guard let self, self.playerNode == nil, self.videoURL == url,
                  self.isNodeLoaded, self.view.window != nil else { return }
            VideoRangePrefetcher.shared.prefetch(url, allowsExpensiveNetwork: true)
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
