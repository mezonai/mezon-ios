import Foundation
import UIKit
import AsyncDisplayKit

final class ChatImageGalleryItemNode: ZoomableContentGalleryItemNode {

    private let instantPreviewNode: ASDisplayNode
    private let imageNode: ASDisplayNode
    private let spinnerNode: ASDisplayNode
    private var imageView: UIImageView { return imageNode.view as! UIImageView }
    private var instantPreviewView: UIImageView { return instantPreviewNode.view as! UIImageView }
    private var lockedContentSize: CGSize?
    private var hasProxyImage = false
    private var hasOriginalImage = false
    private var isLoadingProxy = false
    private var isLoadingOriginal = false
    private var pendingProxyURL: URL?
    private var pendingOriginalURLString: String?
    private var isCentral = false
    private var hasVisibleBitmap = false
    private var isZoomDisplayReady = false

    override init() {
        self.instantPreviewNode = ASDisplayNode(viewBlock: {
            let v = UIImageView()
            v.contentMode = .scaleAspectFit
            v.isUserInteractionEnabled = false
            v.backgroundColor = .clear
            return v
        })
        self.imageNode = ASDisplayNode(viewBlock: {
            let v = UIImageView()
            v.contentMode = .scaleAspectFit
            v.isUserInteractionEnabled = true
            v.backgroundColor = .clear
            return v
        })
        self.spinnerNode = ASDisplayNode(viewBlock: {
            let spinner = UIActivityIndicatorView.mezonLarge()
            spinner.color = .white
            spinner.startAnimating()
            return spinner
        })
        super.init()
        self.addSubnode(instantPreviewNode)
        self.addSubnode(spinnerNode)
    }

    func configure(info: GalleryItemInfo) {
        hasProxyImage = false
        hasOriginalImage = false
        isLoadingProxy = false
        isLoadingOriginal = false
        hasVisibleBitmap = false
        isZoomDisplayReady = false
        lockedContentSize = nil
        pendingProxyURL = nil
        pendingOriginalURLString = nil
        imageView.image = nil
        instantPreviewView.image = nil
        instantPreviewNode.isHidden = true
        zoomableContent = nil
        spinnerNode.isHidden = true

        establishLayoutLockFromMetadata(info)
        if lockedContentSize == nil {
            establishLayoutLockFromMemoryCache(info)
        }

        if let preview = info.image {
            applyPreviewImmediately(preview)
        } else if let cached = bestFitPreviewImageFromMemory(for: info) {
            applyPreviewImmediately(cached)
        } else {
            spinnerNode.isHidden = false
            loadCachedPreviewIfNeeded(info)
        }

        if let url = URL(string: info.url), !info.url.isEmpty {
            pendingProxyURL = url
            if let sourceURL = info.sourceURL,
               !sourceURL.isEmpty,
               sourceURL != info.url {
                pendingOriginalURLString = sourceURL
            }
            if isCentral {
                DispatchQueue.main.async { [weak self] in
                    self?.startProxyLoadIfNeeded()
                }
            }
        }
    }

    override func centralityUpdated(isCentral: Bool) {
        super.centralityUpdated(isCentral: isCentral)
        self.isCentral = isCentral
        guard isCentral else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.hasProxyImage {
                self.scheduleOriginalLoadIfNeeded()
            } else {
                self.startProxyLoadIfNeeded()
            }
        }
    }

    private func layoutLockKeys(for info: GalleryItemInfo) -> [String] {
        var keys: [String] = []
        if let placeholderURL = info.placeholderURL, !placeholderURL.isEmpty {
            keys.append(placeholderURL)
        }
        if !info.url.isEmpty {
            keys.append(info.url)
        }
        if let sourceURL = info.sourceURL, !sourceURL.isEmpty {
            keys.append(contentsOf: GalleryItemInfo.previewCacheKeys(sourceURL: sourceURL, placeholderProxySize: 150))
            keys.append(contentsOf: GalleryItemInfo.previewCacheKeys(sourceURL: sourceURL, placeholderProxySize: 400))
        }
        var unique: [String] = []
        for key in keys where !unique.contains(key) {
            unique.append(key)
        }
        return unique
    }

    private func establishLayoutLockFromMetadata(_ info: GalleryItemInfo) {
        guard let size = info.pixelSize, size.width > 0, size.height > 0 else { return }
        lockDisplaySize(from: size)
    }

    private func establishLayoutLockFromMemoryCache(_ info: GalleryItemInfo) {
        guard lockedContentSize == nil else { return }
        for key in layoutLockKeys(for: info) {
            if let cached = ImageCache.shared.memoryImage(forKey: key) {
                lockDisplaySize(from: cached.size)
                return
            }
        }
    }

    private func bestFitPreviewImageFromMemory(for info: GalleryItemInfo) -> UIImage? {
        for key in layoutLockKeys(for: info) {
            if let cached = ImageCache.shared.memoryImage(forKey: key) {
                return cached
            }
        }
        return nil
    }

    private func loadCachedPreviewIfNeeded(_ info: GalleryItemInfo) {
        guard !hasVisibleBitmap else { return }
        for key in layoutLockKeys(for: info) {
            guard ImageCache.shared.memoryImage(forKey: key) == nil else { continue }
            guard ImageCache.shared.hasDiskCache(forKey: key) else { continue }
            ImageCache.shared.imageFromDisk(forKey: key) { [weak self] image in
                guard let self, let image, !self.hasProxyImage, !self.hasOriginalImage else { return }
                self.applyPreviewImmediately(image)
            }
            return
        }
        guard let placeholderURL = info.placeholderURL, !placeholderURL.isEmpty else { return }
        ImageCache.shared.loadImage(urlString: placeholderURL) { [weak self] image in
            guard let self, let image, !self.hasProxyImage, !self.hasOriginalImage else { return }
            self.applyPreviewImmediately(image)
        }
    }

    private func startProxyLoadIfNeeded() {
        guard isCentral, !hasProxyImage, !isLoadingProxy, let url = pendingProxyURL else { return }
        isLoadingProxy = true
        if !hasVisibleBitmap {
            spinnerNode.isHidden = false
        }
        loadImage(urlString: url.absoluteString) { [weak self] image in
            guard let self else { return }
            self.isLoadingProxy = false
            guard !self.hasProxyImage else { return }
            if let image {
                self.applyProxyImage(image)
                self.scheduleOriginalLoadIfNeeded()
                return
            }
            if let fallback = self.pendingOriginalURLString,
               !fallback.isEmpty,
               fallback != url.absoluteString {
                self.loadOriginalAsFallback(fallback)
            } else {
                self.spinnerNode.isHidden = self.hasVisibleBitmap
            }
        }
    }

    private func scheduleOriginalLoadIfNeeded() {
        guard isCentral, !hasOriginalImage, !isLoadingOriginal,
              let originalURLString = pendingOriginalURLString,
              !originalURLString.isEmpty else { return }
        let proxyURLString = pendingProxyURL?.absoluteString
        guard originalURLString != proxyURLString else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.startOriginalLoadIfNeeded()
        }
    }

    private func startOriginalLoadIfNeeded() {
        guard isCentral, !hasOriginalImage, !isLoadingOriginal,
              let originalURLString = pendingOriginalURLString,
              !originalURLString.isEmpty else { return }
        let proxyURLString = pendingProxyURL?.absoluteString
        guard originalURLString != proxyURLString else { return }
        isLoadingOriginal = true
        loadImage(urlString: originalURLString) { [weak self] image in
            guard let self else { return }
            self.isLoadingOriginal = false
            guard let image, !self.hasOriginalImage else { return }
            self.upgradeToOriginalImage(image)
        }
    }

    private func loadOriginalAsFallback(_ urlString: String) {
        guard !hasOriginalImage else { return }
        isLoadingOriginal = true
        if !hasVisibleBitmap {
            spinnerNode.isHidden = false
        }
        loadImage(urlString: urlString) { [weak self] image in
            guard let self else { return }
            self.isLoadingOriginal = false
            guard !self.hasOriginalImage else { return }
            if let image {
                self.hasOriginalImage = true
                self.hasProxyImage = true
                self.applyProxyImage(image)
            } else {
                self.spinnerNode.isHidden = self.hasVisibleBitmap
            }
        }
    }

    private func applyPreviewImmediately(_ image: UIImage) {
        guard !hasProxyImage, !hasOriginalImage else { return }
        if lockedContentSize == nil {
            lockDisplaySize(from: image.size)
        }
        hasVisibleBitmap = true
        instantPreviewView.image = image
        if !isZoomDisplayReady {
            instantPreviewNode.isHidden = false
        }
        imageView.image = image
        spinnerNode.isHidden = true
        revealZoomDisplayIfNeeded()
    }

    private func lockDisplaySize(from size: CGSize) {
        let normalized = normalizedContentSize(size)
        guard lockedContentSize == nil else { return }
        lockedContentSize = normalized
        updateZoomableContentIfNeeded(displaySize: normalized)
    }

    private func applyProxyImage(_ image: UIImage) {
        hasProxyImage = true
        if lockedContentSize == nil {
            lockDisplaySize(from: image.size)
        }
        showBitmap(image, animated: hasVisibleBitmap && lockedContentSize == nil)
    }

    private func upgradeToOriginalImage(_ image: UIImage) {
        hasOriginalImage = true
        hideInstantPreview()
        showBitmap(image, animated: false)
    }

    private func hideInstantPreview() {
        instantPreviewNode.isHidden = true
        instantPreviewView.image = nil
    }

    private func showBitmap(_ image: UIImage, animated: Bool) {
        if lockedContentSize == nil {
            lockDisplaySize(from: image.size)
        }
        guard lockedContentSize != nil else { return }
        hasVisibleBitmap = true

        let useInstantPreview = !isZoomDisplayReady && !hasOriginalImage

        if useInstantPreview {
            instantPreviewNode.isHidden = false
            if animated {
                UIView.transition(with: instantPreviewView, duration: 0.2, options: .transitionCrossDissolve) {
                    self.instantPreviewView.image = image
                }
            } else {
                instantPreviewView.image = image
            }
        } else {
            hideInstantPreview()
        }

        if animated {
            UIView.transition(with: imageView, duration: 0.2, options: .transitionCrossDissolve) {
                self.imageView.image = image
            }
        } else {
            imageView.image = image
        }
        spinnerNode.isHidden = true
        revealZoomDisplayIfNeeded()
    }

    private func revealZoomDisplayIfNeeded() {
        guard hasVisibleBitmap, !isZoomDisplayReady else { return }
        let boundsSize = scrollNode.bounds.size
        guard boundsSize.width > 1, boundsSize.height > 1, zoomableContent != nil else { return }
        isZoomDisplayReady = true
        hideInstantPreview()
    }

    private func normalizedContentSize(_ size: CGSize) -> CGSize {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        return CGSize(width: width, height: height)
    }

    private func updateZoomableContentIfNeeded(displaySize: CGSize) {
        if let current = zoomableContent,
           current.1 === imageNode,
           abs(current.0.width - displaySize.width) < 0.5,
           abs(current.0.height - displaySize.height) < 0.5 {
            return
        }
        zoomableContent = (displaySize, imageNode)
        revealZoomDisplayIfNeeded()
    }

    private func loadImage(urlString: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = ImageCache.shared.memoryImage(forKey: urlString) {
            completion(cached)
            return
        }
        ImageCache.shared.loadImage(urlString: urlString, completion: completion)
    }

    override func scrollViewDidZoom(_ scrollView: UIScrollView) {
        super.scrollViewDidZoom(scrollView)
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            hideInstantPreview()
            isZoomDisplayReady = true
        }
    }

    override func containerLayoutUpdated(_ size: CGSize, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(size, navigationBarHeight: navigationBarHeight, transition: transition)
        transition.updateFrame(node: instantPreviewNode, frame: CGRect(origin: .zero, size: size))
        let spinnerSize = CGSize(width: 40, height: 40)
        transition.updateFrame(node: spinnerNode, frame: CGRect(
            x: (size.width - spinnerSize.width) / 2,
            y: (size.height - spinnerSize.height) / 2,
            width: spinnerSize.width, height: spinnerSize.height
        ))
        revealZoomDisplayIfNeeded()
    }

    var currentImage: UIImage? {
        return instantPreviewView.image ?? imageView.image
    }
}
