import UIKit
import AsyncDisplayKit

private final class ShimmerPlaceholderNode: ASDisplayNode {
    private let gradientLayer = CAGradientLayer()

    override init() {
        super.init()
        isLayerBacked = true
        cornerRadius = 8
        clipsToBounds = true
    }

    override func didLoad() {
        super.didLoad()
        backgroundColor = UIColor.theme.secondary
        gradientLayer.colors = [
            UIColor.theme.secondary.cgColor,
            UIColor.theme.secondaryLight.cgColor,
            UIColor.theme.secondary.cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 0.5, 1]
        layer.addSublayer(gradientLayer)
        startAnimation()
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
    }

    private func startAnimation() {
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [0, 0, 0.25]
        anim.toValue = [0.75, 1, 1]
        anim.duration = 1.2
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(anim, forKey: "shimmer")
    }
}

final class MessageMediaContentNode: ASDisplayNode {

    private var imageNodes: [TransformImageNode] = []
    private var videoOverlayNodes: [ASDisplayNode] = []
    private var shimmerNodes: [ShimmerPlaceholderNode] = []
    private var overlayCountNode: ASTextNode2?
    private var overlayBgNode: ASDisplayNode?
    private var stickerNode: ASDisplayNode?
    private var attachments: [ParsedAttachment] = []
    private(set) var isUploading: Bool = false

    var onImageTapped: ((Int) -> Void)?


    private var cachedImageFrames: [CGRect] = []
    private var cachedTotalSize: CGSize = .zero
    private var isSingleImage = false
    private var isSticker = false
    private var isGifSticker = false
    private var isMultiple = false
    private var lastRemoteProxyURLByIndex: [Int: String] = [:]

    override init() {
        super.init()
    }

    func configure(media: [ParsedAttachment]) {

        imageNodes.forEach { $0.removeFromSupernode(); $0.reset() }
        imageNodes.removeAll()
        videoOverlayNodes.forEach { $0.removeFromSupernode() }
        videoOverlayNodes.removeAll()
        shimmerNodes.forEach { $0.removeFromSupernode() }
        shimmerNodes.removeAll()
        overlayCountNode?.removeFromSupernode()
        overlayCountNode = nil
        overlayBgNode?.removeFromSupernode()
        overlayBgNode = nil
        stickerNode?.removeFromSupernode()
        stickerNode = nil
        attachments = media
        lastRemoteProxyURLByIndex.removeAll()
        cachedImageFrames = []

        isUploading = media.contains { $0.isUploading }

        guard !media.isEmpty else { return }


        let isGifType = media.count == 1 && media[0].filetype == "image/gif"
        if media.count == 1, media[0].isSticker || isGifType {
            isSticker = true
            isGifSticker = isGifType && !media[0].isSticker
            isSingleImage = false
            isMultiple = false
            let node = ASDisplayNode()
            node.setViewBlock {
                let imageView = UIImageView()
                imageView.contentMode = .scaleAspectFit
                imageView.clipsToBounds = true
                return imageView
            }
            stickerNode = node
            addSubnode(node)
            loadStickerImage(url: media[0].url, into: node)
        } else if media.count == 1 {
            isSticker = false
            isSingleImage = true
            isMultiple = false
            let shimmer = ShimmerPlaceholderNode()
            shimmerNodes.append(shimmer)
            addSubnode(shimmer)
            let node = TransformImageNode()
            node.contentAnimations = [.firstUpdate]
            node.imageUpdated = { [weak shimmer] _ in
                shimmer?.removeFromSupernode()
            }
            imageNodes.append(node)
            addSubnode(node)
            loadImage(at: 0, into: node, media: media[0], isMultiple: false, measuredPtSize: nil)

            if media[0].isVideo {
                let overlay = makePlayOverlayNode()
                videoOverlayNodes.append(overlay)
                addSubnode(overlay)
            }
            if media[0].isUploading {
                let overlay = makeUploadingOverlay()
                videoOverlayNodes.append(overlay)
                addSubnode(overlay)
            }
        } else {
            isSticker = false
            isSingleImage = false
            isMultiple = true
            let items = Array(media.prefix(4))
            for (i, att) in items.enumerated() {
                let shimmer = ShimmerPlaceholderNode()
                shimmerNodes.append(shimmer)
                addSubnode(shimmer)
                let node = TransformImageNode()
                node.contentAnimations = [.firstUpdate]
                node.imageUpdated = { [weak shimmer] _ in
                    shimmer?.removeFromSupernode()
                }
                imageNodes.append(node)
                addSubnode(node)
                loadImage(at: i, into: node, media: att, isMultiple: true, measuredPtSize: nil)

                if att.isVideo {
                    let overlay = makePlayOverlayNode()
                    videoOverlayNodes.append(overlay)
                    addSubnode(overlay)
                } else if att.isUploading {
                    let overlay = makeUploadingOverlay()
                    videoOverlayNodes.append(overlay)
                    addSubnode(overlay)
                } else {
                    let placeholder = ASDisplayNode()
                    placeholder.isHidden = true
                    videoOverlayNodes.append(placeholder)
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
                let bg = ASDisplayNode()
                bg.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                overlayBgNode = bg
                addSubnode(bg)
                addSubnode(countNode)
            }
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let maxH = UIScreen.main.bounds.height * 0.5
        cachedImageFrames = []

        if isSticker {
            if isGifSticker {
                let att = attachments[0]
                let hasSize = (att.width ?? 0) > 0 && (att.height ?? 0) > 0
                if hasSize {
                    var w = CGFloat(att.width!)
                    var h = CGFloat(att.height!)
                    let maxH = UIScreen.main.bounds.height * 0.4
                    let ratio = min(maxWidth / w, maxH / h, 1.0)
                    w = max(floor(w * ratio), 80)
                    h = max(floor(h * ratio), 60)
                    cachedTotalSize = CGSize(width: w, height: h)
                } else {
                    cachedTotalSize = CGSize(width: 200, height: 200)
                }
            } else {
                cachedTotalSize = CGSize(width: 120, height: 120)
            }
            return cachedTotalSize
        }

        if isSingleImage {
            let att = attachments[0]
            var w = max(CGFloat(att.width ?? 300), 1)
            var h = max(CGFloat(att.height ?? 200), 1)
            let safeMaxW = max(maxWidth, 1)
            let safeMaxH = max(maxH, 1)
            let ratio = min(safeMaxW / w, safeMaxH / h, 1.0)
            w = max(floor(w * ratio), 100)
            h = max(floor(h * ratio), 80)

            cachedImageFrames = [CGRect(x: 0, y: 0, width: w, height: h)]
            cachedTotalSize = CGSize(width: w, height: h)


            if let node = imageNodes.first {
                let args = TransformImageArguments(
                    corners: ImageCorners(radius: 8.swh),
                    imageSize: CGSize(width: w, height: h),
                    boundingSize: CGSize(width: w, height: h),
                    intrinsicInsets: .zero
                )
                let layout = node.asyncLayout()
                let apply = layout(args)
                apply()
            }
            ensureRemoteImageLoaded(at: 0, media: att, isMultiple: false)
            return cachedTotalSize
        }

        if isMultiple {
            let thumbH: CGFloat = max(120.sh, 1)
            let spacing: CGFloat = 4.sw
            let itemW = max((maxWidth - spacing) / 2, 1)
            let items = Array(imageNodes.prefix(4))

            var frames: [CGRect] = []
            let row1Count = min(items.count, 2)
            for i in 0..<row1Count {
                frames.append(CGRect(x: CGFloat(i) * (itemW + spacing), y: 0, width: itemW, height: thumbH))
            }

            if items.count > 2 {
                let row2Count = items.count - 2
                for i in 0..<row2Count {
                    frames.append(CGRect(x: CGFloat(i) * (itemW + spacing), y: thumbH + spacing, width: itemW, height: thumbH))
                }
            }


            for (i, node) in items.enumerated() {
                let args = TransformImageArguments(
                    corners: ImageCorners(radius: 8.swh),
                    imageSize: CGSize(width: itemW, height: thumbH),
                    boundingSize: CGSize(width: itemW, height: thumbH),
                    intrinsicInsets: .zero
                )
                let layout = node.asyncLayout()
                let apply = layout(args)
                apply()
                if i < attachments.count {
                    ensureRemoteImageLoaded(at: i, media: attachments[i], isMultiple: true)
                }
            }

            cachedImageFrames = frames
            let totalH = items.count > 2 ? thumbH * 2 + spacing : thumbH
            cachedTotalSize = CGSize(width: maxWidth, height: totalH)
            return cachedTotalSize
        }

        cachedTotalSize = .zero
        return .zero
    }

    override func layout() {
        super.layout()

        if isSticker {
            stickerNode?.frame = CGRect(origin: .zero, size: cachedTotalSize)
            return
        }

        for (i, node) in imageNodes.enumerated() {
            guard i < cachedImageFrames.count else { break }
            node.frame = cachedImageFrames[i]
            if i < shimmerNodes.count {
                shimmerNodes[i].frame = cachedImageFrames[i]
            }
        }


        if isSingleImage {
            if let overlay = videoOverlayNodes.first, !overlay.isHidden {
                let imgFrame = cachedImageFrames.first ?? bounds
                if attachments.first?.isVideo == true {
                    let sz: CGFloat = 48
                    overlay.frame = CGRect(
                        x: imgFrame.midX - sz / 2,
                        y: imgFrame.midY - sz / 2,
                        width: sz, height: sz
                    )
                } else if attachments.first?.isUploading == true {
                    overlay.frame = imgFrame
                }
            }
        } else if isMultiple {
            for (i, overlay) in videoOverlayNodes.enumerated() {
                guard i < cachedImageFrames.count, !overlay.isHidden else { continue }
                if i < attachments.count, attachments[i].isVideo {
                    let imgFrame = cachedImageFrames[i]
                    let sz: CGFloat = 48
                    overlay.frame = CGRect(x: imgFrame.midX - sz / 2, y: imgFrame.midY - sz / 2, width: sz, height: sz)
                } else if i < attachments.count, attachments[i].isUploading {
                    overlay.frame = cachedImageFrames[i]
                }
            }


            if let countNode = overlayCountNode, let bg = overlayBgNode,
               let lastFrame = cachedImageFrames.last {
                bg.frame = lastFrame
                let countSz = countNode.measure(lastFrame.size)
                countNode.frame = CGRect(
                    x: lastFrame.midX - countSz.width / 2,
                    y: lastFrame.midY - countSz.height / 2,
                    width: countSz.width, height: countSz.height
                )
            }
        }
    }


    private func loadStickerImage(url: String, into node: ASDisplayNode) {
        guard let imageURL = URL(string: url), !url.isEmpty else { return }

        if let cachedData = ImageCache.shared.cachedData(forKey: url) {
            if let animated = UIImage.animatedImage(from: cachedData) {
                DispatchQueue.main.async {
                    (node.view as? UIImageView)?.image = animated
                }
                return
            }
        }
        if let cached = ImageCache.shared.cachedImage(forURL: url) {
            DispatchQueue.main.async {
                (node.view as? UIImageView)?.image = cached
            }
            return
        }

        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            guard let data else { return }
            let image = UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data)
            if let image {
                ImageCache.shared.setImage(image, data: data, forKey: url)
                DispatchQueue.main.async {
                    (node.view as? UIImageView)?.image = image
                }
            }
        }.resume()
    }

    private func ensureRemoteImageLoaded(at index: Int, media: ParsedAttachment, isMultiple: Bool) {
        guard !media.isVideo, media.localImage == nil else { return }
        guard index < imageNodes.count else { return }
        let node = imageNodes[index]
        let w = 400
        let h = 400
        let resizeMode: ImageResizeMode = isMultiple ? .fill : .fit
        let proxyURL = ImgproxyURL.attachmentURL(
            from: media.url,
            width: w,
            height: h,
            resizeType: isMultiple ? "fill" : "fit"
        )
        if lastRemoteProxyURLByIndex[index] == proxyURL, node.image != nil { return }
        lastRemoteProxyURLByIndex[index] = proxyURL
        node.reset()
        if index < shimmerNodes.count {
            let sh = shimmerNodes[index]
            if sh.supernode == nil {
                insertSubnode(sh, belowSubnode: node)
            }
        }
        let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
            || ImageCache.shared.memoryImage(forKey: media.url) != nil
        node.setSignal(
            remoteAttachmentImageSignal(proxyURL: proxyURL, originalURL: media.url, resizeMode: resizeMode),
            attemptSynchronously: hasMem
        )
    }

    private func loadImage(at index: Int, into node: TransformImageNode, media: ParsedAttachment, isMultiple: Bool, measuredPtSize: CGSize?) {
        if let localImage = media.localImage {
            node.setSignal(staticImageSignal(image: localImage), attemptSynchronously: true)
        } else if media.isVideo {
            node.setSignal(videoThumbnailSignal(url: media.url, resizeMode: .fill), attemptSynchronously: false)
        } else if measuredPtSize != nil {
            ensureRemoteImageLoaded(at: index, media: media, isMultiple: isMultiple)
        }
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

    private func makeUploadingOverlay() -> ASDisplayNode {
        let overlay = ASDisplayNode()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        overlay.cornerRadius = 8.swh
        overlay.clipsToBounds = true
        overlay.isUserInteractionEnabled = false

        let spinner = ASDisplayNode()
        spinner.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = .white
            indicator.startAnimating()
            return indicator
        }
        spinner.style.preferredSize = CGSize(width: 36, height: 36)
        overlay.addSubnode(spinner)

        overlay.layoutSpecBlock = { _, _ in
            ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: spinner)
        }

        return overlay
    }

    private func makePlayOverlayNode() -> ASDisplayNode {
        let container = ASDisplayNode()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        container.cornerRadius = 24
        container.clipsToBounds = true
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
        container.addSubnode(playIcon)


        container.layoutSpecBlock = { _, _ in
            playIcon.style.preferredSize = CGSize(width: 22, height: 22)
            return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: playIcon)
        }

        return container
    }
}
