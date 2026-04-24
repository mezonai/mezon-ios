import Foundation
import UIKit
import AsyncDisplayKit

final class TabBarControllerNode: ASDisplayNode {
    let tabBarNode = TabBarNode()

    private let itemSelected: (Int, Bool) -> Void

    private(set) var tabBarItems: [TabBarNodeItem] = []
    private(set) var selectedIndex: Int = 0

    private weak var currentController: ViewController?

    var tabBarHidden = false

    init(itemSelected: @escaping (Int, Bool) -> Void) {
        self.itemSelected = itemSelected
        super.init()

        addSubnode(tabBarNode)
        tabBarNode.onSelect = { [weak self] index, longTap in
            self?.itemSelected(index, longTap)
        }

        backgroundColor = UIColor.theme.secondaryLight
    }

    func setCurrentController(_ controller: ViewController?) -> () -> Void {
        guard controller !== self.currentController else { return {} }

        let previousNode = self.currentController?.displayNode
        self.currentController = controller

        if let currentNode = controller?.displayNode {
            if let previousNode {
                insertSubnode(currentNode, aboveSubnode: previousNode)
            } else {
                insertSubnode(currentNode, at: 0)
            }
            view.bringSubviewToFront(tabBarNode.view)
        }

        return { [weak previousNode, weak self] in
            if previousNode !== self?.currentController?.displayNode {
                previousNode?.removeFromSupernode()
            }
        }
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, toolbar: Toolbar?, transition: ContainedViewLayoutTransition) -> CGFloat {
        let bottomInset = layout.safeInsets.bottom
        let tabBarTotalHeight = TabBarNode.barHeight + bottomInset

        let tabBarFrame = CGRect(
            x: 0,
            y: layout.size.height - (tabBarHidden ? 0 : tabBarTotalHeight),
            width: layout.size.width,
            height: tabBarTotalHeight
        )
        transition.updateFrame(node: tabBarNode, frame: tabBarFrame)
        tabBarNode.updateLayout(size: layout.size, bottomInset: bottomInset, transition: transition)

        transition.updateAlpha(node: tabBarNode, alpha: tabBarHidden ? 0.0 : 1.0)

        backgroundColor = UIColor.theme.secondaryLight

        return tabBarHidden ? layout.intrinsicInsets.bottom : max(layout.intrinsicInsets.bottom, tabBarTotalHeight)
    }

    func frameForControllerTab(at index: Int) -> CGRect? {
        guard let itemFrame = tabBarNode.frameForItem(at: index) else { return nil }
        return view.convert(itemFrame, from: tabBarNode.view)
    }

    func isPointInsideContentArea(point: CGPoint) -> Bool {
        return point.y < tabBarNode.frame.minY
    }

    func updateTabBarItems(items: [TabBarNodeItem]) {
        self.tabBarItems = items
        tabBarNode.setItems(items)
    }

    func updateSelectedIndex(index: Int) {
        self.selectedIndex = index
        tabBarNode.setSelectedIndex(index)
    }

    func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition) {
        tabBarNode.isUserInteractionEnabled = value
        transition.updateAlpha(node: tabBarNode, alpha: value ? 1.0 : 0.5)
    }
}
