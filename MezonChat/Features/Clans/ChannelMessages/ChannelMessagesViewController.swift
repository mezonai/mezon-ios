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

struct ChannelMessageDisplay: Identifiable {
    let message: Message
    let senderDisplayName: String
    let avatarURL: String?
    let isCombine: Bool
    let attachments: [ParsedAttachment]
    let reactions: [ParsedReaction]
    var id: String { message.id }

    static func isCombineWithPrevious(current: Message, previous: Message?) -> Bool {
        guard let prev = previous else { return false }
        guard current.senderId == prev.senderId else { return false }
        let diff = current.createdAt.timeIntervalSince(prev.createdAt)
        return diff < 120 && diff >= 0
    }
}

struct ChannelMessagesState {
    var messages: [ChannelMessageDisplay]
    var channelLabel: String
    var hasMoreOlder: Bool
    var isLoadingMore: Bool
    var isLoading: Bool
    var errorMessage: String?

    static let empty = ChannelMessagesState(messages: [], channelLabel: "", hasMoreOlder: false, isLoadingMore: false, isLoading: false, errorMessage: nil)
}

final class ChannelMessagesViewController: ViewController {

    let clanId: Int64
    let channel: Mezon_Api_ChannelDescription
    let context: AccountContext

    private let needsReloadPipe = ValuePipe<Void>()
    var needsReloadSignal: Signal<Void, NoError> { needsReloadPipe.signal() }
    private let stateDisposables = DisposableSet()

    private(set) var messages: [ChannelMessageDisplay] = []
    private(set) var channelLabel: String = ""
    private(set) var hasMoreOlder: Bool = true
    private(set) var isLoadingMore: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

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
    private var hasScrolledToBottomInitially = false

    private var messagesNode: ChannelMessagesContainerNode { displayNode as! ChannelMessagesContainerNode }

    init(clanId: Int64, channel: Mezon_Api_ChannelDescription, context: AccountContext) {
        self.clanId = clanId
        self.channel = channel
        self.context = context
        self.channelLabel = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = ChannelMessagesInteraction(
            onBackTapped: { [weak self] in self?.navigationController?.popViewController(animated: true) },
            onSearchTapped: { },
            onHistoryTapped: { },
            onMenuTapped: { },
            onScrolledNearTop: { [weak self] in
                guard let self, self.hasMoreOlder, !self.isLoadingMore else { return }
                self.fetchMoreMessages()
            },
            onScrolledToBottom: { [weak self] atBottom in self?.shouldScrollToBottom = atBottom }
        )
        displayNode = ChannelMessagesContainerNode(signal: stateSignal(), interaction: interaction)
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

    private func setMessages(_ v: [ChannelMessageDisplay]) { messages = v; needsReloadPipe.putNext(()) }
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
                    self.setMessages(self.buildDisplayMessages(from: view.messages))
                })
        )
        fetchMessages()
        joinChat()
    }

    func onLeave() {
        context.currentChannel = nil
        stateDisposables.dispose()
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

    var currentState: ChannelMessagesState {
        ChannelMessagesState(messages: messages, channelLabel: channelLabel, hasMoreOlder: hasMoreOlder, isLoadingMore: isLoadingMore, isLoading: isLoading, errorMessage: errorMessage)
    }

    func stateSignal() -> Signal<ChannelMessagesState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }

    private func buildDisplayMessages(from records: [MessageRecord]) -> [ChannelMessageDisplay] {
        let currentUserId = context.currentUser?.id
        let displays = records.map { record -> ChannelMessageDisplay in
            let content = extractTextFromContent(record)
            let msg = Message(id: record.id, channelId: record.channelId, clanId: record.clanId, senderId: record.senderId, content: .text(content), createdAt: record.createdAt, editedAt: record.editedAt, isDeleted: record.isDeleted, reactions: [], replyToId: nil, mentionedUserIds: [], isPinned: false)
            let attachments = Self.parseAttachments(record.attachmentsJSON)
            let reactions = Self.parseReactions(record.reactionsJSON, currentUserId: currentUserId)
            return ChannelMessageDisplay(message: msg, senderDisplayName: record.senderDisplayName, avatarURL: record.senderAvatarURL, isCombine: false, attachments: attachments, reactions: reactions)
        }
        return Self.applyCombine(to: displays)
    }

    private static func applyCombine(to displays: [ChannelMessageDisplay]) -> [ChannelMessageDisplay] {
        displays.enumerated().map { i, d in
            let prev = i > 0 ? displays[i - 1].message : nil
            return ChannelMessageDisplay(message: d.message, senderDisplayName: d.senderDisplayName, avatarURL: d.avatarURL, isCombine: ChannelMessageDisplay.isCombineWithPrevious(current: d.message, previous: prev), attachments: d.attachments, reactions: d.reactions)
        }
    }

    private static func parseAttachments(_ data: Data) -> [ParsedAttachment] {
        guard !data.isEmpty else { return [] }
        var jsonArray: [[String: Any]]?
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            jsonArray = arr
        } else if let str = String(data: data, encoding: .utf8),
                  let strData = str.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: strData) as? [[String: Any]] {
            jsonArray = arr
        }
        guard let json = jsonArray else { return [] }
        return json.compactMap { item in
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

    private static func parseReactions(_ data: Data, currentUserId: String?) -> [ParsedReaction] {
        guard !data.isEmpty else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var grouped: [String: (emoji: String, senderIds: [String])] = [:]
        for item in json {
            let emojiId = item["emoji_id"] as? String ?? item["emojiid"] as? String ?? ""
            let emoji = item["emoji"] as? String ?? ""
            let senderId = item["sender_id"] as? String ?? "\(item["sender_id"] ?? "")"
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
        let rowCount = messages.count
        let lastRow = rowCount - 1
        guard lastRow >= 0, lastRow < messagesNode.tableView.numberOfRows(inSection: 0) else { return }
        let last = IndexPath(row: lastRow, section: 0)
        let isInitial = !hasScrolledToBottomInitially
        hasScrolledToBottomInitially = true
        if isInitial {
            messagesNode.tableView.scrollToRow(at: last, at: .bottom, animated: false)
            messagesNode.tableView.setContentOffset(
                CGPoint(x: 0, y: max(-messagesNode.tableView.contentInset.top, messagesNode.tableView.contentSize.height - messagesNode.tableView.bounds.height + messagesNode.tableView.contentInset.bottom)),
                animated: false
            )
        } else {
            messagesNode.tableView.scrollToRow(at: last, at: .bottom, animated: true)
        }
    }
}
