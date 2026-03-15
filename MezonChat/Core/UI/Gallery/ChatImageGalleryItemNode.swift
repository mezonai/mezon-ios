import Foundation
import UIKit
import AsyncDisplayKit

final class ChatImageGalleryItemNode: ZoomableContentGalleryItemNode {

    private let imageNode = TransformImageNode()
    private let spinnerNode: ASDisplayNode
    private var imageSize: CGSize = .zero

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
            self.setImage(existingImage)
        } else if let url = URL(string: info.url), !info.url.isEmpty {
            loadRemoteImage(url: url)
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
            context?.withFlippedContext { ctx in
                if let cgImage = image.cgImage {
                    ctx.draw(cgImage, in: CGRect(origin: .zero, size: arguments.drawingSize))
                }
            }
            return context
        }))

        self.zoomableContent = (image.size, self.imageNode)
    }

    private func loadRemoteImage(url: URL) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.setImage(image)
            }
        }.resume()
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
