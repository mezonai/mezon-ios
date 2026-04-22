import AsyncDisplayKit
import UIKit

final class ChatBottomLoaderItem: ListViewItem {

    var selectable: Bool { false }
    var approximateHeight: CGFloat { ChatBottomLoaderNode.rowHeight }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatBottomLoaderNode()
            let layout = node.asyncLayout()
            let (nodeLayout, apply) = layout(params)

            node.contentSize = nodeLayout.contentSize
            node.insets = nodeLayout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let itemNode = node() as? ChatBottomLoaderNode else { return }
            let layout = itemNode.asyncLayout()
            async {
                let (nodeLayout, apply) = layout(params)
                Queue.mainQueue().async {
                    completion(nodeLayout, { _ in apply() })
                }
            }
        }
    }

    func selected(listView: ListView) {}
}

final class ChatBottomLoaderNode: ListViewItemNode {

    private let indicatorHost = ASDisplayNode()
    static let rowHeight: CGFloat = 28
    private static let indicatorSide: CGFloat = 18

    init() {
        super.init(layerBacked: false, rotated: true)
        self.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
        let t = UIColor.theme
        indicatorHost.setViewBlock {
            let v = UIActivityIndicatorView(style: .medium)
            v.hidesWhenStopped = false
            v.color = t.iconPrimary
            v.startAnimating()
            return v
        }
        addSubnode(indicatorHost)
    }

    func asyncLayout() -> (ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] params in
            let width = params.width
            let height = ChatBottomLoaderNode.rowHeight
            let nodeLayout = ListViewItemNodeLayout(
                contentSize: CGSize(width: width, height: height),
                insets: UIEdgeInsets()
            )
            return (nodeLayout, {
                guard let self else { return }
                let s = ChatBottomLoaderNode.indicatorSide
                self.indicatorHost.frame = CGRect(x: (width - s) / 2, y: (height - s) / 2, width: s, height: s)
                if let indicator = self.indicatorHost.view as? UIActivityIndicatorView {
                    indicator.startAnimating()
                }
            })
        }
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, removeOnCompletion: false)
        self.layer.animateScale(from: 1.0, to: 0.6, duration: duration, removeOnCompletion: false)
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: duration)
    }
}
