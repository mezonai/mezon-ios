import UIKit

enum PanelKeyboardTab: Int, CaseIterable {
    case emoji = 0
    case gifs = 1
    case stickers = 2

    var title: String {
        switch self {
        case .emoji: return "Emoji"
        case .gifs: return "GIFs"
        case .stickers: return "Stickers"
        }
    }
}

final class PanelKeyboardView: UIView, UIGestureRecognizerDelegate {

    var onEmojiSelected: ((String, String) -> Void)?
    var onStickerSelected: ((CachedClanStickerRecord) -> Void)?
    var onGifSelected: ((String) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?
    var onPanelSearchBegin: (() -> Void)?

    var collapsedHeight: CGFloat = 260
    var expandedHeight: CGFloat = 500

    private(set) var isExpanded = false
    private(set) var currentTab: PanelKeyboardTab = .emoji
    private(set) var isPanelSearchFocused = false


    private var loadedTabs: Set<PanelKeyboardTab> = []

    private let grabberBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.label.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let handleArea: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let tabContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 20
        v.clipsToBounds = true
        return v
    }()

    private var tabButtons: [UIButton] = []
    private let tabIndicatorView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 16
        return v
    }()

    private let separatorLine: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.label.withAlphaComponent(0.1)
        return v
    }()

    private let contentScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = false
        sv.bounces = false
        return sv
    }()

    private let emojisPanel = EmojisPanel()
    private let gifsPanel = GifsPanel()
    private let stickersPanel = StickersPanel()

    private static let handleHeight: CGFloat = 24
    private static let tabBarHeight: CGFloat = 44

    private var sheetPanGesture: UIPanGestureRecognizer!
    private var dragStartHeight: CGFloat = 0
    private var isDraggingSheet = false

    private var tabIndicatorLeadingConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        setupLayout()
        setupTabs()
        setupPanels()
        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        addSubview(handleArea)
        handleArea.addSubview(grabberBar)
        addSubview(tabContainerView)
        addSubview(separatorLine)
        addSubview(contentScrollView)

        NSLayoutConstraint.activate([
            handleArea.topAnchor.constraint(equalTo: topAnchor),
            handleArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            handleArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            handleArea.heightAnchor.constraint(equalToConstant: Self.handleHeight),

            grabberBar.centerXAnchor.constraint(equalTo: handleArea.centerXAnchor),
            grabberBar.centerYAnchor.constraint(equalTo: handleArea.centerYAnchor),
            grabberBar.widthAnchor.constraint(equalToConstant: 36),
            grabberBar.heightAnchor.constraint(equalToConstant: 5),

            tabContainerView.topAnchor.constraint(equalTo: handleArea.bottomAnchor, constant: 4),
            tabContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tabContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            tabContainerView.heightAnchor.constraint(equalToConstant: Self.tabBarHeight),

            separatorLine.topAnchor.constraint(equalTo: tabContainerView.bottomAnchor, constant: 4),
            separatorLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5),

            contentScrollView.topAnchor.constraint(equalTo: separatorLine.bottomAnchor),
            contentScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupTabs() {
        tabContainerView.addSubview(tabIndicatorView)
        let indicatorLeading = tabIndicatorView.leadingAnchor.constraint(equalTo: tabContainerView.leadingAnchor, constant: 4)
        tabIndicatorLeadingConstraint = indicatorLeading
        NSLayoutConstraint.activate([
            tabIndicatorView.topAnchor.constraint(equalTo: tabContainerView.topAnchor, constant: 4),
            tabIndicatorView.bottomAnchor.constraint(equalTo: tabContainerView.bottomAnchor, constant: -4),
            indicatorLeading,
        ])

        let tabStack = UIStackView()
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabStack.axis = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 0
        tabContainerView.addSubview(tabStack)
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: tabContainerView.topAnchor),
            tabStack.leadingAnchor.constraint(equalTo: tabContainerView.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: tabContainerView.trailingAnchor),
            tabStack.bottomAnchor.constraint(equalTo: tabContainerView.bottomAnchor),
        ])

        for tab in PanelKeyboardTab.allCases {
            let btn = UIButton(type: .system)
            btn.tag = tab.rawValue
            btn.setTitle(tab.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(btn)
            tabButtons.append(btn)
        }

        tabIndicatorView.widthAnchor.constraint(
            equalTo: tabContainerView.widthAnchor,
            multiplier: 1.0 / 3.0,
            constant: -8.0 / 3.0
        ).isActive = true

        updateTabSelection(animated: false)
    }

    private func setupPanels() {
        contentScrollView.addSubview(emojisPanel)
        contentScrollView.addSubview(gifsPanel)
        contentScrollView.addSubview(stickersPanel)

        NSLayoutConstraint.activate([
            emojisPanel.topAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.topAnchor),
            emojisPanel.leadingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.leadingAnchor),
            emojisPanel.trailingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.trailingAnchor),
            emojisPanel.widthAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.widthAnchor),
            emojisPanel.heightAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.heightAnchor),

            gifsPanel.topAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.topAnchor),
            gifsPanel.leadingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.leadingAnchor),
            gifsPanel.trailingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.trailingAnchor),
            gifsPanel.widthAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.widthAnchor),
            gifsPanel.heightAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.heightAnchor),

            stickersPanel.topAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.topAnchor),
            stickersPanel.leadingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.leadingAnchor),
            stickersPanel.trailingAnchor.constraint(equalTo: contentScrollView.contentLayoutGuide.trailingAnchor),
            stickersPanel.widthAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.widthAnchor),
            stickersPanel.heightAnchor.constraint(equalTo: contentScrollView.frameLayoutGuide.heightAnchor),
        ])

        emojisPanel.onEmojiSelected = { [weak self] id, shortname in
            self?.onEmojiSelected?(id, shortname)
        }
        stickersPanel.onStickerSelected = { [weak self] sticker in
            self?.onStickerSelected?(sticker)
        }
        gifsPanel.onGifSelected = { [weak self] url in
            self?.onGifSelected?(url)
        }

        let syncSearchFocus: (Bool) -> Void = { [weak self] focused in
            guard let self else { return }
            self.isPanelSearchFocused = focused
            if focused {
                self.onPanelSearchBegin?()
            }
        }
        emojisPanel.onSearchFocusChanged = syncSearchFocus
        gifsPanel.onSearchFocusChanged = syncSearchFocus
        stickersPanel.onSearchFocusChanged = syncSearchFocus


        let scrollHandler: (CGFloat, Bool) -> Void = { [weak self] offset, isDragging in
            self?.handleInnerScroll(offset: offset, isDragging: isDragging)
        }
        emojisPanel.onInnerScroll = scrollHandler
        stickersPanel.onInnerScroll = scrollHandler
        gifsPanel.onInnerScroll = scrollHandler


        gifsPanel.isHidden = true
        stickersPanel.isHidden = true
    }

    private func setupGestures() {
        sheetPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        sheetPanGesture.delegate = self
        addGestureRecognizer(sheetPanGesture)

        contentScrollView.panGestureRecognizer.require(toFail: sheetPanGesture)
        contentScrollView.delegate = self
        updateScrollEnabled()
    }

    var isSearchFieldActive: Bool {
        return findFirstResponder(in: self) is UITextField
    }

    func dismissSearch() {
        endEditing(true)
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
        tabContainerView.backgroundColor = UIColor.theme.primary.withAlphaComponent(0.6)
        tabIndicatorView.backgroundColor = UIColor.theme.bgViolet
        updateTabColors()
        emojisPanel.applyTheme()
        gifsPanel.applyTheme()
        stickersPanel.applyTheme()
    }


    func configureMediaPanelCache(engine: MezonEngine) {
        emojisPanel.bindEmojiCache(engine: engine)
        stickersPanel.bindStickerCache(engine: engine)
        gifsPanel.bindGifCache(engine: engine)
    }


    func refreshMediaPanelCache() {
        loadedTabs.removeAll()
        loadTabDataIfNeeded(currentTab)
    }


    private func loadTabDataIfNeeded(_ tab: PanelKeyboardTab) {
        guard !loadedTabs.contains(tab) else { return }
        loadedTabs.insert(tab)
        switch tab {
        case .emoji:    emojisPanel.reloadFromPostboxCache()
        case .stickers: stickersPanel.reloadFromPostboxCache()
        case .gifs:     gifsPanel.reloadFromPostboxCache()
        }
    }

    func resetToCollapsed() {
        isExpanded = false
        contentScrollView.setContentOffset(.zero, animated: false)
        updateScrollEnabled()
    }


    func applySnapExpanded(height: CGFloat) {
        expandedHeight = height
        isExpanded = true
        updateScrollEnabled()
        onHeightChanged?(height)
    }

    func applySnapCollapsed() {
        isExpanded = false
        updateScrollEnabled()
        contentScrollView.setContentOffset(.zero, animated: false)
        onHeightChanged?(collapsedHeight)
    }

    private func findFirstResponder(in view: UIView) -> UIResponder? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = findFirstResponder(in: sub) { return found }
        }
        return nil
    }

    @objc private func tabTapped(_ sender: UIButton) {
        guard let tab = PanelKeyboardTab(rawValue: sender.tag), tab != currentTab else { return }
        dismissSearch()
        currentTab = tab
        updateTabSelection(animated: true)
        updateVisiblePanel()

        loadTabDataIfNeeded(tab)
    }

    private func updateTabSelection(animated: Bool) {
        let idx = currentTab.rawValue
        let tabWidth = 1.0 / CGFloat(PanelKeyboardTab.allCases.count)
        let containerWidth = tabContainerView.bounds.width > 0 ? tabContainerView.bounds.width : (UIScreen.main.bounds.width - 32)
        let padding: CGFloat = 4
        let newLeading = padding + CGFloat(idx) * (containerWidth - padding * 2) * tabWidth

        tabIndicatorLeadingConstraint?.constant = newLeading

        let update = {
            self.layoutIfNeeded()
            self.updateTabColors()
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.8, options: [.curveEaseInOut], animations: update)
        } else {
            update()
        }
    }

    private func updateTabColors() {
        let t = UIColor.theme
        for btn in tabButtons {
            let isSelected = btn.tag == currentTab.rawValue

            let titleColor = isSelected ? UIColor.white : t.textStrong
            btn.setTitleColor(titleColor, for: .normal)
            btn.setTitleColor(titleColor, for: .highlighted)
            btn.tintColor = titleColor
        }
    }

    private func updateVisiblePanel() {
        emojisPanel.isHidden = (currentTab != .emoji)
        gifsPanel.isHidden = (currentTab != .gifs)
        stickersPanel.isHidden = (currentTab != .stickers)
        updateScrollEnabled()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTabSelection(animated: false)
    }

    private func updateScrollEnabled() {
        contentScrollView.isScrollEnabled = false
        contentScrollView.alwaysBounceVertical = false
    }


    private var didExpandThisDrag = false

    private func handleInnerScroll(offset: CGFloat, isDragging: Bool) {
        if !isDragging {
            didExpandThisDrag = false
            return
        }

        if !isExpanded {

            if offset > 10, !didExpandThisDrag {
                didExpandThisDrag = true
                snapTo(expanded: true)
            }
        } else {

            if offset < -40 {
                snapTo(expanded: false)
            }
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == sheetPanGesture else { return true }

        let velocity = sheetPanGesture.velocity(in: self)
        let isVertical = abs(velocity.y) > abs(velocity.x)
        guard isVertical else { return false }

        if !isExpanded {
            return true
        } else {
            let atTop = contentScrollView.contentOffset.y <= 0
            let draggingDown = velocity.y > 0
            return atTop && draggingDown
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragStartHeight = bounds.height
            isDraggingSheet = true
        case .changed:
            let translation = gesture.translation(in: self)
            let raw = dragStartHeight - translation.y
            let newHeight = raw.clamped(to: collapsedHeight...expandedHeight)
            onHeightChanged?(newHeight)
        case .ended, .cancelled:
            isDraggingSheet = false
            let velocity = gesture.velocity(in: self).y
            snapWithVelocity(velocity)
        default:
            break
        }
    }

    private func snapWithVelocity(_ velocityY: CGFloat) {
        let currentH = bounds.height
        let midPoint = (collapsedHeight + expandedHeight) / 2

        if velocityY < -500 {
            snapTo(expanded: true)
        } else if velocityY > 500 {
            snapTo(expanded: false)
        } else {
            snapTo(expanded: currentH > midPoint)
        }
    }

    private func snapTo(expanded: Bool) {
        let targetH = expanded ? expandedHeight : collapsedHeight
        let wasExpanded = isExpanded
        isExpanded = expanded
        onHeightChanged?(targetH)

        updateScrollEnabled()

        if !expanded && wasExpanded {
            dismissSearch()
            contentScrollView.setContentOffset(.zero, animated: false)
        }
    }
}

extension PanelKeyboardView: UIScrollViewDelegate {}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
