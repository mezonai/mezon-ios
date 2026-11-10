import Foundation

struct MessageHistoryView: PostboxView {
    let channelId: String
    let messages: [MessageRecord]
    let newestHistoricalMessageId: Int64?
}

final class MutableMessageHistoryView: MutablePostboxView {

    private var view: MessageHistoryView

    init(initial: MessageHistoryView) {
        self.view = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedMessageChannelIds.contains(view.channelId) else { return false }
        view = transaction.messageHistoryView(channelId: view.channelId)
        return true
    }

    func immutableView() -> MessageHistoryView {
        view
    }
}
