import AsyncDisplayKit
import UIKit

final class MessageSkeletonCellNode: ASCellNode {

    private let avatarNode = ASDisplayNode()
    private let shortLineNode = ASDisplayNode()
    private let normalLineNode = ASDisplayNode()
    private let longLineNode: ASDisplayNode?
    private var shimmerLayers: [CAGradientLayer] = []

    private let showLongLine: Bool

    init(showLongLine: Bool) {
        self.showLongLine = showLongLine
        longLineNode = showLongLine ? ASDisplayNode() : nil
        super.init()
        selectionStyle = .none

        addSubnode(avatarNode)
        addSubnode(shortLineNode)
        addSubnode(normalLineNode)
        if let longLineNode { addSubnode(longLineNode) }
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

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let inset: CGFloat = 14.sf
        let avatarSz: CGFloat = 40.sf
        let lineH: CGFloat = 12.sf
        let lineSpacing: CGFloat = 8.sf
        let lineCount: CGFloat = showLongLine ? 3 : 2
        let linesH = lineH * lineCount + lineSpacing * (lineCount - 1)
        let height = inset + max(avatarSz, linesH) + inset
        return CGSize(width: constrainedSize.width, height: height)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14.sf
        let avatarSz: CGFloat = 40.sf
        let lineH: CGFloat = 12.sf
        let lineSpacing: CGFloat = 8.sf
        let rowSpacing: CGFloat = 12.sf

        avatarNode.frame = CGRect(x: inset, y: inset, width: avatarSz, height: avatarSz)
        let lineX = inset + avatarSz + rowSpacing
        var y = inset

        shortLineNode.frame = CGRect(x: lineX, y: y, width: 100.sf, height: lineH)
        y += lineH + lineSpacing

        normalLineNode.frame = CGRect(x: lineX, y: y, width: 200.sf, height: lineH)
        y += lineH + lineSpacing

        if let longLineNode {
            longLineNode.frame = CGRect(x: lineX, y: y, width: 260.sf, height: lineH)
        }

        let nodes: [ASDisplayNode?] = [avatarNode, shortLineNode, normalLineNode, longLineNode]
        for (i, node) in nodes.enumerated() {
            guard let node, i < shimmerLayers.count else { continue }
            shimmerLayers[i].frame = node.layer.bounds
        }
    }


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

    init(count: Int = 8) {
        self.skeletonNodes = (0..<count).map { i in
            MessageSkeletonCellNode(showLongLine: i % 2 == 1)
        }
        super.init()
        isUserInteractionEnabled = false
        skeletonNodes.forEach { addSubnode($0) }
    }

    override func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        let spacing: CGFloat = 4.sf
        var totalH: CGFloat = 0
        for (i, node) in skeletonNodes.enumerated() {
            if i > 0 { totalH += spacing }
            let sz = node.calculateSizeThatFits(constrainedSize)
            _ = sz
            totalH += sz.height
        }
        return CGSize(width: constrainedSize.width, height: totalH + 8.sf)
    }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 4.sf
        let w = bounds.width
        var y: CGFloat = 0

        var heights: [CGFloat] = []
        for node in skeletonNodes {
            let sz = node.calculateSizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
            heights.append(sz.height)
        }
        let totalH = heights.reduce(0, +) + spacing * CGFloat(max(skeletonNodes.count - 1, 0))
        y = max(bounds.height - 8.sf - totalH, 0)

        for (i, node) in skeletonNodes.enumerated() {
            if i > 0 { y += spacing }
            node.frame = CGRect(x: 0, y: y, width: w, height: heights[i])
            y += heights[i]
        }
    }
}
