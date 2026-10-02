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
    var setControlsVisible: ((Bool) -> Void)?
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
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        self.view.addSubview(scrollView)
    }

    func setPagingEnabled(_ enabled: Bool) {
        scrollView.isScrollEnabled = enabled
    }

    func configure(items: [GalleryItemInfo], initialIndex: Int, factory: @escaping (GalleryItemInfo, Int) -> GalleryItemNode) {
        self.items = items
        self.itemNodeFactory = factory
        self.centralItemIndex = max(0, min(initialIndex, items.count - 1))
    }

    func replaceItems(_ items: [GalleryItemInfo], focusIndex: Int) {
        for node in itemNodes.values {
            node.view.removeFromSuperview()
        }
        itemNodes.removeAll()
        self.items = items
        self.centralItemIndex = max(0, min(focusIndex, items.count - 1))
        self.hasPerformedInitialLayout = false
        if currentSize.width > 0, currentSize.height > 0 {
            updateLayout(size: currentSize, navigationBarHeight: 0)
        }
    }

    func replaceItemsPreservingCurrent(_ items: [GalleryItemInfo], focusIndex: Int) {
        guard currentSize.width > 0, currentSize.height > 0,
              !items.isEmpty,
              let currentNode = itemNodes[centralItemIndex]
        else {
            replaceItems(items, focusIndex: focusIndex)
            return
        }

        let targetIndex = max(0, min(focusIndex, items.count - 1))
        for (index, node) in itemNodes where index != centralItemIndex {
            node.view.removeFromSuperview()
        }
        itemNodes.removeAll()
        itemNodes[targetIndex] = currentNode

        self.items = items
        self.centralItemIndex = targetIndex
        self.hasPerformedInitialLayout = true

        UIView.performWithoutAnimation {
            scrollView.contentSize = CGSize(width: currentSize.width * CGFloat(items.count), height: currentSize.height)
            scrollView.contentOffset = CGPoint(x: CGFloat(targetIndex) * currentSize.width, y: 0)
            currentNode.index = targetIndex
            currentNode.itemInfo = items[targetIndex]
            currentNode.frame = CGRect(
                x: CGFloat(targetIndex) * currentSize.width,
                y: 0,
                width: currentSize.width,
                height: currentSize.height
            )
            currentNode.containerLayoutUpdated(currentSize, navigationBarHeight: 0, transition: .immediate)
            currentNode.centralityUpdated(isCentral: true)
            scrollView.layoutIfNeeded()
        }

        loadVisibleItems(size: currentSize, navigationBarHeight: 0)
    }

    func setCentralItemIndex(_ index: Int, animated: Bool) {
        let targetIndex = max(0, min(index, items.count - 1))
        guard targetIndex != centralItemIndex || animated else { return }
        if currentSize.width <= 0 {
            centralItemIndex = targetIndex
            return
        }
        let targetOffset = CGPoint(x: CGFloat(targetIndex) * currentSize.width, y: 0)
        scrollView.setContentOffset(targetOffset, animated: animated)
        if !animated {
            updateCentralIndex()
        }
    }

    func updateLayout(size: CGSize, navigationBarHeight: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        let widthChanged = abs(currentSize.width - size.width) > 0.5
        self.currentSize = size
        scrollView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = CGSize(width: size.width * CGFloat(items.count), height: size.height)

        if !hasPerformedInitialLayout || widthChanged {
            scrollView.contentOffset = CGPoint(x: CGFloat(centralItemIndex) * size.width, y: 0)
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
                node.setControlsVisible = { [weak self] visible in self?.setControlsVisible?(visible) }
                node.dismiss = { [weak self] in self?.dismiss?() }
                node.setPagingEnabled = { [weak self] enabled in self?.setPagingEnabled(enabled) }
                node.itemInfo = items[index]

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
