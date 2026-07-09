import Foundation

enum ForwardTargetUsageStore {
    private static let defaultsKey = "forward_target_usage_v2"
    private static let lock = NSLock()

    private static func key(channelID: Int64, channelType: Int32) -> String {
        "\(channelType)_\(channelID)"
    }

    static func snapshot() -> [String: TimeInterval] {
        lock.lock()
        defer { lock.unlock() }

        let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
        return stored.reduce(into: [:]) { result, entry in
            if let timestamp = entry.value as? NSNumber {
                result[entry.key] = timestamp.doubleValue
            }
        }
    }

    static func lastSent(
        channelID: Int64,
        channelType: Int32,
        in snapshot: [String: TimeInterval]
    ) -> TimeInterval {
        guard channelID != 0, channelType != 0 else { return 0 }
        return snapshot[key(channelID: channelID, channelType: channelType)] ?? 0
    }

    static func markLastSent(
        channelID: Int64,
        channelType: Int32,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        guard channelID != 0, channelType != 0, timestamp > 0 else { return }
        lock.lock()
        defer { lock.unlock() }

        let targetKey = key(channelID: channelID, channelType: channelType)
        var values = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
        let previous = (values[targetKey] as? NSNumber)?.doubleValue ?? 0
        guard timestamp > previous else { return }

        values[targetKey] = timestamp
        UserDefaults.standard.set(values, forKey: defaultsKey)
    }
}
