import AsyncDisplayKit
import UIKit

private enum VoiceReactionPickerSheetLayout {
    static let collapsedFraction: CGFloat = 0.5
    static let expandedFraction: CGFloat = 0.92
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
        statusBar.statusBarStyle = .Hide
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

    private enum SheetDetent {
        case collapsed
        case expanded
    }

    private let engine: MezonEngine
    private let onEmojiSelected: (String, String) -> Void
    private let onDimTapped: () -> Void

    private let dimmingNode = ASDisplayNode()
    private let containerNode = ASDisplayNode()
    private let handleNode = ASDisplayNode()
    private let emojisPanel = EmojisPanel()

    private var containerHeight: CGFloat = 0
    private var validLayout: ContainerViewLayout?
    private let handleH: CGFloat = 25
    private var detent: SheetDetent = .collapsed
    private var collapsedHeight: CGFloat = 0
    private var expandedHeight: CGFloat = 0
    private var displayedHeight: CGFloat = 0
    private var panGesture: UIPanGestureRecognizer!
    private var panStartDisplayedHeight: CGFloat = 0
    private var isDraggingSheet = false

    private var canResizeSheet: Bool { expandedHeight > collapsedHeight + 40 }

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

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
        emojisPanel.sheetPanCoordinationScrollView.panGestureRecognizer.require(toFail: panGesture)
        syncHostedPanelFrame()
    }

    override func layout() {
        super.layout()
        syncHostedPanelFrame()
    }

    private func syncHostedPanelFrame() {
        guard emojisPanel.superview === containerNode.view else { return }
        let w = containerNode.bounds.width
        let h = containerNode.bounds.height
        guard w > 0, h > handleH else { return }
        let panelH = h - handleH
        let r = CGRect(x: 0, y: handleH, width: w, height: panelH)
        if !emojisPanel.frame.equalTo(r) {
            emojisPanel.frame = r
            emojisPanel.layoutIfNeeded()
            (emojisPanel.sheetPanCoordinationScrollView as? UICollectionView)?.collectionViewLayout.invalidateLayout()
        }
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let kb = layout.inputHeight ?? 0
        let fullBottom = layout.size.height - kb
        let screenW = layout.size.width

        switch gesture.state {
        case .began:
            isDraggingSheet = true
            panStartDisplayedHeight = displayedHeight
        case .changed:
            var newH = panStartDisplayedHeight - translation.y
            let minH = collapsedHeight
            let maxH = expandedHeight
            var dismissPull: CGFloat = 0
            if newH < minH {
                dismissPull = minH - newH
                newH = minH
            } else if newH > maxH {
                newH = maxH
            }
            let newY = fullBottom - newH + dismissPull
            displayedHeight = newH
            containerHeight = newH
            containerNode.frame = CGRect(x: 0, y: newY, width: screenW, height: newH)
            syncHostedPanelFrame()
            if dismissPull > 0 {
                dimmingNode.alpha = max(0, 1 - dismissPull / max(minH * 0.45, 80))
            } else {
                dimmingNode.alpha = 1
            }
        case .ended, .cancelled:
            isDraggingSheet = false
            let baseCollapsedY = fullBottom - collapsedHeight
            let dismissThreshold = min(collapsedHeight * 0.28, 120)
            if containerNode.frame.origin.y > baseCollapsedY + dismissThreshold || velocity.y > 700 {
                onDimTapped()
                return
            }
            let mid = (collapsedHeight + expandedHeight) / 2
            if canResizeSheet {
                if velocity.y < -200 {
                    detent = .expanded
                } else if velocity.y > 200 {
                    detent = .collapsed
                } else {
                    detent = displayedHeight > mid ? .expanded : .collapsed
                }
            } else {
                detent = .collapsed
            }
            let targetH = detent == .expanded ? expandedHeight : collapsedHeight
            let targetY = fullBottom - targetH
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0, options: []) {
                self.displayedHeight = targetH
                self.containerHeight = targetH
                self.containerNode.frame = CGRect(x: 0, y: targetY, width: screenW, height: targetH)
                self.dimmingNode.alpha = 1
                self.syncHostedPanelFrame()
            }
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let vel = panGesture.velocity(in: containerNode.view)
        let p = panGesture.location(in: containerNode.view)
        let onHandleStrip = p.y < handleH + 14
        if onHandleStrip {
            return abs(vel.y) >= abs(vel.x)
        }
        guard abs(vel.y) > abs(vel.x) else { return false }
        let grid = emojisPanel.sheetPanCoordinationScrollView
        let topInset = grid.adjustedContentInset.top
        let atTop = grid.contentOffset.y <= -topInset + 1
        let eps: CGFloat = 6
        if vel.y < 0 {
            return canResizeSheet && displayedHeight < expandedHeight - eps
        }
        if vel.y > 0 {
            return atTop
        }
        return false
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let screenW = layout.size.width
        collapsedHeight = VoiceReactionPickerSheetLayout.sheetHeight(
            layout: layout, handleH: handleH, fraction: VoiceReactionPickerSheetLayout.collapsedFraction)
        expandedHeight = VoiceReactionPickerSheetLayout.sheetHeight(
            layout: layout, handleH: handleH, fraction: VoiceReactionPickerSheetLayout.expandedFraction)
        if expandedHeight <= collapsedHeight + 8 {
            expandedHeight = min(layout.size.height - (layout.inputHeight ?? 0), collapsedHeight + 120)
        }
        if !isDraggingSheet {
            displayedHeight = detent == .expanded ? expandedHeight : collapsedHeight
        } else {
            displayedHeight = min(max(displayedHeight, collapsedHeight), expandedHeight)
        }
        containerHeight = displayedHeight
        let kb = layout.inputHeight ?? 0
        let containerY = layout.size.height - kb - displayedHeight
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: displayedHeight))
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
        detent = .collapsed
        displayedHeight = collapsedHeight
        containerHeight = collapsedHeight
        let kb = layout.inputHeight ?? 0
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight - kb
        containerNode.frame = CGRect(x: 0, y: fromY, width: layout.size.width, height: containerHeight)
        syncHostedPanelFrame()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame = CGRect(x: 0, y: toY, width: layout.size.width, height: self.containerHeight)
            self.syncHostedPanelFrame()
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
            self.containerNode.frame = CGRect(x: 0, y: bottomY, width: layout.size.width, height: self.containerHeight)
        }) { _ in
            completion()
        }
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
        statusBar.statusBarStyle = .Hide
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

private final class ReactionSoundStickerPickerSheetNode: ASDisplayNode, UIGestureRecognizerDelegate {

    private enum SheetDetent {
        case collapsed
        case expanded
    }

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
    private var detent: SheetDetent = .collapsed
    private var collapsedHeight: CGFloat = 0
    private var expandedHeight: CGFloat = 0
    private var displayedHeight: CGFloat = 0
    private var panGesture: UIPanGestureRecognizer!
    private var panStartDisplayedHeight: CGFloat = 0
    private var isDraggingSheet = false

    private var canResizeSheet: Bool { expandedHeight > collapsedHeight + 40 }

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

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        containerNode.view.addGestureRecognizer(panGesture)
        stickersPanel.sheetPanCoordinationScrollView.panGestureRecognizer.require(toFail: panGesture)
        syncHostedPanelFrame()
    }

    override func layout() {
        super.layout()
        syncHostedPanelFrame()
    }

    private func syncHostedPanelFrame() {
        guard stickersPanel.superview === containerNode.view else { return }
        let w = containerNode.bounds.width
        let h = containerNode.bounds.height
        guard w > 0, h > handleH else { return }
        let panelH = h - handleH
        let r = CGRect(x: 0, y: handleH, width: w, height: panelH)
        if !stickersPanel.frame.equalTo(r) {
            stickersPanel.frame = r
            stickersPanel.layoutIfNeeded()
            (stickersPanel.sheetPanCoordinationScrollView as? UICollectionView)?.collectionViewLayout.invalidateLayout()
        }
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let layout = validLayout else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let kb = layout.inputHeight ?? 0
        let fullBottom = layout.size.height - kb
        let screenW = layout.size.width

        switch gesture.state {
        case .began:
            isDraggingSheet = true
            panStartDisplayedHeight = displayedHeight
        case .changed:
            var newH = panStartDisplayedHeight - translation.y
            let minH = collapsedHeight
            let maxH = expandedHeight
            var dismissPull: CGFloat = 0
            if newH < minH {
                dismissPull = minH - newH
                newH = minH
            } else if newH > maxH {
                newH = maxH
            }
            let newY = fullBottom - newH + dismissPull
            displayedHeight = newH
            containerHeight = newH
            containerNode.frame = CGRect(x: 0, y: newY, width: screenW, height: newH)
            syncHostedPanelFrame()
            if dismissPull > 0 {
                dimmingNode.alpha = max(0, 1 - dismissPull / max(minH * 0.45, 80))
            } else {
                dimmingNode.alpha = 1
            }
        case .ended, .cancelled:
            isDraggingSheet = false
            let baseCollapsedY = fullBottom - collapsedHeight
            let dismissThreshold = min(collapsedHeight * 0.28, 120)
            if containerNode.frame.origin.y > baseCollapsedY + dismissThreshold || velocity.y > 700 {
                onDimTapped()
                return
            }
            let mid = (collapsedHeight + expandedHeight) / 2
            if canResizeSheet {
                if velocity.y < -200 {
                    detent = .expanded
                } else if velocity.y > 200 {
                    detent = .collapsed
                } else {
                    detent = displayedHeight > mid ? .expanded : .collapsed
                }
            } else {
                detent = .collapsed
            }
            let targetH = detent == .expanded ? expandedHeight : collapsedHeight
            let targetY = fullBottom - targetH
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.92, initialSpringVelocity: 0, options: []) {
                self.displayedHeight = targetH
                self.containerHeight = targetH
                self.containerNode.frame = CGRect(x: 0, y: targetY, width: screenW, height: targetH)
                self.dimmingNode.alpha = 1
                self.syncHostedPanelFrame()
            }
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let vel = panGesture.velocity(in: containerNode.view)
        let p = panGesture.location(in: containerNode.view)
        let onHandleStrip = p.y < handleH + 14
        if onHandleStrip {
            return abs(vel.y) >= abs(vel.x)
        }
        guard abs(vel.y) > abs(vel.x) else { return false }
        let grid = stickersPanel.sheetPanCoordinationScrollView
        let topInset = grid.adjustedContentInset.top
        let atTop = grid.contentOffset.y <= -topInset + 1
        let eps: CGFloat = 6
        if vel.y < 0 {
            return canResizeSheet && displayedHeight < expandedHeight - eps
        }
        if vel.y > 0 {
            return atTop
        }
        return false
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let screenW = layout.size.width
        collapsedHeight = VoiceReactionPickerSheetLayout.sheetHeight(
            layout: layout, handleH: handleH, fraction: VoiceReactionPickerSheetLayout.collapsedFraction)
        expandedHeight = VoiceReactionPickerSheetLayout.sheetHeight(
            layout: layout, handleH: handleH, fraction: VoiceReactionPickerSheetLayout.expandedFraction)
        if expandedHeight <= collapsedHeight + 8 {
            expandedHeight = min(layout.size.height - (layout.inputHeight ?? 0), collapsedHeight + 120)
        }
        if !isDraggingSheet {
            displayedHeight = detent == .expanded ? expandedHeight : collapsedHeight
        } else {
            displayedHeight = min(max(displayedHeight, collapsedHeight), expandedHeight)
        }
        containerHeight = displayedHeight
        let kb = layout.inputHeight ?? 0
        let containerY = layout.size.height - kb - displayedHeight
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: displayedHeight))
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
        detent = .collapsed
        displayedHeight = collapsedHeight
        containerHeight = collapsedHeight
        let kb = layout.inputHeight ?? 0
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight - kb
        containerNode.frame = CGRect(x: 0, y: fromY, width: layout.size.width, height: containerHeight)
        syncHostedPanelFrame()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame = CGRect(x: 0, y: toY, width: layout.size.width, height: self.containerHeight)
            self.syncHostedPanelFrame()
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
            self.containerNode.frame = CGRect(x: 0, y: bottomY, width: layout.size.width, height: self.containerHeight)
        }) { _ in
            completion()
        }
    }
}
