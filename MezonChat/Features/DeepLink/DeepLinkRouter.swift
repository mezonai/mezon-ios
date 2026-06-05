import Foundation

enum DeepLinkRoute: Equatable {
    case channelApp(channelId: String, clanId: String?, code: String?, subpath: String?)
    case invite(code: String)
    case chat(username: String, data: String?)
    case botInstall(appId: String)
}

enum DeepLinkRouter {
    static let supportedPrefixes = ["https://mezon.ai", "http://mezon.ai", "mezon.ai://", "mezon://"]

    private(set) static var pending: DeepLinkRoute?

    static func isDeepLink(_ url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased() {
            if scheme == "mezon" || scheme == "mezon.ai" { return true }
            if scheme == "http" || scheme == "https" {
                return url.host?.lowercased() == "mezon.ai"
            }
        }
        let lowered = url.absoluteString.lowercased()
        return supportedPrefixes.contains(where: { lowered.hasPrefix($0) })
    }

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard isDeepLink(url), let route = route(from: url) else { return false }
        pending = route
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mezonHandleDeepLink, object: nil)
        }
        return true
    }

    @discardableResult
    static func handle(userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        return handle(url)
    }

    static func consumePending() -> DeepLinkRoute? {
        defer { pending = nil }
        return pending
    }

    static func route(from url: URL) -> DeepLinkRoute? {
        let raw = url.absoluteString
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String? {
            queryItems.first(where: { $0.name == name })?.value
        }

        if raw.contains("channel-app/") {
            if let m = firstMatch(in: raw, pattern: "channel-app/([0-9]+)/([0-9]+)") {
                return .channelApp(channelId: m[1], clanId: m[2], code: query("code"), subpath: query("subpath"))
            }
            if let m = firstMatch(in: raw, pattern: "channel-app/([0-9]+)") {
                return .channelApp(channelId: m[1], clanId: nil, code: query("code"), subpath: query("subpath"))
            }
        }

        if raw.contains("invite/") {
            if let m = firstMatch(in: raw, pattern: "invite/(?:chat/)?([0-9]+)") {
                return .invite(code: m[1])
            }
        }

        if raw.contains("chat/") {
            if let m = firstMatch(in: raw, pattern: "(?:^|/)chat/([^/?#]+)") {
                return .chat(username: m[1], data: query("data"))
            }
        }

        if raw.contains("app/install/") || raw.contains("bot/install/") {
            if let m = firstMatch(in: raw, pattern: "(?:bot|app)/install/([0-9]+)") {
                return .botInstall(appId: m[1])
            }
        }

        return nil
    }

    static func decodeProfileData(_ dataParam: String) -> QRUserProfileData? {
        let s = dataParam.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
        guard !s.isEmpty else { return nil }
        if let raw = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
           let p = try? JSONDecoder().decode(QRUserProfileData.self, from: raw) {
            return p
        }
        if let raw = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
           let str = String(data: raw, encoding: .utf8),
           let json = str.removingPercentEncoding,
           let j = json.data(using: .utf8),
           let p = try? JSONDecoder().decode(QRUserProfileData.self, from: j) {
            return p
        }
        return nil
    }

    private static func firstMatch(in string: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            if let r = Range(match.range(at: index), in: string) {
                groups.append(String(string[r]))
            } else {
                groups.append("")
            }
        }
        return groups
    }
}

extension Notification.Name {
    static let mezonHandleDeepLink = Notification.Name("MezonHandleDeepLink")
}
