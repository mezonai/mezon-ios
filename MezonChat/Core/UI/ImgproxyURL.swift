import Foundation

enum ImgproxyURL {

    private static var proxyBase: String {
        let env = MezonEnvironment.current
        return "\(env.imgproxyBaseURL)/\(env.imgproxySigningPath)"
    }
    private static var cdnHosts: Set<String> {
        Set([
            "cdn.mezon.ai", "cdn.mezon.vn", "cdn.komu.vn", "cdn.komu.ai",
            "profile.mezon.ai", "profile.mezon.vn",
        ] + [MezonConfig.cloudflareCdnURL, MezonConfig.mezonCdnURL, MezonConfig.profileImgURL]
            .compactMap { URL(string: $0)?.host?.lowercased() })
    }

    private static var proxyHosts: Set<String> {
        Set([
            "imgproxy.mezon.ai", "imgproxy.mezon.vn", "imgproxy.komu.vn", "imgproxy.komu.ai",
        ] + [URL(string: MezonEnvironment.current.imgproxyBaseURL)?.host?.lowercased()].compactMap { $0 })
    }

    private static func hasHost(_ sourceURL: String, in hosts: Set<String>) -> Bool {
        guard let components = URLComponents(string: sourceURL),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased() else { return false }
        return hosts.contains(host)
    }
    private static let skipExtensions: Set<String> = ["gif", "webp"]

    private static let attachmentOutputSuffix = "@webp"

    private static func sourceExtension(_ sourceURL: String) -> String {
        let s = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if let components = URLComponents(string: s), !components.path.isEmpty {
            return (components.path as NSString).pathExtension.lowercased()
        }
        return (s as NSString).pathExtension.lowercased()
    }

    private static func shouldSkipProxy(_ sourceURL: String) -> Bool {
        skipExtensions.contains(sourceExtension(sourceURL))
    }

    static func sourceURL(fromProxyURL proxyURL: String) -> URL? {
        guard hasHost(proxyURL, in: proxyHosts),
              let marker = proxyURL.range(of: "/plain/") else { return nil }
        var encoded = proxyURL[marker.upperBound...]
        if let suffix = encoded.lastIndex(of: "@") {
            encoded = encoded[..<suffix]
        }
        let source = String(encoded).removingPercentEncoding ?? String(encoded)
        guard source.hasPrefix("http://") || source.hasPrefix("https://") else { return nil }
        return URL(string: source)
    }

    static func secureURLString(from sourceURL: String) -> String {
        let s = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: s),
              components.scheme?.lowercased() == "http",
              hasHost(s, in: cdnHosts) else {
            return s
        }
        components.scheme = "https"
        return components.string ?? s
    }

    static func absoluteResourceURL(from raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if let u = URL(string: t), u.scheme != nil { return secureURLString(from: t) }
        if t.hasPrefix("//") { return secureURLString(from: "https:\(t)") }
        let base = MezonConfig.cloudflareCdnURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if t.hasPrefix("/") { return "\(base)\(t)" }
        return "\(base)/\(t)"
    }

    static func attachmentURL(
        from sourceURL: String,
        width: Int,
        height: Int,
        resizeType: String = "fit",
        forceProxy: Bool = false
    ) -> String {
        let resolvedSourceURL = secureURLString(from: sourceURL)
        guard !resolvedSourceURL.isEmpty else { return resolvedSourceURL }
        guard hasHost(resolvedSourceURL, in: cdnHosts) else {
            return resolvedSourceURL
        }
        if !forceProxy && shouldSkipProxy(resolvedSourceURL) {
            return resolvedSourceURL
        }
        let w = max(1, width)
        let h = max(1, height)
        let processingOptions = "rs:\(resizeType):\(w):\(h):1/mb:2097152"
        let encodedSource = resolvedSourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolvedSourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)\(attachmentOutputSuffix)"
    }

    static func create(
        from sourceURL: String,
        width: Int = 100,
        height: Int = 100,
        resizeType: String = "fit"
    ) -> String {
        let resolvedSourceURL = secureURLString(from: sourceURL)
        guard !resolvedSourceURL.isEmpty else { return resolvedSourceURL }
        if hasHost(resolvedSourceURL, in: proxyHosts) {
            return resolvedSourceURL
        }

        if shouldSkipProxy(resolvedSourceURL) {
            return resolvedSourceURL
        }

        guard hasHost(resolvedSourceURL, in: cdnHosts) else {
            return resolvedSourceURL
        }

        let processingOptions = "rs:\(resizeType):\(width):\(height):1/mb:2097152"
        let encodedSource = resolvedSourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolvedSourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@webp"
    }

    static func avatarProxyURL(from sourceURL: String, width: Int = 100, height: Int = 100) -> String {
        let s = secureURLString(from: sourceURL)
        guard !s.isEmpty else { return s }
        if hasHost(s, in: proxyHosts) {
            return s
        }
        guard s.hasPrefix("http://") || s.hasPrefix("https://") else {
            return s
        }
        guard hasHost(s, in: cdnHosts) else {
            return s
        }
        if shouldSkipProxy(s) {
            return s
        }
        let w = max(1, width)
        let h = max(1, height)
        let processingOptions = "rs:fit:\(w):\(h):1/mb:2097152"
        let encodedSource = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@webp"
    }

    static func avatarPreviewProxyURL(from sourceURL: String, width: Int = 100, height: Int = 100) -> String {
        let s = secureURLString(from: sourceURL)
        guard !s.isEmpty else { return s }
        if hasHost(s, in: proxyHosts) {
            return s
        }
        guard s.hasPrefix("http://") || s.hasPrefix("https://") else { return s }
        guard hasHost(s, in: cdnHosts) else { return s }
        let w = max(1, width)
        let h = max(1, height)
        let processingOptions = "rs:fit:\(w):\(h):1/mb:2097152"
        let encodedSource = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@png"
    }

    static func createEmoji(from sourceURL: String, width: Int, height: Int, resizeType: String = "fit") -> String {
        let resolvedSourceURL = secureURLString(from: sourceURL)
        guard !resolvedSourceURL.isEmpty else { return resolvedSourceURL }
        if shouldSkipProxy(resolvedSourceURL) {
            return resolvedSourceURL
        }
        guard hasHost(resolvedSourceURL, in: cdnHosts) else {
            return resolvedSourceURL
        }
        let processingOptions = "rs:\(resizeType):\(width):\(height):1/mb:2097152"
        let encodedSource = resolvedSourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolvedSourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@webp"
    }
}
