import Foundation
import UIKit

final class SharingManager {

    static let shared = SharingManager()

    private let sharedKey = "mezon.mobile.sharing"

    private init() {}

    struct SharedMediaFile: Codable {
        var path: String
        var thumbnail: String?
        var duration: Double?
        var type: SharedMediaType
        var width: CGFloat?
        var height: CGFloat?
    }

    struct ExistingVideoAttachment: Codable {
        var url: String
        var thumbnail: String
        var filename: String
        var filetype: String
        var size: Int64
        var width: Int
        var height: Int
        var durationSeconds: Int
    }

    enum SharedMediaType: Int, Codable {
        case image = 0
        case video = 1
        case file = 2
    }

    enum SharedContent {
        case media([SharedMediaFile])
        case text([String])
        case existingVideo(ExistingVideoAttachment)
    }

    func loadSharedContent(type: String) -> SharedContent? {
        guard let userDefaults = UserDefaults(
            suiteName: ExistingVideoSharePayload.appGroupIdentifier
        ) else { return nil }

        defer {
            userDefaults.removeObject(forKey: sharedKey)
            userDefaults.synchronize()
        }

        switch type {
        case "existingVideo":
            guard let data = userDefaults.data(forKey: sharedKey),
                  let attachment = try? JSONDecoder().decode(ExistingVideoAttachment.self, from: data) else { return nil }
            return .existingVideo(attachment)

        case "media", "file":
            guard let data = userDefaults.data(forKey: sharedKey) else { return nil }
            guard let files = try? JSONDecoder().decode([SharedMediaFile].self, from: data) else { return nil }
            return files.isEmpty ? nil : .media(files)

        case "text":
            guard let texts = userDefaults.stringArray(forKey: sharedKey) else { return nil }
            return texts.isEmpty ? nil : .text(texts)

        default:
            if let data = userDefaults.data(forKey: sharedKey),
               let attachment = try? JSONDecoder().decode(ExistingVideoAttachment.self, from: data) {
                return .existingVideo(attachment)
            }
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
        guard let userDefaults = UserDefaults(
            suiteName: ExistingVideoSharePayload.appGroupIdentifier
        ) else { return false }
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
