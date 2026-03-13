import Foundation

protocol MutablePostboxView: AnyObject {

    func replay(transaction: PostboxTransaction) -> Bool
}

struct ChannelListView: PostboxView {
    let clanId: Int64
    let channels: [ChannelRecord]
}

final class MutableChannelListView: MutablePostboxView {

    let clanId: Int64
    private(set) var channels: [ChannelRecord]

    init(clanId: Int64, initial: [ChannelRecord]) {
        self.clanId   = clanId
        self.channels = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedChannelClanIds.contains(clanId) else { return false }
        channels = transaction.channelTable.getChannels(clanId: clanId)
        return true
    }

    func immutableView() -> ChannelListView {
        ChannelListView(clanId: clanId, channels: channels)
    }
}

struct ChannelMetaView: PostboxView {
    let channelId: Int64
    let record: ChannelRecord?
}

final class MutableChannelMetaView: MutablePostboxView {

    let channelId: Int64
    private(set) var record: ChannelRecord?

    init(channelId: Int64, initial: ChannelRecord?) {
        self.channelId = channelId
        self.record = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedChannelMetaIds.contains(channelId) else { return false }
        record = transaction.channelTable.getChannelMeta(channelId: channelId)
        return true
    }

    func immutableView() -> ChannelMetaView {
        ChannelMetaView(channelId: channelId, record: record)
    }
}
