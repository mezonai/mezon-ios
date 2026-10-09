import Foundation

final class BuzzState {
    enum Reception {
        case duplicate, received, badgeAdded
    }

    private struct Mark {
        let clanId: Int64
        var messages: [Int64: Int64] = [:]
    }
    private struct MessageKey: Hashable {
        let targetId: Int64
        let messageId: Int64
    }

    private let lock = NSLock()
    private var marks: [Int64: Mark] = [:]
    private var processed = Set<MessageKey>()
    private var processedOrder: [MessageKey] = []
    private var readCursors: [Int64: Int64] = [:]

    func receive(clanId: Int64, channelId: Int64, topicId: Int64, messageId: Int64, isViewing: Bool) -> Reception {
        lock.lock(); defer { lock.unlock() }
        let targetId = topicId != 0 ? topicId : channelId
        if messageId != 0 {
            let key = MessageKey(targetId: targetId, messageId: messageId)
            guard processed.insert(key).inserted else { return .duplicate }
            processedOrder.append(key)
            if processedOrder.count > 200 {
                processed.remove(processedOrder.removeFirst())
            }
        }
        let alreadySeen = messageId != 0 && readCursors[targetId].map {
            (messageId >> 22) <= ($0 >> 22)
        } == true
        guard !isViewing, !alreadySeen else { return .received }
        let badgeAdded = marks[channelId] == nil
        var mark = marks[channelId] ?? Mark(clanId: clanId)
        if mark.messages[targetId].map({ (messageId >> 22) >= ($0 >> 22) }) ?? true {
            mark.messages[targetId] = messageId
        }
        marks[channelId] = mark
        return badgeAdded ? .badgeAdded : .received
    }

    func hasBuzz(channelId: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return marks[channelId] != nil
    }

    func channelIdsSnapshot() -> Set<Int64> {
        lock.lock(); defer { lock.unlock() }
        return Set(marks.keys)
    }

    @discardableResult
    func clearTarget(_ targetId: Int64, seenMessageId: Int64? = nil) -> Set<Int64> {
        lock.lock(); defer { lock.unlock() }
        if let seenMessageId, seenMessageId > 0,
           readCursors[targetId].map({ (seenMessageId >> 22) > ($0 >> 22) }) ?? true {
            readCursors[targetId] = seenMessageId
        }
        var changed = Set<Int64>()
        for channelId in Array(marks.keys) {
            guard var mark = marks[channelId], let messageId = mark.messages[targetId] else { continue }
            if let seenMessageId, (seenMessageId >> 22) < (messageId >> 22) { continue }
            mark.messages.removeValue(forKey: targetId)
            if mark.messages.isEmpty {
                marks.removeValue(forKey: channelId)
                changed.insert(channelId)
            } else {
                marks[channelId] = mark
            }
        }
        return changed
    }

    @discardableResult
    func clearRows(targetIds: Set<Int64> = [], matches: (Int64, Int64) -> Bool) -> Set<Int64> {
        lock.lock(); defer { lock.unlock() }
        var changed = Set<Int64>()
        for channelId in Array(marks.keys) {
            guard var mark = marks[channelId] else { continue }
            if !matches(mark.clanId, channelId) {
                guard !targetIds.isEmpty else { continue }
                for targetId in targetIds { mark.messages.removeValue(forKey: targetId) }
                if !mark.messages.isEmpty {
                    marks[channelId] = mark
                    continue
                }
            }
            marks.removeValue(forKey: channelId)
            changed.insert(channelId)
        }
        return changed
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        marks.removeAll()
        processed.removeAll()
        processedOrder.removeAll()
        readCursors.removeAll()
    }
}
