import AsyncDisplayKit
import Combine
import UIKit

final class NotificationsViewController: ViewController {


    private let context: AccountContext


    private let itemsPipe = ValuePipe<[NotificationItem]>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let isLoadingMorePipe = ValuePipe<Bool>()
    private let needsReloadPipe = ValuePipe<Void>()

    private(set) var items: [NotificationItem] = []
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var currentCategory: Int32 = 1

    private var loadedCategories: Set<Int32> = []

    private var dataDisposable: Disposable?

    private var notificationsNode: NotificationsContainerNode {
        displayNode as! NotificationsContainerNode
    }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = NotificationsInteraction(
            onTabSelected: { [weak self] categoryTag in
                guard let self else { return }
                self.currentCategory = categoryTag
                Task { await self.fetchNotifications(category: categoryTag) }
            },
            onLoadMore: { [weak self] in
                guard let self else { return }
                Task {
                    await self.fetchNotifications(category: self.currentCategory, isLoadMore: true)
                }
            },
            onItemSelected: { [weak self] item in
                guard let self else { return }
                self.processItemDetail(item)
            }
        )
        displayNode = NotificationsContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.secondary
        notificationsNode.applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        notificationsNode.applyTheme()
        if items.isEmpty {
            Task { await fetchNotifications(category: currentCategory) }
        }
    }

    private var lastLayout: ContainerViewLayout?

    override func containerLayoutUpdated(
        _ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition
    ) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout
        notificationsNode.updateLayout(layout: layout, transition: transition)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let layout = lastLayout {
            notificationsNode.updateLayout(layout: layout, transition: .immediate)
        }
    }

    func fetchNotifications(category: Int32, isLoadMore: Bool = false) async {
        if isLoadMore {
            guard !isLoadingMore else { return }
            setIsLoadingMore(true)
        } else {
            guard !isLoading else { return }
            setIsLoading(true)
        }

        let token = await context.getToken()
        let clanId = context.currentClanId

        if isLoadMore, token == nil {
            setIsLoadingMore(false)
            return
        }

        if category == 4 {
            dataDisposable?.dispose()
            dataDisposable =
                (context.engine.data.subscribe(
                    MezonEngine.EngineData.Item.TopicList(clanId: clanId)
                ) |> deliverOnMainQueue).start(next: { [weak self] topics in
                    guard let self else { return }
                    self.setItems(self.enrichTopicItems(topics))
                })

            if let token {
                do {
                    try await context.engine.topicDiscussion.listTopics(
                        clanId: clanId, token: token)
                } catch {
                }
            }
            loadedCategories.insert(category)
            setIsLoading(false)
            return
        }

        var notificationId: Int64 = 0
        if isLoadMore, let last = items.last {
            notificationId = last.id
        }

        defer {
            loadedCategories.insert(category)
            if isLoadMore { setIsLoadingMore(false) } else { setIsLoading(false) }
        }

        if !isLoadMore {
            dataDisposable?.dispose()
            dataDisposable =
                (context.engine.data.subscribe(
                    MezonEngine.EngineData.Item.NotificationList(clanId: clanId, category: category)
                ) |> deliverOnMainQueue).start(next: { [weak self] notifications in
                    self?.setNotifications(notifications)
                })
        }

        guard let token else { return }

        do {
            try await context.engine.notifications.listNotifications(
                clanId: clanId,
                category: category,
                notificationId: notificationId,
                token: token
            )
        } catch {
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        dataDisposable?.dispose()
    }

    private func setNotifications(_ v: [NotificationRecord]) {
        self.items = enrichNotificationItems(v)
        needsReloadPipe.putNext(())
    }

    private func enrichNotificationItems(_ records: [NotificationRecord]) -> [NotificationItem] {
        let friends = context.engine.friendsData.allFriends()
        return context.account.postbox.read { tx in
            records.map { record in
                let friendAvatar =
                    friends.first(where: { $0.user.id == record.senderID })?.user.avatarURL
                    ?? ""
                let enriched = record.enrichedSenderAvatar(
                    transaction: tx, fallbackAvatarURL: friendAvatar)
                return .notification(enriched)
            }
        }
    }

    private func setItems(_ v: [NotificationItem]) {
        self.items = v
        needsReloadPipe.putNext(())
    }

    private func enrichTopicItems(_ topics: [TopicRecord]) -> [NotificationItem] {
        context.account.postbox.read { tx in
            topics.map { topic in
                var avatar = topic.senderAvatarURL
                var displayName = topic.senderDisplayName
                let senderId = topic.lastSenderID != 0 ? topic.lastSenderID : topic.creatorID
                if senderId != 0, let profile = tx.getProfile(userId: String(senderId)) {
                    if avatar.isEmpty, let url = profile.avatarUrl, !url.isEmpty {
                        avatar = url
                    }
                    if displayName.isEmpty {
                        if let dn = profile.displayName, !dn.isEmpty {
                            displayName = dn
                        } else if !profile.username.isEmpty {
                            displayName = profile.username
                        }
                    }
                }
                if avatar == topic.senderAvatarURL, displayName == topic.senderDisplayName {
                    return .topic(topic)
                }
                return .topic(
                    TopicRecord(
                        id: topic.id,
                        channelID: topic.channelID,
                        clanID: topic.clanID,
                        messageID: topic.messageID,
                        creatorID: topic.creatorID,
                        lastSenderID: topic.lastSenderID,
                        senderAvatarURL: avatar,
                        senderDisplayName: displayName,
                        content: topic.content,
                        updateTimeSeconds: topic.updateTimeSeconds,
                        lastSentMessageContent: topic.lastSentMessageContent,
                        rootMessageCode: topic.rootMessageCode,
                        rootHasAttachment: topic.rootHasAttachment
                    )
                )
            }
        }
    }

    private func processItemDetail(_ item: NotificationItem) {
        var channel = Mezon_Api_ChannelDescription()
        switch item {
        case .notification(let record):
            guard record.channelID != 0 else { return }
            channel.clanID = record.clanID
            channel.channelID = record.channelID
            channel.type = record.channelType
            if record.clanID == 0, channel.type == 0 {
                channel.type = MezonConstants.ChannelType.group.rawValue
            }
            context.currentClanId = record.clanID
            let vc = ChatViewController(
                clanId: record.clanID, channel: channel, context: self.context)
            if record.category == 1 && record.messageID != 0 {
                vc.pendingJumpToMessageId = String(record.messageID)
            }
            hostingNavigationController()?.pushViewController(vc, animated: true)
        case .topic(let record):
            guard record.clanID != 0, record.channelID != 0 else { return }
            channel.clanID = record.clanID
            channel.channelID = record.channelID
            channel.channelLabel = "Topic Discussion"
            context.currentClanId = record.clanID
            
            let vc = ChatViewController(
                clanId: record.clanID, channel: channel, context: self.context)
            vc.topicId = record.id
            self.hostingNavigationController()?.pushViewController(vc, animated: true)
        }
    }

    private func hostingNavigationController() -> NavigationController? {
        if let n = navigationController as? NavigationController { return n }
        var ancestor: UIViewController? = parent
        while let c = ancestor {
            if let n = c as? NavigationController { return n }
            if let n = c.navigationController as? NavigationController { return n }
            ancestor = c.parent
        }
        return nil
    }

    private func setIsLoading(_ v: Bool) {
        isLoading = v
        isLoadingPipe.putNext(v)
        needsReloadPipe.putNext(())
    }

    private func setIsLoadingMore(_ v: Bool) {
        isLoadingMore = v
        isLoadingMorePipe.putNext(v)
        needsReloadPipe.putNext(())
    }

    @objc private func handleThemeChange() {
        view.backgroundColor = UIColor.theme.secondary
        notificationsNode.applyTheme()
    }

    var currentState: NotificationsState {
        return NotificationsState(
            items: items, isLoading: isLoading, isLoadingMore: isLoadingMore,
            hasLoaded: loadedCategories.contains(currentCategory))
    }

    func stateSignal() -> Signal<NotificationsState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)

            return
                (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue).start(next: { subscriber.putNext($0) })
        }
    }
}
