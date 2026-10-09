import Foundation

@MainActor
enum ClientSnowflakeID {
    private static var sequence: UInt64 = 0

    static func next() -> Int64 {
        sequence = (sequence + 1) % 4096
        let millis = UInt64(Date().timeIntervalSince1970 * 1000)
        let shard: UInt64 = 1
        return Int64(truncatingIfNeeded: (millis << 22) | (shard << 12) | sequence)
    }
}
