import Foundation

extension MezonEngine.EngineData.Item {

    struct MessageHistory: PostboxViewDataItem {
        typealias Result = [MessageRecord]

        let channelId: String

        init(channelId: String) {
            self.channelId = channelId
        }

        var key: PostboxViewKey { .messageHistory(channelId: channelId) }

        func extract(view: PostboxView) -> [MessageRecord] {
            guard let view = view as? MessageHistoryView else { return [] }
            return view.messages
        }
    }
}
