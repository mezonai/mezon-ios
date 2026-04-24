import AVFoundation
import AsyncDisplayKit
import UIKit

struct ChannelHashtagTapInfo: Equatable {
    let channelId: String
    let clanId: String?

    static func parse(_ payload: Any) -> ChannelHashtagTapInfo? {
        if let d = payload as? NSDictionary {
            let c = (d["c"] as? String) ?? (d["c"] as? NSString).map { "\($0)" } ?? ""
            if c.isEmpty { return nil }
            let gRaw = (d["g"] as? String) ?? (d["g"] as? NSString).map { "\($0)" } ?? ""
            return ChannelHashtagTapInfo(channelId: c, clanId: gRaw.isEmpty ? nil : gRaw)
        }
        if let s = payload as? NSString {
            let c = "\(s)"
            if c.isEmpty { return nil }
            return ChannelHashtagTapInfo(channelId: c, clanId: nil)
        }
        return nil
    }
}

struct ChatInteraction {
    let onBackTapped: () -> Void
    let onHeaderTapped: () -> Void
    let onSearchTapped: () -> Void
    let onCallTapped: (() -> Void)?
    let onHistoryTapped: () -> Void
    let onMenuTapped: () -> Void
    let onScrolledNearTop: () -> Void
    let onScrolledNearBottom: () -> Void
    let onScrolledToBottom: (Bool) -> Void
    let onJumpToPresent: () -> Void
    let onMentionTapped: (String) -> Void
    let onHashtagTapped: (ChannelHashtagTapInfo) -> Void
    let hashtagChannelIsAccessible: (String, String?) -> Bool
    let onMessageLongPressed: (ChatMessageDisplay) -> Void
    let onReplyTapped: (String) -> Void
    let onTopicTapped: (TopicData) -> Void
    let onReactionTapped: (ParsedReaction, ChatMessageDisplay) -> Void
    let onReactionDetailRequested: (ParsedReaction, ChatMessageDisplay) -> Void
    let onAddReactionTapped: (ChatMessageDisplay) -> Void
    let onAvatarTapped: (ChatMessageDisplay) -> Void
    let onSwipeReply: (ChatMessageDisplay) -> Void
    let loadClanInviteInfo: (String, @escaping (ClanInviteInfo?) -> Void) -> Void
    let onClanInvitePrimaryAction: (String, ClanInviteInfo) -> Void
    let onSendTokenLogTapped: () -> Void
    var onMessagesReloaded: (() -> Void)?
}

final class ChatContainerNode: ASDisplayNode {

    let listView: ListView

    private let headerNode = ChatHeaderNode()
    private let skeletonNode = MessageSkeletonContainerNode(count: 8)
    private let loadingOlderNode = ASDisplayNode()
    private let jumpToPresentNode = ASButtonNode()


    private lazy var gradientLayer: CAGradientLayer = {
        let gl = CAGradientLayer()
        gl.startPoint = CGPoint(x: 0.5, y: 0)
        gl.endPoint   = CGPoint(x: 0.5, y: 1)
        return gl
    }()

    private(set) var state: ChatState = .empty
    private(set) var committedMessageIds: [String] = []
    private let interaction: ChatInteraction
    private let isDM: Bool
    private let disposables = DisposableSet()
    var pendingJumpMessageId: String?
    private(set) var didAutoScrollForNewMessages = false
    private var isLoadMoreGuardActive = false
    private var lastKnownDistanceFromBottom: CGFloat = 0

    init(signal: Signal<ChatState, NoError>, interaction: ChatInteraction, isDM: Bool = false) {
        listView = ListView()
        self.interaction = interaction
        self.isDM = isDM

        let t = UIColor.theme
        loadingOlderNode.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.hidesWhenStopped = true
            indicator.color = t.textDisabled
            return indicator
        }
        loadingOlderNode.isHidden = true

        super.init()
        headerNode.onBackTapped = { interaction.onBackTapped() }
        headerNode.onHeaderTapped = { interaction.onHeaderTapped() }
        headerNode.onSearchTapped = { interaction.onSearchTapped() }
        headerNode.onCallTapped = { interaction.onCallTapped?() }
        addSubnode(headerNode)
        addSubnode(listView)
        addSubnode(skeletonNode)
        addSubnode(loadingOlderNode)
        addSubnode(jumpToPresentNode)

        listView.rotated = true
        listView.transform = CATransform3DMakeScale(1.0, -1.0, 1.0)
        listView.preloadPages = true

        listView.visibleContentOffsetChanged = { [weak self] offset, _ in
            guard let self else { return }
            switch offset {
            case let .known(value):
                self.lastKnownDistanceFromBottom = value
                let atBottom = value < 100
                self.interaction.onScrolledToBottom(atBottom)
                self.refreshJumpButtonVisibility()
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
                self.interaction.onScrolledNearTop()
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
                self.refreshJumpButtonVisibility()


                let isEmpty = newState.messages.isEmpty

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
        gradientLayer.colors = [t.secondary.cgColor, t.primaryGradient.cgColor]
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

    private func refreshJumpButtonVisibility() {
        let isFarFromBottom = lastKnownDistanceFromBottom >= 100
        let hasNewerToLoad = state.hasMoreNewer
        setJumpButtonVisible(isFarFromBottom || hasNewerToLoad)
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
        gradientLayer.colors = [t.secondary.cgColor, t.primaryGradient.cgColor]
        headerNode.applyTheme()

        reloadAllItems()
    }

    private func updateHeader(state: ChatState) {
        headerNode.configure(
            title: state.channelLabel,
            subtitle: state.parentName,
            channelType: state.channelType,
            isPrivate: state.isPrivate,
            isAgeRestricted: state.isAgeRestricted,
            isDM: isDM
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
        guard let row = committedMessageIds.firstIndex(of: id) else { return }
        listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: ListViewScrollToItem(index: row, position: .center(.top), animated: true, curve: .Default(duration: nil), directionHint: .Down),
            updateOpaqueState: nil,
            completion: { _ in }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            guard let itemIndex = self.committedMessageIds.firstIndex(of: id) else { return }
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

    static let unreadLineId = "__unread_line__"
    private func buildIds(from state: ChatState) -> [String] {
        let messages = state.messages
        let lastSeenId = state.lastSeenMessageId
        let lastMessageId = messages.last?.id
        var ids: [String] = []
        for display in messages.reversed() {
            ids.append(display.id)
            if let seenId = lastSeenId,
               display.id == seenId,
               display.id != lastMessageId,
               messages.count > 2 {
                ids.append(Self.unreadLineId)
            }
        }
        return ids
    }

    private func buildItems(from state: ChatState) -> [ListViewItem] {
        let messages = state.messages
        var items: [ListViewItem] = []
        let lastSeenId = state.lastSeenMessageId
        let lastMessageId = messages.last?.id
        var didInsertWelcomeHero = false
        for display in messages.reversed() {
            if display.isWelcome {
                if !didInsertWelcomeHero {
                    items.append(ChatWelcomeItem(
                        channelLabel: state.channelLabel,
                        channelType: state.channelType,
                        isPrivate: state.isPrivate,
                        isAgeRestricted: state.isAgeRestricted
                    ))
                    didInsertWelcomeHero = true
                } else {
                    items.append(ChatSystemMessageItem(display: display, interaction: interaction))
                }
            } else if display.isSystemMessage {
                items.append(ChatSystemMessageItem(display: display, interaction: interaction))
            } else {
                items.append(ChatMessageItem(display: display, interaction: interaction))
            }
            if let seenId = lastSeenId,
               display.id == seenId,
               display.id != lastMessageId,
               messages.count > 2 {
                items.append(ChatNewMessageLineItem())
            }
        }
        return items
    }

    private func reloadAllItems() {
        let items = buildItems(from: state)
        let newIds = buildIds(from: state)

        var deleteItems: [ListViewDeleteItem] = []
        for i in (0..<committedMessageIds.count).reversed() {
            deleteItems.append(ListViewDeleteItem(index: i, directionHint: nil))
        }

        var insertItems: [ListViewInsertItem] = []
        for (i, item) in items.enumerated() {
            insertItems.append(ListViewInsertItem(index: i, previousIndex: nil, item: item, directionHint: nil))
        }

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
        let newIds = buildIds(from: new)

        if oldIds == newIds {
            applyInPlaceUpdates(old: old, new: new, newIds: newIds)
            return
        }

        if oldIds.isEmpty {
            reloadAllItems()
            return
        }

        if oldIds.count == newIds.count {
            var isPendingReplacement = true
            var hasAnyChange = false
            for i in 0..<oldIds.count {
                if oldIds[i] != newIds[i] {
                    hasAnyChange = true
                    let isPendingSwap = oldIds[i].hasPrefix("pending-") && !newIds[i].hasPrefix("pending-")
                    let isRealSwap = !oldIds[i].hasPrefix("pending-") && newIds[i].hasPrefix("pending-")
                    if !isPendingSwap && !isRealSwap {
                        isPendingReplacement = false
                        break
                    }
                }
            }
            if isPendingReplacement && hasAnyChange {
                committedMessageIds = Array(newIds)
                applyInPlaceUpdates(old: old, new: new, newIds: newIds, forceAll: true)
                return
            }
        }

        let newItems = buildItems(from: new)

        let oldSet = Set(oldIds)
        let newSet = Set(newIds)
        let removedIds = oldSet.subtracting(newSet)
        let addedIds = newSet.subtracting(oldSet)

        guard !addedIds.isEmpty || !removedIds.isEmpty else { return }

        var oldIndexMap: [String: Int] = [:]
        oldIndexMap.reserveCapacity(oldIds.count)
        for (index, id) in oldIds.enumerated() {
            oldIndexMap[id] = index
        }

        var deleteItems: [ListViewDeleteItem] = []
        for id in removedIds {
            if let idx = oldIndexMap[id] {
                deleteItems.append(ListViewDeleteItem(index: idx, directionHint: nil))
            }
        }
        deleteItems.sort { $0.index > $1.index }

        let hasNewAtBottom = !addedIds.isEmpty && newIds.first.map({ addedIds.contains($0) }) ?? false

        var insertItems: [ListViewInsertItem] = []
        for (newIdx, id) in newIds.enumerated() {
            if addedIds.contains(id) {
                let hint: ListViewItemOperationDirectionHint = hasNewAtBottom ? .Up : .Down
                insertItems.append(ListViewInsertItem(index: newIdx, previousIndex: nil, item: newItems[newIdx], directionHint: hint))
            }
        }
        insertItems.sort { $0.index < $1.index }

        let isAtBottom: Bool = {
            switch self.listView.visibleContentOffset() {
            case let .known(value):
                return value < 10
            case .none, .unknown:
                return true
            }
        }()

        isLoadMoreGuardActive = true

        committedMessageIds = Array(newIds)

        let isLoadMoreResult = old.isLoadingMore || old.isLoadingNewer
            || new.isLoadingMore || new.isLoadingNewer
            || old.isLoadingMessageContext || new.isLoadingMessageContext

        let newestMessageIsMe: Bool = {
            guard hasNewAtBottom else { return false }
            return new.messages.last?.isMe == true
        }()

        var scrollToItem: ListViewScrollToItem?
        if hasNewAtBottom && !isLoadMoreResult && !new.hasMoreNewer && (isAtBottom || newestMessageIsMe) {
            didAutoScrollForNewMessages = true
            scrollToItem = ListViewScrollToItem(index: 0, position: .top(0), animated: true, curve: .Spring(duration: 0.3), directionHint: .Up)
        }

        let transactionOptions: ListViewDeleteAndInsertOptions = [.Synchronous, .LowLatency]

        listView.transaction(
            deleteIndices: deleteItems,
            insertIndicesAndItems: insertItems,
            updateIndicesAndItems: [],
            options: transactionOptions,
            scrollToItem: scrollToItem,
            stationaryItemRange: scrollToItem == nil ? (0, Int.max) : nil,
            updateOpaqueState: nil,
            completion: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isLoadMoreGuardActive = false
                }
            }
        )
    }

    private static func listFingerprint(_ m: ChatMessageDisplay) -> String {
        let edited = m.message.editedAt.map { String($0.timeIntervalSince1970) } ?? ""
        let att = m.attachments
            .map { "\($0.url)|\($0.filename)|\($0.filetype)|\($0.isUploading)" }
            .joined(separator: ";")
        return "\(m.id)|\(edited)|\(m.parsedContent.text)|\(att)"
    }

    private func applyInPlaceUpdates(old: ChatState, new: ChatState, newIds: [String], forceAll: Bool = false) {
        let newItems = buildItems(from: new)
        var updateItems: [ListViewUpdateItem] = []

        var oldLookup: [String: (reactions: [ParsedReaction], sendingState: SendingState, fingerprint: String)] = [:]
        for msg in old.messages {
            oldLookup[msg.id] = (msg.reactions, msg.sendingState, Self.listFingerprint(msg))
        }

        var itemIdx = 0
        for newMsg in new.messages.reversed() {
            while itemIdx < newItems.count,
                  !(newItems[itemIdx] is ChatMessageItem) {
                itemIdx += 1
            }
            guard itemIdx < newItems.count else { break }

            let changed: Bool
            if let oldEntry = oldLookup[newMsg.id] {
                changed = oldEntry.reactions != newMsg.reactions
                    || oldEntry.sendingState != newMsg.sendingState
                    || oldEntry.fingerprint != Self.listFingerprint(newMsg)
            } else {
                changed = forceAll
            }

            if changed {
                updateItems.append(ListViewUpdateItem(
                    index: itemIdx,
                    previousIndex: itemIdx,
                    item: newItems[itemIdx],
                    directionHint: nil
                ))
            }
            itemIdx += 1
        }

        if !updateItems.isEmpty {
            listView.transaction(
                deleteIndices: [],
                insertIndicesAndItems: [],
                updateIndicesAndItems: updateItems,
                options: [.Synchronous, .LowLatency],
                scrollToItem: nil,
                updateOpaqueState: nil,
                completion: { _ in }
            )
        }
    }

    private func applyFrameLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }
        let inputBarHeight = lastInputBarHeight
        let realSafeTop = view.safeAreaInsets.top
        let safeTop = max(realSafeTop, layout.safeInsets.top)

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
        let animDuration: Double
        if case let .animated(duration, _) = transition {
            animDuration = duration
        } else {
            animDuration = 0
        }
        listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: nil,
            updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: tvFrame.size, insets: listInsets, duration: animDuration, curve: .Default(duration: nil)),
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
