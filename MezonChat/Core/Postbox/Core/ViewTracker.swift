import Foundation

final class ViewTracker {

    private var channelListViews    = Bag<(MutableChannelListView,    ValuePipe<ChannelListView>)>()
    private var clanListViews       = Bag<(MutableClanListView,      ValuePipe<ClanListView>)>()
    private var messageHistoryViews = Bag<(MutableMessageHistoryView, ValuePipe<MessageHistoryView>)>()
    private var channelMetaViews    = Bag<(MutableChannelMetaView,   ValuePipe<ChannelMetaView>)>()
    private var notificationSettingViews = Bag<(MutableNotificationSettingView, ValuePipe<NotificationSettingView>)>()
    private var notificationListViews = Bag<(MutableNotificationListView, ValuePipe<NotificationListView>)>()
    private var topicListViews        = Bag<(MutableTopicListView,        ValuePipe<TopicListView>)>()
    private var clanMemberViews       = Bag<(MutableClanMemberView,       ValuePipe<ClanMemberView>)>()
    private var profileViews          = Bag<(MutableProfileView,          ValuePipe<ProfileView>)>()

    func addChannelListView(
        clanId: Int64,
        initialChannels: [ChannelRecord]
    ) -> (Bag<(MutableChannelListView, ValuePipe<ChannelListView>)>.Index, Signal<ChannelListView, NoError>) {
        let mutableView = MutableChannelListView(clanId: clanId, initial: initialChannels)
        let pipe        = ValuePipe<ChannelListView>()
        let index       = channelListViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeChannelListView(index: Bag<(MutableChannelListView, ValuePipe<ChannelListView>)>.Index) {
        channelListViews.remove(index)
    }


    func addClanListView(
        initial: [ClanRecord]
    ) -> (Bag<(MutableClanListView, ValuePipe<ClanListView>)>.Index, Signal<ClanListView, NoError>) {
        let mutableView = MutableClanListView(initial: initial)
        let pipe        = ValuePipe<ClanListView>()
        let index       = clanListViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeClanListView(index: Bag<(MutableClanListView, ValuePipe<ClanListView>)>.Index) {
        clanListViews.remove(index)
    }

    func addClanMemberView(
        clanId: Int64,
        initial: [ClanMemberRecord]
    ) -> (Bag<(MutableClanMemberView, ValuePipe<ClanMemberView>)>.Index, Signal<ClanMemberView, NoError>) {
        let mutableView = MutableClanMemberView(clanId: clanId, members: initial)
        let pipe        = ValuePipe<ClanMemberView>()
        let index       = clanMemberViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeClanMemberView(index: Bag<(MutableClanMemberView, ValuePipe<ClanMemberView>)>.Index) {
        clanMemberViews.remove(index)
    }

    func addMessageHistoryView(
        channelId: String,
        initial: [MessageRecord]
    ) -> (Bag<(MutableMessageHistoryView, ValuePipe<MessageHistoryView>)>.Index, Signal<MessageHistoryView, NoError>) {
        let mutableView = MutableMessageHistoryView(channelId: channelId, initial: initial)
        let pipe        = ValuePipe<MessageHistoryView>()
        let index       = messageHistoryViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeMessageHistoryView(index: Bag<(MutableMessageHistoryView, ValuePipe<MessageHistoryView>)>.Index) {
        messageHistoryViews.remove(index)
    }

    func addChannelMetaView(
        channelId: Int64,
        initial: ChannelRecord?
    ) -> (Bag<(MutableChannelMetaView, ValuePipe<ChannelMetaView>)>.Index, Signal<ChannelMetaView, NoError>) {
        let mutableView = MutableChannelMetaView(channelId: channelId, initial: initial)
        let pipe        = ValuePipe<ChannelMetaView>()
        let index       = channelMetaViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeChannelMetaView(index: Bag<(MutableChannelMetaView, ValuePipe<ChannelMetaView>)>.Index) {
        channelMetaViews.remove(index)
    }

    func addNotificationSettingView(
        entityId: Int64,
        initial: NotificationSettingRecord?
    ) -> (Bag<(MutableNotificationSettingView, ValuePipe<NotificationSettingView>)>.Index, Signal<NotificationSettingView, NoError>) {
        let mutableView = MutableNotificationSettingView(entityId: entityId, initial: initial)
        let pipe        = ValuePipe<NotificationSettingView>()
        let index       = notificationSettingViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeNotificationSettingView(index: Bag<(MutableNotificationSettingView, ValuePipe<NotificationSettingView>)>.Index) {
        notificationSettingViews.remove(index)
    }

    func addProfileView(
        userId: String,
        initial: ProfileRecord?
    ) -> (Bag<(MutableProfileView, ValuePipe<ProfileView>)>.Index, Signal<ProfileView, NoError>) {
        let mutableView = MutableProfileView(userId: userId, record: initial)
        let pipe        = ValuePipe<ProfileView>()
        let index       = profileViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeProfileView(index: Bag<(MutableProfileView, ValuePipe<ProfileView>)>.Index) {
        profileViews.remove(index)
    }
    func addNotificationListView(
        clanId: Int64,
        category: Int32,
        initial: [NotificationRecord]
    ) -> (Bag<(MutableNotificationListView, ValuePipe<NotificationListView>)>.Index, Signal<NotificationListView, NoError>) {
        let mutableView = MutableNotificationListView(clanId: clanId, category: category, initial: initial)
        let pipe        = ValuePipe<NotificationListView>()
        let index       = notificationListViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeNotificationListView(index: Bag<(MutableNotificationListView, ValuePipe<NotificationListView>)>.Index) {
        notificationListViews.remove(index)
    }

    func addTopicListView(
        clanId: Int64,
        initial: [TopicRecord]
    ) -> (Bag<(MutableTopicListView, ValuePipe<TopicListView>)>.Index, Signal<TopicListView, NoError>) {
        let mutableView = MutableTopicListView(clanId: clanId, initial: initial)
        let pipe        = ValuePipe<TopicListView>()
        let index       = topicListViews.add((mutableView, pipe))
        return (index, pipe.signal())
    }

    func removeTopicListView(index: Bag<(MutableTopicListView, ValuePipe<TopicListView>)>.Index) {
        topicListViews.remove(index)
    }

    func replay(transaction: PostboxTransaction) {
        guard !transaction.isEmpty else { return }

        for (_, (view, pipe)) in channelListViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView())
            }
        }

        for (_, (view, pipe)) in clanListViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView())
            }
        }

        for (_, (view, pipe)) in messageHistoryViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView())
            }
        }

        for (_, (view, pipe)) in channelMetaViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView())
            }
        }

        for (_, (view, pipe)) in notificationSettingViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView())
            }
        }

        for (_, (view, pipe)) in notificationListViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView())
            }
        }

        for (_, (view, pipe)) in topicListViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView())
            }
        }


        for (_, (view, pipe)) in clanMemberViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView() as! ClanMemberView)
            }
        }

        for (_, (view, pipe)) in profileViews.copyItemsWithIndices() {
            if view.replay(transaction: transaction) {
                pipe.putNext(view.immutableView() as! ProfileView)
            }
        }
    }
}
