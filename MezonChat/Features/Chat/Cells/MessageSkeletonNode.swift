import AsyncDisplayKit
import UIKit

final class MessageSkeletonCellNode: ASCellNode {

    private let avatarNode = ASDisplayNode()
    private let shortLineNode = ASDisplayNode()
    private let normalLineNode = ASDisplayNode()
    private let longLineNode: ASDisplayNode?
    private var shimmerLayers: [CAGradientLayer] = []

    init(showLongLine: Bool) {
        longLineNode = showLongLine ? ASDisplayNode() : nil
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
    }

    override func didLoad() {
        super.didLoad()
        let t = UIColor.theme

        avatarNode.backgroundColor = t.secondaryLight
        avatarNode.cornerRadius = 20.sf

        shortLineNode.backgroundColor = t.secondaryLight
        shortLineNode.cornerRadius = 5.sf

        normalLineNode.backgroundColor = t.secondaryLight
        normalLineNode.cornerRadius = 5.sf

        longLineNode?.backgroundColor = t.secondaryLight
        longLineNode?.cornerRadius = 5.sf

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.addShimmer()
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        avatarNode.style.preferredSize = CGSize(width: 40.sf, height: 40.sf)
        shortLineNode.style.preferredSize = CGSize(width: 100.sf, height: 12.sf)
        normalLineNode.style.preferredSize = CGSize(width: 200.sf, height: 12.sf)

        var lines: [ASLayoutElement] = [shortLineNode, normalLineNode]
        if let longLine = longLineNode {
            longLine.style.preferredSize = CGSize(width: 260.sf, height: 12.sf)
            lines.append(longLine)
        }

        let linesStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8.sf,
            justifyContent: .start,
            alignItems: .start,
            children: lines
        )
        linesStack.style.flexShrink = 1

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12.sf,
            justifyContent: .start,
            alignItems: .start,
            children: [avatarNode, linesStack]
        )

        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 10.sf, left: 14.sf, bottom: 10.sf, right: 14.sf),
            child: row
        )
    }

    // MARK: - Shimmer

    private func addShimmer() {
        let skeletonNodes: [ASDisplayNode?] = [avatarNode, shortLineNode, normalLineNode, longLineNode]
        for node in skeletonNodes {
            guard let node, let layer = node.layer as CALayer? else { continue }
            let shimmer = CAGradientLayer()
            shimmer.frame = layer.bounds
            shimmer.cornerRadius = layer.cornerRadius
            shimmer.startPoint = CGPoint(x: 0, y: 0.5)
            shimmer.endPoint = CGPoint(x: 1, y: 0.5)

            let base = UIColor.theme.secondaryLight
            let highlight = UIColor.theme.tertiary
            shimmer.colors = [base.cgColor, highlight.cgColor, base.cgColor]
            shimmer.locations = [0, 0.5, 1]

            layer.addSublayer(shimmer)
            shimmerLayers.append(shimmer)

            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = [-1.0, -0.5, 0.0]
            animation.toValue = [1.0, 1.5, 2.0]
            animation.duration = 1.5
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            shimmer.add(animation, forKey: "shimmer")
        }
    }

    override func layout() {
        super.layout()
        let nodes: [ASDisplayNode?] = [avatarNode, shortLineNode, normalLineNode, longLineNode]
        for (i, node) in nodes.enumerated() {
            guard let node, i < shimmerLayers.count else { continue }
            shimmerLayers[i].frame = node.layer.bounds
        }
    }

    override func didExitVisibleState() {
        super.didExitVisibleState()
        for layer in shimmerLayers {
            layer.removeAllAnimations()
        }
    }

    override func didEnterVisibleState() {
        super.didEnterVisibleState()
        for layer in shimmerLayers {
            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = [-1.0, -0.5, 0.0]
            animation.toValue = [1.0, 1.5, 2.0]
            animation.duration = 1.5
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "shimmer")
        }
    }
}

final class MessageSkeletonContainerNode: ASDisplayNode {

    private let skeletonNodes: [MessageSkeletonCellNode]
    private let count: Int

    init(count: Int = 8) {
        self.count = count
        self.skeletonNodes = (0..<count).map { i in
            MessageSkeletonCellNode(showLongLine: i % 2 == 1)
        }
        super.init()
        automaticallyManagesSubnodes = true
        isUserInteractionEnabled = false
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 4.sf,
            justifyContent: .end,
            alignItems: .stretch,
            children: skeletonNodes
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 0, bottom: 8.sf, right: 0),
            child: stack
        )
    }
}
