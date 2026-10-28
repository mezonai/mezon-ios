import Foundation

/// The server uses the same event for assignments, self selection and closing rooms.
enum VoiceBreakoutSignal: Equatable {
    case assigned(Int64)
    case choose([Int64])
    case returnToMain
    case closed

    static func classify(channelId: Int64, hasToken: Bool, selfSelectIds: [Int64],
                         currentChannelId: Int64, parentChannelId: Int64,
                         knownParents: Set<Int64>) -> Self? {
        var seen = Set<Int64>()
        let rooms = selfSelectIds.filter { $0 > 0 && $0 != parentChannelId && seen.insert($0).inserted }
        if !rooms.isEmpty { return .choose(rooms) }
        guard channelId > 0 else { return nil }
        if channelId == parentChannelId {
            return currentChannelId == parentChannelId ? .closed : .returnToMain
        }
        guard hasToken, channelId != currentChannelId, !knownParents.contains(channelId) else { return nil }
        return .assigned(channelId)
    }
}
