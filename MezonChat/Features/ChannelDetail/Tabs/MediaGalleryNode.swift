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
                let targetClanId =
                    (channelType == MezonConstants.ChannelType.dm.rawValue
                        || channelType == MezonConstants.ChannelType.group.rawValue) ? 0 : clanId


                let res = try await context.account.network.listChannelAttachments(
                    clanId: targetClanId,
                    channelId: channelId,
                    fileType: "image",
                    limit: 50,
                    token: token
                )
                let raw = res.attachments
                let visual = raw.filter { Self.isVisualAttachment($0) }
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
        att.filetype.lowercased().hasPrefix("video/")
    }

    private func gridItemSide(collectionWidth: CGFloat) -> CGFloat {
        let columns: CGFloat = 3
        let spacing = flowLayout.minimumInteritemSpacing
        let inner = max(0, collectionWidth - spacing * (columns - 1))
        return max(1, floor(inner / columns))
    }

    private func fullScreenProxyPixels() -> Int {
        let longest = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let px = Int((longest * UIScreen.main.scale).rounded(.up))
        return max(512, min(px, 2048))
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

    private func presentGallery(startingAt index: Int) {
        guard index >= 0, index < attachments.count else { return }
        let fullPx = fullScreenProxyPixels()
        let items: [GalleryItemInfo] = attachments.map { att in
            let url: String
            if Self.isVideo(att) {
                url = att.url
            } else {
                url = ImgproxyURL.attachmentURL(
                    from: att.url, width: fullPx, height: fullPx, resizeType: "fit")
            }
            let ts: Date? =
                att.createTimeSeconds > 0
                ? Date(timeIntervalSince1970: TimeInterval(att.createTimeSeconds)) : nil
            return GalleryItemInfo(
                url: url,
                image: nil,
                senderName: "",
                senderAvatarURL: nil,
                timestamp: ts,
                isVideo: Self.isVideo(att)
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

    func collectionNode(_ collectionNode: ASCollectionNode, nodeBlockForItemAt indexPath: IndexPath)
        -> ASCellNodeBlock
    {
               let attachment = attachments[indexPath.item]
        let isVideo = Self.isVideo(attachment)
        let imageThumbURL = ImgproxyURL.attachmentURL(
            from: attachment.url, width: 100, height: 100, resizeType: "fit")
        let index = indexPath.item
        return { [weak self] in
            let cell = MediaThumbCellNode(
                rawSourceURL: attachment.url,
                imageThumbnailURL: imageThumbURL,
                isVideo: isVideo,
                onTap: { self?.presentGallery(startingAt: index) }
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
