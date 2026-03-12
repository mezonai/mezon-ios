import Foundation
import UIKit
import AsyncDisplayKit

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
        badgeBg.cornerRadius = 9
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
        iconNode.style.preferredSize = CGSize(width: 26, height: 26)

        let labelFont = UIFont.systemFont(ofSize: 10, weight: isSelected ? .semibold : .regular)
        let labelColor = isSelected ? UIColor.theme.channelUnread : UIColor.theme.textDisabled
        labelNode.attributedText = NSAttributedString(
            string: item.title ?? "",
            attributes: [.font: labelFont, .foregroundColor: labelColor]
        )

        let badgeValue = item.badgeValue ?? ""
        let iconWithBadge: ASLayoutElement
        if !badgeValue.isEmpty {
            badgeText.style.minWidth = ASDimensionMake(18)
            badgeText.style.height = ASDimensionMake(18)
            badgeBg.style.minWidth = ASDimensionMake(18)
            badgeBg.style.height = ASDimensionMake(18)
            let badgeStack = ASBackgroundLayoutSpec(
                child: ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: badgeText),
                background: badgeBg
            )
            let corner = ASCornerLayoutSpec(child: iconNode, corner: badgeStack, location: .topRight)
            corner.offset = CGPoint(x: 6, y: -6)
            iconWithBadge = corner
        } else {
            iconWithBadge = iconNode
        }

        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 3,
            justifyContent: .center,
            alignItems: .center,
            children: [iconWithBadge, labelNode]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 9, left: 0, bottom: 7, right: 0),
            child: stack
        )
    }

    private func applyStyle(selected: Bool) {
        let icon = selected ? (item.selectedImage ?? item.image) : item.image
        let color = selected ? UIColor.theme.channelUnread : UIColor.theme.channelNormal
        iconNode.image = icon?.withRenderingMode(.alwaysTemplate)
        iconNode.tintColor = color
        setNeedsLayout()
    }

    private func refreshBadge() {
        let text = item.badgeValue ?? ""
        let hidden = text.isEmpty
        badgeBg.isHidden = hidden
        badgeText.isHidden = hidden
        if !hidden {
            badgeText.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
            )
        }
    }

    @objc private func handleTap() { onTap?() }
}

public final class TabBarNode: ASDisplayNode {
    public static let barHeight: CGFloat = 49.0

    private let backgroundNode: NavigationBackgroundNode
    private let separatorNode = ASDisplayNode()
    private(set) var itemNodes: [TabBarItemNode] = []

    var onSelect: ((Int, Bool) -> Void)?

    override public init() {
        backgroundNode = NavigationBackgroundNode(
            color: UIColor.theme.secondary.withAlphaComponent(0.92),
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
        backgroundNode.updateColor(color: UIColor.theme.secondary.withAlphaComponent(0.92), transition: transition)
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
