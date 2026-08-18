import Foundation
import UIKit
import AsyncDisplayKit

public struct GalleryVideoShareMetadata {
    public let filename: String
    public let filetype: String
    public let size: Int64
    public let durationSeconds: Int
    public let thumbnail: String

    public init(
        filename: String = "",
        filetype: String = "",
        size: Int64 = 0,
        durationSeconds: Int = 0,
        thumbnail: String = ""
    ) {
        self.filename = filename
        self.filetype = filetype
        self.size = size
        self.durationSeconds = durationSeconds
        self.thumbnail = thumbnail
    }
}

public struct GalleryItemInfo {
    public static let detailProxySize = 700

    public let url: String
    public let sourceURL: String?
    public let image: UIImage?
    public let pixelSize: CGSize?
    public let placeholderURL: String?
    public let senderName: String
    public let senderId: String?
    public let senderAvatarURL: String?
    public let timestamp: Date?
    public let isVideo: Bool
    public let videoShareMetadata: GalleryVideoShareMetadata?

    public var stableIdentity: String {
        if let sourceURL, !sourceURL.isEmpty { return sourceURL }
        return url
    }

    public init(
        url: String,
        sourceURL: String? = nil,
        image: UIImage? = nil,
        pixelSize: CGSize? = nil,
        placeholderURL: String? = nil,
        senderName: String = "",
        senderId: String? = nil,
        senderAvatarURL: String? = nil,
        timestamp: Date? = nil,
        isVideo: Bool = false,
        videoShareMetadata: GalleryVideoShareMetadata? = nil
    ) {
        self.url = url
        self.sourceURL = sourceURL
        self.image = image
        self.pixelSize = pixelSize
        self.placeholderURL = placeholderURL
        self.senderName = senderName
        self.senderId = senderId
        self.senderAvatarURL = senderAvatarURL
        self.timestamp = timestamp
        self.isVideo = isVideo
        self.videoShareMetadata = videoShareMetadata
    }

    public static func pixelSize(width: Int?, height: Int?) -> CGSize? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    public static func pixelSize(width: Int32, height: Int32) -> CGSize? {
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    public static func imageItem(
        sourceURL: String,
        image: UIImage? = nil,
        pixelSize: CGSize? = nil,
        placeholderProxySize: Int = 400,
        senderName: String = "",
        senderId: String? = nil,
        senderAvatarURL: String? = nil,
        timestamp: Date? = nil
    ) -> GalleryItemInfo {
        let proxyURL = ImgproxyURL.attachmentURL(
            from: sourceURL,
            width: detailProxySize,
            height: detailProxySize,
            resizeType: "fit"
        )
        let placeholderURL = ImgproxyURL.attachmentURL(
            from: sourceURL,
            width: placeholderProxySize,
            height: placeholderProxySize,
            resizeType: "fit"
        )
        let cachedPreview = fitCachedPreviewMemory(
            sourceURL: sourceURL,
            placeholderProxySize: placeholderProxySize
        )
        return GalleryItemInfo(
            url: proxyURL,
            sourceURL: sourceURL,
            image: image ?? cachedPreview,
            pixelSize: pixelSize,
            placeholderURL: placeholderURL,
            senderName: senderName,
            senderId: senderId,
            senderAvatarURL: senderAvatarURL,
            timestamp: timestamp,
            isVideo: false
        )
    }

    public static func fitCachedPreview(
        sourceURL: String,
        placeholderProxySize: Int = 400
    ) -> UIImage? {
        for key in previewCacheKeys(sourceURL: sourceURL, placeholderProxySize: placeholderProxySize) {
            if let image = ImageCache.shared.memoryImage(forKey: key) {
                return image
            }
            if let image = ImageCache.shared.image(forKey: key) {
                return image
            }
        }
        return nil
    }

    public static func fitCachedPreviewMemory(
        sourceURL: String,
        placeholderProxySize: Int = 400
    ) -> UIImage? {
        for key in previewCacheKeys(sourceURL: sourceURL, placeholderProxySize: placeholderProxySize) {
            if let image = ImageCache.shared.memoryImage(forKey: key) {
                return image
            }
        }
        return nil
    }

    public static func previewCacheKeys(
        sourceURL: String,
        placeholderProxySize: Int = 400
    ) -> [String] {
        [
            ImgproxyURL.attachmentURL(
                from: sourceURL,
                width: placeholderProxySize,
                height: placeholderProxySize,
                resizeType: "fit"
            ),
            ImgproxyURL.attachmentURL(
                from: sourceURL,
                width: 150,
                height: 150,
                resizeType: "fit"
            ),
            ImgproxyURL.attachmentURL(
                from: sourceURL,
                width: detailProxySize,
                height: detailProxySize,
                resizeType: "fit"
            ),
        ]
    }
}

open class GalleryItemNode: ASDisplayNode {

    private var _index: Int = 0
    public var index: Int {
        get { _index }
        set { _index = newValue }
    }

    public var toggleControlsVisibility: () -> Void = {}
    public var setControlsVisible: (Bool) -> Void = { _ in }
    public var dismiss: () -> Void = {}
    public var setPagingEnabled: (Bool) -> Void = { _ in }
    public var itemInfo: GalleryItemInfo?

    override public init() {
        super.init()
        self.setViewBlock { UITracingLayerView() }
    }

    open func ready() -> Signal<Void, NoError> {
        return .single(Void())
    }

    open func containerLayoutUpdated(_ size: CGSize, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
    }

    open func centralityUpdated(isCentral: Bool) {
    }

    open func visibilityUpdated(isVisible: Bool) {
    }

    open func animateIn(from sourceView: UIView?, completion: @escaping () -> Void) {
        completion()
    }

    open func animateOut(to sourceView: UIView?, completion: @escaping () -> Void) {
        completion()
    }
}
