import Foundation
import CryptoKit

// Shared by the app and notification extension, which can both receive existing proxy URLs.
enum AvatarProxyURL {
    static let cacheVersion = "fixed-images-100-200-v1:"

    static let knownHosts: Set<String> = [
        "imgproxy.mezon.ai", "imgproxy.mezon.vn", "imgproxy.komu.vn", "imgproxy.komu.ai",
        "dev-imgproxy.nccsoft.vn",
    ]

    static func cacheKey(_ key: String, proxyHosts: Set<String> = knownHosts) -> String {
        if key.hasPrefix(cacheVersion) { return key }
        if key.hasPrefix("optimized-avatar:") { return cacheVersion + key }
        guard let host = URL(string: key)?.host?.lowercased(), proxyHosts.contains(host) else { return key }
        let optionsEnd = key.range(of: "/plain/")?.lowerBound ?? key.endIndex
        for option in key[..<optionsEnd].components(separatedBy: "/") {
            let parts = option.components(separatedBy: ":")
            guard parts.count >= 4, ["rs", "resize"].contains(parts[0]) else { continue }
            if (parts[1] == "fill-down" && parts[2] == "100" && parts[3] == "100")
                || (parts[1] == "fill" && parts[2] == "200" && parts[3] == "200") {
                return cacheVersion + key
            }
        }
        return key
    }

    static func normalized(
        _ sourceURL: String,
        proxyHosts: Set<String> = knownHosts,
        preserveResizeType: Bool = false
    ) -> String {
        resized(
            sourceURL, pixelSide: preserveResizeType ? nil : 100,
            resizeType: preserveResizeType ? nil : "fill-down", enlarge: false, extend: true,
            proxyHosts: proxyHosts
        )
    }

    static func resized(
        _ sourceURL: String,
        pixelSide: Int?,
        resizeType: String?,
        enlarge: Bool,
        extend: Bool,
        proxyHosts: Set<String> = knownHosts
    ) -> String {
        guard let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(), proxyHosts.contains(host) else { return sourceURL }

        // Only edit processing options; preserve the source URL, output format, and other options.
        let optionsEnd = sourceURL.range(of: "/plain/")?.lowerBound ?? sourceURL.endIndex
        var parts = sourceURL[..<optionsEnd].components(separatedBy: "/")
        for index in parts.indices {
            var resize = parts[index].components(separatedBy: ":")
            guard ["rs", "resize"].contains(resize[0]), resize.count >= 4,
                  let width = Int(resize[2]), let height = Int(resize[3]),
                  width >= 0, height >= 0, width > 0 || height > 0 else { continue }
            if pixelSide == nil && (width <= 0 || width != height) { continue }
            while resize.count < 6 { resize.append("") }
            if let pixelSide {
                resize[2] = String(pixelSide)
                resize[3] = String(pixelSide)
            }
            if let resizeType { resize[1] = resizeType }
            resize[4] = enlarge ? "1" : "0"
            resize[5] = extend ? "1" : "0"
            parts[index] = resize.joined(separator: ":")
        }
        return parts.joined(separator: "/") + sourceURL[optionsEnd...]
    }
}

enum NotificationAvatarStore {
    private static let appGroupIdentifier = "group.mezon.mobile"
    private static let maxFileCount = 300
    private static let trimmedFileCount = 250
    private static let maxAvatarBytes = 512 * 1024

    private static let directory: URL? = {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let url = container.appendingPathComponent("Library/Caches/notification-avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func data(for avatarURL: String) -> Data? {
        guard let file = fileURL(for: avatarURL),
              let data = try? Data(contentsOf: file),
              !data.isEmpty else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    static func contains(_ avatarURL: String) -> Bool {
        guard let file = fileURL(for: avatarURL) else { return false }
        return FileManager.default.fileExists(atPath: file.path)
    }

    static func store(_ data: Data, for avatarURL: String) {
        guard !data.isEmpty, data.count <= maxAvatarBytes, let file = fileURL(for: avatarURL) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        trimIfNeeded()
    }

    static func removeAll() {
        guard let directory = directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func fileURL(for avatarURL: String) -> URL? {
        guard !avatarURL.isEmpty, let directory = directory else { return nil }
        let key = AvatarProxyURL.cacheVersion + AvatarProxyURL.normalized(avatarURL)
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    private static func trimIfNeeded() {
        guard let directory = directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey]
              ),
              files.count > maxFileCount else { return }
        let oldestFirst = files.sorted { modificationDate(of: $0) < modificationDate(of: $1) }
        for file in oldestFirst.prefix(files.count - trimmedFileCount) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func modificationDate(of file: URL) -> Date {
        (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
