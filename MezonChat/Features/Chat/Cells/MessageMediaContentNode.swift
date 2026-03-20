import UIKit
import AsyncDisplayKit

final class MessageMediaContentNode: ASDisplayNode {

    private var imageNodes: [TransformImageNode] = []
    private var videoOverlayNodes: [ASDisplayNode] = []
    private var overlayCountNode: ASTextNode2?
    private var attachments: [ParsedAttachment] = []
    private(set) var isUploading: Bool = false

    var onImageTapped: ((Int) -> Void)?

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
    }

    func configure(media: [ParsedAttachment]) {
        // Clear previous
        imageNodes.forEach { $0.reset() }
        imageNodes.removeAll()
        videoOverlayNodes.removeAll()
        overlayCountNode = nil
        attachments = media

        isUploading = media.contains { $0.isUploading }

        guard !media.isEmpty else { return }

        if media.count == 1 {
            let node = TransformImageNode()
            node.contentAnimations = [.firstUpdate]
            imageNodes.append(node)
            loadImage(at: 0, into: node, media: media[0], isMultiple: false)
        } else {
            let items = Array(media.prefix(4))
            for (i, att) in items.enumerated() {
                let node = TransformImageNode()
                node.contentAnimations = [.firstUpdate]
                imageNodes.append(node)
                loadImage(at: i, into: node, media: att, isMultiple: true)

                if att.isVideo {
                    let overlay = makePlayOverlayNode()
                    videoOverlayNodes.append(overlay)
                } else {
                    videoOverlayNodes.append(ASDisplayNode()) // placeholder
                }
            }
            if media.count > 4 {
                let countNode = ASTextNode2()
                countNode.attributedText = NSAttributedString(
                    string: "+\(media.count - 4)",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 20.sf, weight: .bold),
                        .foregroundColor: UIColor.white,
                    ]
                )
                overlayCountNode = countNode
            }
        }
        setNeedsLayout()
    }

    private func loadImage(at index: Int, into node: TransformImageNode, media: ParsedAttachment, isMultiple: Bool) {
        if let localImage = media.localImage {
            node.setSignal(staticImageSignal(image: localImage), attemptSynchronously: true)
        } else {
            let resizeMode: ImageResizeMode = isMultiple ? .fill : .fit
            if media.isVideo {
                node.setSignal(videoThumbnailSignal(url: media.url, resizeMode: .fill), attemptSynchronously: false)
            } else {
                node.setSignal(remoteImageSignal(url: media.url, resizeMode: resizeMode), attemptSynchronously: false)
            }
        }
    }

    private func makeUploadingOverlay() -> ASDisplayNode {
        let overlay = ASDisplayNode()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        overlay.cornerRadius = 8.swh
        overlay.clipsToBounds = true
        overlay.automaticallyManagesSubnodes = true
        overlay.isUserInteractionEnabled = false

        let spinner = ASDisplayNode()
        spinner.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = .white
            indicator.startAnimating()
            return indicator
        }
        spinner.style.preferredSize = CGSize(width: 36, height: 36)

        overlay.layoutSpecBlock = { _, _ in
            return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: spinner)
        }
        return overlay
    }

    override func didLoad() {
        super.didLoad()
        for (i, node) in imageNodes.enumerated() {
            node.view.isUserInteractionEnabled = true
            node.view.tag = i
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleImageTap(_:)))
            node.view.addGestureRecognizer(tap)
        }
    }

    @objc private func handleImageTap(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        onImageTapped?(view.tag)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        guard !imageNodes.isEmpty else {
            return ASLayoutSpec()
        }

        let maxW = constrainedSize.max.width
        let maxH = UIScreen.main.bounds.height * 0.5

        if imageNodes.count == 1 {
            return layoutSingleImage(maxW: maxW, maxH: maxH)
        } else {
            return layoutMultipleImages(maxW: maxW)
        }
    }

    private func layoutSingleImage(maxW: CGFloat, maxH: CGFloat) -> ASLayoutSpec {
        let att = attachments[0]
        let node = imageNodes[0]

        var w = max(CGFloat(att.width ?? 300), 1)
        var h = max(CGFloat(att.height ?? 200), 1)
        let safeMaxW = max(maxW, 1)
        let safeMaxH = max(maxH, 1)
        let ratio = min(safeMaxW / w, safeMaxH / h, 1.0)
        w = max(floor(w * ratio), 100)
        h = max(floor(h * ratio), 80)

        node.style.preferredSize = CGSize(width: w, height: h)

        let args = TransformImageArguments(
            corners: ImageCorners(radius: 8.swh),
            imageSize: CGSize(width: w, height: h),
            boundingSize: CGSize(width: w, height: h),
            intrinsicInsets: .zero
        )
        let layout = node.asyncLayout()
        let apply = layout(args)
        apply()

        if att.isVideo {
            let overlay = makePlayOverlayNode()
            overlay.style.preferredSize = CGSize(width: 48, height: 48)
            let center = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: overlay)
            return ASOverlayLayoutSpec(child: node, overlay: center)
        }

        if att.isUploading {
            let overlay = makeUploadingOverlay()
            return ASOverlayLayoutSpec(child: node, overlay: overlay)
        }

        return ASWrapperLayoutSpec(layoutElement: node)
    }

    private func layoutMultipleImages(maxW: CGFloat) -> ASLayoutSpec {
        let thumbH: CGFloat = max(120.sh, 1)
        let spacing: CGFloat = 4.sw
        let items = Array(imageNodes.prefix(4))

        // Apply transform arguments to each image
        for node in items {
            let itemW = max((maxW - spacing) / 2, 1)
            node.style.preferredSize = CGSize(width: itemW, height: thumbH)
            let args = TransformImageArguments(
                corners: ImageCorners(radius: 8.swh),
                imageSize: CGSize(width: itemW, height: thumbH),
                boundingSize: CGSize(width: itemW, height: thumbH),
                intrinsicInsets: .zero
            )
            let layout = node.asyncLayout()
            let apply = layout(args)
            apply()
        }

        // Build row children — only add overlay if uploading
        let rowItems: [ASLayoutElement] = items.enumerated().map { i, node in
            if isUploading, i < attachments.count, attachments[i].isUploading {
                return ASOverlayLayoutSpec(child: node, overlay: makeUploadingOverlay())
            }
            return node as ASLayoutElement
        }

        let row1Children = Array(rowItems.prefix(2))
        let row1 = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: spacing,
            justifyContent: .start,
            alignItems: .stretch,
            children: row1Children
        )
        row1.style.height = ASDimensionMake(thumbH)

        var rows: [ASLayoutElement] = [row1]

        if items.count > 2 {
            let row2Items = Array(items[2...])
            var row2Children: [ASLayoutElement] = Array(rowItems[2...])

            // Add overlay count on last item if needed
            if let countNode = overlayCountNode, let lastNode = row2Items.last {
                let overlayBg = ASDisplayNode()
                overlayBg.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                let center = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: countNode)
                let overlaid = ASOverlayLayoutSpec(child: lastNode, overlay: ASOverlayLayoutSpec(child: overlayBg, overlay: center))
                row2Children[row2Children.count - 1] = overlaid
            }

            let row2 = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: spacing,
                justifyContent: .start,
                alignItems: .stretch,
                children: row2Children
            )
            row2.style.height = ASDimensionMake(thumbH)
            rows.append(row2)
        }

        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: spacing,
            justifyContent: .start,
            alignItems: .stretch,
            children: rows
        )
    }

    private func makePlayOverlayNode() -> ASDisplayNode {
        let container = ASDisplayNode()
        container.automaticallyManagesSubnodes = true
        container.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        container.cornerRadius = 24
        container.clipsToBounds = true
        container.style.preferredSize = CGSize(width: 48, height: 48)
        container.isUserInteractionEnabled = false

        let playIcon = ASImageNode()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if let sfImage = UIImage(systemName: "play.fill", withConfiguration: symbolConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22))
            playIcon.image = renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: CGSize(width: 22, height: 22))
                sfImage.draw(in: rect.insetBy(dx: 1, dy: 0))
            }
        }
        playIcon.contentMode = .scaleAspectFit
        playIcon.style.preferredSize = CGSize(width: 22, height: 22)

        container.layoutSpecBlock = { _, _ in
            return ASCenterLayoutSpec(
                centeringOptions: .XY,
                sizingOptions: [],
                child: playIcon
            )
        }

        return container
    }
}
