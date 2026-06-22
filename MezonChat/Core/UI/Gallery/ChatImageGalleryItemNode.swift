import Foundation
import UIKit
import AsyncDisplayKit

final class ChatImageGalleryItemNode: ZoomableContentGalleryItemNode {

    private let imageNode: ASDisplayNode
    private let spinnerNode: ASDisplayNode
    private var imageView: UIImageView { return imageNode.view as! UIImageView }
    private var imageSize: CGSize = .zero
    private var hasProxyImage = false
    private var hasOriginalImage = false
    private var isLoadingProxy = false
    private var isLoadingOriginal = false
    private var pendingProxyURL: URL?
    private var pendingOriginalURLString: String?
    private var isCentral = false

    override init() {
        self.imageNode = ASDisplayNode(viewBlock: {
            let v = UIImageView()
            v.contentMode = .scaleAspectFit
            v.isUserInteractionEnabled = true
            v.backgroundColor = .clear
            return v
        })
        self.spinnerNode = ASDisplayNode(viewBlock: {
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.color = .white
            spinner.startAnimating()
            return spinner
        })
        super.init()
        self.addSubnode(spinnerNode)
    }

    func configure(info: GalleryItemInfo) {
        hasProxyImage = false
        hasOriginalImage = false
        isLoadingProxy = false
        isLoadingOriginal = false
        pendingProxyURL = nil
        pendingOriginalURLString = nil
        spinnerNode.isHidden = false

        let hasLocalImage = info.image != nil

        if let existingImage = info.image {
            applyInitialImage(existingImage)
        }

        if let placeholderURL = info.placeholderURL, !placeholderURL.isEmpty {
            if let cachedPlaceholder = ImageCache.shared.memoryImage(forKey: placeholderURL) {
                if !hasProxyImage {
                    applyInitialImage(cachedPlaceholder, hideSpinner: false, markProxyComplete: false)
                }
            } else {
                ImageCache.shared.loadImage(urlString: placeholderURL) { [weak self] image in
                    guard let self, let image, !self.hasProxyImage, !self.hasOriginalImage else { return }
                    self.applyInitialImage(image, hideSpinner: false, markProxyComplete: false)
                }
            }
        }

        if let url = URL(string: info.url), !info.url.isEmpty {
            pendingProxyURL = url
            if let sourceURL = info.sourceURL,
               !sourceURL.isEmpty,
               sourceURL != info.url {
                pendingOriginalURLString = sourceURL
            }
            if isCentral {
                if hasLocalImage {
                    startOriginalLoadIfNeeded()
                } else {
                    startProxyLoadIfNeeded()
                }
            }
        }
    }

    override func centralityUpdated(isCentral: Bool) {
        super.centralityUpdated(isCentral: isCentral)
        self.isCentral = isCentral
        guard isCentral else { return }
        if hasProxyImage {
            startOriginalLoadIfNeeded()
        } else {
            startProxyLoadIfNeeded()
        }
    }

    private func startProxyLoadIfNeeded() {
        guard isCentral, !hasProxyImage, !isLoadingProxy, let url = pendingProxyURL else { return }
        isLoadingProxy = true
        loadImage(urlString: url.absoluteString) { [weak self] image in
            guard let self else { return }
            self.isLoadingProxy = false
            guard !self.hasProxyImage else { return }
            if let image {
                self.applyInitialImage(image)
                self.startOriginalLoadIfNeeded()
                return
            }
            if let fallback = self.pendingOriginalURLString,
               !fallback.isEmpty,
               fallback != url.absoluteString {
                self.loadOriginalAsFallback(fallback)
            } else {
                self.spinnerNode.isHidden = self.imageView.image != nil
            }
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
        loadImage(urlString: urlString) { [weak self] image in
            guard let self else { return }
            self.isLoadingOriginal = false
            guard !self.hasOriginalImage else { return }
            if let image {
                self.hasOriginalImage = true
                self.hasProxyImage = true
                self.applyInitialImage(image)
            } else {
                self.spinnerNode.isHidden = self.imageView.image != nil
            }
        }
    }

    private func applyInitialImage(
        _ image: UIImage,
        hideSpinner: Bool = true,
        markProxyComplete: Bool = true
    ) {
        imageSize = image.size
        imageView.image = image
        zoomableContent = (image.size, imageNode)
        if markProxyComplete {
            hasProxyImage = true
        }
        if hideSpinner {
            spinnerNode.isHidden = true
        }
    }

    private func upgradeToOriginalImage(_ image: UIImage) {
        hasOriginalImage = true
        UIView.transition(with: imageView, duration: 0.2, options: .transitionCrossDissolve) {
            self.imageView.image = image
        }
    }

    private func loadImage(urlString: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = ImageCache.shared.memoryImage(forKey: urlString) {
            completion(cached)
            return
        }
        ImageCache.shared.loadImage(urlString: urlString, completion: completion)
    }

    override func containerLayoutUpdated(_ size: CGSize, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(size, navigationBarHeight: navigationBarHeight, transition: transition)
        let spinnerSize = CGSize(width: 40, height: 40)
        transition.updateFrame(node: spinnerNode, frame: CGRect(
            x: (size.width - spinnerSize.width) / 2,
            y: (size.height - spinnerSize.height) / 2,
            width: spinnerSize.width, height: spinnerSize.height
        ))
    }

    var currentImage: UIImage? {
        return imageView.image
    }
}
