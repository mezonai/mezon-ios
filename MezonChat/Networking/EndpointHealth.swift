import Foundation

struct RealtimeEndpoint: Equatable {
    let id: Int32
    let host: String
    let port: UInt16

    func isSameNode(_ other: RealtimeEndpoint) -> Bool {
        host == other.host && port == other.port
    }

    var label: String {
        id > 0 ? "\(id) (\(host):\(port))" : "\(host):\(port)"
    }
}

enum HealthyEndpointReason: Int32 {
    case unreachable = 1
    case highLatency = 2
}

struct HealthyEndpoint {
    let apiURL: String
    let wsURL: String
    let tcpURL: String
}

enum EndpointFailoverFlags {
    static var enabled: Bool { flag("MEZON_ENDPOINT_FAILOVER", fallback: true) }
    static var slowSwitchEnabled: Bool { flag("MEZON_ENDPOINT_FAILOVER_SLOW", fallback: false) }

    private static func flag(_ key: String, fallback: Bool) -> Bool {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) else { return fallback }
        if let value = raw as? Bool { return value }
        guard let text = raw as? String else { return fallback }
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return fallback
        }
    }
}

func doubledBackoff(_ current: TimeInterval, cap: TimeInterval) -> TimeInterval {
    if current >= cap { return cap }
    return min(current * 2, cap)
}

enum EndpointAddress {
    static func host(of raw: String?) -> String? {
        guard let url = normalized(raw), let host = url.host, !host.isEmpty else { return nil }
        return host
    }

    static func port(of raw: String?) -> Int? {
        normalized(raw)?.port
    }

    static func node(answeredBy response: HealthyEndpoint, fallbackTcpURL: String?) -> RealtimeEndpoint? {
        let tcp = response.tcpURL.isEmpty ? fallbackTcpURL : response.tcpURL
        guard let host = host(of: tcp) ?? host(of: response.wsURL) else { return nil }
        let env = MezonConfig.env
        let port = port(of: tcp) ?? port(of: response.wsURL) ?? env.tcpPort ?? env.wsPort ?? 443
        return RealtimeEndpoint(id: 0, host: host, port: UInt16(exactly: port) ?? 443)
    }

    private static func normalized(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "tcp://\(trimmed)"
        return URL(string: withScheme)
    }
}

final class EndpointHealth {
    static let slowRttMs: Double = 800
    static let slowStreakRequired = 5
    static let slowSwitchCooldown: TimeInterval = 120

    private var endpoint: RealtimeEndpoint?
    private var connectedSince: Date?
    private var slowStreak = 0
    private var slowReportSuppressedUntil: Date?
    private var slowReportsDisabled = false

    func setEndpoint(_ next: RealtimeEndpoint?) {
        if isOnSameNode(as: next) {
            endpoint = next
            return
        }
        endpoint = next
        forgetConnection()
        slowReportSuppressedUntil = nil
        slowReportsDisabled = false
    }

    func connectedEndpoint() -> RealtimeEndpoint? {
        guard connectedSince != nil else { return nil }
        return endpoint
    }

    func recordConnected(at now: Date) {
        connectedSince = now
        slowStreak = 0
        slowReportSuppressedUntil = nil
        slowReportsDisabled = false
    }

    func recordDisconnected() {
        forgetConnection()
    }

    func recordActiveProbe(rttMs: Double, at now: Date) -> Bool {
        guard let connectedSince else { return false }
        if slowReportsDisabled || (slowReportSuppressedUntil.map { $0 > now } ?? false) {
            slowStreak = 0
            return false
        }
        let settledOnThisNode = now.timeIntervalSince(connectedSince) >= Self.slowSwitchCooldown
        if settledOnThisNode && rttMs >= Self.slowRttMs {
            slowStreak += 1
        } else {
            slowStreak = 0
        }
        guard slowStreak >= Self.slowStreakRequired else { return false }
        slowStreak = 0
        slowReportSuppressedUntil = now.addingTimeInterval(Self.slowSwitchCooldown)
        return true
    }

    func disableSlowReports() {
        slowReportsDisabled = true
        slowStreak = 0
    }

    private func isOnSameNode(as other: RealtimeEndpoint?) -> Bool {
        switch (endpoint, other) {
        case let (current?, next?): return current.isSameNode(next)
        case (nil, nil): return true
        default: return false
        }
    }

    private func forgetConnection() {
        connectedSince = nil
        slowStreak = 0
    }
}
