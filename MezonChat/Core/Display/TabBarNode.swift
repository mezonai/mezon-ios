import Foundation
import ObjectiveC
import UIKit
import AsyncDisplayKit

private var mezonTabBarFaceAssetKey: UInt8 = 0

extension UITabBarItem {
    var mezonTabBarFaceAssetName: String? {
        get { objc_getAssociatedObject(self, &mezonTabBarFaceAssetKey) as? String }
        set { objc_setAssociatedObject(self, &mezonTabBarFaceAssetKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }
}

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
    private static let imageBundle = Bundle.main
    private let primaryIconNode = ASImageNode()
    private let faceIconNode = ASImageNode()
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

        primaryIconNode.isUserInteractionEnabled = false
        primaryIconNode.contentMode = .scaleAspectFit
        faceIconNode.isUserInteractionEnabled = false
        faceIconNode.contentMode = .scaleAspectFit
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

    func refreshAppearanceForThemeChange() {
        applyStyle(selected: isSelected)
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
            primaryIconNode.layer.add(spring, forKey: "selectionBounce")
            faceIconNode.layer.add(spring, forKey: "selectionBounceFace")
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let s = TabBarLayoutScale.value
        let iconSize: CGFloat = 22 * s
        primaryIconNode.style.preferredSize = CGSize(width: iconSize, height: iconSize)
        faceIconNode.style.preferredSize = CGSize(width: iconSize, height: iconSize)
        let iconStack = ASOverlayLayoutSpec(child: primaryIconNode, overlay: faceIconNode)

        let fontSize: CGFloat = 10 * s
        let labelFont = UIFont.systemFont(ofSize: fontSize, weight: isSelected ? .semibold : .regular)
        let labelColor = isSelected ? UIColor.theme.textStrong : UIColor.theme.channelNormal
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
            let corner = ASCornerLayoutSpec(child: iconStack, corner: badgeStack, location: .topRight)
            corner.offset = CGPoint(x: 6 * s, y: -6 * s)
            iconWithBadge = corner
        } else {
            iconWithBadge = iconStack
        }

        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 6 * s,
            justifyContent: .center,
            alignItems: .center,
            children: [iconWithBadge, labelNode]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 18 * s, left: 0, bottom: 26 * s, right: 0),
            child: stack
        )
    }

    private func applyStyle(selected: Bool) {
        let icon = selected ? (item.selectedImage ?? item.image) : item.image
        primaryIconNode.image = icon?.withRenderingMode(.alwaysTemplate)
        let primaryTint: UIColor
        if !ThemeManager.shared.current.usesLightStatusBarContent {
            primaryTint = selected ? UIColor(hex: 0xC0C8F2) : UIColor(hex: 0xCECECE)
        } else {
            primaryTint = selected ? UIColor.theme.iconPrimary : UIColor.theme.iconSecondary
        }
        let faceTint = selected ? UIColor(hex: 0x475ED9) : UIColor.theme.borderRadio
        primaryIconNode.tintColor = primaryTint
        if let faceName = item.mezonTabBarFaceAssetName,
           let face = UIImage(named: faceName, in: Self.imageBundle, compatibleWith: nil) {
            faceIconNode.image = face.withRenderingMode(.alwaysTemplate)
            faceIconNode.tintColor = faceTint
            faceIconNode.isHidden = false
        } else {
            faceIconNode.image = nil
            faceIconNode.isHidden = true
        }
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
    public static var barHeight: CGFloat { 67 * TabBarLayoutScale.value }

    private let backgroundNode: NavigationBackgroundNode
    private let separatorNode = ASDisplayNode()
    private(set) var itemNodes: [TabBarItemNode] = []

    var onSelect: ((Int, Bool) -> Void)?

    private static var shouldEnableBackgroundBlurForCurrentTheme: Bool {
        !ThemeManager.shared.current.usesLightStatusBarContent
    }

    override public init() {
        backgroundNode = NavigationBackgroundNode(
            color: UIColor.theme.secondaryLight,
            enableBlur: Self.shouldEnableBackgroundBlurForCurrentTheme
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

    func refreshItemAppearanceForThemeChange() {
        separatorNode.backgroundColor = UIColor.theme.border
        itemNodes.forEach { $0.refreshAppearanceForThemeChange() }
    }

    func updateLayout(size: CGSize, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        let totalHeight = Self.barHeight + bottomInset

        transition.updateFrame(node: backgroundNode, frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: totalHeight)))
        backgroundNode.updateColor(
            color: UIColor.theme.secondaryLight,
            enableBlur: Self.shouldEnableBackgroundBlurForCurrentTheme,
            transition: transition
        )
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
