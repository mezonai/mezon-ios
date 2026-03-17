import AsyncDisplayKit
import Combine
import UIKit

final class NotificationViewController: ViewController {

    // MARK: - Dependencies

    private let context: AccountContext

    // MARK: - State pipes (Signal-based, matching MessagesViewController pattern)

    private let itemsPipe = ValuePipe<[NotificationItem]>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let isLoadingMorePipe = ValuePipe<Bool>()
    private let needsReloadPipe = ValuePipe<Void>()

    private(set) var items: [NotificationItem] = []
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var currentCategory: Int32 = 1

    private var dataDisposable: Disposable?

    // MARK: - Node accessor

    private var notificationsNode: NotificationsContainerNode {
        displayNode as! NotificationsContainerNode
    }

    // MARK: - Init

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Display node

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

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Fetch the default tab (Mentions = tag 1)
        Task { await fetchNotifications(category: 1) }
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

    // MARK: - Data

    func fetchNotifications(category: Int32, isLoadMore: Bool = false) async {
        if isLoadMore {
            guard !isLoadingMore else { return }
        } else {
            guard !isLoading else { return }
        }
        guard let token = context.session?.token else { return }

        let clanId = context.currentClanId

        // Handle Topic Tab (tag 4)
        if category == 4 {
            dataDisposable?.dispose()  // Dispose previous subscription if any
            asyncDetached { [weak self] in
                guard let self else { return }
                do {
                    try await context.engine.topicDiscussion.listTopics(
                        clanId: clanId, token: token)
                } catch {
                    AppLogger.network.error("fetchTopics error: \(error)")
                }
            }

            dataDisposable =
                (context.engine.data.subscribe(
                    MezonEngine.EngineData.Item.TopicList(clanId: clanId)
                ) |> deliverOnMainQueue).start(next: { [weak self] topics in
                    self?.setItems(topics.map { .topic($0) })
                })
            return
        }

        var notificationId: Int64 = 0
        if isLoadMore, let last = items.last {
            notificationId = last.id
            setIsLoadingMore(true)
        } else {
            setIsLoading(true)
        }

        defer {
            if isLoadMore { setIsLoadingMore(false) } else { setIsLoading(false) }
        }

        // Subscribe to real-time engine data changes
        if !isLoadMore {
            dataDisposable?.dispose()
            dataDisposable =
                (context.engine.data.subscribe(
                    MezonEngine.EngineData.Item.NotificationList(clanId: clanId, category: category)
                ) |> deliverOnMainQueue).start(next: { [weak self] notifications in
                    self?.setNotifications(notifications)
                })
        }

        do {
            try await context.engine.notifications.listNotifications(
                clanId: clanId,
                category: category,
                notificationId: notificationId,
                token: token
            )
        } catch {
            AppLogger.network.error("fetchNotifications error: \(error)")
        }
    }

    deinit {
        dataDisposable?.dispose()
    }

    private func setNotifications(_ v: [NotificationRecord]) {
        self.items = v.map { .notification($0) }
        needsReloadPipe.putNext(())
    }

    private func setItems(_ v: [NotificationItem]) {
        self.items = v
        needsReloadPipe.putNext(())
    }

    private func processItemDetail(_ item: NotificationItem) {
        var channel = Mezon_Api_ChannelDescription()
        switch item {
        case .notification(let record):
            channel.clanID = record.clanID
            channel.channelID = record.channelID
            channel.type = record.channelType
            // For notifications, we navigate to the chat.
            // topicID in record might be used if ChatViewController supported it.
            let vc = ChatViewController(
                clanId: record.clanID, channel: channel, context: self.context)
            self.navigationController?.pushViewController(vc, animated: true)
        case .topic(let record):
            channel.clanID = record.clanID
            channel.channelID = record.channelID
            // For topics, we also navigate to the chat but specifically for this topic
            // TODO: Ensure ChatViewController handles topicId from notification/direct select
            let vc = ChatViewController(
                clanId: record.clanID, channel: channel, context: self.context)
            // If ChatViewController is updated to take topicId, we would pass record.id here.
            self.navigationController?.pushViewController(vc, animated: true)
        }
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

    // MARK: - State Signal

    var currentState: NotificationsState {
        return NotificationsState(
            items: items, isLoading: isLoading, isLoadingMore: isLoadingMore)
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
