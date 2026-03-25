import Foundation
import UIKit
import AVFoundation

enum ImageResizeMode {
    case fit   // aspect-fit (contain) — show full image
    case fill  // aspect-fill (cover) — fill bounding box, crop overflow
}

final class ImageCache {

    static let shared = ImageCache()

    private let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        c.totalCostLimit = 400 * 1024 * 1024 // 400MB
        return c
    }()

    private let diskCacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("mezon_image_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let ioQueue = DispatchQueue(label: "mezon.imagecache.io", qos: .utility)

    func image(forKey key: String) -> UIImage? {
        let nsKey = key as NSString

        if let cached = memoryCache.object(forKey: nsKey) {
            return cached
        }

        let fileURL = diskCacheURL.appendingPathComponent(key.sha256Hash)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage.decodeImage(from: data) else { return nil }

        memoryCache.setObject(image, forKey: nsKey, cost: data.count)
        return image
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

        if let cached = image(forKey: urlString) {
            completion(cached)
            return nil
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage.decodeImage(from: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self?.setImage(image, data: data, forKey: urlString)
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }

    func cachedImage(forURL urlString: String) -> UIImage? {
        return image(forKey: urlString)
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
        let context = DrawingContext(size: arguments.boundingSize, scale: arguments.scale ?? UIScreen.main.scale, clear: true)
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
            switch resizeMode {
            case .fit:
                fittedSize = imageSize.aspectFitted(arguments.boundingSize)
            case .fill:
                fittedSize = imageSize.aspectFilled(arguments.boundingSize)
            }
            let drawOrigin = CGPoint(
                x: (arguments.boundingSize.width - fittedSize.width) / 2,
                y: (arguments.boundingSize.height - fittedSize.height) / 2
            )

            if let cgImage = image.cgImage {
                ctx.draw(cgImage, in: CGRect(origin: drawOrigin, size: fittedSize))
            }
        }
        return context
    }
}

func remoteImageSignal(url: String, resizeMode: ImageResizeMode = .fit) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    return Signal { subscriber in
        guard let imageURL = URL(string: url), !url.isEmpty else {
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let cache = ImageCache.shared
        if let cached = cache.image(forKey: url) {
            subscriber.putNext(makeTransform(for: cached, resizeMode: resizeMode))
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let task = URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            guard let data, let image = UIImage.decodeImage(from: data) else {
                subscriber.putCompletion()
                return
            }

            // Store in both caches
            cache.setImage(image, data: data, forKey: url)

            subscriber.putNext(makeTransform(for: image, resizeMode: resizeMode))
            subscriber.putCompletion()
        }
        task.resume()

        return ActionDisposable { task.cancel() }
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
        if let cached = cache.image(forKey: url) {
            subscriber.putNext(cached)
            subscriber.putCompletion()
            return EmptyDisposable
        }

        let task = URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            let image = data.flatMap { UIImage.decodeImage(from: $0) }
            if let image, let data {
                cache.setImage(image, data: data, forKey: url)
            }
            subscriber.putNext(image)
            subscriber.putCompletion()
        }
        task.resume()
        return ActionDisposable { task.cancel() }
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
    for url in urls {
        guard ImageCache.shared.image(forKey: url) == nil else { continue }
        guard let imageURL = URL(string: url) else { continue }
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            guard let data, let image = UIImage.decodeImage(from: data) else { return }
            ImageCache.shared.setImage(image, data: data, forKey: url)
        }.resume()
    }
}
