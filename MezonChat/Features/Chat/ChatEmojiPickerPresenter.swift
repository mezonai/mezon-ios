import UIKit

final class ChatEmojiPickerPresenter {

    enum KeyboardWillShowOutcome {
        case searchAbsorbed
        case dismissedForKeyboard
        case unaffected
    }

    private(set) lazy var pickerView: PanelKeyboardView = makePickerView()

    private weak var hostView: UIView?
    private weak var sendInput: SendMessageInputViewController?

    private var heightConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    private(set) var collapsedHeight: CGFloat = 0
    private(set) var wasJustDismissed: Bool = false

    private static let panelOpenAnimationDuration: TimeInterval = 0.22
    private static let panelOpenSpringDamping: CGFloat = 0.94
    private static let panelSnapAnimationDuration: TimeInterval = 0.52

    private static let panelSnapSpringDamping: CGFloat = 0.86

    var panelHeightForChatLayout: CGFloat {
        heightConstraint?.constant ?? 0
    }

    var composerLayoutEmojiOffset: CGFloat {
        guard collapsedHeight > 0, !pickerView.isHidden else { return 0 }
        return collapsedHeight
    }

    var isEmojiPanelExpandedOverContent: Bool {
        guard collapsedHeight > 0, !pickerView.isHidden else { return false }
        return panelHeightForChatLayout > collapsedHeight + 1
    }

    var isEmojiPanelSearchConsumingKeyboard: Bool {
        guard !pickerView.isHidden, panelHeightForChatLayout > 0.5 else { return false }
        return pickerView.isPanelSearchFocused || pickerView.isSearchFieldActive
    }

    var onRequestRelayout: ((ContainedViewLayoutTransition) -> Void)?
    var onSetSuppressNextScrollToBottom: ((Bool) -> Void)?

    init(sendInput: SendMessageInputViewController) {
        self.sendInput = sendInput
    }

    func install(in hostView: UIView, engine: MezonEngine) {
        self.hostView = hostView
        let v = pickerView
        hostView.addSubview(v)
        let h = v.heightAnchor.constraint(equalToConstant: 0)
        let b = v.bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
        heightConstraint = h
        bottomConstraint = b
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            h,
            b,
        ])
        v.configureMediaPanelCache(engine: engine)
        v.applyTheme()
        v.ensureCurrentTabLoaded()
        DispatchQueue.main.async { [weak v] in
            v?.layoutIfNeeded()
        }
    }

    func bringToFront() {
        hostView?.bringSubviewToFront(pickerView)
    }

    func updateBottomInset(_ inset: CGFloat) {
        bottomConstraint?.constant = -inset
    }

    func clearJustDismissedFlag() {
        wasJustDismissed = false
    }

    func setVisible(_ visible: Bool, collapsedHeight: CGFloat) {
        if visible {
            onSetSuppressNextScrollToBottom?(false)
            let screenH = UIScreen.main.bounds.height
            let expandedH = Self.expandedPanelHeight(collapsedHeight: collapsedHeight, screenHeight: screenH)
            pickerView.collapsedHeight = collapsedHeight
            pickerView.expandedHeight = expandedH
            pickerView.resetToCollapsed()

            self.collapsedHeight = collapsedHeight
            heightConstraint?.constant = collapsedHeight
            pickerView.isHidden = false
            pickerView.applyThemeChrome()
            pickerView.ensureCurrentTabLoaded()
        } else {
            onSetSuppressNextScrollToBottom?(true)
            self.collapsedHeight = 0
            heightConstraint?.constant = 0
            pickerView.isHidden = true
            pickerView.resetToCollapsed()
        }

        let transition: ContainedViewLayoutTransition = visible
            ? .animated(duration: Self.panelOpenAnimationDuration, curve: .easeInOut)
            : .immediate
        onRequestRelayout?(transition)

        if visible {
            UIView.animate(
                withDuration: Self.panelOpenAnimationDuration,
                delay: 0,
                usingSpringWithDamping: Self.panelOpenSpringDamping,
                initialSpringVelocity: 1.0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
                animations: {
                    self.hostView?.layoutIfNeeded()
                }
            )
        } else {
            hostView?.layoutIfNeeded()
        }
    }

    func dismissSilently(markAsJustDismissed: Bool) {
        guard collapsedHeight > 0 else { return }
        if markAsJustDismissed { wasJustDismissed = true }
        collapsedHeight = 0
        heightConstraint?.constant = 0
        pickerView.isHidden = true
        pickerView.resetToCollapsed()
    }

    func updateOverlayHeight(_ newHeight: CGFloat, mode: PanelHeightUpdateMode) {
        let lo = pickerView.collapsedHeight
        let hi = pickerView.expandedHeight
        let clamped = min(max(newHeight, lo), hi)
        if mode == .snap {
            guard abs((heightConstraint?.constant ?? 0) - clamped) > 0.5 else { return }
        }
        heightConstraint?.constant = clamped
        bringToFront()

        let animateLayout = {
            self.hostView?.layoutIfNeeded()
            return ()
        }
        switch mode {
        case .interactive:
            animateLayout()
        case .snap:
            UIView.animate(
                withDuration: Self.panelSnapAnimationDuration,
                delay: 0,
                usingSpringWithDamping: Self.panelSnapSpringDamping,
                initialSpringVelocity: 0.5,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: animateLayout
            )
        }
    }

    private static func expandedPanelHeight(collapsedHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        min(max(screenHeight * 0.80, collapsedHeight + 200), screenHeight * 0.80)
    }

    func updateForSearchKeyboard() {
        guard collapsedHeight > 0, !pickerView.isHidden else { return }
        guard pickerView.isPanelSearchFocused || pickerView.isSearchFieldActive else { return }
        let screenH = UIScreen.main.bounds.height
        let panelH = Self.expandedPanelHeight(collapsedHeight: collapsedHeight, screenHeight: screenH)
        pickerView.expandedHeight = panelH
        pickerView.applySnapExpanded(height: panelH)
    }

    func handleKeyboardWillHide() {
        if collapsedHeight > 0 && !pickerView.isHidden {
            pickerView.applySnapCollapsed()
        }
    }

    func handleKeyboardWillShow() -> KeyboardWillShowOutcome {
        let searchFocused = pickerView.isPanelSearchFocused || pickerView.isSearchFieldActive
        if collapsedHeight > 0 && searchFocused {
            updateForSearchKeyboard()
            return .searchAbsorbed
        }
        if collapsedHeight > 0 {
            wasJustDismissed = true
            collapsedHeight = 0
            heightConstraint?.constant = 0
            pickerView.isHidden = true
            pickerView.resetToCollapsed()
            return .dismissedForKeyboard
        }
        return .unaffected
    }

    private func makePickerView() -> PanelKeyboardView {
        let v = PanelKeyboardView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.onEmojiSelected = { [weak self] emojiId, shortname in
            guard let send = self?.sendInput else { return }
            send.insertEmoji(emojiId, shortname: shortname)
            send.hideEmojiPickerIfNeeded()
            send.focusComposerAfterEmojiPanelSelection()
        }
        v.onStickerSelected = { [weak self] sticker in
            guard let send = self?.sendInput else { return }
            send.sendSticker(sticker)
            send.hideEmojiPickerIfNeeded()
            send.focusComposerAfterEmojiPanelSelection()
        }
        v.onGifSelected = { [weak self] url in
            guard let send = self?.sendInput else { return }
            send.sendGif(url: url)
            send.hideEmojiPickerIfNeeded()
            send.focusComposerAfterEmojiPanelSelection()
        }
        v.onHeightChanged = { [weak self] newHeight, mode in
            self?.updateOverlayHeight(newHeight, mode: mode)
        }
        v.onPanelSearchBegin = { [weak self] in
            DispatchQueue.main.async {
                self?.updateForSearchKeyboard()
            }
        }
        return v
    }
}
