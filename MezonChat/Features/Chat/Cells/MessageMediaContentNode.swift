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
    private var stickerNode: ASDisplayNode?
    private var attachments: [ParsedAttachment] = []
    private(set) var isUploading: Bool = false

    var onImageTapped: ((Int) -> Void)?

    private static let gridSpacing: CGFloat = 2.0

    private var cachedImageFrames: [CGRect] = []
    private var cachedPositions: [MediaMosaicItemPosition] = []
    private var cachedTotalSize: CGSize = .zero
    private var isSingleImage = false
    private var isSticker = false
    private var isGifSticker = false
    private var isMultiple = false
    private var lastRemoteProxyURLByIndex: [Int: String] = [:]

    override init() {
        super.init()
    }

    private static func mosaicItemSize(for att: ParsedAttachment) -> CGSize {
        if let local = att.localImage, local.size.width > 0, local.size.height > 0 {
            return local.size
        }
        let w = att.width ?? 0
        let h = att.height ?? 0
        if w > 0 && h > 0 {
            return CGSize(width: w, height: h)
        }
        return CGSize(width: 1, height: 1)
    }

    private func uniformGridLayout(count: Int, maxWidth: CGFloat, spacing: CGFloat) -> ([CGRect], [MediaMosaicItemPosition]) {
        let columns = count <= 9 ? 3 : 4
        let rows = Int(ceil(CGFloat(count) / CGFloat(columns)))
        let itemW = floor((maxWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let itemH = itemW

        var frames: [CGRect] = []
        var positions: [MediaMosaicItemPosition] = []
        for i in 0..<count {
            let row = i / columns
            let col = i % columns
            let lineCount = min(columns, count - row * columns)
            let x = CGFloat(col) * (itemW + spacing)
            let y = CGFloat(row) * (itemH + spacing)
            frames.append(CGRect(x: x, y: y, width: itemW, height: itemH))

            var position: MediaMosaicItemPosition = []
            if row == 0 { position.insert(.top) }
            if row == rows - 1 { position.insert(.bottom) }
            if col == 0 { position.insert(.left) }
            if col == lineCount - 1 { position.insert(.right) }
            if position.isEmpty { position = .inside }
            positions.append(position)
        }
        return (frames, positions)
    }

    private func splitIntoChunks(count: Int) -> [Int] {
        guard count > 10 else { return [count] }
        var chunks: [Int] = []
        var remaining = count
        while remaining > 0 {
            if remaining <= 10 {
                chunks.append(remaining)
                remaining = 0
            } else if remaining == 11 {
                chunks.append(6)
                chunks.append(5)
                remaining = 0
            } else if remaining == 12 {
                chunks.append(6)
                chunks.append(6)
                remaining = 0
            } else {
                chunks.append(10)
                remaining -= 10
            }
        }
        return chunks
    }

    private func dynamicGridLayout(attachments: [ParsedAttachment], maxWidth: CGFloat, maxHeight: CGFloat, spacing: CGFloat) -> ([CGRect], [MediaMosaicItemPosition]) {
        let chunkSizes = splitIntoChunks(count: attachments.count)

        var allFrames: [CGRect] = []
        var allPositions: [MediaMosaicItemPosition] = []
        var offsetY: CGFloat = 0
        var startIndex = 0

        for chunkSize in chunkSizes {
            let chunk = Array(attachments[startIndex ..< startIndex + chunkSize])
            startIndex += chunkSize

            let itemSizes = chunk.map { Self.mosaicItemSize(for: $0) }
            let (framesAndPositions, dimensions) = mediaMosaicLayout(
                maxSize: CGSize(width: maxWidth, height: maxHeight),
                itemSizes: itemSizes,
                spacing: spacing,
                fillWidth: true
            )

            var frames = framesAndPositions.map { $0.0 }
            var positions = framesAndPositions.map { $0.1 }

            let mosaicValid = !frames.isEmpty
                && frames.count == chunk.count
                && dimensions.width > 0
                && dimensions.height > 0
                && !frames.contains { $0.width <= 0 || $0.height <= 0 }

            if mosaicValid {
                if abs(dimensions.width - maxWidth) > 0.5 {
                    let scale = maxWidth / dimensions.width
                    frames = frames.map {
                        CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale)
                    }
                }
            } else {
                (frames, positions) = uniformGridLayout(count: chunk.count, maxWidth: maxWidth, spacing: spacing)
            }

            var chunkMaxY: CGFloat = 0
            for frame in frames {
                let shifted = CGRect(x: frame.minX, y: frame.minY + offsetY, width: frame.width, height: frame.height)
                allFrames.append(shifted)
                chunkMaxY = max(chunkMaxY, shifted.maxY)
            }
            allPositions.append(contentsOf: positions)
            offsetY = chunkMaxY + spacing
        }

        return (allFrames, allPositions)
    }

    func prepareForMeasurement(media: [ParsedAttachment]) {
        attachments = media
        lastRemoteProxyURLByIndex.removeAll()
        cachedImageFrames = []
        cachedPositions = []
        isUploading = media.contains { $0.isUploading }
        isSticker = false
        isGifSticker = false
        isSingleImage = false
        isMultiple = false
        guard !media.isEmpty else { return }
        let isGifType = media.count == 1 && media[0].filetype == "image/gif"
        if media.count == 1, media[0].isSticker || isGifType {
            isSticker = true
            isGifSticker = isGifType && !media[0].isSticker
        } else if media.count == 1 {
            isSingleImage = true
        } else {
            isMultiple = true
        }
    }

    func configure(media: [ParsedAttachment]) {

        imageNodes.forEach { $0.removeFromSupernode(); $0.reset() }
        imageNodes.removeAll()
        videoOverlayNodes.forEach { $0.removeFromSupernode() }
        videoOverlayNodes.removeAll()
        shimmerNodes.forEach { $0.removeFromSupernode() }
        shimmerNodes.removeAll()
        stickerNode?.removeFromSupernode()
        stickerNode = nil
        attachments = media
        lastRemoteProxyURLByIndex.removeAll()
        cachedImageFrames = []
        cachedPositions = []

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
            if media[0].uploadFailed {
                let overlay = makeFailedOverlay()
                videoOverlayNodes.append(overlay)
                addSubnode(overlay)
            }
        } else {
            isSticker = false
            isSingleImage = false
            isMultiple = true
            let items = media
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
                } else if att.uploadFailed {
                    let overlay = makeFailedOverlay()
                    videoOverlayNodes.append(overlay)
                    addSubnode(overlay)
                } else {
                    let placeholder = ASDisplayNode()
                    placeholder.isHidden = true
                    videoOverlayNodes.append(placeholder)
                }
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
            let spacing = Self.gridSpacing
            let gridAttachments = attachments
            let items = imageNodes

            let (frames, positions) = dynamicGridLayout(
                attachments: gridAttachments,
                maxWidth: maxWidth,
                maxHeight: maxH,
                spacing: spacing
            )

            for (i, node) in items.enumerated() {
                guard i < frames.count else { break }
                let frame = frames[i]
                let args = TransformImageArguments(
                    corners: ImageCorners(radius: 0),
                    imageSize: frame.size,
                    boundingSize: frame.size,
                    intrinsicInsets: .zero
                )
                let layout = node.asyncLayout()
                let apply = layout(args)
                apply()
                if i < gridAttachments.count {
                    ensureRemoteImageLoaded(at: i, media: gridAttachments[i], isMultiple: true)
                }
            }

            cachedImageFrames = frames
            cachedPositions = positions
            var totalH: CGFloat = 0
            for frame in frames {
                totalH = max(totalH, frame.maxY)
            }
            cachedTotalSize = CGSize(width: maxWidth, height: ceil(totalH))
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
                let shimmer = shimmerNodes[i]
                shimmer.frame = cachedImageFrames[i]
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
                } else if attachments.first?.isUploading == true || attachments.first?.uploadFailed == true {
                    overlay.frame = imgFrame
                }
            }
        } else if isMultiple {
            for (i, overlay) in videoOverlayNodes.enumerated() {
                guard i < cachedImageFrames.count, !overlay.isHidden else { continue }
                let imgFrame = cachedImageFrames[i]
                if i < attachments.count, attachments[i].isVideo {
                    let sz: CGFloat = 48
                    overlay.frame = CGRect(x: imgFrame.midX - sz / 2, y: imgFrame.midY - sz / 2, width: sz, height: sz)
                } else if i < attachments.count, attachments[i].isUploading || attachments[i].uploadFailed {
                    overlay.frame = imgFrame
                    overlay.cornerRadius = 0
                }
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

        URLSession.shared.dataTask(with: imageURL) { data, _, error in
            if let error {
                SentryLogger.captureMediaError(error, extras: [
                    "where": "MessageMediaContentNode.loadImage",
                    "url": url,
                ])
            }
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

    func currentImage(at index: Int) -> UIImage? {
        guard index >= 0, index < imageNodes.count else { return nil }
        return imageNodes[index].image
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

    private func makeFailedOverlay() -> ASDisplayNode {
        let overlay = ASDisplayNode()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        overlay.cornerRadius = 8.swh
        overlay.clipsToBounds = true
        overlay.isUserInteractionEnabled = false

        let icon = ASImageNode()
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        if let sfImage = UIImage(systemName: "arrow.clockwise.circle.fill", withConfiguration: symbolConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) {
            icon.image = sfImage
        }
        icon.contentMode = .scaleAspectFit
        icon.style.preferredSize = CGSize(width: 40, height: 40)
        overlay.addSubnode(icon)

        overlay.layoutSpecBlock = { _, _ in
            ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: icon)
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
