import AsyncDisplayKit
import UIKit

final class ChatMessageItem: ListViewItem {

    let display: ChatMessageDisplay
    let interaction: ChatInteraction

    let relayoutVersion: Int
    
    var selectable: Bool { false }
    var approximateHeight: CGFloat { display.isCombine ? 60 : 100 }
    
    init(display: ChatMessageDisplay, interaction: ChatInteraction, relayoutVersion: Int = 0) {
        self.display = display
        self.interaction = interaction
        self.relayoutVersion = relayoutVersion
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
    
    func isEqual(to other: ListViewItem) -> Bool {
        guard let other = other as? ChatMessageItem else { return false }
        return self.display.id == other.display.id
            && self.display.message.senderId == other.display.message.senderId
            && self.display.message.createdAt == other.display.message.createdAt
            && self.display.message.editedAt == other.display.message.editedAt
            && self.display.senderDisplayName == other.display.senderDisplayName
            && self.display.avatarURL == other.display.avatarURL
            && self.display.isCombine == other.display.isCombine
            && self.display.isMe == other.display.isMe
            && self.display.sendingState == other.display.sendingState
            && self.display.showsSendingFeedback == other.display.showsSendingFeedback
            && self.display.hasIncludeMention == other.display.hasIncludeMention
            && self.display.isForward == other.display.isForward
            && self.display.showForwardHeader == other.display.showForwardHeader
            && self.display.messageCode == other.display.messageCode
            && self.display.topicData == other.display.topicData
            && self.display.clanInviteLinkCode == other.display.clanInviteLinkCode
            && self.display.parsedContent.text == other.display.parsedContent.text
            && self.display.attachments == other.display.attachments
            && self.display.reactions == other.display.reactions
            && (self.display.replyRef != nil) == (other.display.replyRef != nil)
            && self.display.isDeletedReply == other.display.isDeletedReply
            && self.display.pollData?.totalVotes == other.display.pollData?.totalVotes
            && self.display.pollData?.answerCounts == other.display.pollData?.answerCounts
            && self.relayoutVersion == other.relayoutVersion
            && self.display.parsedContent.embeds == other.display.parsedContent.embeds
            && self.display.parsedContent.ogpPreviews == other.display.parsedContent.ogpPreviews
    }
}

final class ChatMessageItemNode: ListViewItemNode, UIGestureRecognizerDelegate {

    private static func isBodyPresentationStable(existing: ChatMessageDisplay, item: ChatMessageDisplay) -> Bool {
        let editedA = existing.message.editedAt?.timeIntervalSince1970
        let editedB = item.message.editedAt?.timeIntervalSince1970
        return existing.parsedContent.text == item.parsedContent.text
            && editedA == editedB
            && existing.pollData?.totalVotes == item.pollData?.totalVotes
            && existing.pollData?.answerCounts == item.pollData?.answerCounts
            && existing.parsedContent.embeds == item.parsedContent.embeds
            && existing.parsedContent.ogpPreviews == item.parsedContent.ogpPreviews
            && existing.messageCode == item.messageCode
            && existing.topicData == item.topicData
            && existing.reactions == item.reactions
            && existing.sendingState == item.sendingState
            && existing.showsSendingFeedback == item.showsSendingFeedback
    }

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
                if existing.display.isCombine != item.display.isCombine { return false }
                if existing.display.id == item.display.id { return true }
                let wasPending = existing.display.id.hasPrefix("pending-")
                let isNowReal = !item.display.id.hasPrefix("pending-")
                return wasPending && isNowReal
                    && existing.display.message.senderId == item.display.message.senderId
            }()

            let attachmentsChanged: Bool = {
                guard let existing = existingBubble, isSameLogicalMessage else { return false }
                return ParsedAttachment.attachmentsRequireBubbleRebuild(
                    existing.display.attachments, item.display.attachments)
            }()

            let uploadPresentationChanged: Bool = {
                guard let existing = existingBubble, isSameLogicalMessage else { return false }
                return !ParsedAttachment.attachmentsUploadStateEqual(
                    existing.display.attachments, item.display.attachments)
            }()

            let incrementalMediaPresentation: Bool = {
                guard let existing = existingBubble, isSameLogicalMessage else { return false }
                return ParsedAttachment.attachmentsIdentityEqual(
                    existing.display.attachments, item.display.attachments)
            }()

            let mediaPresentationDelta = uploadPresentationChanged
                || (incrementalMediaPresentation && attachmentsChanged)

            let bodyPresentationStable: Bool = {
                guard let existing = existingBubble else { return false }
                return Self.isBodyPresentationStable(existing: existing.display, item: item.display)
            }()

            var skipMeasureSize = false
            if let existing = existingBubble, isSameLogicalMessage {
                if incrementalMediaPresentation && mediaPresentationDelta && bodyPresentationStable {
                    skipMeasureSize = !existing.updateMediaPresentation(item.display)
                    bubble = existing
                } else if !attachmentsChanged {
                    if existing.display.sendingState == item.display.sendingState,
                       existing.display.showsSendingFeedback == item.display.showsSendingFeedback,
                       existing.display.id == item.display.id {
                        let bodyUnchanged = Self.isBodyPresentationStable(existing: existing.display, item: item.display)
                            && existing.display.rawContentData == item.display.rawContentData
                        if bodyUnchanged && !uploadPresentationChanged {
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
                    existing.updateDisplay(item.display)
                    bubble = existing
                }
            } else {
                bubble = MessageBubbleNode(display: item.display, interaction: item.interaction)
            }

            let measuredSize: CGSize
            if skipMeasureSize,
               bubble.layoutContentSize.height > 0,
               abs(bubble.layoutContentSize.width - width) < 0.5 {
                measuredSize = bubble.layoutContentSize
            } else {
                measuredSize = bubble.measureSize(width: width)
            }
            
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
