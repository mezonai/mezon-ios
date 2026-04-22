import Foundation
import UIKit
import AsyncDisplayKit

final class ChatImageGalleryItemNode: ZoomableContentGalleryItemNode {

    private let imageNode: ASDisplayNode
    private let spinnerNode: ASDisplayNode
    private var imageView: UIImageView { return imageNode.view as! UIImageView }
    private var imageSize: CGSize = .zero
    private var hasFullResolutionImage = false

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
        spinnerNode.isHidden = false

        if let existingImage = info.image {
            self.setImage(existingImage)
        }

        if let placeholderURL = info.placeholderURL, !placeholderURL.isEmpty {
            if let cachedPlaceholder = ImageCache.shared.memoryImage(forKey: placeholderURL) {
                self.setImage(cachedPlaceholder)
            } else {
                ImageCache.shared.loadImage(urlString: placeholderURL) { [weak self] image in
                    guard let self, let image else { return }
                    guard !self.hasFullResolutionImage else { return }
                    self.setImage(image)
                }
            }
        }

        if let url = URL(string: info.url), !info.url.isEmpty {
            loadRemoteImage(url: url)
        }
    }

    private func setImage(_ image: UIImage) {
        self.imageSize = image.size
        self.imageView.image = image
        self.zoomableContent = (image.size, self.imageNode)
    }

    private func loadRemoteImage(url: URL) {
        let urlString = url.absoluteString
        if let cached = ImageCache.shared.memoryImage(forKey: urlString) {
            hasFullResolutionImage = true
            spinnerNode.isHidden = true
            setImage(cached)
            return
        }
        ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            guard let self, let image else { return }
            guard !self.hasFullResolutionImage else { return }
            self.hasFullResolutionImage = true
            self.spinnerNode.isHidden = true
            self.setImage(image)
        }
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
