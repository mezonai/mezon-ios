import UIKit

final class StorageMaintenance {

    static let shared = StorageMaintenance()

    private static let cacheByteLimit: Int64 = 500 * 1024 * 1024
    private static let cacheTrimTargetBytes: Int64 = 400 * 1024 * 1024
    private static let cacheWriteCheckBytes: Int64 = 32 * 1024 * 1024
    private static let heavyFileBytes: Int64 = 256 * 1024
    private static let unusedFileLifetime: TimeInterval = 10 * 24 * 3600
    private static let recentUseGrace: TimeInterval = 30 * 60
    private static let backgroundPassInterval: TimeInterval = 3600
    private static let staleTempFileMargin: TimeInterval = 3600
    private static let uploadTempFilePrefixes = [
        "picked-", "camera-", "pasted-", "edited-", "voice-", "gallery-video-", "transfer-success-"
    ]
    private static let uploadTempDirectoryNames = ["mezon-uploads", "mezon_video_shares"]
    private static let usageTrackingStartKey = "mezon.storage.cacheUsageTrackingStart"
    private static let legacyFilesRemovedKey = "mezon.storage.legacyReactNativeFilesRemoved"

    private final class BackgroundTaskLease {
        private var id: UIBackgroundTaskIdentifier = .invalid

        init(name: String) {
            id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
                self?.end()
            }
        }

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }

    private struct CacheFile {
        let url: URL
        let bytes: Int64
        let lastUsed: Date
        let isAttachedToPlayer: Bool
    }

    private let queue = DispatchQueue(label: "mezon.storage.maintenance", qos: .utility)
    private var bytesWrittenSinceTrim: Int64 = 0
    private var lastBackgroundPass: Date?
    private var processLaunchDate: Date?

    private init() {}

    func noteProcessLaunch() {
        let launchDate = Date()
        queue.async { [self] in
            if processLaunchDate == nil {
                processLaunchDate = launchDate
            }
        }
    }

    func purgeAccountScopedCaches() {
        queue.async {
            try? FileManager.default.removeItem(at: VLCVideoPlayerNode.streamCacheDirectory)
        }
    }

    func noteDiskCacheWrite(byteCount: Int) {
        queue.async { [self] in
            bytesWrittenSinceTrim += Int64(byteCount)
            guard bytesWrittenSinceTrim >= StorageMaintenance.cacheWriteCheckBytes else { return }
            trimDiskCaches()
        }
    }

    func runBackgroundPass() {
        let now = Date()
        if let last = lastBackgroundPass,
           now.timeIntervalSince(last) < StorageMaintenance.backgroundPassInterval {
            return
        }
        lastBackgroundPass = now
        let lease = BackgroundTaskLease(name: "mezon.storage.maintenance")
        let group = DispatchGroup()
        group.enter()
        Postbox.shared.compactSettingsStorage {
            group.leave()
        }
        group.enter()
        queue.async { [self] in
            trimDiskCaches()
            removeStaleUploadTempFiles()
            removeLegacyFilesIfNeeded()
            group.leave()
        }
        group.notify(queue: .main) {
            lease.end()
        }
    }

    private func trimDiskCaches() {
        bytesWrittenSinceTrim = 0
        let fileManager = FileManager.default
        let now = Date()
        let trackingStart = usageTrackingStart(now: now)
        let attachedVideoNames = VLCVideoPlayerNode.attachedStreamCacheFileNames()
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]
        var files: [CacheFile] = []
        for directory in [ImageCache.shared.diskCacheURL, VLCVideoPlayerNode.streamCacheDirectory] {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            ) else { continue }
            for url in urls {
                guard let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true else { continue }
                files.append(CacheFile(
                    url: url,
                    bytes: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
                    lastUsed: values.contentModificationDate ?? .distantPast,
                    isAttachedToPlayer: attachedVideoNames.contains(url.lastPathComponent)
                ))
            }
        }
        var totalBytes = files.reduce(Int64(0)) { $0 + $1.bytes }
        var retained: [CacheFile] = []
        for file in files {
            let lastUsed = max(file.lastUsed, trackingStart)
            if !file.isAttachedToPlayer,
               now.timeIntervalSince(lastUsed) > StorageMaintenance.unusedFileLifetime,
               removeCacheFile(file) {
                totalBytes -= file.bytes
            } else {
                retained.append(file)
            }
        }
        guard totalBytes > StorageMaintenance.cacheByteLimit - StorageMaintenance.cacheWriteCheckBytes else { return }
        let evictable = retained
            .filter { !$0.isAttachedToPlayer && now.timeIntervalSince($0.lastUsed) > StorageMaintenance.recentUseGrace }
            .sorted { lhs, rhs in
                let lhsIsHeavy = lhs.bytes >= StorageMaintenance.heavyFileBytes
                let rhsIsHeavy = rhs.bytes >= StorageMaintenance.heavyFileBytes
                if lhsIsHeavy != rhsIsHeavy { return lhsIsHeavy }
                return lhs.lastUsed < rhs.lastUsed
            }
        for file in evictable {
            guard totalBytes > StorageMaintenance.cacheTrimTargetBytes else { break }
            if removeCacheFile(file) {
                totalBytes -= file.bytes
            }
        }
    }

    private func removeCacheFile(_ file: CacheFile) -> Bool {
        let fileManager = FileManager.default
        if (try? fileManager.removeItem(at: file.url)) != nil {
            return true
        }
        return !fileManager.fileExists(atPath: file.url.path)
    }

    private func removeStaleUploadTempFiles() {
        guard let launchDate = processLaunchDate else { return }
        let staleBefore = launchDate.addingTimeInterval(-StorageMaintenance.staleTempFileMargin)
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .attributeModificationDateKey]
        var candidates: [URL] = []
        if let urls = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) {
            candidates += urls.filter { url in
                StorageMaintenance.uploadTempFilePrefixes.contains(where: { url.lastPathComponent.hasPrefix($0) })
            }
        }
        for name in StorageMaintenance.uploadTempDirectoryNames {
            if let urls = try? fileManager.contentsOfDirectory(
                at: temporaryDirectory.appendingPathComponent(name, isDirectory: true),
                includingPropertiesForKeys: Array(resourceKeys),
                options: []
            ) {
                candidates += urls
            }
        }
        for url in candidates {
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true,
                  let changedAt = values.attributeModificationDate,
                  changedAt < staleBefore else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    private func usageTrackingStart(now: Date) -> Date {
        let defaults = UserDefaults.standard
        let stored = defaults.double(forKey: StorageMaintenance.usageTrackingStartKey)
        if stored > 0 {
            return Date(timeIntervalSince1970: stored)
        }
        defaults.set(now.timeIntervalSince1970, forKey: StorageMaintenance.usageTrackingStartKey)
        return now
    }

    private func removeLegacyFilesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: StorageMaintenance.legacyFilesRemovedKey) else { return }
        let fileManager = FileManager.default
        var legacyURLs: [URL] = []
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            legacyURLs.append(documents.appendingPathComponent("mmkv", isDirectory: true))
            legacyURLs.append(documents.appendingPathComponent("VideoThumbnailCache", isDirectory: true))
        }
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            legacyURLs.append(caches.appendingPathComponent("com.hackemist.SDImageCache", isDirectory: true))
        }
        for url in legacyURLs {
            try? fileManager.removeItem(at: url)
        }
        if !legacyURLs.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            defaults.set(true, forKey: StorageMaintenance.legacyFilesRemovedKey)
        }
    }
}
