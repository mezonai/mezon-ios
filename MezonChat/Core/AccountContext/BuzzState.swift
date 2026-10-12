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
    private var rowReadCursors: [Int64: Int64] = [:]

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
        let readCursor = max(readCursors[targetId] ?? 0, rowReadCursors[channelId] ?? 0)
        let alreadySeen = messageId != 0 && readCursor != 0 && messageId <= readCursor
        guard !isViewing, !alreadySeen else { return .received }
        let badgeAdded = marks[channelId] == nil
        var mark = marks[channelId] ?? Mark(clanId: clanId)
        if mark.messages[targetId].map({ messageId >= $0 }) ?? true {
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
        if let seenMessageId { advanceReadCursor(targetId, to: seenMessageId) }
        var changed = Set<Int64>()
        for channelId in Array(marks.keys) {
            guard var mark = marks[channelId], let messageId = mark.messages[targetId] else { continue }
            if let seenMessageId, seenMessageId < messageId { continue }
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
    func clearRows(targetIds: Set<Int64> = [], seenMessageIds: [Int64: Int64]? = nil,
                   matches: (Int64, Int64) -> Bool) -> Set<Int64> {
        lock.lock(); defer { lock.unlock() }
        if let seenMessageIds {
            for (rowId, messageId) in seenMessageIds {
                advanceReadCursor(rowId, to: messageId)
                if let cursor = readCursors[rowId] {
                    rowReadCursors[rowId] = max(rowReadCursors[rowId] ?? 0, cursor)
                }
            }
        }
        var changed = Set<Int64>()
        for channelId in Array(marks.keys) {
            guard var mark = marks[channelId] else { continue }
            if matches(mark.clanId, channelId) {
                if seenMessageIds != nil {
                    if let cursor = readCursors[channelId] {
                        rowReadCursors[channelId] = max(rowReadCursors[channelId] ?? 0, cursor)
                    }
                   
                    for (targetId, messageId) in mark.messages {
                        advanceReadCursor(targetId, to: messageId)
                        if messageId > 0 {
                            rowReadCursors[channelId] = max(rowReadCursors[channelId] ?? 0, messageId)
                        }
                    }
                }
            } else {
                guard !targetIds.isEmpty else { continue }
                for targetId in targetIds {
                    if seenMessageIds != nil, let messageId = mark.messages[targetId] {
                        advanceReadCursor(targetId, to: messageId)
                    }
                    mark.messages.removeValue(forKey: targetId)
                }
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

    private func advanceReadCursor(_ targetId: Int64, to messageId: Int64) {
        if messageId > 0, readCursors[targetId].map({ messageId > $0 }) ?? true {
            readCursors[targetId] = messageId
        }
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        marks.removeAll()
        processed.removeAll()
        processedOrder.removeAll()
        readCursors.removeAll()
        rowReadCursors.removeAll()
    }
}
