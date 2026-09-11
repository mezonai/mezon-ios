import AsyncDisplayKit
import UIKit

private enum ChannelMediaType: String {
    case image
    case video
}

private struct ChannelMediaState {
    var attachments: [Mezon_Api_ChannelAttachment] = []
    var didLoad = false
    var fetchCompleted = false
    var isLoadingMore = false
    var hasMore = true
}

@MainActor
final class MediaGalleryNode: ASDisplayNode {

    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let channelType: Int32
    private var mediaStateByType: [ChannelMediaType: ChannelMediaState] = [:]
    private var selectedMediaType: ChannelMediaType = .image
    private let mediaPageLimit: Int32 = 50

    private let mediaTypeControl: UISegmentedControl
    private let mediaTypeControlNode: ASDisplayNode
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

        let mediaTypeControl = UISegmentedControl(items: [
            L(L10n.ChannelDetail.images),
            L(L10n.ChannelDetail.videos),
        ])
        self.mediaTypeControl = mediaTypeControl
        self.mediaTypeControlNode = ASDisplayNode(viewBlock: { mediaTypeControl })
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

        mediaTypeControl.selectedSegmentIndex = 0
        mediaTypeControl.addTarget(
            self, action: #selector(mediaTypeChanged(_:)), for: .valueChanged)
        mediaTypeControl.selectedSegmentTintColor = UIColor.theme.bgViolet
        mediaTypeControl.backgroundColor = UIColor.theme.secondary
        let segmentFont = UIFont.systemFont(ofSize: 14.sf, weight: .semibold)
        mediaTypeControl.setTitleTextAttributes(
            [.font: segmentFont, .foregroundColor: UIColor.theme.text], for: .normal)
        mediaTypeControl.setTitleTextAttributes(
            [.font: segmentFont, .foregroundColor: UIColor.white], for: .selected)
        mediaTypeControlNode.style.height = ASDimension(unit: .points, value: 40.sf)
        loadingHostNode.style.preferredSize = CGSize(width: 44, height: 44)
        overlayBackdropNode.style.flexGrow = 1

        collectionNode.dataSource = self
        collectionNode.delegate = self
        collectionNode.backgroundColor = .clear
        collectionNode.view.contentInsetAdjustmentBehavior = .never
    }

    func loadTabDataIfNeeded() {
        loadMediaIfNeeded(for: .image)
    }

    private var attachments: [Mezon_Api_ChannelAttachment] {
        mediaState(for: selectedMediaType).attachments
    }

    private func mediaState(for mediaType: ChannelMediaType) -> ChannelMediaState {
        mediaStateByType[mediaType] ?? ChannelMediaState()
    }

    private func loadMediaIfNeeded(for mediaType: ChannelMediaType) {
        var state = mediaState(for: mediaType)
        guard !state.didLoad else { return }
        state.didLoad = true
        state.fetchCompleted = false
        mediaStateByType[mediaType] = state
        if selectedMediaType == mediaType {
            setNeedsLayout()
        }
        fetchMedia(mediaType)
    }

    private func fetchMedia(_ mediaType: ChannelMediaType) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = await context.getToken() ?? ""
                let res = try await self.requestAttachments(
                    before: 0, token: token, mediaType: mediaType)
                let raw = res.attachments
                var state = self.mediaState(for: mediaType)
                state.hasMore = raw.count >= Int(self.mediaPageLimit)
                state.attachments = raw
                    .filter { Self.isAttachment($0, matching: mediaType) }
                    .sorted { $0.createTimeSeconds > $1.createTimeSeconds }
                state.fetchCompleted = true
                self.mediaStateByType[mediaType] = state

                if self.selectedMediaType == mediaType {
                    await self.collectionNode.reloadData()
                    self.setNeedsLayout()
                }
            } catch {
                var state = self.mediaState(for: mediaType)
                state.fetchCompleted = true
                self.mediaStateByType[mediaType] = state
                if self.selectedMediaType == mediaType {
                    self.setNeedsLayout()
                }
            }
        }
    }

    private func requestAttachments(
        before: UInt32, token: String, mediaType: ChannelMediaType
    ) async throws
        -> Mezon_Api_ChannelAttachmentList
    {
        let targetClanId =
            (channelType == MezonConstants.ChannelType.dm.rawValue
                || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId
        return try await context.account.network.listChannelAttachments(
            clanId: targetClanId,
            channelId: channelId,
            fileType: mediaType.rawValue,
            limit: mediaPageLimit,
            before: before,
            token: token
        )
    }

    private func loadMoreMediaIfNeeded() {
        let mediaType = selectedMediaType
        var state = mediaState(for: mediaType)
        guard state.fetchCompleted, state.hasMore, !state.isLoadingMore,
            let oldest = state.attachments.last, oldest.createTimeSeconds > 0
        else { return }
        state.isLoadingMore = true
        mediaStateByType[mediaType] = state
        let before = oldest.createTimeSeconds
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                var state = self.mediaState(for: mediaType)
                state.isLoadingMore = false
                self.mediaStateByType[mediaType] = state
            }
            do {
                let token = await self.context.getToken() ?? ""
                let res = try await self.requestAttachments(
                    before: before, token: token, mediaType: mediaType)
                let raw = res.attachments
                var state = self.mediaState(for: mediaType)
                state.hasMore = raw.count >= Int(self.mediaPageLimit)
                let existingKeys = Set(state.attachments.map { Self.dedupKey($0) })
                let newItems = raw
                    .filter { Self.isAttachment($0, matching: mediaType) }
                    .filter { !existingKeys.contains(Self.dedupKey($0)) }
                    .sorted { $0.createTimeSeconds > $1.createTimeSeconds }
                guard !newItems.isEmpty else {
                    state.hasMore = false
                    self.mediaStateByType[mediaType] = state
                    return
                }
                let startIndex = state.attachments.count
                state.attachments.append(contentsOf: newItems)
                self.mediaStateByType[mediaType] = state
                guard self.selectedMediaType == mediaType else { return }
                let indexPaths = (startIndex..<state.attachments.count).map {
                    IndexPath(item: $0, section: 0)
                }
                self.collectionNode.performBatch(
                    animated: false,
                    updates: { self.collectionNode.insertItems(at: indexPaths) },
                    completion: { _ in }
                )
            } catch {
            }
        }
    }

    private static func dedupKey(_ att: Mezon_Api_ChannelAttachment) -> String {
        att.id != 0 ? "id:\(att.id)" : "url:\(att.url)"
    }

    private static func isAttachment(
        _ att: Mezon_Api_ChannelAttachment, matching mediaType: ChannelMediaType
    ) -> Bool {
        let url = att.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty || url.lowercased().contains("/stickers") { return false }
        switch mediaType {
        case .image: return AttachmentTypeClassifier.isImage(att.filetype)
        case .video: return AttachmentTypeClassifier.isVideo(att.filetype)
        }
    }

    private static func isVideo(_ att: Mezon_Api_ChannelAttachment) -> Bool {
        AttachmentTypeClassifier.isVideo(att.filetype)
    }

    private func gridItemSide(collectionWidth: CGFloat) -> CGFloat {
        let columns: CGFloat = 3
        let spacing = flowLayout.minimumInteritemSpacing
        let inner = max(0, collectionWidth - spacing * (columns - 1))
        return max(1, floor(inner / columns))
    }

    @objc private func mediaTypeChanged(_ control: UISegmentedControl) {
        let mediaType: ChannelMediaType = control.selectedSegmentIndex == 1 ? .video : .image
        guard mediaType != selectedMediaType else { return }
        selectedMediaType = mediaType
        collectionNode.view.setContentOffset(.zero, animated: false)
        collectionNode.reloadData()
        setNeedsLayout()
        loadMediaIfNeeded(for: mediaType)
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
            let uploader = resolvedUploaderInfo(uploaderId: att.uploader)
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
                    pixelSize: GalleryItemInfo.pixelSize(width: att.width, height: att.height),
                    placeholderURL: nil,
                    senderName: uploader.name,
                    senderId: String(att.uploader),
                    senderAvatarURL: uploader.avatarURL,
                    timestamp: ts,
                    isVideo: true,
                    videoShareMetadata: GalleryVideoShareMetadata(
                        filename: att.filename,
                        filetype: att.filetype,
                        size: Int64(att.filesize) ?? 0
                    )
                )
            }
            return GalleryItemInfo.imageItem(
                sourceURL: att.url,
                image: preview,
                pixelSize: GalleryItemInfo.pixelSize(width: Int(att.width), height: Int(att.height)),
                placeholderProxySize: 150,
                senderName: uploader.name,
                senderId: String(att.uploader),
                senderAvatarURL: uploader.avatarURL,
                timestamp: ts
            )
        }
        let gallery = GalleryController(items: items, initialIndex: index)
        guard let vc = view.findViewController() else { return }
        vc.present(gallery, animated: true)
    }

    private func resolvedUploaderInfo(uploaderId: Int64) -> (name: String, avatarURL: String?) {
        guard uploaderId != 0 else { return ("", nil) }
        let idString = String(uploaderId)
        var name = ""
        var avatarURL: String?
        context.account.postbox.read { tx in
            guard let profile = tx.getProfile(userId: idString) else { return }
            if let displayName = profile.displayName, !displayName.isEmpty {
                name = displayName
            } else if !profile.username.isEmpty {
                name = profile.username
            }
            if let avatar = profile.avatarUrl, !avatar.isEmpty {
                avatarURL = avatar
            }
        }
        return (name.isEmpty ? idString : name, avatarURL)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        collectionNode.style.flexGrow = 1
        collectionNode.style.flexShrink = 1

        let state = mediaState(for: selectedMediaType)
        let showLoading = state.didLoad && !state.fetchCompleted
        let showEmpty = state.fetchCompleted && state.attachments.isEmpty
        let contentSpec: ASLayoutSpec
        if showLoading {
            contentSpec = ASOverlayLayoutSpec(
                child: collectionNode,
                overlay: mediaOverlaySpec(centering: loadingHostNode)
            )
        } else if showEmpty {
            contentSpec = ASOverlayLayoutSpec(
                child: collectionNode,
                overlay: mediaOverlaySpec(centering: emptyStateNode)
            )
        } else {
            contentSpec = ASWrapperLayoutSpec(layoutElement: collectionNode)
        }
        contentSpec.style.flexGrow = 1
        contentSpec.style.flexShrink = 1

        let mediaTypeInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sf, left: 8.sw, bottom: 8.sf, right: 8.sw),
            child: mediaTypeControlNode
        )
        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [mediaTypeInset, contentSpec]
        )
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
