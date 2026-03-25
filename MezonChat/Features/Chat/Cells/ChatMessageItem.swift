import AsyncDisplayKit
import UIKit

final class ChatMessageItem: ListViewItem {

    let display: ChatMessageDisplay
    let interaction: ChatInteraction

    var selectable: Bool { false }
    var approximateHeight: CGFloat { display.isCombine ? 60 : 100 }

    init(display: ChatMessageDisplay, interaction: ChatInteraction) {
        self.display = display
        self.interaction = interaction
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = ChatMessageItemNode()
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
            guard let itemNode = node() as? ChatMessageItemNode else { return }
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

final class ChatMessageItemNode: ListViewItemNode {

    private var bubbleNode: MessageBubbleNode?
    private var currentItem: ChatMessageItem?

    init() {
        super.init(layerBacked: false, rotated: true)
        self.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
    }

    override func layoutForParams(_ params: ListViewItemLayoutParams, item: ListViewItem, previousItem: ListViewItem?, nextItem: ListViewItem?) {
        guard let chatItem = item as? ChatMessageItem else { return }
        let layout = asyncLayout()
        let (nodeLayout, apply) = layout(chatItem, params)
        self.contentSize = nodeLayout.contentSize
        self.insets = nodeLayout.insets
        apply()
    }

    func asyncLayout() -> (ChatMessageItem, ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        let currentBubble = self.bubbleNode

        return { [weak self] item, params in
            let width = params.width
            let bubble: MessageBubbleNode
            if let existing = currentBubble, existing.display.id == item.display.id {
                if existing.display.reactions == item.display.reactions
                    && existing.display.sendingState == item.display.sendingState {
                    bubble = existing
                } else if existing.display.sendingState == item.display.sendingState {
                    existing.updateReactions(newDisplay: item.display)
                    bubble = existing
                } else {
                    bubble = MessageBubbleNode(display: item.display, interaction: item.interaction)
                }
            } else {
                bubble = MessageBubbleNode(display: item.display, interaction: item.interaction)
            }

            let constrainedSize = CGSize(width: width, height: .greatestFiniteMagnitude)
            let measuredSize = bubble.measureSize(width: width)

            let nodeLayout = ListViewItemNodeLayout(
                contentSize: CGSize(width: width, height: measuredSize.height),
                insets: UIEdgeInsets()
            )

            return (nodeLayout, {
                guard let self else { return }
                self.currentItem = item
                if self.bubbleNode !== bubble {
                    self.bubbleNode?.removeFromSupernode()
                    self.addSubnode(bubble)
                    self.bubbleNode = bubble
                }
                bubble.frame = CGRect(origin: .zero, size: measuredSize)
            })
        }
    }
}
