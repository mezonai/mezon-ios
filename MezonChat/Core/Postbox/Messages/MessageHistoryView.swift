import Foundation

struct MessageHistoryView: PostboxView {
    let channelId: String
    let messages: [MessageRecord]
}

final class MutableMessageHistoryView: MutablePostboxView {

    let channelId: String
    private(set) var messages: [MessageRecord]

    init(channelId: String, initial: [MessageRecord]) {
        self.channelId = channelId
        self.messages  = initial.filter { $0.channelId == channelId }
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedMessageChannelIds.contains(channelId) else { return false }
        let next = transaction.messageTable.getMessages(channelId: channelId)
            .filter { $0.channelId == channelId }
        messages = next
        return true
    }

    func immutableView() -> MessageHistoryView {
        MessageHistoryView(channelId: channelId, messages: messages)
    }
}
