import Foundation
import UIKit
import ImageIO
import QuartzCore

enum ReactionEmojiImageLoader {

    @discardableResult
    static func load(from url: URL, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        let key = url.absoluteString
        if let cached = ImageCache.shared.image(forKey: key) {
            DispatchQueue.main.async { completion(cached) }
            return nil
        }
        if ImageCache.shared.hasDiskCache(forKey: key) {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let diskData = ImageCache.shared.cachedData(forKey: key) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let image = UIImage.animatedImage(from: diskData) ?? UIImage.decodeImage(from: diskData)
                if let image {
                    ImageCache.shared.setImage(image, data: nil, forKey: key)
                }
                DispatchQueue.main.async { completion(image) }
            }
            return nil
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                SentryLogger.captureMediaError(error, extras: [
                    "where": "ReactionEmojiImageLoader.load",
                    "url": url.absoluteString,
                ])
            }
            guard let data,
                  let image = UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data)
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            ImageCache.shared.setImage(image, data: data, forKey: key)
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }

    @discardableResult
    static func load(emojiId: String, imgproxyFitSide: Int, completion: @escaping (UIImage?) -> Void) -> URLSessionDataTask? {
        guard let url = MezonConfig.emojiResourceURL(emojiId: emojiId, imgproxyFitSide: imgproxyFitSide) else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        return load(from: url, completion: completion)
    }

    @discardableResult
    static func loadEmojiBestEffort(
        emojiId: String, imgproxyFitSide: Int, completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask? {
        guard let proxied = MezonConfig.emojiResourceURL(emojiId: emojiId, imgproxyFitSide: imgproxyFitSide)
        else {
            if let direct = MezonConfig.emojiImageURL(emojiId: emojiId) {
                return load(from: direct, completion: completion)
            }
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        return load(from: proxied) { image in
            if let image {
                completion(image)
                return
            }
            guard let direct = MezonConfig.emojiImageURL(emojiId: emojiId),
                direct.absoluteString != proxied.absoluteString
            else {
                completion(nil)
                return
            }
            _ = load(from: direct, completion: completion)
        }
    }


    @discardableResult
    static func loadDataBestEffort(
        emojiId: String, imgproxyFitSide: Int, completion: @escaping (Data?) -> Void
    ) -> URLSessionDataTask? {
        guard let proxied = MezonConfig.emojiResourceURL(emojiId: emojiId, imgproxyFitSide: imgproxyFitSide)
        else {
            if let direct = MezonConfig.emojiImageURL(emojiId: emojiId) {
                return loadData(from: direct, completion: completion)
            }
            DispatchQueue.main.async { completion(nil) }
            return nil
        }
        return loadData(from: proxied) { data in
            if data != nil {
                completion(data)
                return
            }
            guard let direct = MezonConfig.emojiImageURL(emojiId: emojiId),
                direct.absoluteString != proxied.absoluteString
            else {
                completion(nil)
                return
            }
            _ = loadData(from: direct, completion: completion)
        }
    }

    @discardableResult
    static func loadAnimatedData(from url: URL, completion: @escaping (Data?) -> Void) -> URLSessionDataTask? {
        loadData(from: url, completion: completion)
    }

    @discardableResult
    static func loadAnimatedDataBestEffort(
        emojiId: String, imgproxyFitSide: Int, completion: @escaping (Data?) -> Void
    ) -> URLSessionDataTask? {
        guard let direct = MezonConfig.emojiImageURL(emojiId: emojiId) else {
            return loadDataBestEffort(emojiId: emojiId, imgproxyFitSide: imgproxyFitSide, completion: completion)
        }
        return loadData(from: direct) { data in
            if data != nil {
                completion(data)
                return
            }
            guard let proxied = MezonConfig.emojiResourceURL(emojiId: emojiId, imgproxyFitSide: imgproxyFitSide),
                proxied.absoluteString != direct.absoluteString
            else {
                completion(nil)
                return
            }
            _ = loadData(from: proxied, completion: completion)
        }
    }

    @discardableResult
    private static func loadData(from url: URL, completion: @escaping (Data?) -> Void) -> URLSessionDataTask? {
        let key = url.absoluteString
        if let cached = EmojiDataCache.shared.data(forKey: key) {
            if isValidImageData(cached) {
                DispatchQueue.main.async { completion(cached) }
            } else {
                EmojiDataCache.shared.remove(forKey: key)
                DispatchQueue.main.async { completion(nil) }
            }
            return nil
        }
        if ImageCache.shared.hasDiskCache(forKey: key) {
            DispatchQueue.global(qos: .userInitiated).async {
                let data = ImageCache.shared.cachedData(forKey: key)
                if let data, isValidImageData(data) {
                    EmojiDataCache.shared.setData(data, forKey: key)
                    DispatchQueue.main.async { completion(data) }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            }
            return nil
        }
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error {
                SentryLogger.captureMediaError(error, extras: [
                    "where": "ReactionEmojiImageLoader.loadData",
                    "url": url.absoluteString,
                ])
            }
            guard let data, isValidImageData(data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            EmojiDataCache.shared.setData(data, forKey: key)
            ImageCache.shared.persistData(data, forKey: key)
            DispatchQueue.main.async { completion(data) }
        }
        task.resume()
        return task
    }

    private static func isValidImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }
}


final class EmojiDataCache {

    static let shared = EmojiDataCache()

    private let cache: NSCache<NSString, NSData> = {
        let c = NSCache<NSString, NSData>()
        c.countLimit = 512
        c.totalCostLimit = 32 * 1024 * 1024
        return c
    }()

    func data(forKey key: String) -> Data? {
        cache.object(forKey: key as NSString) as Data?
    }

    func setData(_ data: Data, forKey key: String) {
        cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
    }

    func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
}


final class AnimatedEmojiImageView: UIView {

    private let decodeQueue = DispatchQueue(label: "mezon.emoji.framedecode", qos: .userInitiated)

    private var imageSource: CGImageSource?
    private var frameDelays: [CFTimeInterval] = []
    private var totalDuration: CFTimeInterval = 0
    private var startTime: CFTimeInterval = 0
    private var lastFrameIndex: Int = -1
    private var requestedFrameIndex: Int = -1
    private var pixelTargetMaxSide: CGFloat = 0
    private var isStatic: Bool = true
    private var pendingDecodeGeneration: Int = 0
    private var currentDataKey: String?
    private var lastRenderedContents: CGImage?

    var contentsGravity: CALayerContentsGravity = .resizeAspect {
        didSet { layer.contentsGravity = contentsGravity }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.contentsGravity = contentsGravity
        layer.minificationFilter = .trilinear
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        AnimatedEmojiTicker.shared.unregister(self)
    }

    func reset() {
        pendingDecodeGeneration &+= 1
        AnimatedEmojiTicker.shared.unregister(self)
        imageSource = nil
        frameDelays = []
        totalDuration = 0
        lastFrameIndex = -1
        isStatic = true
        currentDataKey = nil
        lastRenderedContents = nil
        layer.contents = nil
    }

    func reapplyContentsIfCleared() {
        guard layer.contents == nil, let lastRenderedContents else { return }
        layer.contents = lastRenderedContents
        if !isStatic, imageSource != nil, window != nil {
            requestedFrameIndex = -1
            AnimatedEmojiTicker.shared.register(self)
        }
    }


    func setImage(_ image: UIImage?) {
        reset()
        guard let image else { return }
        lastRenderedContents = image.cgImage
        layer.contents = lastRenderedContents
    }


    func setData(_ data: Data?, displayPixelMaxSide: CGFloat, cacheKey: String? = nil) {
        if data == nil {
            reset()
            return
        }

        if let cacheKey, cacheKey == currentDataKey, !isStatic, layer.contents != nil {
            return
        }

        pendingDecodeGeneration &+= 1
        let gen = pendingDecodeGeneration
        currentDataKey = cacheKey
        pixelTargetMaxSide = max(displayPixelMaxSide, 16)
        let maxSide = pixelTargetMaxSide

        let payload = data!
        decodeQueue.async { [weak self] in
            guard let source = CGImageSourceCreateWithData(payload as CFData, nil) else {
                DispatchQueue.main.async { self?.applyStaticFallback(payload, gen: gen) }
                return
            }
            let count = CGImageSourceGetCount(source)
            if count <= 1 {
                let cg = Self.decodeThumbnailFrame(source: source, index: 0, maxSide: maxSide)
                DispatchQueue.main.async {
                    guard let self, gen == self.pendingDecodeGeneration else { return }
                    AnimatedEmojiTicker.shared.unregister(self)
                    self.imageSource = nil
                    self.isStatic = true
                    self.frameDelays = []
                    self.totalDuration = 0
                    self.lastFrameIndex = -1
                    self.requestedFrameIndex = -1
                    self.lastRenderedContents = cg
                    self.layer.contents = cg
                }
                return
            }
            var delays: [CFTimeInterval] = []
            delays.reserveCapacity(count)
            for i in 0..<count {
                delays.append(Self.frameDelay(source: source, index: i))
            }
            let total = delays.reduce(0, +)
            let firstFrame = Self.decodeThumbnailFrame(source: source, index: 0, maxSide: maxSide)
            DispatchQueue.main.async {
                guard let self, gen == self.pendingDecodeGeneration else { return }
                self.imageSource = source
                self.isStatic = false
                self.frameDelays = delays
                self.totalDuration = total
                self.lastFrameIndex = 0
                self.requestedFrameIndex = 0
                self.startTime = CACurrentMediaTime()
                self.lastRenderedContents = firstFrame
                self.layer.contents = firstFrame
                if self.window != nil {
                    AnimatedEmojiTicker.shared.register(self)
                }
            }
        }
    }

    private func applyStaticFallback(_ data: Data, gen: Int) {
        let image = UIImage.decodeImage(from: data)
        guard gen == pendingDecodeGeneration else { return }
        AnimatedEmojiTicker.shared.unregister(self)
        imageSource = nil
        isStatic = true
        frameDelays = []
        totalDuration = 0
        lastFrameIndex = -1
        lastRenderedContents = image?.cgImage
        layer.contents = lastRenderedContents
    }

    fileprivate func tick(now: CFTimeInterval) {
        guard !isStatic, let source = imageSource, totalDuration > 0 else { return }
        let elapsed = (now - startTime).truncatingRemainder(dividingBy: totalDuration)
        var acc: CFTimeInterval = 0
        var idx = 0
        for (i, d) in frameDelays.enumerated() {
            acc += d
            if elapsed < acc { idx = i; break }
            idx = i
        }
        guard idx != requestedFrameIndex else { return }
        requestedFrameIndex = idx

        let maxSide = pixelTargetMaxSide
        let gen = pendingDecodeGeneration
        let target = idx
        decodeQueue.async { [weak self] in
            let cg = Self.decodeThumbnailFrame(source: source, index: target, maxSide: maxSide)
            DispatchQueue.main.async {
                guard let self, gen == self.pendingDecodeGeneration else { return }
                self.lastFrameIndex = target
                self.lastRenderedContents = cg
                self.layer.contents = cg
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if layer.contents == nil, let lastRenderedContents {
                layer.contents = lastRenderedContents
            }
            if !isStatic, imageSource != nil {
                if layer.contents == nil {
                    requestedFrameIndex = -1
                }
                AnimatedEmojiTicker.shared.register(self)
            }
        } else {
            AnimatedEmojiTicker.shared.unregister(self)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview == nil {
            AnimatedEmojiTicker.shared.unregister(self)
        }
    }


    private static func frameDelay(source: CGImageSource, index: Int) -> CFTimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else {
            return 0.1
        }
        if let webp = props["{WebP}"] as? [String: Any],
           let d = (webp["DelayTime"] as? NSNumber)?.doubleValue, d > 0 {
            return max(d, 0.02)
        }
        if let gif = props["{GIF}"] as? [String: Any] {
            if let unclamped = (gif["UnclampedDelayTime"] as? NSNumber)?.doubleValue, unclamped > 0 {
                return max(unclamped, 0.02)
            }
            if let d = (gif["DelayTime"] as? NSNumber)?.doubleValue, d > 0 {
                return max(d, 0.02)
            }
        }
        if let apng = props["{PNG}"] as? [String: Any],
           let d = (apng["DelayTime"] as? NSNumber)?.doubleValue, d > 0 {
            return max(d, 0.02)
        }
        return 0.1
    }

    private static func decodeThumbnailFrame(source: CGImageSource, index: Int, maxSide: CGFloat) -> CGImage? {
        let opts: NSDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: max(maxSide, 16) as NSNumber,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, index, opts as CFDictionary)
    }
}


final class AnimatedEmojiTicker {

    static let shared = AnimatedEmojiTicker()

    private var displayLink: CADisplayLink?
    private let views = NSHashTable<AnimatedEmojiImageView>.weakObjects()
    private var lastTick: CFTimeInterval = 0
    private var isPaused = false
    private static let targetFrameInterval: CFTimeInterval = 1.0 / 30.0

    func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    func register(_ view: AnimatedEmojiImageView) {
        views.add(view)
        startIfNeeded()
    }

    func unregister(_ view: AnimatedEmojiImageView) {
        views.remove(view)
        if views.allObjects.isEmpty {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    private func startIfNeeded() {
        guard displayLink == nil else { return }
        let dl = CADisplayLink(target: self, selector: #selector(tick(_:)))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        } else {
            dl.preferredFramesPerSecond = 30
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
        lastTick = CACurrentMediaTime()
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard !isPaused else { return }
        let now = link.timestamp
        if now - lastTick < Self.targetFrameInterval { return }
        lastTick = now

        var hasAny = false
        for v in views.allObjects {
            hasAny = true
            if v.window != nil {
                v.tick(now: now)
            }
        }
        if !hasAny {
            link.invalidate()
            displayLink = nil
        }
    }
}
