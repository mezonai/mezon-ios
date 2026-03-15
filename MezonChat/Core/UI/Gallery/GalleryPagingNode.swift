import Foundation
import UIKit
import AsyncDisplayKit

final class GalleryPagingNode: ASDisplayNode, UIScrollViewDelegate {

    private let scrollView = UIScrollView()
    private var itemNodes: [Int: GalleryItemNode] = [:]
    private var items: [GalleryItemInfo] = []
    private var itemNodeFactory: ((GalleryItemInfo, Int) -> GalleryItemNode)?

    private(set) var centralItemIndex: Int = 0
    private var currentSize: CGSize = .zero
    private var hasPerformedInitialLayout = false

    var centralItemIndexUpdated: ((Int) -> Void)?
    var toggleControlsVisibility: (() -> Void)?
    var dismiss: (() -> Void)?

    override init() {
        super.init()
        self.setViewBlock { UITracingLayerView() }
    }

    override func didLoad() {
        super.didLoad()

        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bounces = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        self.view.addSubview(scrollView)
    }

    func configure(items: [GalleryItemInfo], initialIndex: Int, factory: @escaping (GalleryItemInfo, Int) -> GalleryItemNode) {
        self.items = items
        self.itemNodeFactory = factory
        self.centralItemIndex = max(0, min(initialIndex, items.count - 1))
    }

    func updateLayout(size: CGSize, navigationBarHeight: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        self.currentSize = size
        scrollView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = CGSize(width: size.width * CGFloat(items.count), height: size.height)

        let offset = CGFloat(centralItemIndex) * size.width
        if !hasPerformedInitialLayout {
            scrollView.contentOffset = CGPoint(x: offset, y: 0)
            hasPerformedInitialLayout = true
        }

        loadVisibleItems(size: size, navigationBarHeight: navigationBarHeight)
    }

    private func loadVisibleItems(size: CGSize, navigationBarHeight: CGFloat) {
        guard size.width > 0, size.height > 0, !items.isEmpty else { return }

        let visibleRange = max(0, centralItemIndex - 1)...min(items.count - 1, centralItemIndex + 1)

        for (index, node) in itemNodes {
            if !visibleRange.contains(index) {
                node.view.removeFromSuperview()
                itemNodes.removeValue(forKey: index)
            }
        }

        for index in visibleRange {
            let node: GalleryItemNode
            if let existing = itemNodes[index] {
                node = existing
            } else {
                guard let factory = itemNodeFactory else { continue }
                node = factory(items[index], index)
                node.toggleControlsVisibility = { [weak self] in self?.toggleControlsVisibility?() }
                node.dismiss = { [weak self] in self?.dismiss?() }
                node.itemInfo = items[index]
                // Add to scrollView so paging works
                scrollView.addSubview(node.view)
                itemNodes[index] = node
            }

            let frame = CGRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height)
            node.frame = frame
            node.containerLayoutUpdated(size, navigationBarHeight: navigationBarHeight, transition: .immediate)
            node.centralityUpdated(isCentral: index == centralItemIndex)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCentralIndex()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCentralIndex()
    }

    private func updateCentralIndex() {
        guard currentSize.width > 0 else { return }
        let newIndex = Int(round(scrollView.contentOffset.x / currentSize.width))
        let clampedIndex = max(0, min(newIndex, items.count - 1))
        if clampedIndex != centralItemIndex {
            let previousIndex = centralItemIndex
            centralItemIndex = clampedIndex
            itemNodes[previousIndex]?.centralityUpdated(isCentral: false)
            itemNodes[clampedIndex]?.centralityUpdated(isCentral: true)
            centralItemIndexUpdated?(clampedIndex)
            loadVisibleItems(size: currentSize, navigationBarHeight: 0)
        }
    }

    func currentItemNode() -> GalleryItemNode? {
        return itemNodes[centralItemIndex]
    }
}
