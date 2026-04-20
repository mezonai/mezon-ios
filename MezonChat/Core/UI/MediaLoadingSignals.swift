import Foundation
import UIKit
import AVFoundation

enum ImageResizeMode {
    case fit
    case fill
    case fillLeading
}

final class ImageCache {

    static let shared = ImageCache()

    private let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        c.totalCostLimit = 400 * 1024 * 1024
        return c
    }()

    private let diskCacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("mezon_image_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let ioQueue = DispatchQueue(label: "mezon.imagecache.io", qos: .utility)

    private let avatarSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private var inflightCallbacks: [String: [(UIImage?) -> Void]] = [:]
    private let inflightLock = NSLock()
    func memoryImage(forKey key: String) -> UIImage? {
        return memoryCache.object(forKey: key as NSString)
    }

    func image(forKey key: String) -> UIImage? {
        let nsKey = key as NSString

        if let cached = memoryCache.object(forKey: nsKey) {
            return cached
        }

        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage.decompressedImage(from: data) else { return nil }

        memoryCache.setObject(image, forKey: nsKey, cost: data.count)
        return image
    }

    func imageFromDisk(forKey key: String, completion: @escaping (UIImage?) -> Void) {
        ioQueue.async { [weak self] in
            guard let self else { DispatchQueue.main.async { completion(nil) }; return }
            let fileURL = self.diskCacheURL.appendingPathComponent(key.sha256Hash)
            guard let data = try? Data(contentsOf: fileURL),
                  let image = UIImage.decompressedImage(from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
            DispatchQueue.main.async { completion(image) }
        }
    }

    func hasDiskCache(forKey key: String) -> Bool {
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    func setImage(_ image: UIImage, data: Data?, forKey key: String) {
        let nsKey = key as NSString
        let cost = data?.count ?? 0
        memoryCache.setObject(image, forKey: nsKey, cost: cost)

        if let data {
            let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
            ioQueue.async {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    func cachedData(forKey key: String) -> Data? {
        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        return try? Data(contentsOf: fileURL)
    }

    func clearDiskCache() {
        ioQueue.async { [diskCacheURL] in
            try? FileManager.default.removeItem(at: diskCacheURL)
            try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
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

        if let cached = memoryCache.object(forKey: urlString as NSString) {
            completion(cached)
            return nil
        }

        if hasDiskCache(forKey: urlString) {
            imageFromDisk(forKey: urlString) { [weak self] diskImage in
                if let diskImage {
                    completion(diskImage)
                } else {
                    self?.downloadImage(url: url, key: urlString, completion: completion)
                }
            }
            return nil
        }

        return downloadImage(url: url, key: urlString, completion: completion)
    }

    @discardableResult
    private func downloadImage(
        url: URL,
        key: String,
        completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let image = UIImage.decompressedImage(from: data)
            if let image {
                self?.setImage(image, data: data, forKey: key)
            }
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }

    func cachedImage(forURL urlString: String) -> UIImage? {
        return image(forKey: urlString)
    }

    func loadAvatar(urlString: String, completion: @escaping (UIImage?) -> Void) {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            completion(nil)
            return
        }

        if let cached = memoryCache.object(forKey: urlString as NSString) {
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

    private func downloadAvatar(url: URL, key: String, deliver: @escaping (UIImage?) -> Void) {
        avatarSession.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { deliver(nil); return }
            let image = UIImage.decompressedImage(from: data)
            if let image {
                self?.setImage(image, data: data, forKey: key)
            }
            deliver(image)
        }.resume()
    }
}

private extension String {
    var sha256Hash: String {
        var hash: UInt64 = 5381
        for byte in self.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
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

func remoteAvatarSignal(url: String) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        guard !url.isEmpty else {
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cache = ImageCache.shared
        if let cached = cache.memoryImage(forKey: url) {
            subscriber.putNext(makeTransform(for: cached, resizeMode: .fill))
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cancelled = Atomic<Bool>(value: false)
        cache.loadAvatar(urlString: url) { image in
            guard !cancelled.with({ $0 }) else { return }
            if let image {
                subscriber.putNext(makeTransform(for: image, resizeMode: .fill))
            }
            subscriber.putCompletion()
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
        guard let imageURL = URL(string: url), !url.isEmpty else {
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
        var dataTask: URLSessionDataTask?

        cache.imageFromDisk(forKey: url) { diskImage in
            guard !cancelled.with({ $0 }) else { return }
            if let diskImage {
                subscriber.putNext(makeTransform(for: diskImage, resizeMode: resizeMode))
                subscriber.putCompletion()
                return
            }
            let task = URLSession.shared.dataTask(with: imageURL) { data, _, _ in
                guard !cancelled.with({ $0 }) else { return }
                guard let data else {
                    subscriber.putNext(emptyDrawingTransform())
                    subscriber.putCompletion()
                    return
                }
                let image = UIImage.decompressedImage(from: data)
                if let image {
                    cache.setImage(image, data: data, forKey: url)
                    subscriber.putNext(makeTransform(for: image, resizeMode: resizeMode))
                } else {
                    subscriber.putNext(emptyDrawingTransform())
                }
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

func remoteAttachmentImageSignal(proxyURL: String, originalURL: String, resizeMode: ImageResizeMode = .fit) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    Signal { subscriber in
        let cancelled = Atomic<Bool>(value: false)
        var dataTask: URLSessionDataTask?

        func finishEmpty() {
            guard !cancelled.with({ $0 }) else { return }
            subscriber.putNext(emptyDrawingTransform())
            subscriber.putCompletion()
        }

        func emitImage(_ image: UIImage) {
            guard !cancelled.with({ $0 }) else { return }
            subscriber.putNext(makeTransform(for: image, resizeMode: resizeMode))
            subscriber.putCompletion()
        }

        func loadFromNetwork(_ urlString: String, onFailure: @escaping () -> Void) {
            guard let imageURL = URL(string: urlString), !urlString.isEmpty else {
                onFailure()
                return
            }
            let task = URLSession.shared.dataTask(with: imageURL) { data, _, _ in
                guard !cancelled.with({ $0 }) else { return }
                guard let data, let image = UIImage.decompressedImage(from: data) else {
                    onFailure()
                    return
                }
                ImageCache.shared.setImage(image, data: data, forKey: urlString)
                emitImage(image)
            }
            dataTask = task
            task.resume()
        }

        func tryUrl(_ urlString: String, thenFallback: @escaping () -> Void) {
            guard !urlString.isEmpty else {
                thenFallback()
                return
            }
            let cache = ImageCache.shared
            if let cached = cache.memoryImage(forKey: urlString) {
                emitImage(cached)
                return
            }
            cache.imageFromDisk(forKey: urlString) { diskImage in
                guard !cancelled.with({ $0 }) else { return }
                if let diskImage {
                    emitImage(diskImage)
                    return
                }
                loadFromNetwork(urlString, onFailure: thenFallback)
            }
        }

        guard !proxyURL.isEmpty else {
            finishEmpty()
            return EmptyDisposable
        }

        let fallback: () -> Void = {
            guard !cancelled.with({ $0 }) else { return }
            if !originalURL.isEmpty, originalURL != proxyURL {
                tryUrl(originalURL, thenFallback: finishEmpty)
            } else {
                finishEmpty()
            }
        }

        tryUrl(proxyURL, thenFallback: fallback)

        return ActionDisposable {
            let _ = cancelled.modify { _ in true }
            dataTask?.cancel()
        }
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
            let task = URLSession.shared.dataTask(with: imageURL) { data, _, _ in
                guard !cancelled.with({ $0 }) else { return }
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

func videoThumbnailSignal(url: String, resizeMode: ImageResizeMode = .fill) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        guard let videoURL = URL(string: url), !url.isEmpty else {
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cacheKey = "video_thumb_\(url)"
        let cache = ImageCache.shared
        if let cached = cache.image(forKey: cacheKey) {
            subscriber.putNext(makeTransform(for: cached, resizeMode: resizeMode))
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let asset = AVURLAsset(url: videoURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false
        ])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let timeValue = NSValue(time: time)

        generator.generateCGImagesAsynchronously(forTimes: [timeValue]) { _, cgImage, _, _, _ in
            if let cgImage {
                let image = UIImage(cgImage: cgImage)
                let jpegData = image.jpegData(compressionQuality: 0.7)
                cache.setImage(image, data: jpegData, forKey: cacheKey)
                subscriber.putNext(makeTransform(for: image, resizeMode: resizeMode))
            }
            subscriber.putCompletion()
        }

        return ActionDisposable {
            generator.cancelAllCGImageGeneration()
        }
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
        guard let imageURL = URL(string: url) else { continue }
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            guard let data, let image = UIImage.decompressedImage(from: data) else { return }
            cache.setImage(image, data: data, forKey: url)
        }.resume()
    }
}
