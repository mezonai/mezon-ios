import Foundation

extension MezonEngine.EngineData.Item {

    struct ChannelList: PostboxViewDataItem {
        typealias Result = [ChannelRecord]

        let clanId: Int64

        init(clanId: Int64) {
            self.clanId = clanId
        }

        var key: PostboxViewKey { .channelList(clanId: clanId) }

        func extract(view: PostboxView) -> [ChannelRecord] {
            guard let view = view as? ChannelListView else { return [] }
            return view.channels
        }
    }
}
