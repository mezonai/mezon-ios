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
    private let spinnerHost: ASDisplayNode?
    private let percentLabel: ASTextNode2?
    private let barNode: UploadProgressBarNode?
    private let gridCompactMode: Bool

    private static let primeTarget: Double = 0.10
    private static let primeDuration: TimeInterval = 1.5
    private var rampValue: Double = 0
    private var realValue: Double = 0

    init(progress: Double, showsPercent: Bool, gridCompact: Bool = false) {
        gridCompactMode = gridCompact
        if gridCompact {
            spinnerHost = nil
            percentLabel = nil
            barNode = nil
        } else {
            let spinner = ASDisplayNode()
            spinner.setViewBlock {
                let container = UIView()
                container.backgroundColor = .clear
                let indicator = UIActivityIndicatorView.mezonMedium()
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
            spinnerHost = spinner
            if showsPercent {
                barNode = UploadProgressBarNode(
                    progress: min(max(progress, 0), 1),
                    width: 0,
                    height: 3,
                    trackColor: UIColor.white.withAlphaComponent(0.3),
                    fillColor: .white)
                let label = ASTextNode2()
                label.maximumNumberOfLines = 1
                label.truncationMode = .byTruncatingTail
                percentLabel = label
            } else {
                barNode = nil
                percentLabel = nil
            }
        }
        super.init()
        isLayerBacked = false
        backgroundColor = UIColor.black.withAlphaComponent(gridCompact ? 0.35 : 0.4)
        clipsToBounds = true
        isUserInteractionEnabled = false
        if !gridCompact {
            realValue = min(max(progress, 0), 1)
            if let spinnerHost { addSubnode(spinnerHost) }
            if let percentLabel { addSubnode(percentLabel) }
            if let barNode { addSubnode(barNode) }
            if percentLabel != nil { startPriming() }
        }
    }

    private func startPriming() {
        applyDisplay()
        guard realValue < Self.primeTarget else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.primeDuration) { [weak self] in
            guard let self else { return }
            self.rampValue = Self.primeTarget
            self.applyDisplay()
        }
    }

    private func applyDisplay() {
        let shown = min(max(max(rampValue, realValue), 0), 1)
        updatePercentText(shown)
        barNode?.updateProgress(shown)
    }

    private func updatePercentText(_ progress: Double) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        percentLabel?.attributedText = NSAttributedString(
            string: "\(Int(min(max(progress, 0), 1) * 100))%",
            attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para,
            ])
    }

    func setProgress(_ value: Double) {
        guard !gridCompactMode else { return }
        realValue = value
        applyDisplay()
    }

    override func layout() {
        super.layout()
        guard !gridCompactMode else {
            cornerRadius = min(8.swh, min(bounds.width, bounds.height) * 0.12)
            return
        }
        let w = bounds.width
        let h = bounds.height
        cornerRadius = min(8.swh, min(w, h) * 0.12)

        let compact = min(w, h) < 88
        let horizontalPad: CGFloat = 8
        let spinnerSide: CGFloat = compact ? 24 : 32
        let labelHeight: CGFloat = 14
        let barHeight: CGFloat = compact ? 0 : 3
        let spacing: CGFloat = 5

        let hasLabel = percentLabel != nil
        let hasBar = barNode != nil && barHeight > 0

        let stackHeight = spinnerSide
            + (hasLabel ? spacing + labelHeight : 0)
            + (hasBar ? spacing + barHeight : 0)
        var y = max(0, (h - stackHeight) * 0.5)

        spinnerHost?.frame = CGRect(
            x: (w - spinnerSide) * 0.5,
            y: y,
            width: spinnerSide,
            height: spinnerSide)
        y += spinnerSide

        if hasLabel {
            y += spacing
            let labelWidth = max(0, min(w - horizontalPad * 2, 56))
            percentLabel?.frame = CGRect(
                x: (w - labelWidth) * 0.5,
                y: y,
                width: labelWidth,
                height: labelHeight)
            y += labelHeight
        } else {
            percentLabel?.frame = .zero
        }

        if hasBar {
            y += spacing
            let barWidth = max(0, min(w - horizontalPad * 2, 72))
            barNode?.frame = CGRect(
                x: (w - barWidth) * 0.5,
                y: y,
                width: barWidth,
                height: barHeight)
        } else {
            barNode?.frame = .zero
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
        let symbolConfig = MezonSymbolConfiguration(pointSize: 28, weight: .thin)
        iconNode.image = UIImage.mezonSystemImage("photo", withConfiguration: symbolConfig)?
            .mezonTinted(UIColor(white: 0.55, alpha: 1), renderingMode: .alwaysOriginal)
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
    private static let gridDisplayMaxPixelSize: CGFloat = 480
    private static let gridDisplayThumbnailCache = NSCache<NSString, UIImage>()

    private var cachedImageFrames: [CGRect] = []
    private var cachedPositions: [MediaMosaicItemPosition] = []
    private var cachedTotalSize: CGSize = .zero
    private var lastMeasureSignature: String?
    private var isSingleImage = false
    private var isSticker = false
    private var isAnimatedStandaloneImage = false
    private var isMultiple = false
    private var lastRemoteProxyURLByIndex: [Int: String] = [:]
    private var remoteLoadInFlightByIndex: Set<Int> = []
    private var remoteLoadRetryCountByIndex: [Int: Int] = [:]
    private var uploadingOverlayByProgressKey: [String: MediaUploadingOverlayNode] = [:]
    private var slotOverlayKindByIndex: [Int: MediaSlotOverlayKind] = [:]
    private var pendingRevealAnimationIndices: Set<Int> = []

    private enum MediaSlotOverlayKind: Equatable {
        case none
        case play
        case uploading(String)
        case failed
    }

    private static let maxRemoteLoadRetries = 3
    private static let cdnRevealDuration: Double = 0.22
    private static let skeletonFadeDuration: Double = 0.18

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
        remoteLoadInFlightByIndex.removeAll()
        remoteLoadRetryCountByIndex.removeAll()
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
        remoteLoadInFlightByIndex.removeAll()
        remoteLoadRetryCountByIndex.removeAll()
        uploadingOverlayByProgressKey.removeAll()
        slotOverlayKindByIndex.removeAll()
        pendingRevealAnimationIndices.removeAll()
        cachedImageFrames = []
        cachedPositions = []
        lastMeasureSignature = nil

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
            if media[0].isPresignPending {
                let placeholder = makeMediaPlaceholderNode(for: media[0])
                placeholderNodes.append(placeholder)
                addSubnode(placeholder)
            }
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
            node.contentAnimations = []
            if Self.shouldAnimateRemoteReveal(for: att) {
                markSlotForRevealAnimation(at: 0, node: node)
            }
            wireImageLoadCallbacks(index: 0, node: node, skeleton: skeleton, placeholder: placeholder)
            imageNodes.append(node)
            addSubnode(node)
            loadImage(at: 0, into: node, media: att, isMultiple: false)
            setSlotOverlay(at: 0, for: att)
        } else {
            isSticker = false
            isSingleImage = false
            isMultiple = true
            for (i, att) in media.enumerated() {
                let placeholder = makeMediaPlaceholderNode(for: att)
                placeholderNodes.append(placeholder)
                addSubnode(placeholder)
                let skeleton = addSkeletonNode(at: i, cornerRadius: 0, for: att)
                let node = TransformImageNode()
                node.isUserInteractionEnabled = false
                node.contentAnimations = []
                if Self.shouldAnimateRemoteReveal(for: att) {
                    markSlotForRevealAnimation(at: i, node: node)
                }
                wireImageLoadCallbacks(index: i, node: node, skeleton: skeleton, placeholder: placeholder)
                imageNodes.append(node)
                addSubnode(node)
                loadImage(at: i, into: node, media: att, isMultiple: true)
                setSlotOverlay(at: i, for: att)
            }
        }

        if isNodeLoaded {
            attachMediaTapGesture()
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let signature = measureGeometrySignature(maxWidth: maxWidth)
        if signature == lastMeasureSignature, cachedTotalSize != .zero {
            return cachedTotalSize
        }
        lastMeasureSignature = signature

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
            let (frames, positions) = dynamicGridLayout(
                attachments: attachments,
                maxWidth: maxWidth,
                maxHeight: maxH,
                spacing: spacing
            )

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

    private func measureGeometrySignature(maxWidth: CGFloat) -> String {
        let flags = "\(isSticker ? 1 : 0)\(isAnimatedStandaloneImage ? 1 : 0)\(isSingleImage ? 1 : 0)\(isMultiple ? 1 : 0)"
        let dims = attachments.map { "\($0.width ?? -1)x\($0.height ?? -1)" }.joined(separator: ",")
        return "\(Int(maxWidth))|\(flags)|\(dims)"
    }

    override func layout() {
        super.layout()

        if isSticker {
            stickerNode?.frame = CGRect(origin: .zero, size: cachedTotalSize)
            placeholderNodes.first?.frame = CGRect(origin: .zero, size: cachedTotalSize)
            return
        }

        for (i, node) in imageNodes.enumerated() {
            guard i < cachedImageFrames.count else { break }
            let frame = cachedImageFrames[i]
            node.frame = frame
            let cornerRadius: CGFloat = isSingleImage ? 8.swh : 0
            let args = TransformImageArguments(
                corners: ImageCorners(radius: cornerRadius),
                imageSize: frame.size,
                boundingSize: frame.size,
                intrinsicInsets: .zero
            )
            if shouldRefreshImageArguments(node: node, args: args) {
                node.setArguments(args)
            }
            skeletonNodesByIndex[i]?.frame = frame
            if i < placeholderNodes.count {
                placeholderNodes[i].frame = frame
            }
        }


        if isSingleImage {
            if let overlay = videoOverlayNodes.first, !overlay.isHidden {
                let imgFrame = cachedImageFrames.first ?? bounds
                switch slotOverlayKindByIndex[0] {
                case .play:
                    let sz: CGFloat = 48
                    overlay.frame = CGRect(
                        x: imgFrame.midX - sz / 2,
                        y: imgFrame.midY - sz / 2,
                        width: sz, height: sz
                    )
                case .uploading, .failed:
                    overlay.frame = imgFrame
                default:
                    break
                }
            }
        } else if isMultiple {
            for (i, overlay) in videoOverlayNodes.enumerated() {
                guard i < cachedImageFrames.count, !overlay.isHidden else { continue }
                let imgFrame = cachedImageFrames[i]
                switch slotOverlayKindByIndex[i] {
                case .play:
                    let sz: CGFloat = 48
                    overlay.frame = CGRect(x: imgFrame.midX - sz / 2, y: imgFrame.midY - sz / 2, width: sz, height: sz)
                case .uploading, .failed:
                    overlay.frame = imgFrame
                default:
                    break
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
        if attachment.isSticker { return true }
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
        guard !media.isPresignPending else { return }
        let sourceURL = ImgproxyURL.secureURLString(from: media.url)
        let url = media.isSticker
            ? ImgproxyURL.attachmentURL(
                from: sourceURL,
                width: 400,
                height: 400,
                resizeType: "fit",
                forceProxy: true
            )
            : sourceURL
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
        guard let urls = remoteImageURLs(for: media) else { return }
        guard index < imageNodes.count else { return }
        let node = imageNodes[index]
        let proxyURL = urls.proxyURL
        let sourceURL = urls.sourceURL
        let resizeMode: ImageResizeMode = isMultiple ? .fill : .fit
        if lastRemoteProxyURLByIndex[index] == proxyURL {
            if node.image != nil { return }
            if remoteLoadInFlightByIndex.contains(index) { return }
        } else {
            lastRemoteProxyURLByIndex[index] = proxyURL
            if node.image == nil {
                node.reset()
                if let skeleton = skeletonNodesByIndex[index], skeleton.supernode == nil {
                    insertSubnode(skeleton, belowSubnode: node)
                }
                skeletonNodesByIndex[index]?.isHidden = false
            }
        }
        remoteLoadInFlightByIndex.insert(index)
        let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
            || ImageCache.shared.memoryImage(forKey: sourceURL) != nil
        node.setSignal(
            remoteAttachmentImageSignal(proxyURL: proxyURL, originalURL: sourceURL, resizeMode: resizeMode),
            attemptSynchronously: hasMem
        )
    }

    private func loadImage(at index: Int, into node: TransformImageNode, media: ParsedAttachment, isMultiple: Bool) {
        if media.isPresignPending {
            return
        }
        if media.uploadFailed {
            return
        }
        if let localImage = media.localImage {
            if isMultiple {
                let cacheKey = media.uploadProgressKey.isEmpty
                    ? "grid-\(index)"
                    : media.uploadProgressKey
                node.setSignal(
                    Self.localGridImageSignal(image: localImage, cacheKey: cacheKey),
                    attemptSynchronously: false
                )
            } else {
                node.setSignal(staticImageSignal(image: localImage), attemptSynchronously: true)
            }
        } else if media.isVideo && media.thumbnail.isEmpty {
            node.setSignal(videoThumbnailSignal(url: media.url, resizeMode: .fill), attemptSynchronously: false)
        } else if !media.url.isEmpty || (media.isVideo && !media.thumbnail.isEmpty) {
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

    func displayImage(at index: Int) -> UIImage? {
        guard index >= 0, index < imageNodes.count else { return nil }
        let node = imageNodes[index]
        if let image = node.image {
            return image
        }
        guard let contents = node.layer.contents else { return nil }
        let typeID = CFGetTypeID(contents as CFTypeRef)
        guard typeID == CGImage.typeID else { return nil }
        return UIImage(cgImage: contents as! CGImage)
    }

    @discardableResult
    func updateUploadProgress(progressKey: String, progress: Double) -> Bool {
        guard !progressKey.isEmpty, let overlay = uploadingOverlayByProgressKey[progressKey] else { return false }
        overlay.setProgress(progress)
        return true
    }

    func updateUploadOverlays(media: [ParsedAttachment]) {
        let oldMedia = attachments
        guard media.count == oldMedia.count else {
            configure(media: media)
            return
        }
        _ = applyMediaIncrementalUpdate(from: oldMedia, to: media)
    }

    func applyMediaDimensionsUpdate(media: [ParsedAttachment]) {
        let oldMedia = attachments
        guard media.count == oldMedia.count else {
            configure(media: media)
            return
        }
        _ = applyMediaIncrementalUpdate(from: oldMedia, to: media)
    }

    @discardableResult
    func applyMediaUploadStateUpdate(media: [ParsedAttachment]) -> Bool {
        let oldMedia = attachments
        guard media.count == oldMedia.count else {
            configure(media: media)
            return true
        }
        return applyMediaIncrementalUpdate(from: oldMedia, to: media)
    }

    @discardableResult
    func applyMediaIncrementalUpdate(from oldMedia: [ParsedAttachment], to newMedia: [ParsedAttachment]) -> Bool {
        guard newMedia.count == attachments.count, oldMedia.count == newMedia.count else {
            configure(media: newMedia)
            return true
        }
        guard ParsedAttachment.attachmentsIdentityEqual(oldMedia, newMedia) else {
            configure(media: newMedia)
            return true
        }

        var changedSlotIndices: [Int] = []
        changedSlotIndices.reserveCapacity(newMedia.count)
        var dimsChanged = false
        for (i, att) in newMedia.enumerated() {
            let old = oldMedia[i]
            if !dimsChanged,
               old.width != att.width || old.height != att.height || old.durationSeconds != att.durationSeconds {
                dimsChanged = true
            }
            if !ParsedAttachment.slotPresentationEqual(old, att)
                || slotOverlayKind(for: att) != (slotOverlayKindByIndex[i] ?? .none) {
                changedSlotIndices.append(i)
            }
        }
        guard !changedSlotIndices.isEmpty || dimsChanged else {
            return false
        }

        var needsLayout = dimsChanged
        for i in changedSlotIndices {
            let old = oldMedia[i]
            let att = newMedia[i]

            let presignBecameReady = old.isPresignPending && !att.isPresignPending && !att.uploadFailed
            let uploadHandedOff = old.localImage != nil && att.localImage == nil && !att.url.isEmpty
                && !att.isPresignPending && !att.isUploading && !att.uploadFailed

            let newKind = slotOverlayKind(for: att)
            let oldKind = slotOverlayKindByIndex[i] ?? .none
            if newKind != oldKind {
                setSlotOverlay(at: i, for: att)
                if newKind != .none {
                    needsLayout = true
                }
            } else if old.isUploading && att.isUploading,
                      case .uploading(let key) = newKind, !key.isEmpty {
                uploadingOverlayByProgressKey[key]?.setProgress(att.uploadProgress)
            }

            if presignBecameReady || uploadHandedOff {
                if isSticker {
                    if let sticker = stickerNode {
                        if i < placeholderNodes.count {
                            placeholderNodes[i].isHidden = true
                        }
                        loadStickerImage(media: att, into: sticker)
                    }
                    continue
                }
                let alreadyLoaded = i < imageNodes.count && imageNodes[i].image != nil
                if presignBecameReady && alreadyLoaded {
                    if i < placeholderNodes.count {
                        placeholderNodes[i].isHidden = true
                    }
                    skeletonNodesByIndex[i]?.isHidden = true
                } else {
                    beginLoadingSlot(at: i, media: att, replacingLocal: uploadHandedOff)
                }
                if newKind == .play {
                    needsLayout = true
                }
            }
        }

        attachments = newMedia
        let newUploading = newMedia.contains { $0.isUploading }
        if isUploading != newUploading {
            isUploading = newUploading
        }
        if dimsChanged {
            lastMeasureSignature = nil
        }
        if needsLayout {
            setNeedsLayout()
        }
        return needsLayout
    }

    private func shouldRefreshImageArguments(node: TransformImageNode, args: TransformImageArguments) -> Bool {
        guard let current = node.currentArguments else { return true }
        if node.image == nil && node.layer.contents == nil {
            return current != args
        }
        if current.corners != args.corners {
            return true
        }
        let dw = abs(current.boundingSize.width - args.boundingSize.width)
        let dh = abs(current.boundingSize.height - args.boundingSize.height)
        return dw > 0.5 || dh > 0.5
    }

    private func beginLoadingSlot(at index: Int, media: ParsedAttachment, replacingLocal: Bool = false) {
        guard index < imageNodes.count else { return }
        if index < placeholderNodes.count {
            placeholderNodes[index].isHidden = true
        }
        let node = imageNodes[index]
        node.contentAnimations = []
        if replacingLocal {
            node.reset()
            lastRemoteProxyURLByIndex.removeValue(forKey: index)
        }
        markSlotForRevealAnimation(at: index, node: node)
        guard !hasCachedRemoteImage(for: media) else {
            loadImage(at: index, into: node, media: media, isMultiple: isMultiple)
            return
        }
        if skeletonNodesByIndex[index] == nil {
            let cornerRadius: CGFloat = isSingleImage ? 8.swh : 0
            if let skeleton = addSkeletonNode(at: index, cornerRadius: cornerRadius, for: media) {
                insertSubnode(skeleton, belowSubnode: node)
            }
        } else {
            skeletonNodesByIndex[index]?.isHidden = false
            skeletonNodesByIndex[index]?.alpha = 1
        }
        loadImage(at: index, into: node, media: media, isMultiple: isMultiple)
    }

    private static func shouldAnimateRemoteReveal(for media: ParsedAttachment) -> Bool {
        if media.uploadFailed || media.isPresignPending || media.isUploading { return false }
        if media.localImage != nil { return false }
        if media.isVideo {
            return !media.thumbnail.isEmpty || !media.url.isEmpty
        }
        return !media.url.isEmpty
    }

    private func markSlotForRevealAnimation(at index: Int, node: TransformImageNode) {
        pendingRevealAnimationIndices.insert(index)
        node.alpha = 0
    }

    private func revealLoadedImage(
        at index: Int,
        skeleton: MediaSkeletonNode?,
        placeholder: MediaPlaceholderNode?
    ) {
        placeholder?.isHidden = true
        skeletonNodesByIndex.removeValue(forKey: index)
        fadeOutAndRemoveSkeleton(skeleton)
        guard index < imageNodes.count else { return }
        let node = imageNodes[index]
        node.alpha = 1
        node.layer.animateAlpha(
            from: 0,
            to: 1,
            duration: Self.cdnRevealDuration,
            timingFunction: CAMediaTimingFunctionName.easeOut.rawValue
        )
    }

    private func fadeOutAndRemoveSkeleton(_ skeleton: MediaSkeletonNode?) {
        guard let skeleton else { return }
        skeleton.layer.removeAnimation(forKey: "mediaSkeleton")
        skeleton.layer.animateAlpha(
            from: skeleton.alpha,
            to: 0,
            duration: Self.skeletonFadeDuration,
            timingFunction: CAMediaTimingFunctionName.easeOut.rawValue,
            removeOnCompletion: false
        ) { [weak skeleton] _ in
            skeleton?.removeFromSupernode()
        }
    }

    private func hasCachedRemoteImage(for media: ParsedAttachment) -> Bool {
        guard let urls = remoteImageURLs(for: media) else { return false }
        return ImageCache.shared.memoryImage(forKey: urls.proxyURL) != nil
            || ImageCache.shared.memoryImage(forKey: urls.sourceURL) != nil
    }

    private func remoteImageURLs(for media: ParsedAttachment) -> (sourceURL: String, proxyURL: String)? {
        let sourceURL: String
        if media.isVideo {
            guard !media.thumbnail.isEmpty else { return nil }
            sourceURL = media.thumbnail
        } else {
            sourceURL = media.url
        }
        guard !sourceURL.isEmpty else { return nil }
        let proxyURL = ImgproxyURL.attachmentURL(
            from: sourceURL,
            width: 400,
            height: 400,
            resizeType: isMultiple ? "fill" : "fit"
        )
        return (sourceURL, proxyURL)
    }

    private func slotOverlayKind(for att: ParsedAttachment) -> MediaSlotOverlayKind {
        if att.isUploading { return .uploading(att.uploadProgressKey) }
        if att.uploadFailed { return .failed }
        if att.isVideo && !att.isPresignPending { return .play }
        return .none
    }

    private func makeOverlayNode(for att: ParsedAttachment) -> ASDisplayNode {
        switch slotOverlayKind(for: att) {
        case .uploading:
            return addUploadingOverlay(for: att)
        case .failed:
            return makeFailedOverlay()
        case .play:
            return makePlayOverlayNode()
        case .none:
            let node = ASDisplayNode()
            node.isHidden = true
            return node
        }
    }

    private func setSlotOverlay(at index: Int, for att: ParsedAttachment) {
        let kind = slotOverlayKind(for: att)
        if slotOverlayKindByIndex[index] == kind, index < videoOverlayNodes.count {
            videoOverlayNodes[index].isHidden = kind == .none
            return
        }
        if index < videoOverlayNodes.count {
            let old = videoOverlayNodes[index]
            if let priorKind = slotOverlayKindByIndex[index],
               case .uploading(let key) = priorKind, !key.isEmpty {
                uploadingOverlayByProgressKey.removeValue(forKey: key)
            }
            old.removeFromSupernode()
        }
        let overlay = makeOverlayNode(for: att)
        if index < videoOverlayNodes.count {
            videoOverlayNodes[index] = overlay
        } else {
            videoOverlayNodes.append(overlay)
        }
        slotOverlayKindByIndex[index] = kind
        addSubnode(overlay)
        overlay.isHidden = kind == .none
    }

    private func addUploadingOverlay(for attachment: ParsedAttachment, gridCompact: Bool = false) -> MediaUploadingOverlayNode {
        let overlay = MediaUploadingOverlayNode(progress: attachment.uploadProgress, showsPercent: attachment.uploadShowsPercent, gridCompact: gridCompact)
        let key = attachment.uploadProgressKey
        if !key.isEmpty {
            uploadingOverlayByProgressKey[key] = overlay
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
        let symbolConfig = MezonSymbolConfiguration(pointSize: 30, weight: .semibold)
        if let sfImage = UIImage.mezonSystemImage("arrow.clockwise.circle.fill", withConfiguration: symbolConfig)?
            .mezonTinted(.white, renderingMode: .alwaysOriginal) {
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
        let symbolConfig = MezonSymbolConfiguration(pointSize: 18, weight: .medium)
        if let sfImage = UIImage.mezonSystemImage("play.fill", withConfiguration: symbolConfig)?.mezonTinted(.white, renderingMode: .alwaysOriginal) {
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

    private static func gridDisplayThumbnail(from image: UIImage, cacheKey: String) -> UIImage {
        let normalizedKey = "\(cacheKey)|\(Int(image.size.width))x\(Int(image.size.height))" as NSString
        if let cached = gridDisplayThumbnailCache.object(forKey: normalizedKey) {
            return cached
        }
        let maxPixelSize = gridDisplayMaxPixelSize
        let maxDim = max(image.size.width, image.size.height)
        let thumb: UIImage
        if maxDim <= maxPixelSize {
            thumb = image
        } else {
            let scale = maxPixelSize / maxDim
            let newSize = CGSize(
                width: max(1, floor(image.size.width * scale)),
                height: max(1, floor(image.size.height * scale))
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            thumb = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
        gridDisplayThumbnailCache.setObject(thumb, forKey: normalizedKey)
        return thumb
    }

    private static func localGridImageSignal(
        image: UIImage,
        cacheKey: String
    ) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
        return Signal { subscriber in
            let cancelled = Atomic<Bool>(value: false)
            let disposable = MetaDisposable()
            Queue.concurrentDefaultQueue().async {
                guard !cancelled.with({ $0 }) else { return }
                let thumb = gridDisplayThumbnail(from: image, cacheKey: cacheKey)
                guard !cancelled.with({ $0 }) else { return }
                disposable.set(
                    staticImageSignal(image: thumb, resizeMode: .fill).start(next: { value in
                        subscriber.putNext(value)
                    }, completed: {
                        subscriber.putCompletion()
                    })
                )
            }
            return ActionDisposable {
                let _ = cancelled.modify { _ in true }
                disposable.dispose()
            }
        }
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

    private func scheduleRemoteImageRetry(at index: Int) {
        let retries = remoteLoadRetryCountByIndex[index, default: 0]
        guard retries < Self.maxRemoteLoadRetries else { return }
        guard index < attachments.count else { return }
        remoteLoadRetryCountByIndex[index] = retries + 1
        lastRemoteProxyURLByIndex.removeValue(forKey: index)
        let delay = 0.8 * Double(retries + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, index < self.attachments.count else { return }
            self.ensureRemoteImageLoaded(
                at: index,
                media: self.attachments[index],
                isMultiple: self.isMultiple
            )
        }
    }

    private func wireImageLoadCallbacks(
        index: Int,
        node: TransformImageNode,
        skeleton: MediaSkeletonNode?,
        placeholder: MediaPlaceholderNode
    ) {
        node.imageUpdated = { [weak self, weak skeleton, weak placeholder] image in
            guard let self else { return }
            self.remoteLoadInFlightByIndex.remove(index)
            if image != nil {
                self.remoteLoadRetryCountByIndex.removeValue(forKey: index)
                if self.pendingRevealAnimationIndices.remove(index) != nil {
                    self.revealLoadedImage(at: index, skeleton: skeleton, placeholder: placeholder)
                } else {
                    skeleton?.removeFromSupernode()
                    self.skeletonNodesByIndex.removeValue(forKey: index)
                    placeholder?.isHidden = true
                }
            } else if index < self.attachments.count {
                if index < self.imageNodes.count,
                   self.imageNodes[index].image != nil || self.imageNodes[index].layer.contents != nil {
                    return
                }
                let media = self.attachments[index]
                if Self.shouldShowStaticPlaceholder(for: media) {
                    skeleton?.isHidden = true
                    placeholder?.isHidden = false
                } else if Self.shouldShowLoadingSkeleton(for: media) {
                    skeleton?.isHidden = false
                    placeholder?.isHidden = true
                    self.scheduleRemoteImageRetry(at: index)
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
