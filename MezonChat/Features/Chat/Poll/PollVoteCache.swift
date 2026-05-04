import Foundation

final class PollVoteCache {
    static let shared = PollVoteCache()
    private init() {}

    private var votes: [String: [Int]] = [:]
    private let lock = NSLock()

    func setVotes(for messageId: String, indices: [Int]) {
        lock.lock()
        votes[messageId] = indices
        lock.unlock()
    }

    func getVotes(for messageId: String) -> [Int]? {
        lock.lock()
        let result = votes[messageId]
        lock.unlock()
        return result
    }

    func clearVotes(for messageId: String) {
        lock.lock()
        votes.removeValue(forKey: messageId)
        lock.unlock()
    }
}
