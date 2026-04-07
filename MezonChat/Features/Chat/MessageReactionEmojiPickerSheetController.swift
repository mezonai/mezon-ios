import AsyncDisplayKit
import UIKit

final class MessageReactionEmojiPickerSheetController: ViewController {

    private let engine: MezonEngine
    private let onEmojiPicked: (String, String) -> Void
    var onDismiss: (() -> Void)?

    private var sheetNode: MessageReactionEmojiPickerSheetNode {
        displayNode as! MessageReactionEmojiPickerSheetNode
    }

    init(engine: MezonEngine, onEmojiPicked: @escaping (String, String) -> Void) {
        self.engine = engine
        self.onEmojiPicked = onEmojiPicked
        super.init(navigationBarPresentationData: nil)
        statusBar.statusBarStyle = .Hide
        blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = MessageReactionEmojiPickerSheetNode(
            engine: engine,
            onEmojiSelected: { [weak self] id, shortname in
                guard let self else { return }
                self.onEmojiPicked(id, shortname)
                self.animateDismiss(completion: nil)
            },
            onDimTapped: { [weak self] in self?.animateDismiss(completion: nil) }
        )
        displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        sheetNode.updateLayout(layout: layout, transition: transition)
    }

    func animateIn() {
        sheetNode.animateIn()
    }

    private func animateDismiss(completion: (() -> Void)?) {
        sheetNode.animateOut { [weak self] in
            self?.dismiss(animated: false)
            self?.onDismiss?()
            completion?()
        }
    }
}

private final class MessageReactionEmojiPickerSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {

    private let engine: MezonEngine
    private let onEmojiSelected: (String, String) -> Void
    private let onDimTapped: () -> Void

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let emojisPanel = EmojisPanel()

    private var panGesture: UIPanGestureRecognizer!
    private var panStartY: CGFloat = 0
    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private let handleH: CGFloat = 25

    init(engine: MezonEngine, onEmojiSelected: @escaping (String, String) -> Void, onDimTapped: @escaping () -> Void) {
        self.engine = engine
        self.onEmojiSelected = onEmojiSelected
        self.onDimTapped = onDimTapped
        super.init()

        dimmingNode.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimmingNode.alpha = 0

        let t = UIColor.theme
        containerNode.backgroundColor = t.secondary
        containerNode.cornerRadius = 14
        containerNode.clipsToBounds = true
        handleNode.backgroundColor = t.textDisabled.withAlphaComponent(0.55)
        handleNode.cornerRadius = 2.5

        addSubnode(dimmingNode)
        addSubnode(containerNode)
        containerNode.addSubnode(handleNode)

        emojisPanel.translatesAutoresizingMaskIntoConstraints = false
        emojisPanel.searchPlaceholderText = "Find the perfect reaction"
        emojisPanel.onEmojiSelected = { [weak self] id, sn in
            self?.onEmojiSelected(id, sn)
        }
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerNode.view.addSubview(emojisPanel)
        emojisPanel.bindEmojiCache(engine: engine)
        emojisPanel.applyTheme(placement: .secondaryBottomSheet)

        NSLayoutConstraint.activate([
            emojisPanel.topAnchor.constraint(equalTo: containerNode.view.topAnchor, constant: handleH),
            emojisPanel.leadingAnchor.constraint(equalTo: containerNode.view.leadingAnchor),
            emojisPanel.trailingAnchor.constraint(equalTo: containerNode.view.trailingAnchor),
            emojisPanel.bottomAnchor.constraint(equalTo: containerNode.view.bottomAnchor),
        ])

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
        emojisPanel.requireSheetDismissPanGetsPriority(panGesture)
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        switch gesture.state {
        case .began:
            panStartY = containerNode.frame.origin.y
        case .changed:
            let offsetY = max(0, translation.y)
            containerNode.frame.origin.y = panStartY + offsetY
            dimmingNode.alpha = 1 - offsetY / max(containerHeight, 1)
        case .ended, .cancelled:
            if translation.y > containerHeight * 0.3 || velocity.y > 500 {
                onDimTapped()
            } else {
                let targetY = layout.size.height - containerHeight
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
                    self.containerNode.frame.origin.y = targetY
                    self.dimmingNode.alpha = 1
                }
            }
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return true }
        let vel = panGesture.velocity(in: view)
        return emojisPanel.isEmojiGridScrolledToTop && vel.y > 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let safeBottom = layout.intrinsicInsets.bottom
        let screenW = layout.size.width
        let maxBody = layout.size.height * 0.68
        let bodyH = max(280, maxBody - handleH)
        containerHeight = handleH + bodyH + safeBottom + 8
        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))
    }

    func animateIn() {
        guard let layout = validLayout else { return }
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight
        containerNode.frame.origin.y = fromY
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame.origin.y = toY
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else {
            completion()
            return
        }
        let bottomY = layout.size.height
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingNode.alpha = 0
            self.containerNode.frame.origin.y = bottomY
        }) { _ in
            completion()
        }
    }
}
