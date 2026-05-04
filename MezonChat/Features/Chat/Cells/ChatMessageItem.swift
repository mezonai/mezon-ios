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

final class ChatMessageItemNode: ListViewItemNode, UIGestureRecognizerDelegate {

    private var bubbleNode: MessageBubbleNode?
    private var currentItem: ChatMessageItem?

    private var panGesture: UIPanGestureRecognizer?
    private var swipeReplyIcon: UIImageView?
    private var swipeStartX: CGFloat = 0
    private static let swipeThreshold: CGFloat = 80
    private var hasTriggeredReply = false

    init() {
        super.init(layerBacked: false, rotated: true)
        self.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
    }

    override func didLoad() {
        super.didLoad()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSwipePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        panGesture = pan

        var responder: UIResponder? = view
        while let next = responder?.next {
            if let vc = next as? UIViewController,
               let popGesture = vc.navigationController?.interactivePopGestureRecognizer {
                pan.require(toFail: popGesture)
                break
            }
            responder = next
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        let velocity = pan.velocity(in: view)
        guard velocity.x < 0,
              abs(velocity.x) > abs(velocity.y) * 1.5 else { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGesture {
            return false
        }
        return true
    }

    @objc private func handleSwipePan(_ pan: UIPanGestureRecognizer) {
        guard let item = currentItem else { return }
        let translation = pan.translation(in: view)

        switch pan.state {
        case .began:
            swipeStartX = 0
            hasTriggeredReply = false
            showSwipeReplyIcon()

        case .changed:
            let offset = min(0, translation.x)
            let clampedOffset = max(offset, -Self.swipeThreshold - 20)
            bubbleNode?.view.transform = CGAffineTransform(translationX: clampedOffset, y: 0)
            updateSwipeReplyIcon(offset: clampedOffset)

            if abs(clampedOffset) >= Self.swipeThreshold && !hasTriggeredReply {
                hasTriggeredReply = true
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }

        case .ended, .cancelled:
            let didSwipeEnough = hasTriggeredReply
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.bubbleNode?.view.transform = .identity
                self.swipeReplyIcon?.alpha = 0
            } completion: { _ in
                self.swipeReplyIcon?.removeFromSuperview()
                self.swipeReplyIcon = nil
            }
            if didSwipeEnough {
                item.interaction.onSwipeReply(item.display)
            }

        default:
            break
        }
    }

    private func showSwipeReplyIcon() {
        let icon = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        icon.image = UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: config)
        icon.tintColor = UIColor.theme.textDisabled
        icon.alpha = 0
        icon.frame = CGRect(x: bounds.width - 40, y: bounds.height / 2 - 15, width: 30, height: 30)
        view.addSubview(icon)
        swipeReplyIcon = icon
    }

    private func updateSwipeReplyIcon(offset: CGFloat) {
        let progress = min(abs(offset) / Self.swipeThreshold, 1.0)
        swipeReplyIcon?.alpha = progress
        let iconX = bounds.width + offset - 40
        swipeReplyIcon?.frame.origin.x = max(iconX, bounds.width - Self.swipeThreshold - 10)
        if progress >= 1.0 {
            swipeReplyIcon?.tintColor = UIColor.theme.bgViolet
        } else {
            swipeReplyIcon?.tintColor = UIColor.theme.textDisabled
        }
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
        return { [weak self] item, params in
            let width = params.width
            let bubble: MessageBubbleNode
            let existingBubble = self?.bubbleNode
            let isSameLogicalMessage: Bool = {
                guard let existing = existingBubble else { return false }
                if existing.display.id == item.display.id { return true }
                let wasPending = existing.display.id.hasPrefix("pending-")
                let isNowReal = !item.display.id.hasPrefix("pending-")
                return wasPending && isNowReal
                    && existing.display.message.senderId == item.display.message.senderId
            }()

            let attachmentsChanged: Bool = {
                guard let existing = existingBubble, isSameLogicalMessage else { return false }
                return existing.display.attachments != item.display.attachments
            }()

            if let existing = existingBubble, isSameLogicalMessage, !attachmentsChanged {
                if existing.display.sendingState == item.display.sendingState,
                   existing.display.id == item.display.id {
                    let editedA = existing.display.message.editedAt?.timeIntervalSince1970
                    let editedB = item.display.message.editedAt?.timeIntervalSince1970
                    let bodyUnchanged = existing.display.parsedContent.text == item.display.parsedContent.text
                        && editedA == editedB
                        && existing.display.pollData?.totalVotes == item.display.pollData?.totalVotes
                        && existing.display.pollData?.answerCounts == item.display.pollData?.answerCounts
                    if bodyUnchanged {
                        existing.updateReactions(newDisplay: item.display)
                        bubble = existing
                    } else {
                        existing.updateDisplay(item.display)
                        bubble = existing
                    }
                } else {
                    existing.updateDisplay(item.display)
                    bubble = existing
                }
            } else {
                bubble = MessageBubbleNode(display: item.display, interaction: item.interaction)
            }

            _ = CGSize(width: width, height: .greatestFiniteMagnitude)
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
