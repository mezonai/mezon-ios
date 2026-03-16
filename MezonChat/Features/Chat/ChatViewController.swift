import UIKit
import SwiftProtobuf

struct ParsedAttachment: Equatable {
    let url: String
    let filename: String
    let filetype: String
    let width: Int?
    let height: Int?

    var isImage: Bool {
        filetype.hasPrefix("image/") || ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(fileExtension)
    }

    var isVideo: Bool {
        filetype.hasPrefix("video/") || ["mp4", "mov", "m4v", "webm"].contains(fileExtension)
    }

    var isMedia: Bool { isImage || isVideo }

    var fileExtension: String {
        (filename as NSString).pathExtension.lowercased()
    }
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
    var showWelcome: Bool
    var hasMoreOlder: Bool
    var isLoadingMore: Bool
    var isLoading: Bool
    var errorMessage: String?

    static let empty = ChatState(messages: [], channelLabel: "", showWelcome: false, hasMoreOlder: false, isLoadingMore: false, isLoading: false, errorMessage: nil)
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
    private(set) var showWelcome: Bool = false
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
        return vc
    }()

    private var inputBarBottomConstraint: NSLayoutConstraint?
    private var inputBarHeightConstraint: NSLayoutConstraint?
    private let inputBarHeight: CGFloat = 56
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
        messagesNode.updateLayout(layout: layout, inputBarHeight: inputBarHeight, transition: transition)
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

    private func setMessages(_ v: [ChatMessageDisplay], showWelcome w: Bool = false) {
        messages = v
        showWelcome = w
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

        let channelIdStr = "\(channel.channelID)"
        stateDisposables.add(
            (self.context.account.postbox.messageHistoryView(channelId: channelIdStr) |> deliverOnMainQueue)
                .start(next: { [weak self] view in
                    guard let self else { return }
                    let (displays, showWelcome) = self.buildDisplayMessages(from: view.messages)
                    self.setMessages(displays, showWelcome: showWelcome)
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
        ChatState(messages: messages, channelLabel: channelLabel, showWelcome: showWelcome, hasMoreOlder: hasMoreOlder, isLoadingMore: isLoadingMore, isLoading: isLoading, errorMessage: errorMessage)
    }

    func stateSignal() -> Signal<ChatState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }

    private static func hasNoTextContent(_ textContent: String) -> Bool {
        let trimmed = textContent.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "{}"
    }

    private static func isSystemWelcomeMessage(_ record: MessageRecord, textContent: String) -> Bool {
        record.senderId == "0"
            && hasNoTextContent(textContent)
            && record.senderDisplayName.lowercased() == "system"
    }

    private func buildDisplayMessages(from records: [MessageRecord]) -> ([ChatMessageDisplay], showWelcome: Bool) {
        let currentUserId = context.currentUser?.id
        let validRecords = records.filter { !$0.id.isEmpty && !$0.channelId.isEmpty }
        var showWelcome = false
        var recordsToShow = validRecords
        if let first = validRecords.first, Self.isSystemWelcomeMessage(first, textContent: extractTextFromContent(first)) {
            showWelcome = true
            recordsToShow = Array(validRecords.dropFirst())
        }
        let displays = recordsToShow.map { record -> ChatMessageDisplay in
            let parsed = MessageContentParser.parse(data: record.content)
            let content = parsed.text
            let msg = Message(id: record.id, channelId: record.channelId, clanId: record.clanId, senderId: record.senderId, content: .text(content), createdAt: record.createdAt, editedAt: record.editedAt, isDeleted: record.isDeleted, reactions: [], replyToId: nil, mentionedUserIds: [], isPinned: false)
            let attachments = Self.parseAttachments(record.attachmentsJSON)
            let reactions = Self.parseReactions(record.reactionsJSON, currentUserId: currentUserId)
            let (replyRef, isDeletedReply) = Self.firstReplyRef(from: record.referencesData)
            return ChatMessageDisplay(message: msg, senderDisplayName: record.senderDisplayName, avatarURL: record.senderAvatarURL, isCombine: false, attachments: attachments, reactions: reactions, parsedContent: parsed, replyRef: replyRef, isDeletedReply: isDeletedReply)
        }
        return (Self.applyCombine(to: displays), showWelcome)
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
            return ChatMessageDisplay(message: d.message, senderDisplayName: d.senderDisplayName, avatarURL: d.avatarURL, isCombine: ChatMessageDisplay.isCombineWithPrevious(current: d.message, previous: prev), attachments: d.attachments, reactions: d.reactions, parsedContent: d.parsedContent, replyRef: d.replyRef, isDeletedReply: d.isDeletedReply)
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

    private func extractTextFromContent(_ record: MessageRecord) -> String {
        guard let str = String(data: record.content, encoding: .utf8), !str.isEmpty else { return "" }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return str }
        if let t = json["t"] as? String { return t }
        if let text = json["text"] as? String { return text }
        return str
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
        inputBarBottomConstraint?.constant = -keyboardFrame.height + view.safeAreaInsets.bottom
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) { self.view.layoutIfNeeded() }
        scrollToBottomIfNeeded()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let info = notification.userInfo,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
              let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }
        inputBarBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions(rawValue: curve << 16)) { self.view.layoutIfNeeded() }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func scrollToBottomIfNeeded() {
        guard shouldScrollToBottom, !messages.isEmpty else { return }
        let tv = messagesNode.tableView
        guard tv.numberOfRows(inSection: 0) > 0 else { return }
        tv.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
    }
}
