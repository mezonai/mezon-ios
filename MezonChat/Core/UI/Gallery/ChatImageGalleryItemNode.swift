import Foundation
import UIKit
import AsyncDisplayKit

final class ChatImageGalleryItemNode: ZoomableContentGalleryItemNode {

    private let imageNode = TransformImageNode()
    private let spinnerNode: ASDisplayNode
    private var imageSize: CGSize = .zero
    private var hasFullResolutionImage = false

    override init() {
        self.spinnerNode = ASDisplayNode(viewBlock: {
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.color = .white
            spinner.startAnimating()
            return spinner
        })
        super.init()
        self.imageNode.contentAnimations = [.firstUpdate]
        self.addSubnode(spinnerNode)
    }

    func configure(info: GalleryItemInfo) {
        if let existingImage = info.image {
            hasFullResolutionImage = true
            self.setImage(existingImage)
            return
        }

        var hasPlaceholder = false
        if let placeholderURL = info.placeholderURL,
           !placeholderURL.isEmpty,
           let cachedPlaceholder = ImageCache.shared.cachedImage(forURL: placeholderURL) {
            self.setImage(cachedPlaceholder)
            hasPlaceholder = true
        }

        if let url = URL(string: info.url), !info.url.isEmpty {
            loadRemoteImage(url: url, keepSpinnerHidden: hasPlaceholder)
        }
    }

    private func setImage(_ image: UIImage) {
        self.imageSize = image.size
        self.spinnerNode.isHidden = true

        let makeLayout = self.imageNode.asyncLayout()
        let args = TransformImageArguments(
            corners: ImageCorners(),
            imageSize: image.size,
            boundingSize: image.size,
            intrinsicInsets: .zero
        )
        let apply = makeLayout(args)
        apply()

        self.imageNode.setSignal(.single({ arguments -> DrawingContext? in
            let context = DrawingContext(size: arguments.drawingSize, clear: true)
            context?.withContext { ctx in
                UIGraphicsPushContext(ctx)
                image.draw(in: CGRect(origin: .zero, size: arguments.drawingSize))
                UIGraphicsPopContext()
            }
            return context
        }))

        self.zoomableContent = (image.size, self.imageNode)
    }

    private func loadRemoteImage(url: URL, keepSpinnerHidden: Bool = false) {
        let urlString = url.absoluteString
        if let cached = ImageCache.shared.cachedImage(forURL: urlString) {
            hasFullResolutionImage = true
            setImage(cached)
            return
        }
        if keepSpinnerHidden {
            spinnerNode.isHidden = true
        }
        ImageCache.shared.loadImage(urlString: urlString) { [weak self] image in
            guard let self, let image else { return }
            guard !self.hasFullResolutionImage else { return }
            self.hasFullResolutionImage = true
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
        return imageNode.image
    }
}
