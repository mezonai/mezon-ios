import SwiftProtobuf
import UIKit

enum ActiveChannelTracker {
    private static let lock = NSLock()
    private static var _channelId: Int64 = 0

    static var currentChannelId: Int64 {
        get { lock.lock(); defer { lock.unlock() }; return _channelId }
        set { lock.lock(); defer { lock.unlock() }; _channelId = newValue }
    }
}

struct ParsedAttachment: Equatable {
    let url: String
    let filename: String
    let filetype: String
    let width: Int?
    let height: Int?
    var localImage: UIImage?
    var isUploading: Bool = false

    var isImage: Bool {
        filetype.hasPrefix("image/") || filetype == "sticker"
            || ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(fileExtension)
            || ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(urlExtension)
    }

    var isVideo: Bool {
        filetype.hasPrefix("video/") || ["mp4", "mov", "m4v", "webm"].contains(fileExtension)
    }

    var isSticker: Bool { filetype == "sticker" }

    var isMedia: Bool { isImage || isVideo }

    var fileExtension: String {
        (filename as NSString).pathExtension.lowercased()
    }

    var urlExtension: String {
        guard let urlPath = URL(string: url)?.pathExtension else { return "" }
        return urlPath.lowercased()
    }

    static func ==(lhs: ParsedAttachment, rhs: ParsedAttachment) -> Bool {
        lhs.url == rhs.url && lhs.filename == rhs.filename && lhs.filetype == rhs.filetype
            && lhs.width == rhs.width && lhs.height == rhs.height && lhs.isUploading == rhs.isUploading
    }

    static var pendingImageCache: [String: [UIImage]] = [:]
}

struct ParsedReaction: Equatable {
    let emojiId: String
    let emoji: String
    let count: Int
    let senderIds: [String]
    let isMe: Bool
}

enum CallLogType: Int {
    case timeoutCall = 0
    case rejectCall = 1
    case cancelCall = 2
    case finishCall = 3
    case startCall = 4
}

struct CallLogData {
    let callLogType: CallLogType
    let isVideo: Bool
}

struct TopicData {
    let topicId: String
    let creatorId: String
    let replyCount: Int
}

struct ChatMessageDisplay: Identifiable {
    let message: Message
    let senderDisplayName: String
    let avatarURL: String?
    let isCombine: Bool
    let attachments: [ParsedAttachment]
    let reactions: [ParsedReaction]
    let parsedContent: ParsedContent
    let replyRef: Mezon_Api_MessageRef?
    let isDeletedReply: Bool
    let isWelcome: Bool
    let callLog: CallLogData?
    let topicData: TopicData?
    let isMe: Bool
    let sendingState: SendingState
    let hasIncludeMention: Bool
    var isFailed: Bool { sendingState == .failed }
    var id: String { message.id }
    var isCallLog: Bool { callLog != nil }
    var isTopic: Bool { topicData != nil }

    var checkOneLinkImage: Bool {
        guard attachments.count == 1,
            let att = attachments.first,
              att.isImage else { return false }
        let trimmedText = parsedContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty && trimmedText == att.url
    }

    static func isCombineWithPrevious(current: Message, previous: Message?) -> Bool {
        guard let prev = previous else { return false }
        guard current.senderId == prev.senderId else { return false }
        let diff = current.createdAt.timeIntervalSince(prev.createdAt)
        return diff < 120 && diff >= 0
    }
    static let mentionHereUserId: String = "1775731111020111321"
}

struct ChatState {
    var messages: [ChatMessageDisplay]
    var channelLabel: String
    var channelType: Int32
    var isPrivate: Bool
    var isAgeRestricted: Bool
    var hasMoreOlder: Bool
    var hasMoreNewer: Bool
    var isLoadingMore: Bool
    var isLoadingNewer: Bool
    var isLoading: Bool
    var errorMessage: String?
    var lastSeenMessageId: String?
    var currentUserId: String?
    var parentName: String?

    static let empty = ChatState(
        messages: [], channelLabel: "", channelType: 0, isPrivate: false, isAgeRestricted: false,
        hasMoreOlder: false, hasMoreNewer: false, isLoadingMore: false, isLoadingNewer: false,
        isLoading: false, errorMessage: nil, lastSeenMessageId: nil, currentUserId: nil,
        parentName: nil)
}

final class ChatViewController: ViewController {

    let clanId: Int64
    private(set) var channel: Mezon_Api_ChannelDescription
    let context: AccountContext
    var topicId: Int64 = 0
    private var storageChannelId: String {
        topicId != 0 ? "topic-\(topicId)" : "\(channel.channelID)"
    }

    private let needsReloadPipe = ValuePipe<Void>()
    private let metadataOnlyPipe = ValuePipe<Void>()
    var needsReloadSignal: Signal<Void, NoError> { needsReloadPipe.signal() }
    private let stateDisposables = DisposableSet()

    private(set) var messages: [ChatMessageDisplay] = []
    private(set) var channelLabel: String = ""
    private(set) var hasMoreOlder: Bool = true
    private(set) var hasMoreNewer: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var isLoadingNewer: Bool = false
    private var lastFetchedOlderMessageId: Int64?
    private var lastFetchedNewerMessageId: Int64?
    private var isJumping: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var channelMeta: ChannelRecord?
    private(set) var parentChannelMeta: ChannelRecord?
    private var initialParentName: String?
    private(set) var lastSeenMessageId: String?

    private lazy var sendInputViewController: SendMessageInputViewController = {
        let vc = SendMessageInputViewController(
            placeholder: L(L10n.ChannelMessages.writeMessage),
            channel: channel,
            clanId: clanId,
            context: context
        )
        vc.onSent = { [weak self] in self?.shouldScrollToBottom = true }
        // vc.onError = { Toast.error($0) }
        vc.onHeightChanged = { [weak self] newHeight in
            self?.updateInputBarHeight(newHeight)
        }
        vc.topicId = self.topicId
        return vc
    }()

    private var inputBarHeight: CGFloat = 56
    private var currentKeyboardOffset: CGFloat = 0
    private var isKeyboardVisible = false
    private var trackedKeyboardHeight: CGFloat = 0
    private lazy var shouldScrollToBottom: Bool = lastSeenMessageId == nil
    private var pendingScrollToBottom = false
    private var hasMarkedAsRead = false
    private var readyToLoadMore = false
    private var hasPerformedInitialUnreadScroll = false

    private var messagesNode: ChatContainerNode { displayNode as! ChatContainerNode }

    var pendingJumpToMessageId: String?

    init(
        clanId: Int64, channel: Mezon_Api_ChannelDescription, context: AccountContext,
        parentName: String? = nil
    ) {
        self.clanId = clanId
        self.channel = channel
        self.context = context
        self.initialParentName = parentName
        self.channelLabel = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        if channel.hasLastSeenMessage && channel.lastSeenMessage.id != 0 {
            self.lastSeenMessageId = "\(channel.lastSeenMessage.id)"
        }
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        var interaction = ChatInteraction(
            onBackTapped: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onSearchTapped: { [weak self] in
                guard let self else { return }
                let isPrivateOrThread = self.channel.channelPrivate != 0 || self.channel.parentID != 0
                let searchVC = SearchViewController(
                    clanId: self.clanId,
                    context: self.context,
                    channelId: self.channel.channelID,
                    channelLabel: self.channel.channelLabel,
                    channelType: self.channel.type != 0 ? self.channel.type : MezonConstants.ChannelType.channel.rawValue,
                    needsChannelMemberFilter: isPrivateOrThread
                )
                self.navigationController?.pushViewController(searchVC, animated: true)
            },
            onHistoryTapped: { },
            onMenuTapped: { },
            onScrolledNearTop: { [weak self] in
                guard let self, !self.isJumping, self.readyToLoadMore, self.hasMoreOlder, !self.isLoadingMore else { return }
                self.fetchOlderMessages()
            },
            onScrolledNearBottom: { [weak self] in
                guard let self, !self.isJumping, self.readyToLoadMore, self.hasMoreNewer, !self.isLoadingNewer else { return }
                self.fetchNewerMessages()
            },
            onScrolledToBottom: { [weak self] atBottom in
                guard let self else { return }
                self.shouldScrollToBottom = atBottom
                if atBottom && (self.hasPerformedInitialUnreadScroll || self.lastSeenMessageId == nil) {
                    self.clearLastSeenMessageId()
                }
            },
            onJumpToPresent: { [weak self] in self?.jumpToPresent() },
            onMentionTapped: { [weak self] mentionId in
                self?.showMemberProfileById(mentionId)
            },
            onHashtagTapped: { [weak self] channelId in
                guard let self, !channelId.isEmpty else { return }
                AppLogger.network.info("[Chat] Hashtag tapped: \(channelId)")
                guard channelId != "\(self.channel.channelID)" else { return }
                AppDelegate.navigateToChannel(channelId: channelId, clanId: "\(self.clanId)")
            },
            onMessageLongPressed: { [weak self] display in
                self?.showMessageActions(display)
            },
            onReplyTapped: { [weak self] messageId in
                self?.jumpToMessage(id: messageId)
            },
            onTopicTapped: { [weak self] topicData in
                self?.openTopicDiscussion(topicData: topicData)
            },
            onReactionTapped: { [weak self] reaction, display in
                self?.handleEmojiReaction(emojiId: reaction.emojiId, shortname: reaction.emoji, display: display)
            },
            onAvatarTapped: { [weak self] display in
                self?.showMemberProfile(display)
            },
            onSwipeReply: { [weak self] display in
                self?.sendInputViewController.setReply(display)
            },
            onMessagesReloaded: nil
        )
        interaction.onMessagesReloaded = { [weak self] in
            guard let self else { return }
            if let seenId = self.lastSeenMessageId {
                self.scrollToUnreadLine(lastSeenId: seenId)
                self.hasPerformedInitialUnreadScroll = true
            } else {
                self.hasPerformedInitialUnreadScroll = true
                self.scrollToBottomIfNeeded()
            }
        }
        displayNode = ChatContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        messagesNode.applyTheme()
        setupInputBar()
        start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.readyToLoadMore = true
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSocketReconnected(_:)), name: .mezonSocketStatusChanged, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { onLeave() }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout

        let keyboardHeight = layout.inputHeight ?? 0
        let bottomInset = layout.intrinsicInsets.bottom
        var keyboardOffset = max(keyboardHeight - bottomInset, 0)

        // Safety: if local keyboard tracking says keyboard is hidden,
        // verify via first-responder before accepting a non-zero offset.
        if !isKeyboardVisible && keyboardOffset > 0 {
            let hasFirstResponder = sendInputViewController.view.findFirstResponder() != nil
            if !hasFirstResponder {
                keyboardOffset = 0
            }
        }

        let inputBarY = layout.size.height - bottomInset - keyboardOffset - inputBarHeight
        let inputBarFrame = CGRect(x: 0, y: inputBarY, width: layout.size.width, height: inputBarHeight)
        transition.updateFrame(view: sendInputViewController.view, frame: inputBarFrame)

        if keyboardOffset > 0 && currentKeyboardOffset == 0 {
            scrollToBottomIfNeeded()
        }
        currentKeyboardOffset = keyboardOffset

        messagesNode.updateLayout(layout: layout, inputBarHeight: inputBarHeight + keyboardOffset, transition: transition)
    }

    private var lastLayout: ContainerViewLayout?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Re-evaluate keyboard state when returning to this screen.
        // The window layout may carry a stale inputHeight from a previous VC.
        let hasFirstResponder = sendInputViewController.view.findFirstResponder() != nil
        if !hasFirstResponder {
            isKeyboardVisible = false
            trackedKeyboardHeight = 0
        }
        if let layout = lastLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    @objc private func handleThemeChange() { messagesNode.applyTheme() }

    @objc private func handleSocketReconnected(_ notification: Notification) {
        guard let isConnected = notification.userInfo?["isConnected"] as? Bool, isConnected else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            self.fetchMessages(token: token)
            self.joinChat()
            if !self.hasCompletedInitialFetch {
                self.hasCompletedInitialFetch = true
                self.fetchNotificationSetting(token: token)
                self.fetchChannelPermissions(token: token)
                self.fetchChannelMembers(token: token)
                self.checkBanStatus(token: token)
            }
        }
    }

    deinit {
        stateDisposables.dispose()
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func setMessages(_ v: [ChatMessageDisplay]) {
        let oldFirstId = messages.first(where: { !$0.isWelcome })?.id
        let oldLastId = messages.last?.id
        let oldCount = messages.count
        let oldReactionsCount = messages.reduce(0) { $0 + $1.reactions.count }
        messages = v
        let newReactionsCount = v.reduce(0) { $0 + $1.reactions.count }
        let newFirstId = v.first(where: { !$0.isWelcome })?.id
        let newLastId = v.last?.id
        if newFirstId != oldFirstId { lastFetchedOlderMessageId = nil }
        if newLastId != oldLastId { lastFetchedNewerMessageId = nil }
        needsReloadPipe.putNext(())
        markChannelAsRead()

        if let jumpId = pendingJumpToMessageId, !v.isEmpty {
            pendingJumpToMessageId = nil
            DispatchQueue.main.async { [weak self] in
                self?.jumpToMessage(id: jumpId)
            }
        } else if pendingScrollToBottom && !v.isEmpty {
            pendingScrollToBottom = false
            DispatchQueue.main.async { [weak self] in
                self?.forceScrollToBottom()
            }
        }
    }
    private func setChannelLabel(_ v: String) { channelLabel = v; needsReloadPipe.putNext(()) }
    private func clearLastSeenMessageId() {
        guard lastSeenMessageId != nil else { return }
        lastSeenMessageId = nil
        metadataOnlyPipe.putNext(())
    }
    private func setHasMoreOlder(_ v: Bool) { hasMoreOlder = v; metadataOnlyPipe.putNext(()) }
    private func setHasMoreNewer(_ v: Bool) { hasMoreNewer = v; metadataOnlyPipe.putNext(()) }
    private func setIsLoadingMore(_ v: Bool) { isLoadingMore = v; metadataOnlyPipe.putNext(()) }
    private func setIsLoadingNewer(_ v: Bool) { isLoadingNewer = v; metadataOnlyPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) { isLoading = v; metadataOnlyPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; metadataOnlyPipe.putNext(()) }

    private var hasCompletedInitialFetch = false

    func start() {
        if topicId == 0 {
            context.currentClanId = clanId
            context.currentChannel = channel
            ActiveChannelTracker.currentChannelId = channel.channelID
            Self.removeDeliveredNotifications(forChannelId: channel.channelID)
        }

        if channel.channelLabel.isEmpty {
            resolveChannelLabelFromCache()
        }

        let channelIdStr = storageChannelId

        setIsLoading(true)
        context.account.postbox.write { tx in
            tx.replaceAllMessages([], channelId: channelIdStr)
        }

        stateDisposables.add(
            (self.context.account.postbox.messageHistoryView(channelId: channelIdStr)
                |> deliverOnMainQueue)
                .start(next: { [weak self] view in
                    guard let self else { return }
                    let displays = self.buildDisplayMessages(from: view.messages)
                    self.setMessages(displays)
                })
        )
        stateDisposables.add(
            (self.context.account.postbox.channelMetaView(channelId: channel.channelID) |> deliverOnMainQueue)
                .start(next: { [weak self] view in
                    guard let self else { return }
                    self.channelMeta = view.record
                })
        )
        if channel.type == MezonConstants.ChannelType.thread.rawValue && channel.parentID != 0 {
            stateDisposables.add(
                (self.context.account.postbox.channelMetaView(channelId: channel.parentID)
                    |> deliverOnMainQueue)
                    .start(next: { [weak self] view in
                        guard let self else { return }
                        self.parentChannelMeta = view.record
                        self.metadataOnlyPipe.putNext(())
                    })
            )
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.context.waitForSessionReady()
            guard let token = await self.context.getToken() else {
                AppLogger.network.warning("[Chat] start: getToken returned nil, will retry on socket reconnect")
                return
            }
            self.hasCompletedInitialFetch = true
            self.fetchMessages(token: token)
            self.joinChat()
            self.fetchNotificationSetting(token: token)
            self.fetchChannelPermissions(token: token)
            self.fetchChannelMembers(token: token)
            self.checkBanStatus(token: token)
            self.resolveChannelLabelFromNetwork(token: token)
        }
    }

    private func resolveChannelLabelFromCache() {
        if clanId == 0 {
            if let cached = context.account.postbox.getDMChannelDescription(channelId: channel.channelID),
               !cached.channelLabel.isEmpty {
                channel = cached
                setChannelLabel(cached.channelLabel)
            }
        } else {
            if let (_, cached) = context.account.postbox.getChannelDescription(channelId: channel.channelID),
               !cached.channelLabel.isEmpty {
                channel = cached
                setChannelLabel(cached.channelLabel)
            }
        }
    }

    private func resolveChannelLabelFromNetwork(token: String) {
        guard channel.channelLabel.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if self.clanId == 0 {
                    let channels = try await self.context.account.network.listDirectMessageChannels(token: token)
                    if let found = channels.first(where: { $0.channelID == self.channel.channelID }) {
                        self.channel = found
                        self.setChannelLabel(found.channelLabel)
                    }
                } else {
                    let channels = try await self.context.account.network.listChannelDescs(clanId: self.clanId, token: token)
                    if let found = channels.first(where: { $0.channelID == self.channel.channelID }) {
                        self.channel = found
                        self.setChannelLabel(found.channelLabel)
                    }
                }
            } catch {
                AppLogger.network.error("[Chat] resolveChannelLabel failed: \(error)")
            }
        }
    }

    static func removeDeliveredNotifications(forChannelId channelId: Int64) {
        let center = UNUserNotificationCenter.current()
        let channelIdStr = "\(channelId)"

        center.getDeliveredNotifications { notifications in
            let matchingIds = notifications
                .filter { notification in
                    let userInfo = notification.request.content.userInfo
                    if let ch = userInfo["channel"] as? String { return ch == channelIdStr }
                    if let ch = userInfo["channel"] { return "\(ch)" == channelIdStr }
                    return false
                }
                .map { $0.request.identifier }

            guard !matchingIds.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: matchingIds)

            let shared = UserDefaults(suiteName: "group.mezon.mobile")
            let current = shared?.integer(forKey: "badgeCount") ?? 0
            let newCount = max(0, current - matchingIds.count)
            shared?.set(newCount, forKey: "badgeCount")

            DispatchQueue.main.async {
                if #available(iOS 16.0, *) {
                    UNUserNotificationCenter.current().setBadgeCount(newCount)
                } else {
                    UIApplication.shared.applicationIconBadgeNumber = newCount
                }
            }
        }
    }

    func onLeave() {
        context.currentChannel = nil
        ActiveChannelTracker.currentChannelId = 0
        stateDisposables.dispose()
    }

    private func markChannelAsRead() {
        guard !hasMarkedAsRead, !messages.isEmpty else { return }
        guard let lastMessage = messages.last else { return }
        guard let messageId = Int64(lastMessage.message.id) else { return }
        hasMarkedAsRead = true

        let channelUnreadCount = channel.countMessUnread

        let mode: Int32
        if clanId != 0 {
            mode = MezonConstants.ChannelStreamMode.channel.rawValue
        } else if channel.type == MezonConstants.ChannelType.dm.rawValue {
            mode = MezonConstants.ChannelStreamMode.dm.rawValue
        } else {
            mode = MezonConstants.ChannelStreamMode.group.rawValue
        }

        let now = UInt32(Date().timeIntervalSince1970)
        context.account.socket.writeLastSeenMessage(
            clanId: clanId,
            channelId: channel.channelID,
            mode: mode,
            messageId: messageId,
            timestampSeconds: now,
            badgeCount: 0
        )

        NotificationCenter.default.post(
            name: Notification.Name("MezonChannelMarkedAsRead"),
            object: nil,
            userInfo: [
                "channelId": channel.channelID,
                "clanId": clanId,
                "channelUnreadCount": channelUnreadCount,
                "mode": mode,
                "messageId": String(messageId),
                "timestampSeconds": now
            ]
        )
    }

    func fetchMessages(token: String? = nil) {
        setIsLoading(true)
        setErrorMessage(nil)

        Task { @MainActor in
            defer { self.setIsLoading(false) }
            let resolvedToken: String?
            if let token { resolvedToken = token } else { resolvedToken = await self.context.getToken() }
            guard let token = resolvedToken else { return }
            do {
                var response = try await self.context.account.network.listChannelMessages(clanId: clanId, channelId: channel.channelID, messageId: 0, direction: 2, limit: 30, topicId: self.topicId, token: token)
                if response.messages.isEmpty {
                    response = try await self.context.account.network.listChannelMessages(clanId: clanId, channelId: channel.channelID, messageId: 0, direction: 3, limit: 30, topicId: self.topicId, token: token)
                }
                self.setHasMoreOlder(response.messages.count > 1)
                let records = response.messages.map { self.messageRecord(from: $0) }
                self.context.account.postbox.write { tx in
                    tx.replaceAllMessages(records, channelId: self.storageChannelId)
                }
            } catch {
                self.setErrorMessage(error.localizedDescription)
            }
        }
    }

    func fetchOlderMessages() {
        guard hasMoreOlder, !isLoadingMore else { return }
        guard messages.count >= 10 else { return }

        guard let oldest = messages.first(where: { !$0.isWelcome }),
              let msgId = Int64(oldest.message.id), msgId != 0 else {
            setHasMoreOlder(false)
            return
        }

        guard msgId != lastFetchedOlderMessageId else { return }
        lastFetchedOlderMessageId = msgId

        setIsLoadingMore(true)
        Task { @MainActor in
            defer { self.setIsLoadingMore(false) }
            guard let token = await self.context.getToken() else { return }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: clanId, channelId: channel.channelID,
                    messageId: msgId, direction: 3, limit: 30, topicId: self.topicId, token: token
                )
                self.setHasMoreOlder(!response.messages.isEmpty)
                if !response.messages.isEmpty {
                    self.context.account.postbox.write { tx in
                        tx.addMessages(response.messages.map { self.messageRecord(from: $0) })
                    }
                }
            } catch {
                self.setHasMoreOlder(false)
            }
        }
    }

    func fetchNewerMessages() {
        guard hasMoreNewer, !isLoadingNewer else { return }
        guard messages.count >= 10 else { return }
        guard let newest = messages.last, let msgId = Int64(newest.message.id) else { return }

        guard msgId != lastFetchedNewerMessageId else { return }
        lastFetchedNewerMessageId = msgId

        shouldScrollToBottom = false
        setIsLoadingNewer(true)
        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.setIsLoadingNewer(false)
                return
            }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: clanId, channelId: channel.channelID,
                    messageId: msgId, direction: 1, limit: 30, topicId: self.topicId, token: token
                )
                self.setHasMoreNewer(!response.messages.isEmpty)
                if !response.messages.isEmpty {
                    self.context.account.postbox.write { tx in
                        tx.addMessages(response.messages.map { self.messageRecord(from: $0) })
                    }
                    DispatchQueue.main.async {
                        self.setIsLoadingNewer(false)
                    }
                } else {
                    self.setIsLoadingNewer(false)
                }
            } catch {
                self.setHasMoreNewer(false)
                self.setIsLoadingNewer(false)
            }
        }
    }

    private func jumpToPresent() {
        shouldScrollToBottom = true
        pendingScrollToBottom = true
        setHasMoreNewer(false)

        Task { @MainActor in
            guard let token = await self.context.getToken() else {
                self.pendingScrollToBottom = false
                return
            }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: clanId, channelId: channel.channelID,
                    messageId: 0, direction: 2, limit: 30, topicId: self.topicId, token: token
                )
                self.setHasMoreOlder(response.messages.count >= 30)
                self.context.account.postbox.write { tx in
                    tx.replaceAllMessages(
                        response.messages.map { self.messageRecord(from: $0) },
                        channelId: self.storageChannelId
                    )
                }
            } catch {
                self.pendingScrollToBottom = false
                self.setErrorMessage(error.localizedDescription)
            }
        }
    }


    private func fetchNotificationSetting(token: String? = nil) {
        let channelId = channel.channelID
        Task { @MainActor in
            let resolvedToken: String
            if let token { resolvedToken = token } else if let t = await self.context.getToken() { resolvedToken = t } else { return }
            let token = resolvedToken
            do {
                let response = try await self.context.account.network.getNotificationChannel(channelId: channelId, token: token)
                let record = NotificationSettingRecord(from: response)
                self.context.account.postbox.write { tx in
                    tx.updateNotificationSetting(record)
                }
            } catch {
                AppLogger.network.warning("[ChannelMessages] fetchNotificationSetting failed: \(error)")
            }
        }
    }

    private func fetchChannelPermissions(token: String? = nil) {
        let channelId = channel.channelID
        Task { @MainActor in
            let resolvedToken: String
            if let token { resolvedToken = token } else if let t = await self.context.getToken() { resolvedToken = t } else { return }
            let token = resolvedToken
            do {
                let response = try await self.context.account.network.listUserPermissionInChannel(clanId: clanId, channelId: channelId, token: token)
                let records = response.permissions.permissions.map { PermissionRecord(from: $0) }
                self.context.account.postbox.write { tx in
                    tx.updateChannelPermissions(records, channelId: channelId)
                }
            } catch {
                AppLogger.network.warning("[ChannelMessages] fetchChannelPermissions failed: \(error)")
            }
        }
    }

    private func fetchChannelMembers(token: String? = nil) {
        let channelId = channel.channelID
        let channelType: Int32 = clanId == 0
            ? (channel.type != 0 ? channel.type : MezonConstants.ChannelType.group.rawValue)
            : (channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue)

        Task { @MainActor in
            let resolvedToken: String
            if let token { resolvedToken = token } else if let t = await self.context.getToken() { resolvedToken = t } else { return }
            let token = resolvedToken
            do {
                if channel.parentID != 0 {
                    let parentResponse = try await self.context.account.network.listChannelUsers(
                        clanId: clanId,
                        channelId: channel.parentID,
                        channelType: MezonConstants.ChannelType.channel.rawValue,
                        token: token
                    )
                    let parentMembers = parentResponse.channelUsers.map { ChannelMemberRecord(from: $0) }
                    self.context.account.postbox.write { tx in
                        tx.updateChannelMembers(parentMembers, channelId: self.channel.parentID)
                    }
                }

                if channel.channelPrivate != 0 || channel.parentID != 0 {
                    let response = try await self.context.account.network.listChannelUsers(
                        clanId: clanId,
                        channelId: channelId,
                        channelType: channelType,
                        token: token
                    )
                    let members = response.channelUsers.map { ChannelMemberRecord(from: $0) }
                    self.context.account.postbox.write { tx in
                        tx.updateChannelMembers(members, channelId: channelId)
                    }
                }
            } catch {
                AppLogger.network.warning("[ChannelMessages] fetchChannelMembers failed: \(error)")
            }
        }
    }

    private func checkBanStatus(token: String? = nil) {
        let channelId = channel.channelID
        let isPublic = clanId != 0 && channel.parentID == 0 && channel.channelPrivate == 0
        guard isPublic else { return }

        Task { @MainActor in
            let resolvedToken: String
            if let token { resolvedToken = token } else if let t = await self.context.getToken() { resolvedToken = t } else { return }
            let token = resolvedToken
            do {
                let response = try await self.context.account.network.isBanned(channelId: channelId, token: token)
                self.context.account.postbox.write { tx in
                    tx.updateBanStatus(isBanned: response.isBanned, expiredBanTime: response.expiredBanTime, channelId: channelId)
                }
            } catch {
                AppLogger.network.warning("[ChannelMessages] checkBanStatus failed: \(error)")
            }
        }
    }

    var currentState: ChatState {
        let labelFromMeta = parentChannelMeta?.label
        let resolvedParentName =
            (labelFromMeta?.isEmpty == false) ? labelFromMeta : initialParentName

        return ChatState(
            messages: messages,
            channelLabel: channelLabel,
            channelType: channel.type,
            isPrivate: channel.channelPrivate != 0,
            isAgeRestricted: channel.ageRestricted != 0,
            hasMoreOlder: hasMoreOlder,
            hasMoreNewer: hasMoreNewer,
            isLoadingMore: isLoadingMore,
            isLoadingNewer: isLoadingNewer,
            isLoading: isLoading,
            errorMessage: errorMessage,
            lastSeenMessageId: lastSeenMessageId,
            currentUserId: context.currentUser?.id,
            parentName: resolvedParentName
        )
    }

    func stateSignal() -> Signal<ChatState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var lastIds = self.messages.map { $0.id }
            var lastSendingStates = self.messages.map { $0.sendingState }
            var lastReactions = self.messages.map { $0.reactions }
            var lastLoading = self.isLoading
            var lastLoadingMore = self.isLoadingMore
            var lastLoadingNewer = self.isLoadingNewer
            var lastError = self.errorMessage
            var lastHasMoreOlder = self.hasMoreOlder
            var lastHasMoreNewer = self.hasMoreNewer
            var lastLastSeenMessageId = self.lastSeenMessageId
            var lastParentName = self.currentState.parentName
            subscriber.putNext(self.currentState)
            let merged = Signal<Void, NoError> { subscriber in
                let d1 = self.needsReloadPipe.signal().start(next: { subscriber.putNext(()) })
                let d2 = self.metadataOnlyPipe.signal().start(next: { subscriber.putNext(()) })
                return ActionDisposable { d1.dispose(); d2.dispose() }
                }
            return (merged
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { newState in
                    let newIds = newState.messages.map { $0.id }
                    let newSendingStates = newState.messages.map { $0.sendingState }
                    let newReactions = newState.messages.map { $0.reactions }
                let changed = newIds != lastIds
                        || newSendingStates != lastSendingStates
                        || newReactions != lastReactions
                        || newState.isLoading != lastLoading
                        || newState.isLoadingMore != lastLoadingMore
                        || newState.isLoadingNewer != lastLoadingNewer
                        || newState.errorMessage != lastError
                        || newState.hasMoreOlder != lastHasMoreOlder
                        || newState.hasMoreNewer != lastHasMoreNewer
                        || newState.lastSeenMessageId != lastLastSeenMessageId
                        || newState.parentName != lastParentName
                    guard changed else { return }
                    lastIds = newIds
                    lastSendingStates = newSendingStates
                    lastReactions = newReactions
                    lastLoading = newState.isLoading
                    lastLoadingMore = newState.isLoadingMore
                    lastLoadingNewer = newState.isLoadingNewer
                    lastError = newState.errorMessage
                    lastHasMoreOlder = newState.hasMoreOlder
                    lastHasMoreNewer = newState.hasMoreNewer
                    lastLastSeenMessageId = newState.lastSeenMessageId
                    lastParentName = newState.parentName
                    subscriber.putNext(newState)
                })
        }
    }



    private func buildDisplayMessages(from records: [MessageRecord]) -> [ChatMessageDisplay] {
        let currentUserId = context.currentUser?.id
        let validRecords = records.filter { !$0.id.isEmpty && !$0.channelId.isEmpty }

        // Gather current user's role IDs for role-mention matching
        let currentUserRoleIds: Set<Int64> = {
            guard let roleList = context.engine.clanData.getUserPermissions(clanId: clanId) else { return [] }
            return Set(roleList.roles.map { $0.id })
        }()

        let currentPendingIds = Set(validRecords.compactMap { $0.id.hasPrefix("pending-") ? $0.id : nil })
        for cachedId in ParsedAttachment.pendingImageCache.keys where !currentPendingIds.contains(cachedId) {
            ParsedAttachment.pendingImageCache.removeValue(forKey: cachedId)
        }

        let displays = validRecords.map { record -> ChatMessageDisplay in
            let parsed = MessageContentParser.parse(data: record.content, mentionsData: record.mentionsJSON)
            let content = parsed.text
            let msg = Message(id: record.id, channelId: record.channelId, clanId: record.clanId, senderId: record.senderId, content: .text(content), createdAt: record.createdAt, editedAt: record.editedAt, isDeleted: record.isDeleted, reactions: [], replyToId: nil, mentionedUserIds: [], isPinned: false)

            var attachments = Self.parseAttachments(record.attachmentsJSON)
            if record.id.hasPrefix("pending-"),
               let localImages = ParsedAttachment.pendingImageCache[record.id], !localImages.isEmpty {
                let stillUploading = record.sendingState == .pending
                attachments = localImages.map { image in
                    ParsedAttachment(
                        url: "",
                        filename: "uploading.jpg",
                        filetype: "image/jpeg",
                        width: Int(image.size.width),
                        height: Int(image.size.height),
                        localImage: image,
                        isUploading: stillUploading
                    )
                }
            }

            let reactions = Self.parseReactions(record.reactionsJSON, currentUserId: currentUserId)
            let (replyRef, isDeletedReply) = Self.firstReplyRef(from: record.referencesData)
            let isWelcome = record.senderId == "0"
                && parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && record.senderDisplayName.lowercased() == "system"
            let callLog = Self.parseCallLog(from: record.content)
            let topicData = Self.parseTopicData(from: record.content, code: record.code)
            let isMe = currentUserId != nil && record.senderId == currentUserId
            let hasMention = Self.checkIncludeMention(
                mentionsData: record.mentionsJSON,
                referencesData: record.referencesData,
                currentUserId: currentUserId,
                currentUserRoleIds: currentUserRoleIds
            )
            return ChatMessageDisplay(message: msg, senderDisplayName: record.senderDisplayName, avatarURL: record.senderAvatarURL, isCombine: false, attachments: attachments, reactions: reactions, parsedContent: parsed, replyRef: replyRef, isDeletedReply: isDeletedReply, isWelcome: isWelcome, callLog: callLog, topicData: topicData, isMe: isMe, sendingState: record.sendingState, hasIncludeMention: hasMention)
        }
        return Self.applyCombine(to: displays)
    }

    private static func firstReplyRef(from data: Data) -> (ref: Mezon_Api_MessageRef?, isDeletedReply: Bool) {
        guard !data.isEmpty,
            let list = try? Mezon_Api_MessageRefList(serializedBytes: data),
              !list.refs.isEmpty else { return (nil, false) }
        if let validRef = list.refs.first(where: { $0.messageRefID != 0 }) {
            return (validRef, false)
        }
        if list.refs.first(where: { $0.messageRefID == 0 }) != nil {
            return (nil, true)
        }
        return (nil, false)
    }

    private func messageRecord(from api: Mezon_Api_ChannelMessage) -> MessageRecord {
        var record = MessageRecord(from: api)
        if topicId != 0 {
            record = MessageRecord(
                id: record.id, channelId: storageChannelId, clanId: record.clanId,
                senderId: record.senderId, content: record.content,
                createdAt: record.createdAt, editedAt: record.editedAt,
                isDeleted: record.isDeleted, code: record.code,
                senderDisplayName: record.senderDisplayName,
                senderAvatarURL: record.senderAvatarURL, sendingState: record.sendingState,
                attachmentsJSON: record.attachmentsJSON, reactionsJSON: record.reactionsJSON,
                referencesData: record.referencesData, mentionsJSON: record.mentionsJSON
            )
        }
        return record
    }

    private static let messageCodeTopic: Int32 = 9

    private static func parseTopicData(from data: Data, code: Int32) -> TopicData? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        // Detect topic by code field OR by presence of "tp" in content
        let hasTp = json["tp"] != nil
        guard code == messageCodeTopic || hasTp else { return nil }
        let topicId: String
        if let tp = json["tp"] as? String, !tp.isEmpty { topicId = tp }
        else if let tp = json["tp"] as? Int, tp != 0 { topicId = "\(tp)" }
        else if let tp = json["tp"] as? Double, tp != 0 { topicId = "\(Int64(tp))" }
        else { return nil }
        let creatorId: String
        if let cid = json["cid"] as? String { creatorId = cid }
        else if let cid = json["cid"] as? Int { creatorId = "\(cid)" }
        else if let cid = json["cid"] as? Double { creatorId = "\(Int64(cid))" }
        else { creatorId = "" }
        let replyCount: Int
        if let rpl = json["rpl"] as? Int { replyCount = rpl }
        else if let rpl = json["rpl"] as? Double { replyCount = Int(rpl) }
        else { replyCount = 0 }
        return TopicData(topicId: topicId, creatorId: creatorId, replyCount: replyCount)
    }

    private static func parseCallLog(from data: Data) -> CallLogData? {
        guard !data.isEmpty,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let callLogDict = json["callLog"] as? [String: Any] else { return nil }
        let typeRaw = callLogDict["callLogType"] as? Int ?? 0
        let callLogType = CallLogType(rawValue: typeRaw) ?? .timeoutCall
        let isVideo = callLogDict["isVideo"] as? Bool ?? false
        return CallLogData(callLogType: callLogType, isVideo: isVideo)
    }

    private static func applyCombine(to displays: [ChatMessageDisplay]) -> [ChatMessageDisplay] {
        displays.enumerated().map { i, d in
            let prev = i > 0 ? displays[i - 1].message : nil
            let hasReply = d.replyRef != nil || d.isDeletedReply
            let combine = hasReply ? false : ChatMessageDisplay.isCombineWithPrevious(current: d.message, previous: prev)
            return ChatMessageDisplay(message: d.message, senderDisplayName: d.senderDisplayName, avatarURL: d.avatarURL, isCombine: combine, attachments: d.attachments, reactions: d.reactions, parsedContent: d.parsedContent, replyRef: d.replyRef, isDeletedReply: d.isDeletedReply, isWelcome: d.isWelcome, callLog: d.callLog, topicData: d.topicData, isMe: d.isMe, sendingState: d.sendingState, hasIncludeMention: d.hasIncludeMention)
        }
    }

    private static func checkIncludeMention(
        mentionsData: Data,
        referencesData: Data,
        currentUserId: String?,
        currentUserRoleIds: Set<Int64>
    ) -> Bool {
        guard let currentUserId, !currentUserId.isEmpty else { return false }

        let mentions = parseMentionList(from: mentionsData)
        for mention in mentions {
            // @here
            if mention.userID != 0, "\(mention.userID)" == ChatMessageDisplay.mentionHereUserId {
                return true
            }
            // Direct user mention
            if mention.userID != 0, "\(mention.userID)" == currentUserId {
                return true
            }
            // Role mention
            if mention.roleID != 0, currentUserRoleIds.contains(mention.roleID) {
                return true
            }
        }

        // Replied-to check
        if !referencesData.isEmpty,
           let list = try? Mezon_Api_MessageRefList(serializedBytes: referencesData),
           let firstRef = list.refs.first,
           firstRef.messageSenderID != 0,
           "\(firstRef.messageSenderID)" == currentUserId {
            return true
        }

        return false
    }

    private static func parseMentionList(from data: Data) -> [Mezon_Api_MessageMention] {
        guard !data.isEmpty else { return [] }
        if let list = try? Mezon_Api_MessageMentionList(serializedBytes: data), !list.mentions.isEmpty {
            return list.mentions
        }
        if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { item -> Mezon_Api_MessageMention? in
                var m = Mezon_Api_MessageMention()
                if let uid = item["user_id"] as? String, let v = Int64(uid) { m.userID = v }
                else if let uid = item["user_id"] as? Int64 { m.userID = uid }
                else if let uid = item["user_id"] as? Double { m.userID = Int64(uid) }
                if let rid = item["role_id"] as? String, let v = Int64(rid) { m.roleID = v }
                else if let rid = item["role_id"] as? Int64 { m.roleID = rid }
                else if let rid = item["role_id"] as? Double { m.roleID = Int64(rid) }
                return m
            }
        }
        return []
    }

    private static func parseAttachments(_ data: Data) -> [ParsedAttachment] {
        guard !data.isEmpty else { return [] }

        let isLikelyJson = data.first == UInt8(ascii: "[") || data.first == UInt8(ascii: "{")
        var fromProto: [ParsedAttachment]?
        var fromJson: [ParsedAttachment]?

        if !isLikelyJson,
            let list = try? Mezon_Api_MessageAttachmentList(serializedBytes: data),
           !list.attachments.isEmpty {
            fromProto = list.attachments.compactMap { att -> ParsedAttachment? in
                guard !att.url.isEmpty else { return nil }
                return ParsedAttachment(
                    url: att.url,
                    filename: att.filename,
                    filetype: att.filetype,
                    width: att.width != 0 ? Int(att.width) : nil,
                    height: att.height != 0 ? Int(att.height) : nil
                )
            }
        }

        if fromProto == nil || fromProto?.isEmpty == true {
            var jsonArray: [[String: Any]]?
            if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                jsonArray = arr
            } else if let str = String(data: data, encoding: .utf8),
                let strData = str.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: strData) as? [[String: Any]] {
                jsonArray = arr
            }
            if let json = jsonArray {
                fromJson = json.compactMap { item in
                    guard let url = item["url"] as? String, !url.isEmpty else { return nil }
                    let w = item["width"] as? Int ?? (item["width"] as? String).flatMap { Int($0) }
                    let h = item["height"] as? Int ?? (item["height"] as? String).flatMap { Int($0) }
                    return ParsedAttachment(
                        url: url,
                        filename: item["filename"] as? String ?? "",
                        filetype: item["filetype"] as? String ?? "",
                        width: w,
                        height: h
                    )
                }
            }
        }

        return (fromProto?.isEmpty == false ? fromProto : fromJson) ?? []
    }

    private static func parseReactions(_ data: Data, currentUserId: String?) -> [ParsedReaction] {
        guard !data.isEmpty else { return [] }

        let isLikelyJson = data.first == UInt8(ascii: "[") || data.first == UInt8(ascii: "{")
        var fromProto: [ParsedReaction]?
        var fromJson: [ParsedReaction]?

        if !isLikelyJson, let list = try? Mezon_Api_MessageReactionList(serializedBytes: data), !list.reactions.isEmpty {
            fromProto = parseReactionsFromProtobuf(list.reactions, currentUserId: currentUserId)
        }

        if fromProto == nil || fromProto?.isEmpty == true {
            if let anyJson = try? JSONSerialization.jsonObject(with: data) {
                let json: [[String: Any]]
                if let arr = anyJson as? [[String: Any]] {
                    json = arr
                } else if let dict = anyJson as? [String: Any], let arr = dict["reactions"] as? [[String: Any]] {
                    json = arr
                } else {
                    json = []
                }
                fromJson = parseReactionsFromJSON(json, currentUserId: currentUserId)
            }
        }

        let result = (fromProto?.isEmpty == false ? fromProto : fromJson) ?? []
        return result
    }

    private static func parseReactionsFromJSON(_ items: [[String: Any]], currentUserId: String?) -> [ParsedReaction] {
        var grouped: [String: (emoji: String, senderIds: [String], countFromApi: Int)] = [:]
        for item in items {
            let emojiId: String = {
                if let s = item["emoji_id"] as? String { return s }
                if let n = item["emoji_id"] as? Int { return "\(n)" }
                if let n = item["emoji_id"] as? Int64 { return "\(n)" }
                if let s = item["emojiid"] as? String { return s }
                if let n = item["emojiid"] as? Int { return "\(n)" }
                return ""
            }()
            let emoji = item["emoji"] as? String ?? ""
            let senderId: String = {
                if let s = item["sender_id"] as? String { return s }
                if let n = item["sender_id"] as? Int { return "\(n)" }
                if let n = item["sender_id"] as? Int64 { return "\(n)" }
                return ""
            }()
            let action = item["action"] as? Bool ?? true
            let countFromApi: Int = {
                if let n = item["count"] as? Int { return n }
                if let n = item["count"] as? Int32 { return Int(n) }
                if let n = item["count"] as? Int64 { return Int(n) }
                return 0
            }()
            let key = emojiId.isEmpty ? emoji : emojiId
            guard !key.isEmpty else { continue }

            if grouped[key] == nil {
                grouped[key] = (emoji: emoji, senderIds: [], countFromApi: 0)
            }
            if countFromApi > grouped[key]!.countFromApi {
                grouped[key]!.countFromApi = countFromApi
            }
            if action {
                if !grouped[key]!.senderIds.contains(senderId) {
                    grouped[key]!.senderIds.append(senderId)
                }
            } else {
                grouped[key]!.senderIds.removeAll { $0 == senderId }
            }
        }
        return grouped.compactMap { key, value in
            let count = max(value.senderIds.count, value.countFromApi)
            guard count > 0 else { return nil }
            let isMe = currentUserId.map { value.senderIds.contains($0) } ?? false
            return ParsedReaction(
                emojiId: key,
                emoji: value.emoji,
                count: count,
                senderIds: value.senderIds,
                isMe: isMe
            )
        }.sorted { $0.emojiId < $1.emojiId }
    }

    private static func parseReactionsFromProtobuf(_ reactions: [Mezon_Api_MessageReaction], currentUserId: String?) -> [ParsedReaction] {
        var grouped: [String: (emoji: String, senderIds: [String], countFromApi: Int32)] = [:]
        for r in reactions {
            let emojiKey = r.emojiID != 0 ? "\(r.emojiID)" : (r.emoji.isEmpty ? "?" : r.emoji)
            guard emojiKey != "?" || !r.emoji.isEmpty else { continue }
            let senderId = "\(r.senderID)"
            if grouped[emojiKey] == nil {
                grouped[emojiKey] = (emoji: r.emoji, senderIds: [], countFromApi: 0)
            }
            if r.count > grouped[emojiKey]!.countFromApi {
                grouped[emojiKey]!.countFromApi = r.count
            }
            if !r.action {
                if !grouped[emojiKey]!.senderIds.contains(senderId) {
                    grouped[emojiKey]!.senderIds.append(senderId)
                }
            } else {
                grouped[emojiKey]!.senderIds.removeAll { $0 == senderId }
            }
        }
        return grouped.compactMap { key, value in
            let count = max(Int(value.countFromApi), value.senderIds.count)
            guard count > 0 else { return nil }
            let isMe = currentUserId.map { value.senderIds.contains($0) } ?? false
            return ParsedReaction(
                emojiId: key,
                emoji: value.emoji,
                count: count,
                senderIds: value.senderIds,
                isMe: isMe
            )
        }.sorted { $0.emojiId < $1.emojiId }
    }

    private func joinChat() {
        self.context.account.socket.joinClanChat(clanId: clanId)
        let channelType: Int32 = clanId == 0
            ? (channel.type != 0 ? channel.type : MezonConstants.ChannelType.group.rawValue)
            : (channel.type != 0 ? channel.type : MezonConstants.ChannelType.channel.rawValue)
        let isPublic = clanId == 0 ? false : (channel.parentID != 0 ? false : (channel.channelPrivate == 0))
        self.context.account.socket.joinChannel(clanId: clanId, channelId: channel.channelID, channelType: channelType, isPublic: isPublic)
    }

    private func setupInputBar() {
        addChild(sendInputViewController)
        view.addSubview(sendInputViewController.view)
        sendInputViewController.didMove(toParent: self)

        inputBarHeight = sendInputViewController.totalHeight

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        messagesNode.listView.view.addGestureRecognizer(tap)
        messagesNode.listView.scroller.keyboardDismissMode = .onDrag

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        isKeyboardVisible = true
        if let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            trackedKeyboardHeight = frame.height
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        isKeyboardVisible = false
        trackedKeyboardHeight = 0
    }

    private func updateInputBarHeight(_ newHeight: CGFloat) {
        inputBarHeight = newHeight
        if let layout = lastLayout {
            containerLayoutUpdated(layout, transition: .animated(duration: 0.25, curve: .easeInOut))
        }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func jumpToMessage(id messageId: String) {
        shouldScrollToBottom = false
        isJumping = true

        if messages.contains(where: { $0.id == messageId }) {
            messagesNode.pendingJumpMessageId = messageId
            messagesNode.triggerPendingJump()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isJumping = false
            }
            return
        }

        guard let msgId = Int64(messageId) else {
            isJumping = false
            return
        }

        readyToLoadMore = false
        messagesNode.pendingJumpMessageId = messageId
        lastFetchedOlderMessageId = nil
        lastFetchedNewerMessageId = nil

        Task { @MainActor in
            defer {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.isJumping = false
                    self?.readyToLoadMore = true
                }
            }
            guard let token = await self.context.getToken() else { return }
            do {
                let response = try await self.context.account.network.listChannelMessages(
                    clanId: self.clanId,
                    channelId: self.channel.channelID,
                    messageId: msgId,
                    direction: 2,
                    limit: 30,
                    topicId: self.topicId,
                    token: token
                )
                guard !response.messages.isEmpty else {
                    self.messagesNode.pendingJumpMessageId = nil
                    return
                }
                self.setHasMoreOlder(response.messages.count > 1)
                self.setHasMoreNewer(true)
                self.context.account.postbox.write { tx in
                    tx.replaceAllMessages(
                        response.messages.map { self.messageRecord(from: $0) },
                        channelId: self.storageChannelId
                    )
                }
            } catch {
                self.messagesNode.pendingJumpMessageId = nil
                AppLogger.network.warning("[Chat] jumpToMessage failed: \(error)")
            }
        }
    }

    private func forceScrollToBottom() {
        guard !messages.isEmpty else { return }
        messagesNode.listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: ListViewScrollToItem(index: 0, position: .top(0), animated: false, curve: .Default(duration: nil), directionHint: .Up),
            updateOpaqueState: nil,
            completion: { _ in }
        )
    }

    private func scrollToBottomIfNeeded() {
        guard messagesNode.pendingJumpMessageId == nil else { return }
        guard !messagesNode.didAutoScrollForNewMessages else { return }
        guard shouldScrollToBottom, !messages.isEmpty else { return }
        messagesNode.listView.transaction(
            deleteIndices: [],
            insertIndicesAndItems: [],
            updateIndicesAndItems: [],
            options: [.Synchronous],
            scrollToItem: ListViewScrollToItem(index: 0, position: .top(0), animated: true, curve: .Spring(duration: 0.3), directionHint: .Up),
            updateOpaqueState: nil,
            completion: { _ in }
        )
    }

    private func scrollToUnreadLine(lastSeenId: String) {
        guard messagesNode.pendingJumpMessageId == nil else { return }
        guard !messages.isEmpty else { return }
        if let lineIndex = messagesNode.committedMessageIds.firstIndex(of: ChatContainerNode.unreadLineId) {
            messagesNode.listView.transaction(
                deleteIndices: [],
                insertIndicesAndItems: [],
                updateIndicesAndItems: [],
                options: [.Synchronous],
                scrollToItem: ListViewScrollToItem(index: lineIndex, position: .center(.bottom), animated: false, curve: .Default(duration: nil), directionHint: .Down),
                updateOpaqueState: nil,
                completion: { _ in }
            )
        }
    }

    private func openTopicDiscussion(topicData: TopicData) {
        guard let topicIdInt = Int64(topicData.topicId), topicIdInt != 0 else { return }
        var topicChannel = channel
        topicChannel.channelLabel = "Topic Discussion"
        let topicVC = ChatViewController(
            clanId: clanId, channel: topicChannel, context: context, parentName: nil)
        topicVC.topicId = topicIdInt
        navigationController?.pushViewController(topicVC, animated: true)
    }

    private func showMemberProfile(_ display: ChatMessageDisplay) {
        let senderId = display.message.senderId
        guard senderId != context.currentUser?.id else { return }
        guard let senderIdInt = Int64(senderId) else { return }

        var user = Mezon_Api_User()
        user.id = senderIdInt
        user.displayName = display.senderDisplayName
        if let urlStr = display.avatarURL {
            user.avatarURL = urlStr
        }

        view.endEditing(true)

        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            }
        )
        presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private func showMemberProfileById(_ userId: String) {
        guard userId != context.currentUser?.id else { return }
        guard let userIdInt = Int64(userId) else { return }

        var user = Mezon_Api_User()
        user.id = userIdInt
        if let clanUsers = context.engine.clanData.getClanUsers(clanId: context.currentClanId) {
            if let found = clanUsers.clanUsers.first(where: { $0.user.id == userIdInt }) {
                user = found.user
            }
        }
        if user.displayName.isEmpty, let allUsers = context.engine.clanData.getAllUserClans() {
            if let found = allUsers.users.first(where: { $0.id == userIdInt }) {
                user = found
            }
        }

        view.endEditing(true)

        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                self.context.currentClanId = 0
                let chatVC = ChatViewController(
                    clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            }
        )
        presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }

    private weak var activeActionSheet: MessageActionSheetController?

    private func showMessageActions(_ display: ChatMessageDisplay) {
        view.endEditing(true)
        let isOwnMessage = display.message.senderId == context.currentUser?.id
        let controller = MessageActionSheetController(display: display, isOwnMessage: isOwnMessage) { [weak self] action in
            self?.handleMessageAction(action, display: display)
        }
        controller.onDismiss = { [weak self] in
            self?.activeActionSheet = nil
            self?.dismissMessageHighlight(for: display.id)
        }
        controller.onEmojiReaction = { [weak self] emojiId, shortname in
            self?.handleEmojiReaction(emojiId: emojiId, shortname: shortname, display: display)
        }
        activeActionSheet = controller
        self.presentInGlobalOverlay(controller)
        controller.animateIn()
    }

    private func dismissMessageHighlight(for messageId: String) {
        messagesNode.listView.forEachItemNode { node in
            if let itemNode = node as? ChatMessageItemNode {
                for sub in itemNode.subnodes ?? [] {
                    if let bubble = sub as? MessageBubbleNode {
                        bubble.dismissHighlight()
                    }
                }
            }
        }
    }

    private func handleEmojiReaction(emojiId: String, shortname: String, display: ChatMessageDisplay) {
        guard let msgId = Int64(display.message.id) else { return }
        guard let emojiIdInt = Int64(emojiId) else { return }
        let senderId = Int64(display.message.senderId) ?? 0

        let mode: Int32
        if clanId != 0 {
            mode = MezonConstants.ChannelStreamMode.channel.rawValue
        } else if channel.type == MezonConstants.ChannelType.dm.rawValue {
            mode = MezonConstants.ChannelStreamMode.dm.rawValue
        } else {
            mode = MezonConstants.ChannelStreamMode.group.rawValue
        }

        let isPublic = clanId != 0 && channel.parentID == 0 && channel.channelPrivate == 0

        Task { @MainActor in
            guard let token = await self.context.getToken() else { return }
            do {
                let _ = try await self.context.account.network.writeMessageReaction(
                    clanId: self.clanId,
                    channelId: self.channel.channelID,
                    mode: mode,
                    isPublic: isPublic,
                    messageId: msgId,
                    emojiId: emojiIdInt,
                    emoji: shortname,
                    count: 1,
                    messageSenderId: senderId,
                    actionDelete: false,
                    topicId: self.topicId,
                    token: token
                )
            } catch {
                AppLogger.network.warning("[Chat] writeMessageReaction failed: \(error)")
            }
        }
    }

    private func handleMessageAction(_ action: MessageAction, display: ChatMessageDisplay) {
        switch action {
        case .reply:
            sendInputViewController.setReply(display)
            sendInputViewController.view.becomeFirstResponder()
        case .copyText:
            UIPasteboard.general.string = display.parsedContent.text
            Toast.success(L(L10n.MessageAction.copied))
        case .deleteMessage:
            let msgId = display.message.id
            if let msgIdInt = Int64(msgId) {
                let mode: Int32
                if clanId != 0 {
                    mode = MezonConstants.ChannelStreamMode.channel.rawValue
                } else if channel.type == MezonConstants.ChannelType.dm.rawValue {
                    mode = MezonConstants.ChannelStreamMode.dm.rawValue
                } else {
                    mode = MezonConstants.ChannelStreamMode.group.rawValue
                }
                let isPublic = clanId != 0 && channel.parentID == 0 && channel.channelPrivate == 0
                context.account.socket.removeChannelMessage(
                    clanId: clanId,
                    channelId: channel.channelID,
                    mode: mode,
                    messageId: msgIdInt,
                    isPublic: isPublic,
                    topicId: topicId
                )
            }
            context.account.postbox.write { tx in tx.deleteMessage(id: msgId) }
        case .pinMessage:
            break // TODO: implement pin
        case .forward, .forwardMessage:
            break // TODO: implement forward
        case .resend:
            let msgId = display.message.id
            let text = display.parsedContent.text
            context.account.postbox.write { tx in tx.deleteMessage(id: msgId) }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sendInputViewController.updateText(text)
                sendInputViewController.send()
            }
        case .giveACoffee:
            break // TODO: implement give coffee
        case .createThread:
            break // TODO: implement create thread
        case .markUnread:
            break // TODO: implement mark unread
        case .topicDiscussion:
            break // TODO: implement topic discussion
        case .markMessage:
            break // TODO: implement mark message
        case .quickMenu:
            break // TODO: implement quick menu
        case .editMessage:
            break // TODO: implement edit message
        case .report:
            break // TODO: implement report
        }
    }
}
