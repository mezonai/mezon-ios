import Foundation
import CryptoKit

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
        let name = SHA256.hash(data: Data(avatarURL.utf8)).map { String(format: "%02x", $0) }.joined()
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
