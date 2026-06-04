import Foundation

enum ImgproxyURL {

    private static var proxyBase: String {
        let env = MezonEnvironment.current
        return "\(env.imgproxyBaseURL)/\(env.imgproxySigningPath)"
    }
    private static let cdnHosts = ["cdn.mezon", "profile.mezon"]
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

    static func secureURLString(from sourceURL: String) -> String {
        let s = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("http://"),
              cdnHosts.contains(where: { s.contains($0) }) else {
            return s
        }
        if var components = URLComponents(string: s) {
            components.scheme = "https"
            return components.string ?? "https://" + String(s.dropFirst("http://".count))
        }
        return "https://" + String(s.dropFirst("http://".count))
    }

    static func attachmentURL(
        from sourceURL: String,
        width: Int,
        height: Int,
        resizeType: String = "fit"
    ) -> String {
        let resolvedSourceURL = secureURLString(from: sourceURL)
        guard !resolvedSourceURL.isEmpty else { return resolvedSourceURL }
        guard cdnHosts.contains(where: { resolvedSourceURL.contains($0) }) else {
            return resolvedSourceURL
        }
        if shouldSkipProxy(resolvedSourceURL) {
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
        if resolvedSourceURL.contains("imgproxy.mezon") {
            return resolvedSourceURL
        }

        if shouldSkipProxy(resolvedSourceURL) {
            return resolvedSourceURL
        }

        guard cdnHosts.contains(where: { resolvedSourceURL.contains($0) }) else {
            return resolvedSourceURL
        }

        let processingOptions = "rs:\(resizeType):\(width):\(height):1/mb:2097152"
        let encodedSource = resolvedSourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolvedSourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@webp"
    }

    static func avatarProxyURL(from sourceURL: String, width: Int = 100, height: Int = 100) -> String {
        let s = secureURLString(from: sourceURL)
        guard !s.isEmpty else { return s }
        if s.contains("imgproxy.mezon") {
            return s
        }
        guard s.hasPrefix("http://") || s.hasPrefix("https://") else {
            return s
        }
        guard cdnHosts.contains(where: { s.contains($0) }) else {
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


    static func createEmoji(from sourceURL: String, width: Int, height: Int, resizeType: String = "fit") -> String {
        let resolvedSourceURL = secureURLString(from: sourceURL)
        guard !resolvedSourceURL.isEmpty else { return resolvedSourceURL }
        if shouldSkipProxy(resolvedSourceURL) {
            return resolvedSourceURL
        }
        guard cdnHosts.contains(where: { resolvedSourceURL.contains($0) }) else {
            return resolvedSourceURL
        }
        let processingOptions = "rs:\(resizeType):\(width):\(height):1/mb:2097152"
        let encodedSource = resolvedSourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? resolvedSourceURL
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@webp"
    }
}
