import Foundation

extension MezonEngine.EngineData.Item {

    struct TopicList: PostboxViewDataItem {
        typealias Result = [TopicRecord]

        let clanId: Int64

        init(clanId: Int64) {
            self.clanId = clanId
        }

        var key: PostboxViewKey {
            return .topicList(clanId)
        }

        func extract(view: PostboxView) -> [TopicRecord] {
            guard let view = view as? TopicListView else { return [] }
            return view.topics
        }
    }
}
