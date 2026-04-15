import AsyncDisplayKit
import UIKit

private enum VoiceReactionPickerSheetLayout {
    static let heightFraction: CGFloat = 0.5
    static let bottomChrome: CGFloat = 16
    static let minBody: CGFloat = 120

    static func sheetHeight(layout: ContainerViewLayout, handleH: CGFloat) -> CGFloat {
        let safeBottom = layout.intrinsicInsets.bottom
        let sheetCap = layout.size.height * heightFraction
        let rawBody = sheetCap - handleH - safeBottom - bottomChrome
        let bodyH = max(minBody, rawBody)
        return handleH + bodyH + safeBottom + bottomChrome
    }
}

final class ReactionEmojiPickerSheetController: ViewController {

    private let engine: MezonEngine
    private let dismissOnEmojiSelect: Bool
    private let onEmojiPicked: (String, String) -> Void
    var onDismiss: (() -> Void)?

    private var sheetNode: ReactionEmojiPickerSheetNode {
        displayNode as! ReactionEmojiPickerSheetNode
    }

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

private final class ReactionEmojiPickerSheetNode: ASDisplayNode {

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
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let screenW = layout.size.width
        let h = VoiceReactionPickerSheetLayout.sheetHeight(layout: layout, handleH: handleH)
        containerHeight = h
        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))
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
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight
        containerNode.frame = CGRect(x: 0, y: fromY, width: layout.size.width, height: containerHeight)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame = CGRect(x: 0, y: toY, width: layout.size.width, height: self.containerHeight)
            self.containerNode.view.layoutIfNeeded()
            self.emojisPanel.layoutIfNeeded()
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

final class ReactionSoundStickerPickerSheetController: ViewController {

    private let engine: MezonEngine
    private let dismissOnStickerSelect: Bool
    private let onStickerPicked: (CachedClanStickerRecord) -> Void
    var onDismiss: (() -> Void)?

    private var sheetNode: ReactionSoundStickerPickerSheetNode {
        displayNode as! ReactionSoundStickerPickerSheetNode
    }

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

        stickersPanel.translatesAutoresizingMaskIntoConstraints = false
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

        NSLayoutConstraint.activate([
            stickersPanel.topAnchor.constraint(equalTo: containerNode.view.topAnchor, constant: handleH),
            stickersPanel.leadingAnchor.constraint(equalTo: containerNode.view.leadingAnchor),
            stickersPanel.trailingAnchor.constraint(equalTo: containerNode.view.trailingAnchor),
            stickersPanel.bottomAnchor.constraint(equalTo: containerNode.view.bottomAnchor),
        ])
    }

    @objc private func dimTapped() {
        onDimTapped()
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        let bounds = CGRect(origin: .zero, size: layout.size)
        let screenW = layout.size.width
        let h = VoiceReactionPickerSheetLayout.sheetHeight(layout: layout, handleH: handleH)
        containerHeight = h
        let containerY = layout.size.height - containerHeight
        transition.updateFrame(node: dimmingNode, frame: bounds)
        transition.updateFrame(node: containerNode, frame: CGRect(x: 0, y: containerY, width: screenW, height: containerHeight))
        transition.updateFrame(node: handleNode, frame: CGRect(x: (screenW - 36) / 2, y: 8, width: 36, height: 5))
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
        let fromY = layout.size.height
        let toY = layout.size.height - containerHeight
        containerNode.frame = CGRect(x: 0, y: fromY, width: layout.size.width, height: containerHeight)
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            self.dimmingNode.alpha = 1
            self.containerNode.frame = CGRect(x: 0, y: toY, width: layout.size.width, height: self.containerHeight)
            self.containerNode.view.layoutIfNeeded()
            self.stickersPanel.layoutIfNeeded()
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
