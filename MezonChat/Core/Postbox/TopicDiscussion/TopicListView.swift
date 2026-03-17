import Foundation
import SwiftProtobuf

public struct TopicListView: PostboxView {
    public let clanId: Int64
    public let topics: [TopicRecord]
}

public final class MutableTopicListView: MutablePostboxView {

    public let clanId: Int64
    public private(set) var topics: [TopicRecord]

    public init(clanId: Int64, initial: [TopicRecord]) {
        self.clanId = clanId
        self.topics = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedTopicClanIds.contains(clanId) else { return false }
        topics = transaction.topicTable.getTopics(clanId: clanId)
        return true
    }

    func immutableView() -> TopicListView {
        TopicListView(clanId: clanId, topics: topics)
    }
}
