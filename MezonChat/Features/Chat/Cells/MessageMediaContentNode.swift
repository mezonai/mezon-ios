import UIKit
import AsyncDisplayKit

private final class MediaSkeletonNode: ASDisplayNode {
    private let gradientLayer = CAGradientLayer()
    private let skeletonCornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.skeletonCornerRadius = cornerRadius
        super.init()
        isLayerBacked = true
        self.cornerRadius = skeletonCornerRadius
        clipsToBounds = true
    }

    override func didLoad() {
        super.didLoad()
        let t = UIColor.theme
        backgroundColor = t.secondaryLight
        gradientLayer.colors = [
            t.secondaryLight.cgColor,
            t.tertiary.cgColor,
            t.secondaryLight.cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientLayer.locations = [0, 0.5, 1]
        gradientLayer.cornerRadius = skeletonCornerRadius
        layer.addSublayer(gradientLayer)
        startAnimation()
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
        gradientLayer.cornerRadius = skeletonCornerRadius
    }

    private func startAnimation() {
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [0, 0, 0.25]
        anim.toValue = [0.75, 1, 1]
        anim.duration = 1.2
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.add(anim, forKey: "mediaSkeleton")
    }
}

private final class MediaUploadingOverlayNode: ASDisplayNode {
    private let spinnerHost = ASDisplayNode()
    private let percentLabel = ASTextNode2()
    private let barNode: UploadProgressBarNode

    init(progress: Double) {
        barNode = UploadProgressBarNode(
            progress: progress,
            width: 0,
            height: 3,
            trackColor: UIColor.white.withAlphaComponent(0.3),
            fillColor: .white)
        super.init()
        isLayerBacked = false
        backgroundColor = UIColor.black.withAlphaComponent(0.4)
        clipsToBounds = true
        isUserInteractionEnabled = false
        spinnerHost.setViewBlock {
            let container = UIView()
            container.backgroundColor = .clear
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = .white
            indicator.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                indicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            indicator.startAnimating()
            return container
        }
        percentLabel.maximumNumberOfLines = 1
        percentLabel.truncationMode = .byTruncatingTail
        updatePercentText(progress)
        addSubnode(spinnerHost)
        addSubnode(percentLabel)
        addSubnode(barNode)
    }

    private func updatePercentText(_ progress: Double) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        percentLabel.attributedText = NSAttributedString(
            string: "\(Int(min(max(progress, 0), 1) * 100))%",
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para,
            ])
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        cornerRadius = min(8.swh, min(w, h) * 0.12)

        let compact = min(w, h) < 88
        let horizontalPad: CGFloat = 8
        let spinnerSide: CGFloat = compact ? 24 : 32
        let labelHeight: CGFloat = 14
        let barHeight: CGFloat = compact ? 0 : 3
        let spacing: CGFloat = 5

        let stackHeight = spinnerSide + spacing + labelHeight + (barHeight > 0 ? spacing + barHeight : 0)
        var y = max(0, (h - stackHeight) * 0.5)

        spinnerHost.frame = CGRect(
            x: (w - spinnerSide) * 0.5,
            y: y,
            width: spinnerSide,
            height: spinnerSide)
        y += spinnerSide + spacing

        let labelMaxWidth = max(0, min(w - horizontalPad * 2, 56))
        let measuredLabel = percentLabel.measure(CGSize(width: labelMaxWidth, height: labelHeight))
        let labelWidth = min(labelMaxWidth, max(measuredLabel.width, 1))
        percentLabel.frame = CGRect(
            x: (w - labelWidth) * 0.5,
            y: y,
            width: labelWidth,
            height: labelHeight)
        y += labelHeight

        if barHeight > 0 {
            y += spacing
            let barWidth = max(0, min(w - horizontalPad * 2, 72))
            barNode.frame = CGRect(
                x: (w - barWidth) * 0.5,
                y: y,
                width: barWidth,
                height: barHeight)
        } else {
            barNode.frame = .zero
        }
    }
}

private final class MediaPlaceholderNode: ASDisplayNode {
    private let iconNode = ASImageNode()

    override init() {
        super.init()
        isLayerBacked = false
        cornerRadius = 0
        clipsToBounds = true
        backgroundColor = UIColor(white: 0.18, alpha: 1)
        automaticallyManagesSubnodes = true
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .thin)
        iconNode.image = UIImage(systemName: "photo", withConfiguration: symbolConfig)?
            .withTintColor(UIColor(white: 0.55, alpha: 1), renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 36, height: 36)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: iconNode)
    }
}

final class MessageMediaContentNode: ASDisplayNode {

    private var imageNodes: [TransformImageNode] = []
    private var videoOverlayNodes: [ASDisplayNode] = []
    private var skeletonNodesByIndex: [Int: MediaSkeletonNode] = [:]
    private var placeholderNodes: [MediaPlaceholderNode] = []
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
    private var isAnimatedStandaloneImage = false
    private var isMultiple = false
    private var lastRemoteProxyURLByIndex: [Int: String] = [:]

    private var mediaTapGesture: UITapGestureRecognizer?

    override init() {
        super.init()
        isUserInteractionEnabled = true
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
        isAnimatedStandaloneImage = false
        isSingleImage = false
        isMultiple = false
        guard !media.isEmpty else { return }
        let isGifType = media.count == 1 && Self.isGifImageAttachment(media[0])
        if media.count == 1, media[0].isSticker || isGifType {
            isSticker = true
            isAnimatedStandaloneImage = isGifType && !media[0].isSticker
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
        skeletonNodesByIndex.values.forEach { $0.removeFromSupernode() }
        skeletonNodesByIndex.removeAll()
        placeholderNodes.forEach { $0.removeFromSupernode() }
        placeholderNodes.removeAll()
        stickerNode?.removeFromSupernode()
        stickerNode = nil
        attachments = media
        lastRemoteProxyURLByIndex.removeAll()
        cachedImageFrames = []
        cachedPositions = []

        isUploading = media.contains { $0.isUploading }

        guard !media.isEmpty else { return }


        let isGifType = media.count == 1 && Self.isGifImageAttachment(media[0])
        if media.count == 1, media[0].isSticker || isGifType {
            isSticker = true
            isAnimatedStandaloneImage = isGifType && !media[0].isSticker
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
            loadStickerImage(media: media[0], into: node)
        } else if media.count == 1 {
            isSticker = false
            isSingleImage = true
            isMultiple = false
            let att = media[0]
            let placeholder = makeMediaPlaceholderNode(for: att)
            placeholderNodes.append(placeholder)
            addSubnode(placeholder)
            let skeleton = addSkeletonNode(at: 0, cornerRadius: 8.swh, for: att)
            let node = TransformImageNode()
            node.isUserInteractionEnabled = false
            node.contentAnimations = [.firstUpdate]
            wireImageLoadCallbacks(index: 0, node: node, skeleton: skeleton, placeholder: placeholder)
            imageNodes.append(node)
            addSubnode(node)
            loadImage(at: 0, into: node, media: att, isMultiple: false, measuredPtSize: nil)

            if media[0].isVideo, !media[0].isPresignPending, !media[0].isUploading {
                let overlay = makePlayOverlayNode()
                videoOverlayNodes.append(overlay)
                addSubnode(overlay)
            }
            if media[0].isUploading {
                let overlay = makeUploadingOverlay(progress: media[0].uploadProgress)
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
                let placeholder = makeMediaPlaceholderNode(for: att)
                placeholderNodes.append(placeholder)
                addSubnode(placeholder)
                let skeleton = addSkeletonNode(at: i, cornerRadius: 0, for: att)
                let node = TransformImageNode()
                node.isUserInteractionEnabled = false
                node.contentAnimations = [.firstUpdate]
                wireImageLoadCallbacks(index: i, node: node, skeleton: skeleton, placeholder: placeholder)
                imageNodes.append(node)
                addSubnode(node)
                loadImage(at: i, into: node, media: att, isMultiple: true, measuredPtSize: nil)

                if att.isVideo, !att.isPresignPending, !att.isUploading {
                    let overlay = makePlayOverlayNode()
                    videoOverlayNodes.append(overlay)
                    addSubnode(overlay)
                } else if att.isUploading {
                    let overlay = makeUploadingOverlay(progress: att.uploadProgress)
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

        if isNodeLoaded {
            attachMediaTapGesture()
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let maxH = UIScreen.main.bounds.height * 0.5
        cachedImageFrames = []

        if isSticker {
            if isAnimatedStandaloneImage {
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
            skeletonNodesByIndex[i]?.frame = cachedImageFrames[i]
            if i < placeholderNodes.count {
                placeholderNodes[i].frame = cachedImageFrames[i]
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
                }
            }
        }
    }


    private static func isGifImageAttachment(_ attachment: ParsedAttachment) -> Bool {
        let filetype = attachment.filetype
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mime = filetype.split(separator: ";", maxSplits: 1).first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? filetype
        if mime == "image/gif" || mime == "gif" {
            return true
        }
        return ["gif"].contains(pathExtension(from: attachment.filename))
            || ["gif"].contains(pathExtension(from: attachment.url))
    }

    private static func isAnimatedImageAttachment(_ attachment: ParsedAttachment) -> Bool {
        if isGifImageAttachment(attachment) { return true }
        let filetype = attachment.filetype
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mime = filetype.split(separator: ";", maxSplits: 1).first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? filetype
        if mime == "image/webp" || mime == "webp" {
            return true
        }
        return ["webp"].contains(pathExtension(from: attachment.filename))
            || ["webp"].contains(pathExtension(from: attachment.url))
    }

    private static func pathExtension(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let components = URLComponents(string: trimmed), !components.path.isEmpty {
            return (components.path as NSString).pathExtension.lowercased()
        }
        return (trimmed as NSString).pathExtension.lowercased()
    }

    private func loadStickerImage(media: ParsedAttachment, into node: ASDisplayNode) {
        let url = ImgproxyURL.secureURLString(from: media.url)
        guard let imageURL = URL(string: url), !url.isEmpty else { return }
        let isAnimatedImage = Self.isAnimatedImageAttachment(media)

        if let cachedData = ImageCache.shared.cachedData(forKey: url) {
            if let animated = UIImage.animatedImage(from: cachedData) ?? UIImage.decodeImage(from: cachedData) {
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
            if !isAnimatedImage || (cached.images?.count ?? 0) > 1 {
                return
            }
        }

        URLSession.shared.dataTask(with: imageURL) { data, _, error in
            if let error {
                SentryLogger.captureMediaError(error, extras: [
                    "where": "MessageMediaContentNode.loadStickerImage",
                    "url": url,
                ])
            }
            guard let data else { return }
            let image = isAnimatedImage
                ? (UIImage.animatedImage(from: data) ?? UIImage.decodeImage(from: data))
                : UIImage.decodeImage(from: data)
            if let image {
                ImageCache.shared.setImage(image, data: data, forKey: url)
                DispatchQueue.main.async {
                    (node.view as? UIImageView)?.image = image
                }
            }
        }.resume()
    }

    private func ensureRemoteImageLoaded(at index: Int, media: ParsedAttachment, isMultiple: Bool) {
        guard media.localImage == nil else { return }
        guard !media.isPresignPending else { return }
        let sourceURL: String
        if media.isVideo {
            guard !media.thumbnail.isEmpty else { return }
            sourceURL = media.thumbnail
        } else {
            sourceURL = media.url
        }
        guard !sourceURL.isEmpty else { return }
        guard index < imageNodes.count else { return }
        let node = imageNodes[index]
        let w = 400
        let h = 400
        let resizeMode: ImageResizeMode = isMultiple ? .fill : .fit
        let proxyURL = ImgproxyURL.attachmentURL(
            from: sourceURL,
            width: w,
            height: h,
            resizeType: isMultiple ? "fill" : "fit"
        )
        if lastRemoteProxyURLByIndex[index] == proxyURL, node.image != nil { return }
        lastRemoteProxyURLByIndex[index] = proxyURL
        node.reset()
        if let skeleton = skeletonNodesByIndex[index], skeleton.supernode == nil {
            insertSubnode(skeleton, belowSubnode: node)
        }
        skeletonNodesByIndex[index]?.isHidden = false
        let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
            || ImageCache.shared.memoryImage(forKey: sourceURL) != nil
        node.setSignal(
            remoteAttachmentImageSignal(proxyURL: proxyURL, originalURL: sourceURL, resizeMode: resizeMode),
            attemptSynchronously: hasMem
        )
    }

    private func loadImage(at index: Int, into node: TransformImageNode, media: ParsedAttachment, isMultiple: Bool, measuredPtSize: CGSize?) {
        if media.isPresignPending {
            return
        }
        if let localImage = media.localImage {
            node.setSignal(staticImageSignal(image: localImage), attemptSynchronously: true)
        } else if media.isVideo && media.thumbnail.isEmpty {
            node.setSignal(videoThumbnailSignal(url: media.url, resizeMode: .fill), attemptSynchronously: false)
        } else if measuredPtSize != nil {
            ensureRemoteImageLoaded(at: index, media: media, isMultiple: isMultiple)
        }
    }

    private func attachMediaTapGesture() {
        guard isNodeLoaded else { return }
        isUserInteractionEnabled = true
        view.isUserInteractionEnabled = true
        guard mediaTapGesture == nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMediaTap(_:)))
        view.addGestureRecognizer(tap)
        mediaTapGesture = tap
    }

    override func didLoad() {
        super.didLoad()
        attachMediaTapGesture()
    }

    @objc private func handleMediaTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        let index: Int?
        if isSticker {
            let bounds = CGRect(origin: .zero, size: cachedTotalSize)
            index = bounds.contains(point) ? 0 : nil
        } else {
            index = cachedImageFrames.enumerated().first(where: { $1.contains(point) })?.offset
        }
        guard let index else { return }
        onImageTapped?(index)
    }

    func currentImage(at index: Int) -> UIImage? {
        guard index >= 0, index < imageNodes.count else { return nil }
        return imageNodes[index].image
    }

    private func makeUploadingOverlay(progress: Double = 0) -> ASDisplayNode {
        MediaUploadingOverlayNode(progress: progress)
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

    private static func shouldShowLoadingSkeleton(for media: ParsedAttachment) -> Bool {
        if media.uploadFailed { return false }
        if media.localImage != nil { return false }
        if media.isPresignPending { return false }
        return true
    }

    private static func shouldShowStaticPlaceholder(for media: ParsedAttachment) -> Bool {
        media.isPresignPending || media.uploadFailed
    }

    @discardableResult
    private func addSkeletonNode(at index: Int, cornerRadius: CGFloat, for media: ParsedAttachment) -> MediaSkeletonNode? {
        guard Self.shouldShowLoadingSkeleton(for: media) else { return nil }
        let skeleton = MediaSkeletonNode(cornerRadius: cornerRadius)
        skeleton.isUserInteractionEnabled = false
        skeletonNodesByIndex[index] = skeleton
        addSubnode(skeleton)
        return skeleton
    }

    private func wireImageLoadCallbacks(
        index: Int,
        node: TransformImageNode,
        skeleton: MediaSkeletonNode?,
        placeholder: MediaPlaceholderNode
    ) {
        node.imageUpdated = { [weak self, weak node, weak skeleton, weak placeholder] _ in
            guard let self, let node else { return }
            if node.image != nil {
                skeleton?.removeFromSupernode()
                self.skeletonNodesByIndex.removeValue(forKey: index)
                placeholder?.isHidden = true
            } else if index < self.attachments.count {
                let media = self.attachments[index]
                if Self.shouldShowStaticPlaceholder(for: media) {
                    skeleton?.isHidden = true
                    placeholder?.isHidden = false
                } else if Self.shouldShowLoadingSkeleton(for: media) {
                    skeleton?.isHidden = false
                    placeholder?.isHidden = true
                }
            }
        }
    }

    private func makeMediaPlaceholderNode(for media: ParsedAttachment) -> MediaPlaceholderNode {
        let node = MediaPlaceholderNode()
        node.isHidden = !Self.shouldShowStaticPlaceholder(for: media)
        node.isUserInteractionEnabled = false
        return node
    }
}
