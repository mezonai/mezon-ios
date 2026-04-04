import Foundation
import UIKit

final class SharingManager {

    static let shared = SharingManager()

    private let appGroupIdentifier = "group.mezon.mobile"
    private let sharedKey = "mezon.mobile.sharing"

    private init() {}

    struct SharedMediaFile: Codable {
        var path: String
        var thumbnail: String?
        var duration: Double?
        var type: SharedMediaType
    }

    enum SharedMediaType: Int, Codable {
        case image = 0
        case video = 1
        case file = 2
    }

    enum SharedContent {
        case media([SharedMediaFile])
        case text([String])
    }

    func loadSharedContent(type: String) -> SharedContent? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return nil }

        defer {
            userDefaults.removeObject(forKey: sharedKey)
            userDefaults.synchronize()
        }

        switch type {
        case "media", "file":
            guard let data = userDefaults.data(forKey: sharedKey) else { return nil }
            guard let files = try? JSONDecoder().decode([SharedMediaFile].self, from: data) else { return nil }
            return files.isEmpty ? nil : .media(files)

        case "text":
            guard let texts = userDefaults.stringArray(forKey: sharedKey) else { return nil }
            return texts.isEmpty ? nil : .text(texts)

        default:
            if let data = userDefaults.data(forKey: sharedKey),
               let files = try? JSONDecoder().decode([SharedMediaFile].self, from: data), !files.isEmpty {
                return .media(files)
            }
            if let texts = userDefaults.stringArray(forKey: sharedKey), !texts.isEmpty {
                return .text(texts)
            }
            return nil
        }
    }

    func hasPendingSharedContent() -> Bool {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return false }
        return userDefaults.object(forKey: sharedKey) != nil
    }

    func localFileURL(from sharedPath: String) -> URL? {
        if sharedPath.hasPrefix("file://") {
            return URL(string: sharedPath)
        }
        return URL(fileURLWithPath: sharedPath)
    }

    func cleanupSharedFiles(_ files: [SharedMediaFile]) {
        for file in files {
            if let url = localFileURL(from: file.path) {
                try? FileManager.default.removeItem(at: url)
            }
            if let thumbnail = file.thumbnail, let url = localFileURL(from: thumbnail) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
