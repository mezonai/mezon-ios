import AsyncDisplayKit
import UIKit

@MainActor
final class MediaGalleryNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var attachments: [Mezon_Api_ChannelAttachment] = []
    private var didLoadMedia = false
    private var mediaFetchCompleted = false
    private var isLoadingMore = false
    private var hasMoreMedia = true
    private let mediaPageLimit: Int32 = 50

    private let collectionNode: ASCollectionNode
    private let loadingHostNode: ASDisplayNode
    private let emptyStateNode: MediaEmptyStateNode
    private let overlayBackdropNode: ASDisplayNode
    private let flowLayout: UICollectionViewFlowLayout

    init(context: AccountContext, clanId: Int64, channelId: Int64, channelType: Int32) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.channelType = channelType

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        layout.sectionInset = .zero
        let provisionalWidth = max(1, UIScreen.main.bounds.width - 32 - 32)
        let provisionalSide = max(96, floor((provisionalWidth - 2 * 2) / 3))
        layout.itemSize = CGSize(width: provisionalSide, height: provisionalSide)
        self.flowLayout = layout

        self.collectionNode = ASCollectionNode(collectionViewLayout: layout)

        self.loadingHostNode = ASDisplayNode(viewBlock: {
            let v = UIActivityIndicatorView(style: .large)
            v.color = UIColor.theme.textStrong
            v.startAnimating()
            return v
        })
        self.emptyStateNode = MediaEmptyStateNode()
        self.overlayBackdropNode = ASDisplayNode()
        overlayBackdropNode.backgroundColor = UIColor.theme.primary

        super.init()
        self.automaticallyManagesSubnodes = true

        loadingHostNode.style.preferredSize = CGSize(width: 44, height: 44)
        overlayBackdropNode.style.flexGrow = 1

        collectionNode.dataSource = self
        collectionNode.delegate = self
        collectionNode.backgroundColor = .clear
        collectionNode.view.contentInsetAdjustmentBehavior = .never
    }

    func loadTabDataIfNeeded() {
        guard !didLoadMedia else { return }
        didLoadMedia = true
        fetchMedia()
    }

    private func fetchMedia() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = await context.getToken() ?? ""
                let res = try await self.requestAttachments(before: 0, token: token)
                let raw = res.attachments
                self.hasMoreMedia = raw.count >= Int(self.mediaPageLimit)
                let visual = raw
                    .filter { Self.isVisualAttachment($0) }
                    .sorted { $0.createTimeSeconds > $1.createTimeSeconds }
                self.attachments = visual

                await self.collectionNode.reloadData()
                self.mediaFetchCompleted = true
                self.setNeedsLayout()
            } catch {
                self.mediaFetchCompleted = true
                self.setNeedsLayout()
            }
        }
    }

    private func requestAttachments(before: UInt32, token: String) async throws
        -> Mezon_Api_ChannelAttachmentList
    {
        let targetClanId =
            (channelType == MezonConstants.ChannelType.dm.rawValue
                || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId
        return try await context.account.network.listChannelAttachments(
            clanId: targetClanId,
            channelId: channelId,
            fileType: "image",
            limit: mediaPageLimit,
            before: before,
            token: token
        )
    }

    private func loadMoreMediaIfNeeded() {
        guard mediaFetchCompleted, hasMoreMedia, !isLoadingMore,
            let oldest = attachments.last, oldest.createTimeSeconds > 0
        else { return }
        isLoadingMore = true
        let before = oldest.createTimeSeconds
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }
            do {
                let token = await self.context.getToken() ?? ""
                let res = try await self.requestAttachments(before: before, token: token)
                let raw = res.attachments
                self.hasMoreMedia = raw.count >= Int(self.mediaPageLimit)
                let existingKeys = Set(self.attachments.map { Self.dedupKey($0) })
                let newItems = raw
                    .filter { Self.isVisualAttachment($0) }
                    .filter { !existingKeys.contains(Self.dedupKey($0)) }
                    .sorted { $0.createTimeSeconds > $1.createTimeSeconds }
                guard !newItems.isEmpty else {
                    self.hasMoreMedia = false
                    return
                }
                let startIndex = self.attachments.count
                self.attachments.append(contentsOf: newItems)
                let indexPaths = (startIndex..<self.attachments.count).map {
                    IndexPath(item: $0, section: 0)
                }
                self.collectionNode.performBatch(
                    animated: false,
                    updates: { self.collectionNode.insertItems(at: indexPaths) },
                    completion: nil
                )
            } catch {
            }
        }
    }

    private static func dedupKey(_ att: Mezon_Api_ChannelAttachment) -> String {
        att.id != 0 ? "id:\(att.id)" : "url:\(att.url)"
    }

    private static func isVisualAttachment(_ att: Mezon_Api_ChannelAttachment) -> Bool {
        let ft = att.filetype.lowercased()
        if ft.contains("audio") || ft.hasPrefix("audio/") { return false }
        if ft.hasPrefix("image/") || ft.hasPrefix("video/") { return true }
        if ft.isEmpty {
            let ext = (att.filename as NSString).pathExtension.lowercased()
            if ["mp3", "m4a", "wav", "aac", "ogg", "flac"].contains(ext) { return false }
            return true
        }
        return false
    }

    private static func isVideo(_ att: Mezon_Api_ChannelAttachment) -> Bool {
        let filetype = att.filetype.lowercased()
        if filetype.hasPrefix("video/") { return true }
        let filenameExtension = (att.filename as NSString).pathExtension.lowercased()
        let urlExtension = URL(string: att.url)?.pathExtension.lowercased() ?? ""
        return ["mp4", "mov", "m4v", "webm"].contains(filenameExtension)
            || ["mp4", "mov", "m4v", "webm"].contains(urlExtension)
    }

    private func gridItemSide(collectionWidth: CGFloat) -> CGFloat {
        let columns: CGFloat = 3
        let spacing = flowLayout.minimumInteritemSpacing
        let inner = max(0, collectionWidth - spacing * (columns - 1))
        return max(1, floor(inner / columns))
    }

    override func layout() {
        super.layout()
        let w = collectionNode.bounds.width
        guard w > 1 else { return }
        let side = gridItemSide(collectionWidth: w)
        let newSize = CGSize(width: side, height: side)
        if flowLayout.itemSize != newSize {
            flowLayout.itemSize = newSize
            flowLayout.invalidateLayout()
        }
    }

    private func presentGallery(startingAt index: Int, previewImage: UIImage? = nil) {
        guard index >= 0, index < attachments.count else { return }
        let proxySide = Int(flowLayout.itemSize.width * UIScreen.main.scale)
        let items: [GalleryItemInfo] = attachments.enumerated().map { (itemIndex, att) in
            let isVideo = Self.isVideo(att)
            let imageThumbURL = ImgproxyURL.attachmentURL(
                from: att.url, width: proxySide, height: proxySide, resizeType: "fill")
            let preview = itemIndex == index
                ? (previewImage
                    ?? ImageCache.shared.memoryImage(forKey: imageThumbURL)
                    ?? GalleryItemInfo.fitCachedPreviewMemory(sourceURL: att.url, placeholderProxySize: 150))
                : nil
            let ts: Date? =
                att.createTimeSeconds > 0
                ? Date(timeIntervalSince1970: TimeInterval(att.createTimeSeconds)) : nil
            if isVideo {
                let videoPreview = itemIndex == index
                    ? (previewImage
                        ?? ImageCache.shared.memoryImage(forKey: imageThumbURL)
                        ?? GalleryItemInfo.fitCachedPreviewMemory(
                            sourceURL: att.url, placeholderProxySize: 150))
                    : nil
                return GalleryItemInfo(
                    url: att.url,
                    sourceURL: att.url,
                    image: videoPreview,
                    placeholderURL: nil,
                    senderName: "",
                    senderAvatarURL: nil,
                    timestamp: ts,
                    isVideo: true
                )
            }
            return GalleryItemInfo.imageItem(
                sourceURL: att.url,
                image: preview,
                pixelSize: GalleryItemInfo.pixelSize(width: Int(att.width), height: Int(att.height)),
                placeholderProxySize: 150,
                senderName: "",
                senderAvatarURL: nil,
                timestamp: ts
            )
        }
        let gallery = GalleryController(items: items, initialIndex: index)
        guard let vc = view.findViewController() else { return }
        vc.present(gallery, animated: true)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        collectionNode.style.flexGrow = 1
        collectionNode.style.flexShrink = 1

        let showLoading = didLoadMedia && !mediaFetchCompleted
        let showEmpty = mediaFetchCompleted && attachments.isEmpty
        if showLoading {
            return ASOverlayLayoutSpec(
                child: collectionNode,
                overlay: mediaOverlaySpec(centering: loadingHostNode)
            )
        }
        if showEmpty {
            return ASOverlayLayoutSpec(
                child: collectionNode,
                overlay: mediaOverlaySpec(centering: emptyStateNode)
            )
        }
        return ASWrapperLayoutSpec(layoutElement: collectionNode)
    }

    private func mediaOverlaySpec(centering content: ASLayoutElement) -> ASLayoutSpec {
        let centered = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: content
        )
        return ASOverlayLayoutSpec(child: overlayBackdropNode, overlay: centered)
    }
}

private final class MediaEmptyStateNode: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true

        let cfg = UIImage.SymbolConfiguration(pointSize: 36.sf, weight: .medium)
        iconNode.image = UIImage(systemName: "photo.on.rectangle.angled", withConfiguration: cfg)?
            .withTintColor(UIColor.theme.textDisabled, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 48.sf, height: 48.sf)

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.ChannelDetail.noMediaYet),
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.sf, weight: .medium),
                .foregroundColor: UIColor.theme.text.withAlphaComponent(0.65),
            ]
        )
        titleNode.maximumNumberOfLines = 0
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let stack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 12.sf,
            justifyContent: .center,
            alignItems: .center,
            children: [iconNode, titleNode]
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            child: stack
        )
    }
}

extension MediaGalleryNode: ASCollectionDataSource, ASCollectionDelegate {

    func collectionNode(_ collectionNode: ASCollectionNode, numberOfItemsInSection section: Int)
        -> Int
    {
        attachments.count
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y
        let contentHeight = scrollView.contentSize.height
        let frameHeight = scrollView.frame.height
        guard contentHeight > frameHeight else { return }
        if offset > contentHeight - frameHeight * 1.5 {
            loadMoreMediaIfNeeded()
        }
    }

    func collectionNode(_ collectionNode: ASCollectionNode, nodeBlockForItemAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
        let attachment = attachments[indexPath.item]
        let isVideo = Self.isVideo(attachment)
        let proxySide = Int(flowLayout.itemSize.width * UIScreen.main.scale)
        let imageThumbURL = ImgproxyURL.attachmentURL(
            from: attachment.url, width: proxySide, height: proxySide, resizeType: "fill")
        let index = indexPath.item
        return { [weak self] in
            var cell: MediaThumbCellNode!
            cell = MediaThumbCellNode(
                rawSourceURL: attachment.url,
                imageThumbnailURL: imageThumbURL,
                isVideo: isVideo,
                onTap: { [weak self, weak cell] in
                    let preview = ImageCache.shared.memoryImage(forKey: imageThumbURL) ?? cell?.displayImage
                    self?.presentGallery(startingAt: index, previewImage: preview)
                }
            )
            return cell
        }
    }
}


private final class MediaThumbCellNode: ASCellNode {

    private let imageNode = TransformImageNode()
    private let playOverlayNode: ASDisplayNode?
    private let onTap: () -> Void

    init(
        rawSourceURL: String,
        imageThumbnailURL: String,
        isVideo: Bool,
        onTap: @escaping () -> Void
    ) {
        self.onTap = onTap
        if isVideo {
            self.playOverlayNode = MediaPlayOverlayNode()
        } else {
            self.playOverlayNode = nil
        }

        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = UIColor.theme.secondary.withAlphaComponent(0.35)
        clipsToBounds = true
        cornerRadius = 4

        imageNode.contentAnimations = [.firstUpdate]
        if isVideo {
            imageNode.setSignal(
                videoThumbnailSignal(url: rawSourceURL, resizeMode: .fill),
                attemptSynchronously: false
            )
        } else {
            imageNode.setSignal(
                remoteImageSignal(url: imageThumbnailURL, resizeMode: .fill),
                attemptSynchronously: false
            )
        }
    }

    override func didLoad() {
        super.didLoad()
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTap()
    }

    var currentImage: UIImage? {
        displayImage
    }

    var displayImage: UIImage? {
        if let image = imageNode.image {
            return image
        }
        guard let contents = imageNode.layer.contents else { return nil }
        let typeID = CFGetTypeID(contents as CFTypeRef)
        guard typeID == CGImage.typeID else { return nil }
        return UIImage(cgImage: contents as! CGImage)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let w = constrainedSize.max.width
        let h = constrainedSize.max.height
        let cap: CGFloat = 1024
        func layoutSide(_ x: CGFloat) -> CGFloat {
            guard x.isFinite, x > 0 else { return 100 }
            return min(x, cap)
        }
        let size = CGSize(width: layoutSide(w), height: layoutSide(h))
        let args = TransformImageArguments(
            corners: ImageCorners(radius: 4),
            imageSize: size,
            boundingSize: size,
            intrinsicInsets: .zero
        )
        let makeLayout = imageNode.asyncLayout()
        let apply = makeLayout(args)
        apply()

        if let playOverlayNode {
            return ASOverlayLayoutSpec(child: imageNode, overlay: playOverlayNode)
        }
        return ASWrapperLayoutSpec(layoutElement: imageNode)
    }
}

private final class MediaPlayOverlayNode: ASDisplayNode {

    private let iconNode = ASImageNode()

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        iconNode.image = UIImage(systemName: "play.fill", withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        iconNode.contentMode = .scaleAspectFit
        iconNode.style.preferredSize = CGSize(width: 28, height: 28)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: .minimumXY,
            child: iconNode
        )
    }
}

private extension UIView {
    func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}
