import Foundation
import CryptoKit
import UIKit
import AsyncDisplayKit
import AVFoundation
import MobileVLCKit

enum ImageResizeMode {
    case fit
    case fill
    case fillLeading
}

final class ImageCache {

    static let shared = ImageCache()

    private let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        let physical = ProcessInfo.processInfo.physicalMemory
        c.totalCostLimit = Int(min(physical / 8, 180 * 1024 * 1024))
        return c
    }()

    let diskCacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("mezon_image_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let ioQueue = DispatchQueue(label: "mezon.imagecache.io", qos: .utility)
    private let avatarDecodeQueue = DispatchQueue(
        label: "mezon.imagecache.avatar-decode",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let avatarSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private let notificationAvatarQueue = DispatchQueue(label: "mezon.imagecache.notification-avatar", qos: .background)
    private static let notificationAvatarShareDelay: TimeInterval = 3
    private var notificationAvatarURLs = Set<String>()

    private var inflightCallbacks: [String: [(UIImage?) -> Void]] = [:]
    private var forbiddenKeys: [String: Date] = [:]
    private static let forbiddenRetryAfter: TimeInterval = 60
    private struct OptimizedAvatarCallback {
        let preview: ((UIImage) -> Void)?
        let completion: (UIImage?) -> Void
    }
    private var optimizedAvatarCallbacks: [String: [OptimizedAvatarCallback]] = [:]
    private let inflightLock = NSLock()

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        memoryCache.removeAllObjects()
    }

    private func memoryCost(of image: UIImage) -> Int {
        let frameCount = max(image.images?.count ?? 1, 1)
        if let cg = image.cgImage {
            return cg.bytesPerRow * cg.height * frameCount
        }
        let scale = image.scale
        let pixels = Int(image.size.width * scale) * Int(image.size.height * scale)
        return pixels * 4 * frameCount
    }

    func memoryImage(forKey key: String) -> UIImage? {
        let key = ImgproxyURL.cacheKey(from: key)
        return memoryCache.object(forKey: key as NSString)
    }

    func image(forKey key: String) -> UIImage? {
        let key = ImgproxyURL.cacheKey(from: key)
        let nsKey = key as NSString

        if let cached = memoryCache.object(forKey: nsKey) {
            return cached
        }

        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage.decompressedImage(from: data) else { return nil }

        markDiskEntryUsed(fileURL)
        memoryCache.setObject(image, forKey: nsKey, cost: memoryCost(of: image))
        return image
    }

    func markDiskEntryUsed(forKey key: String) {
        let key = ImgproxyURL.cacheKey(from: key)
        markDiskEntryUsed(diskCacheURL.appendingPathComponent(key.sha256Hash))
    }

    private func markDiskEntryUsed(_ fileURL: URL) {
        ioQueue.async {
            let fileManager = FileManager.default
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
            if let lastUsed = attributes?[.modificationDate] as? Date,
               Date().timeIntervalSince(lastUsed) < 600 {
                return
            }
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        }
    }

    func imageFromDisk(forKey key: String, completion: @escaping (UIImage?) -> Void) {
        let key = ImgproxyURL.cacheKey(from: key)
        ioQueue.async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion(nil) }; return }
            let fileURL = self.diskCacheURL.appendingPathComponent(key.sha256Hash)
            guard let data = try? Data(contentsOf: fileURL),
                  let image = UIImage.decompressedImage(from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.markDiskEntryUsed(fileURL)
            self.memoryCache.setObject(image, forKey: key as NSString, cost: self.memoryCost(of: image))
            DispatchQueue.main.async { completion(image) }
        }
    }

    func hasDiskCache(forKey key: String) -> Bool {
        let key = ImgproxyURL.cacheKey(from: key)
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func setImage(_ image: UIImage, data: Data?, forKey key: String) {
        let key = ImgproxyURL.cacheKey(from: key)
        let nsKey = key as NSString
        memoryCache.setObject(image, forKey: nsKey, cost: memoryCost(of: image))

        if let data {
            let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
            ioQueue.async {
                try? data.write(to: fileURL, options: .atomic)
            }
            StorageMaintenance.shared.noteDiskCacheWrite(byteCount: data.count)
        }
    }

    func cachedData(forKey key: String) -> Data? {
        let key = ImgproxyURL.cacheKey(from: key)
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        markDiskEntryUsed(fileURL)
        return data
    }

    func persistData(_ data: Data, forKey key: String) {
        let key = ImgproxyURL.cacheKey(from: key)
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        ioQueue.async {
            try? data.write(to: fileURL, options: .atomic)
        }
        StorageMaintenance.shared.noteDiskCacheWrite(byteCount: data.count)
    }

    func clearDiskCache() {
        ioQueue.async { [diskCacheURL] in
            try? FileManager.default.removeItem(at: diskCacheURL)
            try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }
    }

    func purgeAccountScopedCaches() {
        memoryCache.removeAllObjects()
        inflightLock.lock()
        inflightCallbacks.removeAll()
        optimizedAvatarCallbacks.removeAll()
        notificationAvatarURLs.removeAll()
        inflightLock.unlock()
        ioQueue.sync {
            try? FileManager.default.removeItem(at: diskCacheURL)
            try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }
        notificationAvatarQueue.async {
            NotificationAvatarStore.removeAll()
        }
    }

    func shareAvatarForNotifications(avatarURL: String, cacheKeys: [String]) {
        guard !avatarURL.isEmpty else { return }
        inflightLock.lock()
        let isNew = notificationAvatarURLs.insert(avatarURL).inserted
        inflightLock.unlock()
        guard isNew else { return }
        let sources = cacheKeys.map { ImgproxyURL.iconURL(from: $0) }
            .filter { !$0.isEmpty }
            .map { diskCacheURL.appendingPathComponent(ImgproxyURL.cacheKey(from: $0).sha256Hash) }
        notificationAvatarQueue.asyncAfter(deadline: .now() + Self.notificationAvatarShareDelay) {
            guard !NotificationAvatarStore.contains(avatarURL) else { return }
            for source in sources {
                if let data = try? Data(contentsOf: source), !data.isEmpty {
                    NotificationAvatarStore.store(data, for: avatarURL)
                    return
                }
            }
        }
    }

    func trimDiskCache(maxAge: TimeInterval = 7 * 24 * 3600) {
        ioQueue.async { [diskCacheURL] in
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: diskCacheURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            ) else { return }

            let cutoff = Date().addingTimeInterval(-maxAge)
            for file in files {
                guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = attrs.contentModificationDate,
                      modified < cutoff else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    @discardableResult
    func loadImage(
        urlString: String,
        completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask? {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            completion(nil)
            return nil
        }

        if let cached = memoryImage(forKey: urlString) {
            completion(cached)
            return nil
        }

        if isForbidden(urlString) {
            completion(nil)
            return nil
        }

        inflightLock.lock()
        if inflightCallbacks[urlString] != nil {
            inflightCallbacks[urlString]?.append(completion)
            inflightLock.unlock()
            return nil
        }
        inflightCallbacks[urlString] = [completion]
        inflightLock.unlock()

        let fetchAndDeliver: (UIImage?) -> Void = { [weak self] image in
            guard let self else { return }
            self.inflightLock.lock()
            let callbacks = self.inflightCallbacks.removeValue(forKey: urlString) ?? []
            self.inflightLock.unlock()
            DispatchQueue.main.async {
                for cb in callbacks { cb(image) }
            }
        }

        if hasDiskCache(forKey: urlString) {
            imageFromDisk(forKey: urlString) { [weak self] diskImage in
                if let diskImage {
                    fetchAndDeliver(diskImage)
                } else {
                    _ = self?.downloadImage(url: url, key: urlString, completion: fetchAndDeliver)
                }
            }
            return nil
        }

        return downloadImage(url: url, key: urlString, completion: fetchAndDeliver)
    }

    private static let maxImageDownloadRetries = 2
    private static let imageDownloadRetryBackoff: [TimeInterval] = [0.6, 1.8]

    func isForbidden(_ urlString: String) -> Bool {
        inflightLock.lock()
        defer { inflightLock.unlock() }
        guard let forbiddenAt = forbiddenKeys[urlString] else { return false }
        if Date().timeIntervalSince(forbiddenAt) < Self.forbiddenRetryAfter {
            return true
        }
        forbiddenKeys[urlString] = nil
        return false
    }

    private func markForbidden(_ key: String) {
        inflightLock.lock()
        forbiddenKeys[key] = Date()
        inflightLock.unlock()
    }

    static func responseStatusAcceptable(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return true }
        return (200..<300).contains(http.statusCode)
    }

    static func isCancellation(_ error: Error?) -> Bool {
        guard let e = error as NSError? else { return false }
        return e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled
    }

    static func shouldRetryMediaRequest(response: URLResponse?, error: Error?) -> Bool {
        if error != nil { return true }
        guard let http = response as? HTTPURLResponse else { return true }
        return http.statusCode == 408
            || http.statusCode == 429
            || (500..<600).contains(http.statusCode)
    }

    private static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        imageDownloadRetryBackoff[min(attempt, imageDownloadRetryBackoff.count - 1)]
    }

    @discardableResult
    private func downloadImage(
        url: URL,
        key: String,
        completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask? {
        return startImageDownload(url: url, key: key, attempt: 0, completion: completion)
    }

    @discardableResult
    private func startImageDownload(
        url: URL,
        key: String,
        attempt: Int,
        completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask? {
        if let request = CDNSigner.shared.readyRequestURL(for: url) {
            return startImageRequest(
                request, url: url, key: key, attempt: attempt,
                isSignatureRetry: false, completion: completion)
        }
        CDNSigner.shared.requestURL(for: url) { [weak self] request in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.startImageRequest(
                request, url: url, key: key, attempt: attempt,
                isSignatureRetry: false, completion: completion)
        }
        return nil
    }

    @discardableResult
    private func startImageRequest(
        _ request: CDNRequestURL,
        url: URL,
        key: String,
        attempt: Int,
        isSignatureRetry: Bool,
        completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask {
        let task = imageSession.dataTask(with: request.url) { [weak self] data, response, error in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            if Self.isCancellation(error) {
                self.handOverCancelledImageRequest(url: url, key: key, completion: completion)
                return
            }

            if Self.responseStatusAcceptable(response),
               let data,
               let image = UIImage.decompressedImage(from: data) {
                self.setImage(image, data: data, forKey: key)
                DispatchQueue.main.async { completion(image) }
                return
            }


            if !isSignatureRetry, CDNSigner.shared.shouldRetry(request, response: response) {
                CDNSigner.shared.freshRequestURL(after: request, for: url) { [weak self] next in
                    guard let self, let next else {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    self.startImageRequest(
                        next, url: url, key: key, attempt: attempt,
                        isSignatureRetry: true, completion: completion)
                }
                return
            }

            if let sourceURL = ImgproxyURL.sourceURL(fromProxyURL: url.absoluteString) {
                _ = self.startImageDownload(url: sourceURL, key: key, attempt: 0, completion: completion)
                return
            }

            if (response as? HTTPURLResponse)?.statusCode == 403,
               request.isSigned || !CDNSigner.shared.canStillSign(url) {
                self.markForbidden(key)
                DispatchQueue.main.async { completion(nil) }
                return
            }

            if let error {
                SentryLogger.captureMediaError(error, extras: [
                    "where": "ImageCache.downloadImage",
                    "url": url.absoluteString,
                    "attempt": "\(attempt)",
                ])
            }

            if attempt < Self.maxImageDownloadRetries {
                let delay = Self.retryDelay(forAttempt: attempt)
                self.ioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    _ = self.startImageDownload(
                        url: url, key: key, attempt: attempt + 1, completion: completion)
                }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        task.resume()
        return task
    }

    private func handOverCancelledImageRequest(
        url: URL,
        key: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        inflightLock.lock()
        guard let waiting = inflightCallbacks[key], waiting.count > 1 else {
            inflightLock.unlock()
            DispatchQueue.main.async { completion(nil) }
            return
        }
        inflightCallbacks[key] = Array(waiting.dropFirst())
        inflightLock.unlock()
        let cancelledOwner = waiting[0]
        DispatchQueue.main.async { cancelledOwner(nil) }
        _ = startImageDownload(url: url, key: key, attempt: 0, completion: completion)
    }

    func cachedImage(forURL urlString: String) -> UIImage? {
        return image(forKey: urlString)
    }

    func loadAvatar(urlString: String, completion: @escaping (UIImage?) -> Void) {
        let urlString = ImgproxyURL.normalizedIconURL(from: urlString)
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            completion(nil)
            return
        }

        if let cached = memoryImage(forKey: urlString) {
            completion(cached)
            return
        }

        inflightLock.lock()
        if inflightCallbacks[urlString] != nil {
            inflightCallbacks[urlString]?.append(completion)
            inflightLock.unlock()
            return
        }
        inflightCallbacks[urlString] = [completion]
        inflightLock.unlock()

        let fetchAndDeliver: (UIImage?) -> Void = { [weak self] image in
            guard let self else { return }
            self.inflightLock.lock()
            let callbacks = self.inflightCallbacks.removeValue(forKey: urlString) ?? []
            self.inflightLock.unlock()
            DispatchQueue.main.async {
                for cb in callbacks { cb(image) }
            }
        }

        if hasDiskCache(forKey: urlString) {
            imageFromDisk(forKey: urlString) { [weak self] diskImage in
                if let diskImage {
                    fetchAndDeliver(diskImage)
                } else {
                    self?.downloadAvatar(url: url, key: urlString, deliver: fetchAndDeliver)
                }
            }
        } else {
            downloadAvatar(url: url, key: urlString, deliver: fetchAndDeliver)
        }
    }

    func memoryOptimizedAvatar(forURL urlString: String, targetPixelSize: Int) -> UIImage? {
        let urlString = ImgproxyURL.normalizedIconURL(from: urlString)
        let variantKey = optimizedAvatarKey(
            urlString: urlString,
            targetPixelSize: targetPixelSize
        )
        return memoryImage(forKey: variantKey)
            ?? memoryImage(forKey: urlString)
    }

    func hasOptimizedAvatarDiskCache(forURL urlString: String, targetPixelSize: Int) -> Bool {
        let urlString = ImgproxyURL.normalizedIconURL(from: urlString)
        let variantKey = optimizedAvatarKey(
            urlString: urlString,
            targetPixelSize: targetPixelSize
        )
        return hasDiskCache(forKey: variantKey) || hasDiskCache(forKey: urlString)
    }

    func loadOptimizedAvatar(
        urlString: String,
        targetPixelSize: Int,
        preview: ((UIImage) -> Void)? = nil,
        completion: @escaping (UIImage?) -> Void
    ) {
        let urlString = ImgproxyURL.normalizedIconURL(from: urlString)
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            completion(nil)
            return
        }

        let pixelSize = max(targetPixelSize, 1)
        let variantKey = optimizedAvatarKey(
            urlString: urlString,
            targetPixelSize: pixelSize
        )
        if let cached = memoryImage(forKey: variantKey)
            ?? memoryImage(forKey: urlString) {
            completion(cached)
            return
        }

        let callback = OptimizedAvatarCallback(preview: preview, completion: completion)
        inflightLock.lock()
        if optimizedAvatarCallbacks[variantKey] != nil {
            optimizedAvatarCallbacks[variantKey]?.append(callback)
            inflightLock.unlock()
            return
        }
        optimizedAvatarCallbacks[variantKey] = [callback]
        inflightLock.unlock()

        avatarDecodeQueue.async { [weak self] in
            guard let self else { return }
            if let data = self.cachedData(forKey: variantKey) {
                self.decodeOptimizedAvatar(
                    data: data,
                    variantKey: variantKey,
                    targetPixelSize: pixelSize,
                    shouldCacheVariant: false
                )
            } else if let data = self.cachedData(forKey: urlString) {
                self.decodeOptimizedAvatar(
                    data: data,
                    variantKey: variantKey,
                    targetPixelSize: pixelSize,
                    shouldCacheVariant: true
                )
            } else {
                self.downloadOptimizedAvatar(
                    url: url,
                    rawKey: urlString,
                    variantKey: variantKey,
                    targetPixelSize: pixelSize,
                    attempt: 0
                )
            }
        }
    }

    private func optimizedAvatarKey(urlString: String, targetPixelSize: Int) -> String {
        "optimized-avatar:\(max(targetPixelSize, 1)):\(ImgproxyURL.normalizedIconURL(from: urlString))"
    }

    private func decodeOptimizedAvatar(
        data: Data,
        variantKey: String,
        targetPixelSize: Int,
        shouldCacheVariant: Bool
    ) {
        avatarDecodeQueue.async { [weak self] in
            guard let self else { return }
            let preview = UIImage.avatarPreviewImage(
                from: data,
                maxPixelSize: targetPixelSize
            )
            if let preview {
                self.emitOptimizedAvatarPreview(preview, variantKey: variantKey)
            }

            let image = UIImage.optimizedAvatarImage(
                from: data,
                maxPixelSize: targetPixelSize
            ) ?? preview
            if let image {
                self.setImage(image, data: nil, forKey: variantKey)
            }
            self.finishOptimizedAvatar(image, variantKey: variantKey)
            if shouldCacheVariant,
               let image,
               let optimizedData = UIImage.optimizedAvatarCacheData(from: image) {
                self.persistData(optimizedData, forKey: variantKey)
            }
        }
    }

    private func emitOptimizedAvatarPreview(_ image: UIImage, variantKey: String) {
        inflightLock.lock()
        let previews = optimizedAvatarCallbacks[variantKey]?.compactMap(\.preview) ?? []
        inflightLock.unlock()
        DispatchQueue.main.async {
            previews.forEach { $0(image) }
        }
    }

    private func finishOptimizedAvatar(_ image: UIImage?, variantKey: String) {
        inflightLock.lock()
        let callbacks = optimizedAvatarCallbacks.removeValue(forKey: variantKey) ?? []
        inflightLock.unlock()
        DispatchQueue.main.async {
            callbacks.forEach { $0.completion(image) }
        }
    }

    private func downloadOptimizedAvatar(
        url: URL,
        rawKey: String,
        variantKey: String,
        targetPixelSize: Int,
        attempt: Int
    ) {
        avatarSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            if Self.isCancellation(error) {
                self.finishOptimizedAvatar(nil, variantKey: variantKey)
                return
            }

            if Self.responseStatusAcceptable(response), let data {
                self.persistData(data, forKey: rawKey)
                self.decodeOptimizedAvatar(
                    data: data,
                    variantKey: variantKey,
                    targetPixelSize: targetPixelSize,
                    shouldCacheVariant: true
                )
                return
            }

            if let sourceURL = ImgproxyURL.sourceURL(fromProxyURL: url.absoluteString) {
                self.downloadOptimizedAvatar(
                    url: sourceURL,
                    rawKey: rawKey,
                    variantKey: variantKey,
                    targetPixelSize: targetPixelSize,
                    attempt: 0
                )
                return
            }

            if let error {
                SentryLogger.captureMediaError(error, extras: [
                    "where": "ImageCache.downloadOptimizedAvatar",
                    "url": url.absoluteString,
                    "attempt": "\(attempt)",
                ])
            }

            if attempt < Self.maxImageDownloadRetries,
               Self.shouldRetryMediaRequest(response: response, error: error) {
                let delay = Self.retryDelay(forAttempt: attempt)
                ioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.downloadOptimizedAvatar(
                        url: url,
                        rawKey: rawKey,
                        variantKey: variantKey,
                        targetPixelSize: targetPixelSize,
                        attempt: attempt + 1
                    )
                }
            } else {
                finishOptimizedAvatar(nil, variantKey: variantKey)
            }
        }.resume()
    }

    private func downloadAvatar(url: URL, key: String, deliver: @escaping (UIImage?) -> Void) {
        startAvatarDownload(url: url, key: key, attempt: 0, deliver: deliver)
    }

    private func startAvatarDownload(
        url: URL,
        key: String,
        attempt: Int,
        deliver: @escaping (UIImage?) -> Void
    ) {
        avatarSession.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { deliver(nil); return }
            if Self.isCancellation(error) { deliver(nil); return }

            if Self.responseStatusAcceptable(response),
               let data,
               let image = UIImage.decompressedImage(from: data) {
                self.setImage(image, data: data, forKey: key)
                deliver(image)
                return
            }

            if let sourceURL = ImgproxyURL.sourceURL(fromProxyURL: url.absoluteString) {
                self.startAvatarDownload(url: sourceURL, key: key, attempt: 0, deliver: deliver)
                return
            }

            if let error {
                SentryLogger.captureMediaError(error, extras: [
                    "where": "ImageCache.downloadAvatar",
                    "url": url.absoluteString,
                    "attempt": "\(attempt)",
                ])
            }

            if attempt < Self.maxImageDownloadRetries {
                let delay = Self.retryDelay(forAttempt: attempt)
                self.ioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { deliver(nil); return }
                    self.startAvatarDownload(
                        url: url, key: key, attempt: attempt + 1, deliver: deliver)
                }
            } else {
                deliver(nil)
            }
        }.resume()
    }
}

private extension String {
    var sha256Hash: String {
        SHA256.hash(data: Data(self.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private func makeTransform(for image: UIImage, resizeMode: ImageResizeMode = .fit) -> (TransformImageArguments) -> DrawingContext? {
    return { arguments -> DrawingContext? in
        let b = arguments.boundingSize
        guard b.width.isFinite, b.height.isFinite, b.width > 0, b.height > 0 else {
            return nil
        }
        let context = DrawingContext(size: b, scale: arguments.scale ?? UIScreen.main.scale, clear: true)
        context?.withFlippedContext { ctx in
            let drawRect = CGRect(origin: .zero, size: arguments.boundingSize)

            let cornerRadius = arguments.corners.topLeft.radius
            if cornerRadius > 0 {
                let path = UIBezierPath(roundedRect: drawRect, cornerRadius: cornerRadius)
                ctx.addPath(path.cgPath)
                ctx.clip()
            }

            let imageSize = image.size
            let fittedSize: CGSize
            let drawOrigin: CGPoint
            switch resizeMode {
            case .fit:
                fittedSize = imageSize.aspectFitted(arguments.boundingSize)
                drawOrigin = CGPoint(
                    x: (arguments.boundingSize.width - fittedSize.width) / 2,
                    y: (arguments.boundingSize.height - fittedSize.height) / 2
                )
            case .fill:
                fittedSize = imageSize.aspectFilled(arguments.boundingSize)
                drawOrigin = CGPoint(
                    x: (arguments.boundingSize.width - fittedSize.width) / 2,
                    y: (arguments.boundingSize.height - fittedSize.height) / 2
                )
            case .fillLeading:
                fittedSize = imageSize.aspectFilled(arguments.boundingSize)
                drawOrigin = CGPoint(
                    x: 0,
                    y: (arguments.boundingSize.height - fittedSize.height) / 2
                )
            }

            if let cgImage = image.cgImage {
                let imageRect = CGRect(origin: drawOrigin, size: fittedSize)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: arguments.boundingSize.height)
                ctx.scaleBy(x: 1.0, y: -1.0)
                UIGraphicsPushContext(ctx)
                image.draw(in: imageRect)
                UIGraphicsPopContext()
                ctx.restoreGState()
            }
        }
        return context
    }
}


func remoteAvatarSignal(proxiedURL: String, originalURL: String, sharesForNotifications: Bool = false, fallbackImage: UIImage? = nil) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        let orig = originalURL
        let proxy = ImgproxyURL.normalizedIconURL(from: proxiedURL)

        guard !proxy.isEmpty || !orig.isEmpty else {
            subscriber.putCompletion()
            return EmptyDisposable
        }

        func buildTransform(for image: UIImage) -> (TransformImageArguments) -> DrawingContext? {
            return makeTransform(for: image, resizeMode: .fill)
        }

        let cache = ImageCache.shared
        if sharesForNotifications {
            cache.shareAvatarForNotifications(avatarURL: orig, cacheKeys: [proxy, orig])
        }
        for rawKey in (proxy.isEmpty ? [orig] : [proxy]) where !rawKey.isEmpty {
            let key = ImgproxyURL.normalizedIconURL(from: rawKey)
            if let cached = cache.memoryImage(forKey: key) {
                subscriber.putNext(buildTransform(for: cached))
                subscriber.putCompletion()
                return EmptyDisposable
            }
        }

        let cancelled = Atomic<Bool>(value: false)

        func emit(_ image: UIImage) {
            guard !cancelled.with({ $0 }) else { return }
            subscriber.putNext(buildTransform(for: image))
            subscriber.putCompletion()
        }

        func finishEmpty() {
            guard !cancelled.with({ $0 }) else { return }
            subscriber.putCompletion()
        }

        cache.loadAvatar(urlString: proxy.isEmpty ? orig : proxy) { image in
            guard !cancelled.with({ $0 }) else { return }
            if let image = image ?? fallbackImage {
                emit(image)
            } else {
                finishEmpty()
            }
        }

        return ActionDisposable {
            let _ = cancelled.modify { _ in true }
        }
    }
}

private func emptyDrawingTransform() -> (TransformImageArguments) -> DrawingContext? {
    return { _ in nil }
}

func remoteImageSignal(url: String, resizeMode: ImageResizeMode = .fit) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        guard !url.isEmpty else {
            subscriber.putNext(emptyDrawingTransform())
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cache = ImageCache.shared
        if let cached = cache.memoryImage(forKey: url) {
            subscriber.putNext(makeTransform(for: cached, resizeMode: resizeMode))
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cancelled = Atomic<Bool>(value: false)

        func deliver(_ image: UIImage?) {
            guard !cancelled.with({ $0 }) else { return }
            if let image {
                subscriber.putNext(makeTransform(for: image, resizeMode: resizeMode))
            } else {
                subscriber.putNext(emptyDrawingTransform())
            }
            subscriber.putCompletion()
        }

        cache.loadImage(urlString: url, completion: deliver)

        return ActionDisposable {
            let _ = cancelled.modify { _ in true }
        }
    }
}

private func loadAttachmentImage(
    proxyURL: String,
    originalURL: String,
    isCancelled: @escaping () -> Bool,
    completion: @escaping (UIImage?) -> Void
) {
    let cache = ImageCache.shared
    let firstURL = proxyURL.isEmpty ? originalURL : proxyURL
    cache.loadImage(urlString: firstURL) { image in
        guard !isCancelled() else { return }
        if image == nil, !originalURL.isEmpty, originalURL != firstURL {
            cache.loadImage(urlString: originalURL, completion: completion)
        } else {
            completion(image)
        }
    }
}

func remoteAttachmentImageSignal(proxyURL: String, originalURL: String, resizeMode: ImageResizeMode = .fit) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    Signal { subscriber in
        guard !proxyURL.isEmpty else {
            subscriber.putNext(emptyDrawingTransform())
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let cancelled = Atomic<Bool>(value: false)
        loadAttachmentImage(proxyURL: proxyURL, originalURL: originalURL, isCancelled: { cancelled.with { $0 } }) { image in
            guard !cancelled.with({ $0 }) else { return }
            subscriber.putNext(image.map { makeTransform(for: $0, resizeMode: resizeMode) } ?? emptyDrawingTransform())
            subscriber.putCompletion()
        }
        return ActionDisposable { _ = cancelled.swap(true) }
    }
}

func staticImageSignal(image: UIImage, resizeMode: ImageResizeMode = .fill) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        subscriber.putNext(makeTransform(for: image, resizeMode: resizeMode))
        subscriber.putCompletion()
        return EmptyDisposable
    }
}

func remoteImageUISignal(url: String) -> Signal<UIImage?, NoError> {
    return Signal { subscriber in
        guard let imageURL = URL(string: url), !url.isEmpty else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cache = ImageCache.shared

        if let cached = cache.memoryImage(forKey: url) {
            subscriber.putNext(cached)
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cancelled = Atomic<Bool>(value: false)
        var dataTask: URLSessionDataTask?

        cache.imageFromDisk(forKey: url) { diskImage in
            guard !cancelled.with({ $0 }) else { return }
            if let diskImage {
                subscriber.putNext(diskImage)
                subscriber.putCompletion()
                return
            }
            let task = URLSession.shared.dataTask(with: imageURL) { data, _, error in
                guard !cancelled.with({ $0 }) else { return }
                if let error {
                    SentryLogger.captureMediaError(error, extras: [
                        "where": "rawImageSignal",
                        "url": url,
                    ])
                }
                let image = data.flatMap { UIImage.decompressedImage(from: $0) }
                if let image, let data {
                    cache.setImage(image, data: data, forKey: url)
                }
                subscriber.putNext(image)
                subscriber.putCompletion()
            }
            dataTask = task
            task.resume()
        }

        return ActionDisposable {
            let _ = cancelled.modify { _ in true }
            dataTask?.cancel()
        }
    }
}

private func videoThumbnailCacheKey(url: String, pixelSize: Int) -> String {
    pixelSize == 600 ? "video_thumb_\(url)" : "video_thumb_\(pixelSize)_\(url)"
}

private func isUsableVideoThumbnail(_ image: UIImage) -> Bool {
    // Older versions cached a transparent 1×1 image for unsupported videos.
    guard let frame = image.cgImage else { return false }
    return frame.width > 1 || frame.height > 1
}

func cachedWebMThumbnail(url: URL, maxPixelSize: Int = 600) -> UIImage? {
    let key = videoThumbnailCacheKey(url: url.absoluteString, pixelSize: max(1, maxPixelSize))
    return ImageCache.shared.memoryImage(forKey: key).flatMap { isUsableVideoThumbnail($0) ? $0 : nil }
}

func webMThumbnailSignal(
    url: URL,
    posterProxyURL: String = "",
    posterURL: String = "",
    resizeMode: ImageResizeMode,
    maxPixelSize: Int = 600,
    allowRemoteGeneration: Bool = true
) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    Signal { subscriber in
        let pixelSize = max(1, maxPixelSize)
        let cacheKey = videoThumbnailCacheKey(url: url.absoluteString, pixelSize: pixelSize)
        let cache = ImageCache.shared
        let cancelled = Atomic<Bool>(value: false)
        let extraction = MetaDisposable()

        func finish(_ image: UIImage?) {
            guard !cancelled.with({ $0 }) else { return }
            subscriber.putNext(image.map { makeTransform(for: $0, resizeMode: resizeMode) } ?? emptyDrawingTransform())
            subscriber.putCompletion()
        }

        func generate() {
            guard !cancelled.with({ $0 }) else { return }
            guard allowRemoteGeneration || url.isFileURL else { finish(nil); return }
            extraction.set(WebMThumbnailLoader.shared.load(url: url, cacheKey: cacheKey, pixelSize: pixelSize, completion: finish))
        }

        if let image = cache.memoryImage(forKey: posterProxyURL) ?? cache.memoryImage(forKey: posterURL)
            ?? cachedWebMThumbnail(url: url, maxPixelSize: pixelSize) {
            finish(image)
            return EmptyDisposable
        }

        cache.imageFromDisk(forKey: cacheKey) { image in
            guard !cancelled.with({ $0 }) else { return }
            if let image, isUsableVideoThumbnail(image) {
                finish(image)
            } else if !posterProxyURL.isEmpty || !posterURL.isEmpty {
                loadAttachmentImage(proxyURL: posterProxyURL, originalURL: posterURL, isCancelled: { cancelled.with { $0 } }) { image in
                    if let image { finish(image) } else { generate() }
                }
            } else {
                generate()
            }
        }
        return ActionDisposable {
            _ = cancelled.swap(true)
            extraction.dispose()
        }
    }
}

private final class WebMThumbnailLoader: NSObject, VLCMediaThumbnailerDelegate {
    static let shared = WebMThumbnailLoader()

    private final class Request {
        let url: URL
        let cacheKey: String
        let pixelSize: Int
        var callbacks: [UUID: (UIImage?) -> Void] = [:]
        var thumbnailer: VLCMediaThumbnailer?

        init(url: URL, cacheKey: String, pixelSize: Int) {
            self.url = url
            self.cacheKey = cacheKey
            self.pixelSize = pixelSize
        }
    }

    // VLCKit's thumbnailer uses run-loop timers and delivers frames on main.
    // Bound concurrent VLC work so a mosaic or a fast scroll cannot start a decoder per cell.
    private let maxConcurrentRequests = 2
    private var pending: [Request] = []
    private var active: [String: Request] = [:]
    private let retryAfter: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 300
        return cache
    }()

    func load(url: URL, cacheKey: String, pixelSize: Int, completion: @escaping (UIImage?) -> Void) -> Disposable {
        let token = UUID()
        DispatchQueue.main.async {
            if let image = cachedWebMThumbnail(url: url, maxPixelSize: pixelSize) {
                completion(image)
                return
            }
            if let retryAt = self.retryAfter.object(forKey: cacheKey as NSString),
               retryAt.doubleValue > ProcessInfo.processInfo.systemUptime {
                completion(nil)
                return
            }
            if let request = self.active[cacheKey] ?? self.pending.first(where: { $0.cacheKey == cacheKey }) {
                request.callbacks[token] = completion
                return
            }
            let request = Request(url: url, cacheKey: cacheKey, pixelSize: pixelSize)
            request.callbacks[token] = completion
            self.pending.append(request)
            // Give a disposed cell a chance to remove its queued request before VLC starts.
            DispatchQueue.main.async { self.startNextRequests() }
        }
        return ActionDisposable {
            DispatchQueue.main.async {
                if let request = self.active[cacheKey] {
                    request.callbacks.removeValue(forKey: token)
                } else if let index = self.pending.firstIndex(where: { $0.cacheKey == cacheKey }) {
                    let request = self.pending[index]
                    request.callbacks.removeValue(forKey: token)
                    if request.callbacks.isEmpty { self.pending.remove(at: index) }
                }
            }
        }
    }

    private func startNextRequests() {
        while active.count < maxConcurrentRequests, !pending.isEmpty {
            let request = pending.removeFirst()
            active[request.cacheKey] = request
            resolveURL(for: request)
        }
    }

    private func resolveURL(for request: Request) {
        DispatchQueue.global(qos: .utility).async {
            if let file = VLCVideoPlayerNode.cachedFile(for: request.url) {
                DispatchQueue.main.async { self.startThumbnailer(request, url: file) }
                return
            }
            if let ready = CDNSigner.shared.readyRequestURL(for: request.url) {
                DispatchQueue.main.async { self.startThumbnailer(request, url: ready.url) }
            } else {
                CDNSigner.shared.requestURL(for: request.url) { signed in
                    DispatchQueue.main.async { self.startThumbnailer(request, url: signed.url) }
                }
            }
        }
    }

    private func startThumbnailer(_ request: Request, url: URL) {
        guard !request.callbacks.isEmpty else {
            active.removeValue(forKey: request.cacheKey)
            startNextRequests()
            return
        }
        let media = VLCMedia(url: url)
        let thumbnailer = VLCMediaThumbnailer(media: media, andDelegate: self)
        thumbnailer.thumbnailWidth = CGFloat(request.pixelSize)
        thumbnailer.thumbnailHeight = CGFloat(request.pixelSize)
        thumbnailer.snapshotPosition = 0.01
        request.thumbnailer = thumbnailer
        thumbnailer.fetchThumbnail()
    }

    func mediaThumbnailer(_ thumbnailer: VLCMediaThumbnailer, didFinishThumbnail thumbnail: CGImage) {
        complete(thumbnailer, frame: thumbnail)
    }

    func mediaThumbnailerDidTimeOut(_ thumbnailer: VLCMediaThumbnailer) {
        complete(thumbnailer, frame: nil)
    }

    private func complete(_ thumbnailer: VLCMediaThumbnailer, frame: CGImage?) {
        DispatchQueue.main.async {
            guard let request = self.active.values.first(where: { $0.thumbnailer === thumbnailer }) else { return }
            request.thumbnailer = nil
            guard let frame else {
                self.retryAfter.setObject(NSNumber(value: ProcessInfo.processInfo.systemUptime + 30), forKey: request.cacheKey as NSString)
                self.finish(request, image: nil)
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let image = self.thumbnailImage(from: frame, pixelSize: request.pixelSize)
                ImageCache.shared.setImage(image, data: image.jpegData(compressionQuality: 0.7), forKey: request.cacheKey)
                DispatchQueue.main.async { self.finish(request, image: image) }
            }
        }
    }

    private func thumbnailImage(from frame: CGImage, pixelSize: Int) -> UIImage {
        let image = UIImage(cgImage: frame)
        let longestEdge = max(frame.width, frame.height)
        guard longestEdge > pixelSize else { return image }
        let scale = CGFloat(pixelSize) / CGFloat(longestEdge)
        let size = CGSize(width: max(1, floor(CGFloat(frame.width) * scale)),
                          height: max(1, floor(CGFloat(frame.height) * scale)))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func finish(_ request: Request, image: UIImage?) {
        active.removeValue(forKey: request.cacheKey)
        for callback in request.callbacks.values { callback(image) }
        startNextRequests()
    }
}

func videoThumbnailSignal(url: String, resizeMode: ImageResizeMode = .fill, maxPixelSize: Int = 600, allowRemoteGeneration: Bool = true) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        guard let videoURL = URL(string: url), !url.isEmpty else {
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let pixelSize = max(1, maxPixelSize)
        if videoURL.pathExtension.lowercased() == "webm" {
            return webMThumbnailSignal(url: videoURL, resizeMode: resizeMode, maxPixelSize: pixelSize, allowRemoteGeneration: allowRemoteGeneration)
                .start(next: subscriber.putNext, completed: subscriber.putCompletion)
        }
        let cacheKey = videoThumbnailCacheKey(url: url, pixelSize: pixelSize)
        let cache = ImageCache.shared
        if let cached = cache.image(forKey: cacheKey) {
            subscriber.putNext(makeTransform(for: cached, resizeMode: resizeMode))
            subscriber.putCompletion()
            return EmptyDisposable
        }

        guard allowRemoteGeneration || videoURL.isFileURL else {
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let fileExtension = videoURL.pathExtension.lowercased()
        let isUnsupportedByAV = ["ogv", "ogg", "mkv", "avi", "flv", "wmv", "3gp", "3g2", "mpg", "mpeg", "ts", "vob"].contains(fileExtension)
        
        if isUnsupportedByAV {
            let transparentImage = createTransparentImage()
            cache.setImage(transparentImage, data: nil, forKey: cacheKey)
            subscriber.putNext(makeTransform(for: transparentImage, resizeMode: resizeMode))
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cancelled = Atomic<Bool>(value: false)
        let activeGenerator = Atomic<AVAssetImageGenerator?>(value: nil)

        func finishWithoutFrame() {
            let transparentImage = createTransparentImage()
            cache.setImage(transparentImage, data: nil, forKey: cacheKey)
            subscriber.putNext(makeTransform(for: transparentImage, resizeMode: resizeMode))
            subscriber.putCompletion()
        }

        func generate(from assetURL: URL, previewFile: URL? = nil) {
            guard !cancelled.with({ $0 }) else {
                if let previewFile { try? FileManager.default.removeItem(at: previewFile) }
                return
            }
            let asset = AVURLAsset(url: assetURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: false
            ])
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: CGFloat(pixelSize), height: CGFloat(pixelSize))
            let _ = activeGenerator.swap(generator)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            let timeValue = NSValue(time: time)

            generator.generateCGImagesAsynchronously(forTimes: [timeValue]) { _, cgImage, _, _, error in
                if let previewFile { try? FileManager.default.removeItem(at: previewFile) }
                if let cgImage {
                    let image = UIImage(cgImage: cgImage)
                    let jpegData = image.jpegData(compressionQuality: 0.7)
                    cache.setImage(image, data: jpegData, forKey: cacheKey)
                    subscriber.putNext(makeTransform(for: image, resizeMode: resizeMode))
                    subscriber.putCompletion()
                } else if previewFile == nil, !videoURL.isFileURL {
                    guard !cancelled.with({ $0 }) else { return }
                    FileIngestHLSCopy.makePreviewFile(
                        attachmentURL: url,
                        shouldContinue: { !cancelled.with { $0 } }
                    ) { preview in
                        if let preview {
                            generate(from: preview, previewFile: preview)
                        } else if !cancelled.with({ $0 }) {
                            finishWithoutFrame()
                        }
                    }
                } else {
                    finishWithoutFrame()
                }
            }
        }

        if let request = CDNSigner.shared.readyRequestURL(for: videoURL) {
            generate(from: request.url)
        } else {
            CDNSigner.shared.requestURL(for: videoURL) { request in
                generate(from: request.url)
            }
        }

        return ActionDisposable {
            let _ = cancelled.modify { _ in true }
            activeGenerator.with { $0 }?.cancelAllCGImageGeneration()
        }
    }
}

private func createTransparentImage() -> UIImage {
    let size = CGSize(width: 1, height: 1)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { context in
        UIColor.clear.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}

func prefetchImages(urls: [String]) {
    let cache = ImageCache.shared
    for url in urls {
        guard cache.memoryImage(forKey: url) == nil else { continue }
        guard !cache.hasDiskCache(forKey: url) else {
            cache.imageFromDisk(forKey: url) { _ in }
            continue
        }
        cache.loadImage(urlString: url) { _ in }
    }
}

extension ASNetworkImageNode {
    func fallBackToImgproxySource() -> Bool {
        guard let failed = url,
              let source = ImgproxyURL.sourceURL(fromProxyURL: failed.absoluteString) else { return false }
        url = source
        return true
    }
}

final class ProfileCoverImageView: UIImageView {
    private var boundSource = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func setCover(_ rawURL: String?) {
        let source = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard source != boundSource else { return }
        boundSource = source
        guard !source.isEmpty else {
            image = nil
            return
        }
        let url = ImgproxyURL.profileCoverURL(from: source)
        if let cached = ImageCache.shared.memoryImage(forKey: url) {
            image = cached
            return
        }
        image = nil
        _ = ImageCache.shared.loadImage(urlString: url) { [weak self] loaded in
            guard let self, self.boundSource == source else { return }
            self.image = loaded
        }
    }

    func showPreview(_ preview: UIImage, for rawURL: String) {
        boundSource = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        image = preview
        ImageCache.shared.setImage(preview, data: nil, forKey: ImgproxyURL.profileCoverURL(from: boundSource))
    }
}
