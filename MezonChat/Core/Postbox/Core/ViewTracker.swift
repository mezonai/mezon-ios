import Foundation

final class ViewTracker {

    private var channelListViews   = Bag<(MutableChannelListView,   ValuePipe<ChannelListView>)>()
    private var clanListViews      = Bag<(MutableClanListView,      ValuePipe<ClanListView>)>()
    private var messageHistoryViews = Bag<(MutableMessageHistoryView, ValuePipe<MessageHistoryView>)>()

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
    }
}
