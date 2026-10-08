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
    private static let nodeIdsByHost: [String: Int32] = [
        "sock.mezon.ai": 1,
        "sock2.mezon.ai": 2,
        "sock3.mezon.ai": 3
    ]

    static func nodeId(ofHost host: String) -> Int32 {
        nodeIdsByHost[host.lowercased()] ?? 0
    }

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
        return RealtimeEndpoint(id: nodeId(ofHost: host), host: host, port: UInt16(exactly: port) ?? 443)
    }

    private static func normalized(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "tcp://\(trimmed)"
        return URL(string: withScheme)
    }
}

enum RealtimeServerChoice: String, CaseIterable {
    case auto
    case vn1
    case vn2
    case us

    private static let storageKey = "mezon.mobile.realtimeServerChoice"

    static var isAvailable: Bool {
        MezonConfig.env == .prod
    }

    static var current: RealtimeServerChoice {
        get {
            guard isAvailable,
                  let stored = UserDefaults.standard.string(forKey: storageKey),
                  let choice = RealtimeServerChoice(rawValue: stored)
            else { return .auto }
            return choice
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    @MainActor
    static var regionNameInUse: String? {
        MezonSocket.shared.targetEndpoint.map { regionName(ofHost: $0.host) }
    }

    static func regionName(ofHost host: String) -> String {
        let normalized = host.lowercased()
        return allCases.first { $0.host == normalized }?.regionName ?? host
    }

    var host: String? {
        switch self {
        case .auto: return nil
        case .vn1: return "sock.mezon.ai"
        case .vn2: return "sock3.mezon.ai"
        case .us: return "sock2.mezon.ai"
        }
    }

    var regionName: String? {
        switch self {
        case .auto: return nil
        case .vn1: return "VN1"
        case .vn2: return "VN2"
        case .us: return "US"
        }
    }
}

final class EndpointHealth {
    static let slowRttMs: Double = 500
    static let slowStreakRequired = 3
    static let probeWarmup: TimeInterval = 15
    static let apiTimeoutsRequired = 2
    static let apiTimeoutWindow: TimeInterval = 30
    static let pongOverdueAfter: TimeInterval = 12
    static let weakReportSpacing: TimeInterval = 60

    private var endpoint: RealtimeEndpoint?
    private var connectedSince: Date?
    private var slowStreak = 0
    private var apiTimeouts: [Date] = []
    private var lastWeakReportAt: Date?
    private var slowReportsDisabled = false

    func setEndpoint(_ next: RealtimeEndpoint?) {
        if isOnSameNode(as: next) {
            endpoint = next
            return
        }
        endpoint = next
        forgetConnection()
        slowReportsDisabled = false
    }

    func connectedEndpoint() -> RealtimeEndpoint? {
        guard connectedSince != nil else { return nil }
        return endpoint
    }

    func recordConnected(at now: Date) {
        connectedSince = now
        slowStreak = 0
        apiTimeouts.removeAll()
        slowReportsDisabled = false
    }

    func recordDisconnected() {
        forgetConnection()
    }

    func recordActiveProbe(rttMs: Double, at now: Date) -> Bool {
        guard let connectedSince, now.timeIntervalSince(connectedSince) >= Self.probeWarmup else { return false }
        slowStreak = rttMs >= Self.slowRttMs ? slowStreak + 1 : 0
        guard slowStreak >= Self.slowStreakRequired else { return false }
        return claimWeakReport(at: now)
    }

    func recordApiTimeout(at now: Date) -> Bool {
        guard connectedSince != nil else { return false }
        apiTimeouts.removeAll { now.timeIntervalSince($0) > Self.apiTimeoutWindow }
        apiTimeouts.append(now)
        guard apiTimeouts.count >= Self.apiTimeoutsRequired else { return false }
        return claimWeakReport(at: now)
    }

    func recordHeartbeat(sinceLastPong gap: TimeInterval, at now: Date) -> Bool {
        guard connectedSince != nil, gap > Self.pongOverdueAfter else { return false }
        return claimWeakReport(at: now)
    }

    func disableSlowReports() {
        slowReportsDisabled = true
        slowStreak = 0
        apiTimeouts.removeAll()
    }

    private func claimWeakReport(at now: Date) -> Bool {
        guard !slowReportsDisabled else { return false }
        if let lastWeakReportAt, now.timeIntervalSince(lastWeakReportAt) < Self.weakReportSpacing {
            return false
        }
        lastWeakReportAt = now
        slowStreak = 0
        apiTimeouts.removeAll()
        return true
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
        apiTimeouts.removeAll()
    }
}
