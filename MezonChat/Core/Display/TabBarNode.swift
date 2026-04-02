import Foundation
import UIKit
import AsyncDisplayKit

private enum TabBarLayoutScale {
    static var value: CGFloat {
        let w = UIScreen.main.bounds.width
        return min(max(w / 375, 1), 1.25)
    }
}

public struct TabBarNodeItem {
    public let item: UITabBarItem

    public init(item: UITabBarItem) {
        self.item = item
    }
}

final class TabBarItemNode: ASDisplayNode {
    private let iconNode = ASImageNode()
    private let labelNode = ASTextNode2()
    private let badgeBg = ASDisplayNode()
    private let badgeText = ASTextNode2()

    private(set) var isSelected: Bool = false
    private var item: UITabBarItem

    var onTap: (() -> Void)?

    init(item: UITabBarItem) {
        self.item = item
        super.init()
        automaticallyManagesSubnodes = true
        isUserInteractionEnabled = true

        iconNode.isUserInteractionEnabled = false
        badgeBg.backgroundColor = .systemRed
        badgeBg.cornerRadius = 9 * TabBarLayoutScale.value
        badgeBg.isUserInteractionEnabled = false
        badgeText.isUserInteractionEnabled = false

        applyStyle(selected: false)
        refreshBadge()
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    func updateItem(_ item: UITabBarItem) {
        self.item = item
        applyStyle(selected: isSelected)
        refreshBadge()
        setNeedsLayout()
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        applyStyle(selected: selected)

        if animated {
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = isSelected ? 0.88 : 1.08
            spring.toValue = 1.0
            spring.damping = 12
            spring.stiffness = 200
            spring.duration = 0.18
            iconNode.layer.add(spring, forKey: "selectionBounce")
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let s = TabBarLayoutScale.value
        let iconSize: CGFloat = 22 * s
        iconNode.style.preferredSize = CGSize(width: iconSize, height: iconSize)

        let fontSize: CGFloat = 10 * s
        let labelFont = UIFont.systemFont(ofSize: fontSize, weight: isSelected ? .semibold : .regular)
        let labelColor = isSelected ? UIColor.theme.channelUnread : UIColor.theme.textDisabled
        labelNode.attributedText = NSAttributedString(
            string: item.title ?? "",
            attributes: [.font: labelFont, .foregroundColor: labelColor]
        )

        let badgeValue = item.badgeValue ?? ""
        let iconWithBadge: ASLayoutElement
        if !badgeValue.isEmpty {
            let badgeSize: CGFloat = 18 * s
            badgeText.style.minWidth = ASDimensionMake(badgeSize)
            badgeText.style.height = ASDimensionMake(badgeSize)
            badgeBg.style.minWidth = ASDimensionMake(badgeSize)
            badgeBg.style.height = ASDimensionMake(badgeSize)
            let badgeStack = ASBackgroundLayoutSpec(
                child: ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: badgeText),
                background: badgeBg
            )
            let corner = ASCornerLayoutSpec(child: iconNode, corner: badgeStack, location: .topRight)
            corner.offset = CGPoint(x: 6 * s, y: -6 * s)
            iconWithBadge = corner
        } else {
            iconWithBadge = iconNode
        }

        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 3 * s,
            justifyContent: .center,
            alignItems: .center,
            children: [iconWithBadge, labelNode]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 14 * s, left: 0, bottom: 20 * s, right: 0),
            child: stack
        )
    }

    private func applyStyle(selected: Bool) {
        let icon = selected ? (item.selectedImage ?? item.image) : item.image
        iconNode.image = icon?.withRenderingMode(.alwaysOriginal)
        iconNode.tintColor = nil
        setNeedsLayout()
    }

    private func refreshBadge() {
        let text = item.badgeValue ?? ""
        let hidden = text.isEmpty
        badgeBg.isHidden = hidden
        badgeText.isHidden = hidden
        if !hidden {
            let fontSize = 10 * TabBarLayoutScale.value
            badgeText.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
            )
        }
    }

    @objc private func handleTap() { onTap?() }
}

public final class TabBarNode: ASDisplayNode {
    public static var barHeight: CGFloat { 57 * TabBarLayoutScale.value }

    private let backgroundNode: NavigationBackgroundNode
    private let separatorNode = ASDisplayNode()
    private(set) var itemNodes: [TabBarItemNode] = []

    var onSelect: ((Int, Bool) -> Void)?

    override public init() {
        backgroundNode = NavigationBackgroundNode(
            color: UIColor.theme.primary,
            enableBlur: true
        )
        super.init()
        automaticallyManagesSubnodes = false
        addSubnode(backgroundNode)
        addSubnode(separatorNode)
        separatorNode.backgroundColor = UIColor.theme.border
        separatorNode.isUserInteractionEnabled = false
    }

    func setItems(_ items: [TabBarNodeItem]) {
        itemNodes.forEach { $0.removeFromSupernode() }
        itemNodes = items.enumerated().map { idx, nodeItem in
            let node = TabBarItemNode(item: nodeItem.item)
            node.onTap = { [weak self] in self?.onSelect?(idx, false) }
            addSubnode(node)
            return node
        }
        setNeedsLayout()
    }

    func updateItems(_ items: [TabBarNodeItem]) {
        for (i, nodeItem) in items.enumerated() where i < itemNodes.count {
            itemNodes[i].updateItem(nodeItem.item)
        }
    }

    func setSelectedIndex(_ index: Int) {
        for (i, node) in itemNodes.enumerated() {
            node.setSelected(i == index, animated: true)
        }
    }

    func frameForItem(at index: Int) -> CGRect? {
        guard index < itemNodes.count else { return nil }
        return itemNodes[index].frame
    }

    func updateLayout(size: CGSize, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let totalHeight = Self.barHeight + bottomInset

        transition.updateFrame(node: backgroundNode, frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: totalHeight)))
        backgroundNode.updateColor(color: UIColor.theme.primary, transition: transition)
        backgroundNode.update(size: CGSize(width: size.width, height: totalHeight), cornerRadius: 0, transition: transition)

        let separatorH = 1.0 / UIScreen.main.scale
        transition.updateFrame(node: separatorNode, frame: CGRect(x: 0, y: 0, width: size.width, height: separatorH))

        guard !itemNodes.isEmpty else { return }
        let itemW = size.width / CGFloat(itemNodes.count)
        for (i, node) in itemNodes.enumerated() {
            let frame = CGRect(x: itemW * CGFloat(i), y: 0, width: itemW, height: Self.barHeight)
            transition.updateFrame(node: node, frame: frame)
        }
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if point.y > Self.barHeight { return nil }
        return super.hitTest(point, with: event)
    }
}
