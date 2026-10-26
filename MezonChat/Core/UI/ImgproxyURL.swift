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
        AvatarProxyURL.knownHosts.union(
            [URL(string: MezonEnvironment.current.imgproxyBaseURL)?.host?.lowercased()].compactMap { $0 }
        )
    }

    private static func hasHost(_ sourceURL: String, in hosts: Set<String>) -> Bool {
        guard let components = URLComponents(string: sourceURL),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    static func cacheKey(from key: String) -> String {
        AvatarProxyURL.cacheKey(key, proxyHosts: proxyHosts)
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

    static func clanLogoURL(from sourceURL: String, width: Int = 100, height: Int = 100) -> String {
        iconURL(from: absoluteResourceURL(from: sourceURL), width: width, height: height, resizeType: "fill-down")
    }

    static func channelMediaThumbnailURL(from sourceURL: String) -> String {
        let source = secureURLString(from: sourceURL)
        if hasHost(source, in: proxyHosts) {
            return AvatarProxyURL.resized(
                source, pixelSide: 200, resizeType: "fill", enlarge: true, extend: false,
                proxyHosts: proxyHosts
            )
        }
        return attachmentURL(from: source, width: 200, height: 200, resizeType: "fill")
    }

    /// Update incoming proxy URLs without creating a new rendition for direct image URLs.
    static func normalizedIconURL(from sourceURL: String, preserveResizeType: Bool = false) -> String {
        AvatarProxyURL.normalized(
            secureURLString(from: sourceURL),
            proxyHosts: proxyHosts,
            preserveResizeType: preserveResizeType
        )
    }

    /// Avatars and logos crop to fill by default, without upscaling small source images.
    static func iconURL(
        from sourceURL: String,
        width: Int = 100,
        height: Int = 100,
        resizeType: String = "fill-down"
    ) -> String {
        iconProxyURL(from: sourceURL, width: width, height: height, resizeType: resizeType, outputFormat: "webp")
    }

    static func avatarProxyURL(from sourceURL: String, width: Int = 100, height: Int = 100) -> String {
        iconURL(from: sourceURL, width: width, height: height, resizeType: "fill-down")
    }

    static func avatarPreviewProxyURL(from sourceURL: String, width: Int = 100, height: Int = 100) -> String {
        iconProxyURL(from: sourceURL, width: width, height: height, resizeType: "fill-down", outputFormat: "png", forceProxy: true)
    }

    private static func iconProxyURL(
        from sourceURL: String,
        width: Int,
        height: Int,
        resizeType: String,
        outputFormat: String,
        forceProxy: Bool = false
    ) -> String {
        let resolvedURL = absoluteResourceURL(from: sourceURL)
        // Rebuild existing renditions so legacy proxy URLs receive the same resize options.
        let proxySource = self.sourceURL(fromProxyURL: resolvedURL)
        let source = secureURLString(from: proxySource?.absoluteString ?? resolvedURL)
        guard !source.isEmpty, hasHost(source, in: cdnHosts) else {
            return normalizedIconURL(from: resolvedURL, preserveResizeType: resizeType == "fit")
        }
        if !forceProxy && proxySource == nil && shouldSkipProxy(source) {
            return resolvedURL
        }
        let w = max(1, width)
        let h = max(1, height)
        let processingOptions = "rs:\(resizeType):\(w):\(h):0:1/mb:2097152"
        let encodedSource = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source
        return "\(proxyBase)/\(processingOptions)/plain/\(encodedSource)@\(outputFormat)"
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
