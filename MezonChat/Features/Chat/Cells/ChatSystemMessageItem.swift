import AsyncDisplayKit
import UIKit

final class ChatSystemMessageItem: ListViewItem {

    let display: ChatMessageDisplay
    let interaction: ChatInteraction

    var selectable: Bool { false }
    var approximateHeight: CGFloat { 50 }

    init(display: ChatMessageDisplay, interaction: ChatInteraction) {
        self.display = display
        self.interaction = interaction
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatSystemMessageItemNode()
            let layout = node.asyncLayout()
            let (nodeLayout, apply) = layout(self, params)

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
            guard let itemNode = node() as? ChatSystemMessageItemNode else { return }
            let layout = itemNode.asyncLayout()
            async {
                let (nodeLayout, apply) = layout(self, params)
                Queue.mainQueue().async {
                    completion(nodeLayout, { _ in apply() })
                }
            }
        }
    }

    func selected(listView: ListView) {}
}

final class ChatSystemMessageItemNode: ListViewItemNode {

    private var systemNode: MessageSystemNode?

    init() {
        super.init(layerBacked: false, rotated: true)
        self.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
    }

    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, previousItem: ListViewItem?, nextItem: ListViewItem?) {
        guard let sysItem = item as? ChatSystemMessageItem else { return }
        let layout = asyncLayout()
        let (nodeLayout, apply) = layout(sysItem, params)
        self.contentSize = nodeLayout.contentSize
        self.insets = nodeLayout.insets
        apply()
    }

    func asyncLayout() -> (ChatSystemMessageItem, ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params in
            let width = params.width
            let node = MessageSystemNode(display: item.display, interaction: item.interaction)
            let measuredSize = node.measureSize(width: width)

            let nodeLayout = ListViewItemNodeLayout(
                contentSize: CGSize(width: width, height: measuredSize.height),
                insets: UIEdgeInsets()
            )

            return (nodeLayout, {
                guard let self else { return }
                self.systemNode?.removeFromSupernode()
                self.addSubnode(node)
                self.systemNode = node
                node.frame = CGRect(origin: .zero, size: measuredSize)
            })
        }
    }
}
