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
    let onVideoCallTapped: (() -> Void)?
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
    let onShareContactProfileTapped: (ShareContactData) -> Void
    let onShareContactMessageTapped: (ShareContactData) -> Void
    let onShareContactCallTapped: (ShareContactData) -> Void
    let isShareContactCallBlocked: (ShareContactData) -> Bool
    let onSwipeReply: (ChatMessageDisplay) -> Void
    let loadClanInviteInfo: (String, @escaping (ClanInviteInfo?) -> Void) -> Void
    let onClanInvitePrimaryAction: (String, ClanInviteInfo) -> Void
    let onSendTokenLogTapped: () -> Void
    let onSystemPinMessageTapped: (ChatMessageDisplay) -> Void
    let onSystemThreadTapped: (Int64, String?) -> Void
    let onSystemAllThreadsTapped: () -> Void
    let onVotePoll: (_ messageId: String, _ channelId: String, _ answerIndices: [Int32], _ completion: @escaping ([Int32]?) -> Void) -> Void
    let onOpenPollDetail: (_ messageId: String, _ channelId: String) -> Void
    let onCallLogCallBackTapped: ((CallLogData) -> Void)?
    let isGroupDMChat: () -> Bool
    let resolveSenderRoleColor: (_ senderId: String, _ fallback: UIColor) -> UIColor
    let resolveSenderRoleIconURL: (_ senderId: String) -> String?
    var onMessagesReloaded: (() -> Void)?
    var onMessageNeedsRelayout: ((String) -> Void)?
    var onEmbedButtonClicked: ((ParsedEmbedButton, String, ChatMessageDisplay) -> Void)?  
    var onMediaTapped: ((_ index: Int, _ media: [ParsedAttachment], _ display: ChatMessageDisplay) -> Void)? = nil
    var onMediaRetryTapped: ((_ index: Int, _ display: ChatMessageDisplay) -> Void)? = nil
}

final class ChatContainerNode: ASDisplayNode {

    let listView: ListView

    private let headerNode = ChatHeaderNode()
    private var messageRelayoutVersions: [String: Int] = [:]
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
    private static let nearBottomDistanceThreshold: CGFloat = 100

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
        headerNode.onVideoCallTapped = { interaction.onVideoCallTapped?() }
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
                let atBottom = value < Self.nearBottomDistanceThreshold
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
        let isFarFromBottom = lastKnownDistanceFromBottom >= Self.nearBottomDistanceThreshold
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
            isDM: isDM,
            isBlocked: state.isPeerBlocked
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
                        isAgeRestricted: state.isAgeRestricted,
                        isDM: state.isDM,
                        dmPeerUsername: state.dmPeerUsername,
                        dmPeerDisplayName: state.dmPeerDisplayName,
                        dmAvatarURL: state.dmAvatarURL,
                        dmGroupAvatarURL: state.dmGroupAvatarURL,
                        threadCreatorName: state.threadCreatorName
                    ))
                    didInsertWelcomeHero = true
                } else {
                    items.append(ChatSystemMessageItem(display: display, interaction: interaction))
                }
            } else if display.isSystemMessage {
                items.append(ChatSystemMessageItem(display: display, interaction: interaction))
            } else {
                let version = self.messageRelayoutVersions[display.id] ?? 0
                items.append(ChatMessageItem(display: display, interaction: interaction, relayoutVersion: version))
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

        guard !addedIds.isEmpty || !removedIds.isEmpty else {
            committedMessageIds = Array(newIds)
            applyInPlaceUpdates(old: old, new: new, newIds: newIds, forceAll: true)
            return
        }

        var oldIndexMap: [String: Int] = [:]
        oldIndexMap.reserveCapacity(oldIds.count)
        for (index, id) in oldIds.enumerated() {
            oldIndexMap[id] = index
        }
        var oldFingerprintById: [String: String] = [:]
        oldFingerprintById.reserveCapacity(old.messages.count)
        for message in old.messages {
            oldFingerprintById[message.id] = Self.listFingerprint(message)
        }
        var newMessageById: [String: ChatMessageDisplay] = [:]
        newMessageById.reserveCapacity(new.messages.count)
        for message in new.messages {
            newMessageById[message.id] = message
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

        var updateItems: [ListViewUpdateItem] = []
        for (newIdx, id) in newIds.enumerated() {
            guard !addedIds.contains(id),
                  !removedIds.contains(id),
                  let oldIdx = oldIndexMap[id],
                  let oldFingerprint = oldFingerprintById[id],
                  let newMessage = newMessageById[id],
                  oldFingerprint != Self.listFingerprint(newMessage),
                  newIdx < newItems.count,
                  newItems[newIdx] is ChatMessageItem else {
                continue
            }
            updateItems.append(ListViewUpdateItem(
                index: newIdx,
                previousIndex: oldIdx,
                item: newItems[newIdx],
                directionHint: nil
            ))
        }

        let isAtBottom: Bool = {
            switch self.listView.visibleContentOffset() {
            case let .known(value):
                return value < Self.nearBottomDistanceThreshold
            case .none, .unknown:
                return self.lastKnownDistanceFromBottom < Self.nearBottomDistanceThreshold
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
            updateIndicesAndItems: updateItems,
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
            .map { "\($0.url)|\($0.filename)|\($0.filetype)|\($0.isUploading)|\(Int($0.uploadProgress * 100))" }
            .joined(separator: ";")
        let grouping = [
            m.isCombine ? "1" : "0",
            m.isForward ? "1" : "0",
            m.showForwardHeader ? "1" : "0",
            m.replyRef != nil ? "1" : "0",
            m.isDeletedReply ? "1" : "0",
            m.hasIncludeMention ? "1" : "0",
            m.isMe ? "1" : "0"
        ].joined(separator: "|")
        let pin = m.message.isPinned ? "1" : "0"
        let pollHash: String
        if let pd = m.pollData {
            let sortedCounts = pd.answerCounts.sorted(by: { $0.key < $1.key })
            let countStrings = sortedCounts.map { "\($0.key):\($0.value)" }
            let countJoined = countStrings.joined(separator: ",")
            pollHash = "\(pd.totalVotes)|\(countJoined)"
        } else {
            pollHash = ""
        }
        let embedHash: String = {
            let embeds = m.parsedContent.embeds
            guard !embeds.isEmpty else { return "" }
            return embeds.map { embed in
                let fields = embed.fields.map { "\($0.name):\($0.value)" }.joined(separator: ",")
                let buttons = embed.actionRows.flatMap { $0.buttons }.map { "\($0.id):\($0.label):\($0.style):\($0.disabled)" }.joined(separator: ";")
                return "\(embed.title ?? "")|\(embed.description ?? "")|\(fields)|\(embed.actionRows.count)|\(buttons)"
            }.joined(separator: "§")
        }()
        let ogpHash = m.parsedContent.ogpPreviews.map {
            "\($0.url)|\($0.title)|\($0.description)|\($0.imageURL)"
        }.joined(separator: "§")
        let topicHash: String = {
            guard let topic = m.topicData else { return "" }
            return "\(topic.topicId)|\(topic.creatorId)|\(topic.replyCount)"
        }()
        let sendFeedback = m.showsSendingFeedback ? "1" : "0"
        return "\(m.id)|\(m.message.senderId)|\(m.message.createdAt.timeIntervalSince1970)|\(edited)|\(m.senderDisplayName)|\(m.avatarURL ?? "")|\(m.messageCode)|\(grouping)|\(m.parsedContent.text)|\(att)|\(pin)|\(pollHash)|\(embedHash)|\(ogpHash)|\(topicHash)|\(sendFeedback)"
    }

    private static func welcomeFingerprint(_ state: ChatState) -> String {
        [
            state.channelLabel,
            "\(state.channelType)",
            state.isPrivate ? "1" : "0",
            state.isAgeRestricted ? "1" : "0",
            state.isDM ? "1" : "0",
            state.dmPeerUsername,
            state.dmPeerDisplayName,
            state.dmAvatarURL,
            state.dmGroupAvatarURL,
            state.threadCreatorName,
        ].joined(separator: "|")
    }

    private func applyInPlaceUpdates(old: ChatState, new: ChatState, newIds: [String], forceAll: Bool = false) {
        let newItems = buildItems(from: new)
        var updateItems: [ListViewUpdateItem] = []

        if Self.welcomeFingerprint(old) != Self.welcomeFingerprint(new),
           let welcomeIndex = newItems.firstIndex(where: { $0 is ChatWelcomeItem }) {
            updateItems.append(ListViewUpdateItem(
                index: welcomeIndex,
                previousIndex: welcomeIndex,
                item: newItems[welcomeIndex],
                directionHint: nil
            ))
        }

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
                let newFingerprint = Self.listFingerprint(newMsg)
                let fingerprintChanged = oldEntry.fingerprint != newFingerprint
                changed = oldEntry.reactions != newMsg.reactions
                    || oldEntry.sendingState != newMsg.sendingState
                    || fingerprintChanged
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
        transition.updateFrame(node: headerNode, frame: headerFrame, beginWithCurrentState: true)

        let layoutBottomInset = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom)
        let tvFrame = CGRect(
            x: 0,
            y: headerFrame.maxY,
            width: fullWidth,
            height: max(layout.size.height - headerFrame.maxY - inputBarHeight - layoutBottomInset, 0)
        )
        transition.updateFrame(node: listView, frame: tvFrame, beginWithCurrentState: true)

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

    func forceUpdateItem(id: String) {
        self.messageRelayoutVersions[id, default: 0] += 1
        let items = buildItems(from: self.state)
        guard let itemIdx = items.firstIndex(where: { ($0 as? ChatMessageItem)?.display.id == id }) else { return }
        
        let updateItem = ListViewUpdateItem(
            index: itemIdx,
            previousIndex: itemIdx,
            item: items[itemIdx],
            directionHint: nil
        )
        
        listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [updateItem],
            options: [.AnimateInsertion],
            scrollToItem: nil,
            additionalScrollDistance: 0.0,
            updateSizeAndInsets: nil,
            stationaryItemRange: (itemIdx, items.count - 1),
            updateOpaqueState: nil,
            completion: { _ in }
        )
    }

    func forceUpdateAllMessageItems() {
        for id in committedMessageIds {
            self.messageRelayoutVersions[id, default: 0] += 1
        }
        let items = buildItems(from: self.state)
        var updateItems: [ListViewUpdateItem] = []
        for (idx, item) in items.enumerated() where item is ChatMessageItem {
            updateItems.append(ListViewUpdateItem(
                index: idx, previousIndex: idx, item: item, directionHint: nil
            ))
        }
        guard !updateItems.isEmpty else { return }
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
