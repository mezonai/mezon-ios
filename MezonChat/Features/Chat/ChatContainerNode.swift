import AVFoundation
import AsyncDisplayKit
import UIKit

struct ChatInteraction {
    let onBackTapped: () -> Void
    let onSearchTapped: () -> Void
    let onHistoryTapped: () -> Void
    let onMenuTapped: () -> Void
    let onScrolledNearTop: () -> Void
    let onScrolledNearBottom: () -> Void
    let onScrolledToBottom: (Bool) -> Void
    let onJumpToPresent: () -> Void
    let onMentionTapped: (String) -> Void
    let onHashtagTapped: (String) -> Void
    let onMessageLongPressed: (ChatMessageDisplay) -> Void
    let onReplyTapped: (String) -> Void
    var onMessagesReloaded: (() -> Void)?
}

final class ChatContainerNode: ASDisplayNode {

    let listView: ListView

    private let headerNode = ChatHeaderNode()
    private let skeletonNode = MessageSkeletonContainerNode(count: 8)
    private let loadingOlderNode = ASDisplayNode()
    private let loadingNewerNode = ASDisplayNode()
    private let jumpToPresentNode = ASButtonNode()

    private let emptyNode = ASTextNode2()

    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private(set) var state: ChatState = .empty
    private var committedItems: [ListViewItem] = []
    private var committedMessageIds: [String] = []
    private let interaction: ChatInteraction
    private let disposables = DisposableSet()
    var pendingJumpMessageId: String?
    private(set) var didAutoScrollForNewMessages = false
    private var isLoadMoreGuardActive = false

    init(signal: Signal<ChatState, NoError>, interaction: ChatInteraction) {
        listView = ListView()
        self.interaction = interaction

        let t = UIColor.theme
        loadingOlderNode.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.hidesWhenStopped = true
            indicator.color = t.textDisabled
            return indicator
        }
        loadingOlderNode.isHidden = true

        loadingNewerNode.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.hidesWhenStopped = true
            indicator.color = t.textDisabled
            return indicator
        }
        loadingNewerNode.isHidden = true

        super.init()
        addSubnode(headerNode)
        addSubnode(listView)
        addSubnode(skeletonNode)
        addSubnode(loadingOlderNode)
        addSubnode(loadingNewerNode)
        addSubnode(emptyNode)
        addSubnode(jumpToPresentNode)

        listView.rotated = true
        listView.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
        listView.preloadPages = true

        listView.visibleContentOffsetChanged = { [weak self] offset, _ in
            guard let self else { return }
            switch offset {
            case let .known(value):
                let atBottom = value < 100
                self.interaction.onScrolledToBottom(atBottom)
                self.setJumpButtonVisible(value >= 100)
            case .none, .unknown:
                break
            }
        }

        listView.displayedItemRangeChanged = { [weak self] range, _ in
            guard let self, !self.isLoadMoreGuardActive else { return }
            guard let loadedRange = range.loadedRange else { return }
            let totalItems = self.committedMessageIds.count
            guard totalItems > 0 else { return }

            if loadedRange.lastIndex >= totalItems - 5 {
                let hasWelcome = self.state.messages.contains(where: { $0.isWelcome })
                if !hasWelcome {
                    self.interaction.onScrolledNearTop()
                }
            }
            if loadedRange.firstIndex <= 2 {
                self.interaction.onScrolledNearBottom()
            }
        }

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                let oldState = self.state
                self.state = newState
                self.updateHeader(state: newState)
                self.updateLoadingState(newState)
                if let msg = newState.errorMessage { Toast.error(msg) }

                let isEmpty = newState.messages.isEmpty
                self.emptyNode.isHidden = !(!newState.isLoading && isEmpty)

                if self.listView.bounds.width > 0 {
                    self.applyTransition(old: oldState, new: newState)
                } else {
                    self.needsReloadAfterLayout = true
                }
                if !isEmpty && oldState.messages.isEmpty {
                    self.interaction.onMessagesReloaded?()
                }
                if self.pendingJumpMessageId != nil {
                    self.triggerPendingJump()
                }
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        layer.insertSublayer(gradientLayer, at: 0)

        listView.backgroundColor = .clear

        let btnSize: CGFloat = 40
        jumpToPresentNode.setImage(
            UIImage(systemName: "chevron.down")?.withConfiguration(
                UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            ).withTintColor(.white, renderingMode: .alwaysOriginal),
            for: .normal
        )
        jumpToPresentNode.backgroundColor = UIColor.theme.textDisabled.withAlphaComponent(0.85)
        jumpToPresentNode.cornerRadius = btnSize / 2
        jumpToPresentNode.clipsToBounds = true
        jumpToPresentNode.style.preferredSize = CGSize(width: btnSize, height: btnSize)
        jumpToPresentNode.isHidden = true
        jumpToPresentNode.alpha = 0
        jumpToPresentNode.addTarget(self, action: #selector(jumpToPresentTapped), forControlEvents: .touchUpInside)
    }

    @objc private func jumpToPresentTapped() {
        interaction.onJumpToPresent()
        setJumpButtonVisible(false)
    }

    private func setJumpButtonVisible(_ visible: Bool) {
        guard jumpToPresentNode.isHidden == visible else { return }
        if visible {
            jumpToPresentNode.isHidden = false
            UIView.animate(withDuration: 0.2) { self.jumpToPresentNode.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.2, animations: { self.jumpToPresentNode.alpha = 0 }) { _ in
                self.jumpToPresentNode.isHidden = true
            }
        }
    }

    func applyTheme() {
        let t = UIColor.theme
        gradientLayer.colors = [t.primary.cgColor, t.primaryGradient.cgColor]
        headerNode.applyTheme()
        emptyNode.attributedText = NSAttributedString(
            string: L(L10n.ChannelMessages.emptyMessages),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf),
                .foregroundColor: t.textDisabled,
            ]
        )
        reloadAllItems()
    }

    private func updateHeader(state: ChatState) {
        headerNode.configure(
            title: state.channelLabel,
            channelType: state.channelType,
            isPrivate: state.isPrivate,
            isAgeRestricted: state.isAgeRestricted
        )
    }

    private func updateLoadingState(_ state: ChatState) {
        let showSkeleton = state.isLoading && state.messages.isEmpty
        skeletonNode.isHidden = !showSkeleton
        skeletonNode.alpha = showSkeleton ? 1 : 0

        let showOlderLoading = state.isLoadingMore && state.hasMoreOlder
        loadingOlderNode.isHidden = !showOlderLoading
        if let indicator = loadingOlderNode.view as? UIActivityIndicatorView {
            showOlderLoading ? indicator.startAnimating() : indicator.stopAnimating()
        }

        let showNewerLoading = state.isLoadingNewer && state.hasMoreNewer
        loadingNewerNode.isHidden = !showNewerLoading
        if let indicator = loadingNewerNode.view as? UIActivityIndicatorView {
            showNewerLoading ? indicator.startAnimating() : indicator.stopAnimating()
        }
    }

    private var lastLayout: ContainerViewLayout?
    private var lastInputBarHeight: CGFloat = 0
    private var needsReloadAfterLayout = false

    func updateLayout(layout: ContainerViewLayout, inputBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let hadZeroFrame = listView.bounds.width == 0
        lastLayout = layout
        lastInputBarHeight = inputBarHeight
        applyFrameLayout(transition: transition)
        if hadZeroFrame && listView.bounds.width > 0 || needsReloadAfterLayout {
            needsReloadAfterLayout = false
            reloadAllItems()
        }
    }

    func triggerPendingJump() {
        guard let jumpId = pendingJumpMessageId,
              state.messages.contains(where: { $0.id == jumpId }) else { return }
        pendingJumpMessageId = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.scrollToMessage(id: jumpId)
        }
    }

    func scrollToMessage(id: String) {
        guard let messageIndex = state.messages.firstIndex(where: { $0.id == id }) else { return }
        let row = state.messages.count - 1 - messageIndex
        listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: ListViewScrollToItem(index: row, position: .center(.top), animated: true, curve: .Default(duration: nil), directionHint: .Down),
            updateOpaqueState: nil,
            completion: { _ in }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            guard let idx = self.state.messages.firstIndex(where: { $0.id == id }) else { return }
            let itemIndex = self.state.messages.count - 1 - idx
            self.listView.forEachItemNode { node in
                if let node = node as? ChatMessageItemNode, node.index == itemIndex {
                    if let bubble = self.findBubble(in: node) {
                        bubble.flashHighlight()
                    }
                }
            }
        }
    }

    private func findBubble(in node: ListViewItemNode) -> MessageBubbleNode? {
        for sub in node.subnodes ?? [] {
            if let bubble = sub as? MessageBubbleNode { return bubble }
        }
        return nil
    }

    private func buildItems(from state: ChatState) -> [ListViewItem] {
        let messages = state.messages
        var items: [ListViewItem] = []
        for display in messages.reversed() {
            if display.isWelcome {
                items.append(ChatWelcomeItem(
                    channelLabel: state.channelLabel,
                    channelType: state.channelType,
                    isPrivate: state.isPrivate,
                    isAgeRestricted: state.isAgeRestricted
                ))
            } else {
                items.append(ChatMessageItem(display: display, interaction: interaction))
            }
        }
        return items
    }

    private func reloadAllItems() {
        let items = buildItems(from: state)
        let newIds = state.messages.reversed().map { $0.id }

        var deleteItems: [ListViewDeleteItem] = []
        for i in (0..<committedMessageIds.count).reversed() {
            deleteItems.append(ListViewDeleteItem(index: i, directionHint: nil))
        }

        var insertItems: [ListViewInsertItem] = []
        for (i, item) in items.enumerated() {
            insertItems.append(ListViewInsertItem(index: i, previousIndex: nil, item: item, directionHint: nil))
        }

        committedItems = items
        committedMessageIds = Array(newIds)

        listView.transaction(
            deleteIndices: deleteItems,
            insertIndicesAndItems: insertItems,
            updateIndicesAndItems: [],
            options: [.Synchronous, .LowLatency],
            scrollToItem: nil,
            updateOpaqueState: nil,
            completion: { _ in }
        )
    }

    private func applyTransition(old: ChatState, new: ChatState) {
        didAutoScrollForNewMessages = false
        let oldIds = committedMessageIds
        let newIds: [String] = new.messages.reversed().map { $0.id }

        guard oldIds != newIds else { return }

        if oldIds.isEmpty {
            reloadAllItems()
            return
        }

        let newItems = buildItems(from: new)

        let oldSet = Set(oldIds)
        let newSet = Set(newIds)
        let removedIds = oldSet.subtracting(newSet)
        let addedIds = newSet.subtracting(oldSet)

        guard !addedIds.isEmpty || !removedIds.isEmpty else { return }

        let oldIndexMap = Dictionary(uniqueKeysWithValues: oldIds.enumerated().map { ($1, $0) })

        var deleteItems: [ListViewDeleteItem] = []
        for id in removedIds {
            if let idx = oldIndexMap[id] {
                deleteItems.append(ListViewDeleteItem(index: idx, directionHint: nil))
            }
        }
        deleteItems.sort { $0.index > $1.index }

        let hasNewAtBottom = !addedIds.isEmpty && newIds.first.map({ addedIds.contains($0) }) ?? false
        let hasOlderAtTop = !addedIds.isEmpty && newIds.last.map({ addedIds.contains($0) }) ?? false

        var insertItems: [ListViewInsertItem] = []
        for (newIdx, id) in newIds.enumerated() {
            if addedIds.contains(id) {
                let hint: ListViewItemOperationDirectionHint = hasNewAtBottom ? .Up : .Down
                insertItems.append(ListViewInsertItem(index: newIdx, previousIndex: nil, item: newItems[newIdx], directionHint: hint))
            }
        }
        insertItems.sort { $0.index < $1.index }

        let isNearBottom: Bool = {
            if case let .known(offset) = self.listView.visibleContentOffset() {
                return offset < 200
            }
            return true
        }()

        isLoadMoreGuardActive = true

        committedItems = newItems
        committedMessageIds = Array(newIds)

        var scrollToItem: ListViewScrollToItem?
        let isLoadMoreResult = old.isLoadingMore || old.isLoadingNewer
            || new.isLoadingMore || new.isLoadingNewer
        let isBatchInsert = addedIds.count > 1
        if isNearBottom && hasNewAtBottom && !isLoadMoreResult && !isBatchInsert {
            didAutoScrollForNewMessages = true
            scrollToItem = ListViewScrollToItem(index: 0, position: .top(0), animated: true, curve: .Default(duration: nil), directionHint: .Up)
        }

        let stationaryRange: (Int, Int)?
        if scrollToItem == nil && !addedIds.isEmpty {
            stationaryRange = (0, Int.max)
        } else {
            stationaryRange = nil
        }

        listView.transaction(
            deleteIndices: deleteItems,
            insertIndicesAndItems: insertItems,
            updateIndicesAndItems: [],
            options: [.Synchronous, .LowLatency],
            scrollToItem: scrollToItem,
            stationaryItemRange: stationaryRange,
            updateOpaqueState: nil,
            completion: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isLoadMoreGuardActive = false
                }
            }
        )
    }

    private func applyFrameLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }
        let inputBarHeight = lastInputBarHeight
        let realSafeTop = view.safeAreaInsets.top
        let safeTop = realSafeTop > 20 ? realSafeTop : max(layout.safeInsets.top, 54)

        let fullWidth = view.bounds.width > 0 ? view.bounds.width : layout.size.width
        let headerH: CGFloat = 44
        let headerFrame = CGRect(x: 0, y: safeTop, width: fullWidth, height: headerH)
        transition.updateFrame(node: headerNode, frame: headerFrame)

        let tvFrame = CGRect(
            x: 0,
            y: headerFrame.maxY,
            width: fullWidth,
            height: max(layout.size.height - headerFrame.maxY - inputBarHeight - layout.intrinsicInsets.bottom, 0)
        )
        transition.updateFrame(node: listView, frame: tvFrame)

        let listInsets = UIEdgeInsets(top: 14, left: 0, bottom: 0, right: 0)
        listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: nil,
            updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: tvFrame.size, insets: listInsets, duration: 0, curve: .Default(duration: nil)),
            updateOpaqueState: nil,
            completion: { _ in }
        )

        transition.updateFrame(node: skeletonNode, frame: tvFrame)

        let liS: CGFloat = 24
        transition.updateFrame(node: loadingOlderNode, frame: CGRect(
            x: (fullWidth - liS) / 2,
            y: headerFrame.maxY + 12,
            width: liS,
            height: liS
        ))
        transition.updateFrame(node: loadingNewerNode, frame: CGRect(
            x: (fullWidth - liS) / 2,
            y: tvFrame.maxY - liS - 12,
            width: liS,
            height: liS
        ))
        let tableY = tvFrame.minY
        let tableH = tvFrame.height
        transition.updateFrame(node: emptyNode, frame: CGRect(
                x: 0,
                y: tableY + (tableH - 44) / 2,
                width: fullWidth,
                height: 44
            ))

        let btnS: CGFloat = 40
        transition.updateFrame(node: jumpToPresentNode, frame: CGRect(
            x: fullWidth - btnS - 10,
            y: tvFrame.maxY - btnS - 28,
            width: btnS,
            height: btnS
        ))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = CGRect(origin: .zero, size: layout.size)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        applyFrameLayout(transition: .immediate)
    }
}
