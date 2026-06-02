import AsyncDisplayKit
import UIKit

private enum VoiceReactionPickerSheetLayout {
    static let defaultSheetFraction: CGFloat = 0.78
    static let bottomChrome: CGFloat = 16
    static let minBody: CGFloat = 120

    static func sheetHeight(layout: ContainerViewLayout, handleH: CGFloat, fraction: CGFloat) -> CGFloat {
        let kb = layout.inputHeight ?? 0
        let safeBottom = layout.intrinsicInsets.bottom
        let visibleH = layout.size.height - kb
        let sheetCap = max(0, visibleH * fraction)
        let rawBody = sheetCap - handleH - safeBottom - bottomChrome
        let bodyH = max(minBody, rawBody)
        let uncapped = handleH + bodyH + safeBottom + bottomChrome
        if visibleH > 0 {
            return min(uncapped, visibleH)
        }
        return uncapped
    }
}

class ReactionEmojiPickerSheetController: ViewController {

    private let engine: MezonEngine
    private let dismissOnEmojiSelect: Bool
    private let onEmojiPicked: (String, String) -> Void
    var onDismiss: (() -> Void)?

    private var sheetNode: ReactionEmojiPickerSheetNode {
        displayNode as! ReactionEmojiPickerSheetNode
    }

    override var overlayWantsToBeBelowKeyboard: Bool { true }

    init(engine: MezonEngine, dismissOnEmojiSelect: Bool = true, onEmojiPicked: @escaping (String, String) -> Void) {
        self.engine = engine
        self.dismissOnEmojiSelect = dismissOnEmojiSelect
        self.onEmojiPicked = onEmojiPicked
        super.init(navigationBarPresentationData: nil)
        statusBar.statusBarStyle = .Ignore
        blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ReactionEmojiPickerSheetNode(
            engine: engine,
            onEmojiSelected: { [weak self] id, shortname in
                guard let self else { return }
                self.onEmojiPicked(id, shortname)
                if self.dismissOnEmojiSelect {
                    self.animateDismiss(completion: nil)
                }
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

private final class ReactionEmojiPickerSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {

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

    private var emojiListObserver: NSObjectProtocol?
    private var emojiPanelHostingConstraints: [NSLayoutConstraint] = []

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

        emojiListObserver = NotificationCenter.default.addObserver(
            forName: .mezonEmojiListDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.emojisPanel.reloadFromPostboxCache()
            self.emojisPanel.logEmojiLoadingState(tag: Notification.Name.mezonEmojiListDidUpdate.rawValue)
            self.syncHostedPanelFrame()
        }
        emojisPanel.logEmojiLoadingState(tag: "didLoadAfterBind")
        syncHostedPanelFrame()
        
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
    }

    deinit {
        if let emojiListObserver {
            NotificationCenter.default.removeObserver(emojiListObserver)
        }
    }

    override func layout() {
        super.layout()
        syncHostedPanelFrame()
    }

    private func installEmojiPanelHostingConstraintsIfNeeded() {
        guard emojiPanelHostingConstraints.isEmpty,
              emojisPanel.superview === containerNode.view else { return }
        emojisPanel.translatesAutoresizingMaskIntoConstraints = false
        let cs = [
            emojisPanel.topAnchor.constraint(equalTo: containerNode.view.topAnchor, constant: handleH),
            emojisPanel.leadingAnchor.constraint(equalTo: containerNode.view.leadingAnchor),
            emojisPanel.trailingAnchor.constraint(equalTo: containerNode.view.trailingAnchor),
            emojisPanel.bottomAnchor.constraint(equalTo: containerNode.view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(cs)
        emojiPanelHostingConstraints = cs
    }

    private func syncHostedPanelFrame() {
        guard emojisPanel.superview === containerNode.view else { return }
        installEmojiPanelHostingConstraintsIfNeeded()
        containerNode.view.setNeedsLayout()
        containerNode.view.layoutIfNeeded()
        emojisPanel.notifyEmbeddedPanelBoundsChanged()
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    private func sheetHeight(for layout: ContainerViewLayout) -> CGFloat {
        VoiceReactionPickerSheetLayout.sheetHeight(
            layout: layout,
            handleH: handleH,
            fraction: VoiceReactionPickerSheetLayout.defaultSheetFraction
        )
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let screenW = layout.size.width
        let sh = sheetHeight(for: layout)
        containerHeight = sh
        let kb = layout.inputHeight ?? 0
        let containerY = layout.size.height - kb - sh
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: sh))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))
        syncHostedPanelFrame()
    }

    private var animateInRetryCount = 0

    func animateIn() {
        guard let layout = validLayout else {
            animateInRetryCount += 1
            guard animateInRetryCount < 90 else {
                animateInRetryCount = 0
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.animateIn()
            }
            return
        }
        animateInRetryCount = 0
        let sh = sheetHeight(for: layout)
        containerHeight = sh
        emojisPanel.reloadFromPostboxCache()
        emojisPanel.logEmojiLoadingState(tag: "animateIn")
        let kb = layout.inputHeight ?? 0
        let fromY = layout.size.height
        let toY = layout.size.height - sh - kb
        containerNode.frame = CGRect(x: 0, y: fromY, width: layout.size.width, height: sh)
        syncHostedPanelFrame()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [], animations: {
            self.dimmingNode.alpha = 1
            self.containerNode.frame = CGRect(x: 0, y: toY, width: layout.size.width, height: sh)
            self.syncHostedPanelFrame()
        }, completion: { _ in
            self.syncHostedPanelFrame()
        })
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
        guard gestureRecognizer === panGesture else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let vel = panGesture.velocity(in: view)
        return vel.y > 0
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGesture, let scrollView = otherGestureRecognizer.view as? UIScrollView {
            if scrollView.contentOffset.y <= 0 {
                return true
            }
            return false
        }
        return false
    }
}

class ReactionSoundStickerPickerSheetController: ViewController {

    private let engine: MezonEngine
    private let dismissOnStickerSelect: Bool
    private let onStickerPicked: (CachedClanStickerRecord) -> Void
    var onDismiss: (() -> Void)?

    private var sheetNode: ReactionSoundStickerPickerSheetNode {
        displayNode as! ReactionSoundStickerPickerSheetNode
    }

    override var overlayWantsToBeBelowKeyboard: Bool { true }

    init(engine: MezonEngine, dismissOnStickerSelect: Bool = true, onStickerPicked: @escaping (CachedClanStickerRecord) -> Void) {
        self.engine = engine
        self.dismissOnStickerSelect = dismissOnStickerSelect
        self.onStickerPicked = onStickerPicked
        super.init(navigationBarPresentationData: nil)
        statusBar.statusBarStyle = .Ignore
        blocksBackgroundWhenInOverlay = true
    }

    required init(coder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = ReactionSoundStickerPickerSheetNode(
            engine: engine,
            onStickerSelected: { [weak self] sticker in
                guard let self else { return }
                self.onStickerPicked(sticker)
                if self.dismissOnStickerSelect {
                    self.animateDismiss(completion: nil)
                }
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

private final class ReactionSoundStickerPickerSheetNode: ASDisplayNode {

    private let engine: MezonEngine
    private let onStickerSelected: (CachedClanStickerRecord) -> Void
    private let onDimTapped: () -> Void

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let stickersPanel = StickersPanel()

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private let handleH: CGFloat = 25
    private var stickerPanelHostingConstraints: [NSLayoutConstraint] = []

    init(engine: MezonEngine, onStickerSelected: @escaping (CachedClanStickerRecord) -> Void, onDimTapped: @escaping () -> Void) {
        self.engine = engine
        self.onStickerSelected = onStickerSelected
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

        stickersPanel.searchPlaceholderText = "Find sound sticker"
        stickersPanel.onStickerSelected = { [weak self] sticker in
            self?.onStickerSelected(sticker)
        }
    }

    override func didLoad() {
        super.didLoad()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimmingNode.view.addGestureRecognizer(tap)

        containerNode.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        containerNode.view.addSubview(stickersPanel)
        stickersPanel.bindStickerCache(engine: engine)
        stickersPanel.configureVoiceReactionSoundOnlyLayout(true)
        stickersPanel.applyTheme(placement: .secondaryBottomSheet)

        syncHostedPanelFrame()
    }

    override func layout() {
        super.layout()
        syncHostedPanelFrame()
    }

    private func installStickerPanelHostingConstraintsIfNeeded() {
        guard stickerPanelHostingConstraints.isEmpty,
              stickersPanel.superview === containerNode.view else { return }
        stickersPanel.translatesAutoresizingMaskIntoConstraints = false
        let cs = [
            stickersPanel.topAnchor.constraint(equalTo: containerNode.view.topAnchor, constant: handleH),
            stickersPanel.leadingAnchor.constraint(equalTo: containerNode.view.leadingAnchor),
            stickersPanel.trailingAnchor.constraint(equalTo: containerNode.view.trailingAnchor),
            stickersPanel.bottomAnchor.constraint(equalTo: containerNode.view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(cs)
        stickerPanelHostingConstraints = cs
    }

    private func syncHostedPanelFrame() {
        guard stickersPanel.superview === containerNode.view else { return }
        installStickerPanelHostingConstraintsIfNeeded()
        containerNode.view.setNeedsLayout()
        containerNode.view.layoutIfNeeded()
        stickersPanel.layoutIfNeeded()
        (stickersPanel.sheetPanCoordinationScrollView as? UICollectionView)?.collectionViewLayout.invalidateLayout()
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    private func sheetHeight(for layout: ContainerViewLayout) -> CGFloat {
        VoiceReactionPickerSheetLayout.sheetHeight(
            layout: layout,
            handleH: handleH,
            fraction: VoiceReactionPickerSheetLayout.defaultSheetFraction
        )
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let screenW = layout.size.width
        let sh = sheetHeight(for: layout)
        containerHeight = sh
        let kb = layout.inputHeight ?? 0
        let containerY = layout.size.height - kb - sh
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: sh))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))
        syncHostedPanelFrame()
    }

    private var animateInRetryCount = 0

    func animateIn() {
        guard let layout = validLayout else {
            animateInRetryCount += 1
            guard animateInRetryCount < 90 else {
                animateInRetryCount = 0
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.animateIn()
            }
            return
        }
        animateInRetryCount = 0
        let sh = sheetHeight(for: layout)
        containerHeight = sh
        let kb = layout.inputHeight ?? 0
        let fromY = layout.size.height
        let toY = layout.size.height - sh - kb
        containerNode.frame = CGRect(x: 0, y: fromY, width: layout.size.width, height: sh)
        syncHostedPanelFrame()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [], animations: {
            self.dimmingNode.alpha = 1
            self.containerNode.frame = CGRect(x: 0, y: toY, width: layout.size.width, height: sh)
            self.syncHostedPanelFrame()
        }, completion: { _ in
            self.syncHostedPanelFrame()
        })
    }

    func animateOut(completion: @escaping () -> Void) {
        guard let layout = validLayout else {
            completion()
            return
        }
        let bottomY = layout.size.height
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
            self.dimmingNode.alpha = 0
            self.containerNode.frame = CGRect(x: 0, y: bottomY, width: layout.size.width, height: self.containerHeight)
        }) { _ in
            completion()
        }
    }
}
