import UIKit
import SwiftProtobuf

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
    var id: String { message.id }

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
}

struct ChatState {
    var messages: [ChatMessageDisplay]
    var channelLabel: String
    var channelType: Int32
    var isPrivate: Bool
    var isAgeRestricted: Bool
    var hasMoreOlder: Bool
    var isLoadingMore: Bool
    var isLoading: Bool
    var errorMessage: String?

    static let empty = ChatState(messages: [], channelLabel: "", channelType: 0, isPrivate: false, isAgeRestricted: false, hasMoreOlder: false, isLoadingMore: false, isLoading: false, errorMessage: nil)
}

final class ChatViewController: ViewController {

    let clanId: Int64
    let channel: Mezon_Api_ChannelDescription
    let context: AccountContext

    private let needsReloadPipe = ValuePipe<Void>()
    var needsReloadSignal: Signal<Void, NoError> { needsReloadPipe.signal() }
    private let stateDisposables = DisposableSet()

    private(set) var messages: [ChatMessageDisplay] = []
    private(set) var channelLabel: String = ""
    private(set) var hasMoreOlder: Bool = true
    private(set) var isLoadingMore: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var channelMeta: ChannelRecord?

    private lazy var sendInputViewController: SendMessageInputViewController = {
        let vc = SendMessageInputViewController(
            placeholder: L(L10n.ChannelMessages.writeMessage),
            channel: channel,
            clanId: clanId,
            context: context
        )
        vc.onSent = { [weak self] in self?.shouldScrollToBottom = true }
        vc.onError = { Toast.error($0) }
        vc.onHeightChanged = { [weak self] newHeight in
            self?.updateInputBarHeight(newHeight)
        }
        return vc
    }()

    private var inputBarBottomConstraint: NSLayoutConstraint?
    private var inputBarHeightConstraint: NSLayoutConstraint?
    private var inputBarHeight: CGFloat = 56
    private var currentKeyboardOffset: CGFloat = 0
    private var shouldScrollToBottom = true
    private var hasMarkedAsRead = false

    private var messagesNode: ChatContainerNode { displayNode as! ChatContainerNode }

    init(clanId: Int64, channel: Mezon_Api_ChannelDescription, context: AccountContext) {
        self.clanId = clanId
        self.channel = channel
        self.context = context
        self.channelLabel = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        var interaction = ChatInteraction(
            onBackTapped: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onSearchTapped: { },
            onHistoryTapped: { },
            onMenuTapped: { },
            onScrolledNearTop: { [weak self] in
                guard let self, self.hasMoreOlder, !self.isLoadingMore else { return }
                self.fetchMoreMessages()
            },
            onScrolledToBottom: { [weak self] atBottom in self?.shouldScrollToBottom = atBottom },
            onMentionTapped: { mentionId in
                AppLogger.network.info("[Chat] Mention tapped: \(mentionId)")
            },
            onHashtagTapped: { channelId in
                AppLogger.network.info("[Chat] Hashtag tapped: \(channelId)")
            },
            onMessageLongPressed: { [weak self] display in
                self?.showMessageActions(display)
            },
            onMessagesReloaded: nil
        )
        interaction.onMessagesReloaded = { [weak self] in self?.scrollToBottomIfNeeded() }
        displayNode = ChatContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        messagesNode.applyTheme()
        setupInputBar()
        setupKeyboardObservers()
        start()

        stateDisposables.add((needsReloadSignal |> deliverOnMainQueue).start(next: { [weak self] _ in
            DispatchQueue.main.async { self?.scrollToBottomIfNeeded() }
        }))

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent { onLeave() }
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout
        messagesNode.updateLayout(layout: layout, inputBarHeight: inputBarHeight + currentKeyboardOffset, transition: transition)
    }

    private var lastLayout: ContainerViewLayout?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let layout = lastLayout {
            messagesNode.updateLayout(layout: layout, inputBarHeight: inputBarHeight, transition: .immediate)
        }
    }

    @objc private func handleThemeChange() { messagesNode.applyTheme() }

    deinit { stateDisposables.dispose() }

    private func setMessages(_ v: [ChatMessageDisplay]) {
        messages = v
        needsReloadPipe.putNext(())
        markChannelAsRead()
    }
    private func setChannelLabel(_ v: String) { channelLabel = v; needsReloadPipe.putNext(()) }
    private func setHasMoreOlder(_ v: Bool) { hasMoreOlder = v }
    private func setIsLoadingMore(_ v: Bool) { isLoadingMore = v; needsReloadPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) { isLoading = v; needsReloadPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; needsReloadPipe.putNext(()) }

    func start() {
        context.currentClanId = clanId
        context.currentChannel = channel
        ActiveChannelTracker.currentChannelId = channel.channelID

        let channelIdStr = "\(channel.channelID)"
        stateDisposables.add(
            (self.context.account.postbox.messageHistoryView(channelId: channelIdStr) |> deliverOnMainQueue)
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
        fetchMessages()
        joinChat()
        fetchNotificationSetting()
        fetchChannelPermissions()
        fetchChannelMembers()
        checkBanStatus()
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

    func fetchMessages() {
        guard let token = context.session?.token else { return }
        setIsLoading(true)
        setErrorMessage(nil)

        Task { @MainActor in
            defer { self.setIsLoading(false) }
            do {
                var response = try await self.context.account.network.listChannelMessages(clanId: clanId, channelId: channel.channelID, messageId: 0, direction: 2, limit: 50, topicId: 0, token: token)
                if response.messages.isEmpty {
                    response = try await self.context.account.network.listChannelMessages(clanId: clanId, channelId: channel.channelID, messageId: 0, direction: 3, limit: 50, topicId: 0, token: token)
                }
                self.setHasMoreOlder(response.messages.count >= 50)
                self.context.account.postbox.write { tx in tx.addMessages(response.messages.map { MessageRecord(from: $0) }) }
            } catch {
                self.setErrorMessage(error.localizedDescription)
            }
        }
    }

    func fetchMoreMessages() {
        guard hasMoreOlder, !isLoadingMore else { return }
        guard let token = context.session?.token else { return }
        guard let oldest = messages.first, let msgId = Int64(oldest.message.id) else { return }

        setIsLoadingMore(true)
        Task { @MainActor in
            defer { self.setIsLoadingMore(false) }
            do {
                let response = try await self.context.account.network.listChannelMessages(clanId: clanId, channelId: channel.channelID, messageId: msgId, direction: 3, limit: 50, topicId: 0, token: token)
                self.setHasMoreOlder(response.messages.count >= 50)
                self.context.account.postbox.write { tx in tx.addMessages(response.messages.map { MessageRecord(from: $0) }) }
            } catch {
                self.setErrorMessage(error.localizedDescription)
            }
        }
    }

    private func fetchNotificationSetting() {
        guard let token = context.session?.token else { return }
        let channelId = channel.channelID
        Task { @MainActor in
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

    private func fetchChannelPermissions() {
        guard let token = context.session?.token else { return }
        let channelId = channel.channelID
        Task { @MainActor in
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

    private func fetchChannelMembers() {
        guard let token = context.session?.token else { return }
        let channelId = channel.channelID
        let channelType: Int32 = clanId == 0
            ? MezonConstants.ChannelType.group.rawValue
            : MezonConstants.ChannelType.channel.rawValue

        Task { @MainActor in
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

    private func checkBanStatus() {
        guard let token = context.session?.token else { return }
        let channelId = channel.channelID
        let isPublic = clanId != 0 && channel.parentID == 0 && channel.channelPrivate == 0
        guard isPublic else { return }

        Task { @MainActor in
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
        ChatState(
            messages: messages,
            channelLabel: channelLabel,
            channelType: channel.type,
            isPrivate: channel.channelPrivate != 0,
            isAgeRestricted: channel.ageRestricted != 0,
            hasMoreOlder: hasMoreOlder,
            isLoadingMore: isLoadingMore,
            isLoading: isLoading,
            errorMessage: errorMessage
        )
    }

    func stateSignal() -> Signal<ChatState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            var lastIds = self.messages.map { $0.id }
            var lastLoading = self.isLoading
            var lastLoadingMore = self.isLoadingMore
            var lastError = self.errorMessage
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { newState in
                let newIds = newState.messages.map { $0.id }
                let changed = newIds != lastIds
                    || newState.isLoading != lastLoading
                    || newState.isLoadingMore != lastLoadingMore
                    || newState.errorMessage != lastError
                guard changed else { return }
                lastIds = newIds
                lastLoading = newState.isLoading
                lastLoadingMore = newState.isLoadingMore
                lastError = newState.errorMessage
                subscriber.putNext(newState)
            })
        }
    }



    private func buildDisplayMessages(from records: [MessageRecord]) -> [ChatMessageDisplay] {
        let currentUserId = context.currentUser?.id
        let validRecords = records.filter { !$0.id.isEmpty && !$0.channelId.isEmpty }
        let displays = validRecords.map { record -> ChatMessageDisplay in
            let parsed = MessageContentParser.parse(data: record.content, mentionsData: record.mentionsJSON)
            let content = parsed.text
            let msg = Message(id: record.id, channelId: record.channelId, clanId: record.clanId, senderId: record.senderId, content: .text(content), createdAt: record.createdAt, editedAt: record.editedAt, isDeleted: record.isDeleted, reactions: [], replyToId: nil, mentionedUserIds: [], isPinned: false)

            var attachments = Self.parseAttachments(record.attachmentsJSON)
            if record.sendingState == .pending,
               let localImages = ParsedAttachment.pendingImageCache[record.id], !localImages.isEmpty {
                attachments = localImages.map { image in
                    ParsedAttachment(
                        url: "",
                        filename: "uploading.jpg",
                        filetype: "image/jpeg",
                        width: Int(image.size.width),
                        height: Int(image.size.height),
                        localImage: image,
                        isUploading: true
                    )
                }
            }

            let reactions = Self.parseReactions(record.reactionsJSON, currentUserId: currentUserId)
            let (replyRef, isDeletedReply) = Self.firstReplyRef(from: record.referencesData)
            let isWelcome = record.senderId == "0"
                && parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && record.senderDisplayName.lowercased() == "system"
            return ChatMessageDisplay(message: msg, senderDisplayName: record.senderDisplayName, avatarURL: record.senderAvatarURL, isCombine: false, attachments: attachments, reactions: reactions, parsedContent: parsed, replyRef: replyRef, isDeletedReply: isDeletedReply, isWelcome: isWelcome)
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

    private static func applyCombine(to displays: [ChatMessageDisplay]) -> [ChatMessageDisplay] {
        displays.enumerated().map { i, d in
            let prev = i > 0 ? displays[i - 1].message : nil
            let hasReply = d.replyRef != nil || d.isDeletedReply
            let combine = hasReply ? false : ChatMessageDisplay.isCombineWithPrevious(current: d.message, previous: prev)
            return ChatMessageDisplay(message: d.message, senderDisplayName: d.senderDisplayName, avatarURL: d.avatarURL, isCombine: combine, attachments: d.attachments, reactions: d.reactions, parsedContent: d.parsedContent, replyRef: d.replyRef, isDeletedReply: d.isDeletedReply, isWelcome: d.isWelcome)
        }
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

    private static func parseReactionsFromJSON(_ json: [[String: Any]], currentUserId: String?) -> [ParsedReaction] {
        var grouped: [String: (emoji: String, senderIds: [String])] = [:]
        for item in json {
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
            let key = emojiId.isEmpty ? emoji : emojiId
            guard !key.isEmpty else { continue }

            if grouped[key] == nil {
                grouped[key] = (emoji: emoji, senderIds: [])
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
            guard !value.senderIds.isEmpty else { return nil }
            return ParsedReaction(
                emojiId: key,
                emoji: value.emoji,
                count: value.senderIds.count,
                senderIds: value.senderIds,
                isMe: currentUserId.map { value.senderIds.contains($0) } ?? false
            )
        }
    }

    private static func parseReactionsFromProtobuf(_ reactions: [Mezon_Api_MessageReaction], currentUserId: String?) -> [ParsedReaction] {
        var grouped: [String: (emoji: String, senderIds: [String], countFromApi: Int32)] = [:]
        for r in reactions {
            let emojiKey = r.emojiID != 0 ? "\(r.emojiID)" : (r.emoji.isEmpty ? "?" : r.emoji)
            guard emojiKey != "?" || !r.emoji.isEmpty else { continue }
            let senderId = "\(r.senderID)"
            if grouped[emojiKey] == nil {
                grouped[emojiKey] = (emoji: r.emoji, senderIds: [], countFromApi: r.count)
            }
            if r.action {
                if !grouped[emojiKey]!.senderIds.contains(senderId) {
                    grouped[emojiKey]!.senderIds.append(senderId)
                }
            } else {
                grouped[emojiKey]!.senderIds.removeAll { $0 == senderId }
            }
        }
        return grouped.compactMap { key, value in
            let count = value.countFromApi > 0 ? Int(value.countFromApi) : value.senderIds.count
            guard count > 0 else { return nil }
            return ParsedReaction(
                emojiId: key,
                emoji: value.emoji,
                count: count,
                senderIds: value.senderIds,
                isMe: currentUserId.map { value.senderIds.contains($0) } ?? false
            )
        }
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
        sendInputViewController.view.translatesAutoresizingMaskIntoConstraints = false

        inputBarHeight = sendInputViewController.totalHeight
        let bottomConstraint = sendInputViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        inputBarBottomConstraint = bottomConstraint
        inputBarHeightConstraint = sendInputViewController.view.heightAnchor.constraint(equalToConstant: inputBarHeight)

        NSLayoutConstraint.activate([
            sendInputViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sendInputViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarHeightConstraint!,
            bottomConstraint,
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        messagesNode.tableView.addGestureRecognizer(tap)
        messagesNode.tableView.keyboardDismissMode = .onDrag
    }

    private func updateInputBarHeight(_ newHeight: CGFloat) {
        inputBarHeight = newHeight
        inputBarHeightConstraint?.constant = newHeight
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
            if let layout = self.lastLayout {
                self.messagesNode.updateLayout(
                    layout: layout,
                    inputBarHeight: newHeight + self.currentKeyboardOffset,
                    transition: .immediate
                )
            }
        }
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let keyboardFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
        let keyboardBottomPadding: CGFloat = 20
        let keyboardOffset = keyboardFrame.height - view.safeAreaInsets.bottom + keyboardBottomPadding
        inputBarBottomConstraint?.constant = -keyboardOffset
        currentKeyboardOffset = keyboardOffset
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.view.layoutIfNeeded()
            if let layout = self.lastLayout {
                self.messagesNode.updateLayout(
                    layout: layout,
                    inputBarHeight: self.inputBarHeight + keyboardOffset,
                    transition: .immediate
                )
            }
        }
        scrollToBottomIfNeeded()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let info = notification.userInfo,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
        inputBarBottomConstraint?.constant = 0
        currentKeyboardOffset = 0
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) {
            self.view.layoutIfNeeded()
            if let layout = self.lastLayout {
                self.messagesNode.updateLayout(
                    layout: layout,
                    inputBarHeight: self.inputBarHeight,
                    transition: .immediate
                )
            }
        }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func scrollToBottomIfNeeded() {
        guard shouldScrollToBottom, !messages.isEmpty else { return }
        let tv = messagesNode.tableView
        guard tv.numberOfSections > 0, tv.numberOfRows(inSection: 0) > 0 else { return }
        tv.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
    }

    private func showMessageActions(_ display: ChatMessageDisplay) {
        view.endEditing(true)
        let isOwnMessage = display.message.senderId == context.currentUser?.id
        let sheet = MessageActionSheet(display: display, isOwnMessage: isOwnMessage) { [weak self] action in
            self?.handleMessageAction(action, display: display)
        }
        sheet.onDismiss = { [weak self] in
            self?.dismissMessageHighlight(for: display.id)
        }
        present(sheet, animated: false)
    }

    private func dismissMessageHighlight(for messageId: String) {
        let tableNode = messagesNode.tableNode
        for cell in tableNode.visibleNodes {
            if let bubble = cell as? MessageBubbleNode {
                bubble.dismissHighlight()
            }
        }
    }

    private func handleMessageAction(_ action: MessageAction, display: ChatMessageDisplay) {
        switch action {
        case .reply:
            break // TODO: implement reply
        case .copyText:
            UIPasteboard.general.string = display.parsedContent.text
            Toast.success(L(L10n.MessageAction.copied))
        case .editMessage:
            break // TODO: implement edit
        case .deleteMessage:
            break // TODO: implement delete
        case .pinMessage:
            break // TODO: implement pin
        case .forward:
            break // TODO: implement forward
        }
    }
}
