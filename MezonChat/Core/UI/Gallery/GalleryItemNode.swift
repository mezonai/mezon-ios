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

struct GallerySenderInfo {
    let name: String
    let avatarURL: String?

    static func anonymous(name: String, avatarURL: String?) -> GallerySenderInfo {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let avatar = avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GallerySenderInfo(
            name: name.isEmpty || name == String(MezonConstants.anonymousUserId) ? "Anonymous" : name,
            avatarURL: avatar.isEmpty ? nil : avatar
        )
    }
}

@MainActor
final class ChannelGallerySenderResolver {
    private let context: AccountContext
    private let clanId: Int64
    private let channelId: Int64
    private let topicId: Int64
    private var fetchedMessages: [Int64: MessageRecord] = [:]

    init(context: AccountContext, clanId: Int64, channelId: Int64, topicId: Int64 = 0) {
        self.context = context
        self.clanId = clanId
        self.channelId = channelId
        self.topicId = topicId
    }

    private func anonymousMessage(for attachment: Mezon_Api_ChannelAttachment) -> MessageRecord? {
        guard attachment.messageID != 0 else { return nil }
        let storageChannelId = topicId == 0 ? String(channelId) : "topic-\(topicId)"
        let message = fetchedMessages[attachment.messageID] ?? context.account.postbox.read {
            $0.getMessageById(String(attachment.messageID), channelId: storageChannelId)
        }
        guard message?.senderId == String(MezonConstants.anonymousUserId) else { return nil }
        return message
    }

    func senderInfo(
        for attachment: Mezon_Api_ChannelAttachment,
        fallback: GallerySenderInfo? = nil
    ) -> GallerySenderInfo {
        if attachment.uploader == MezonConstants.anonymousUserId {
            guard let message = anonymousMessage(for: attachment) else {
                return .anonymous(name: fallback?.name ?? "", avatarURL: fallback?.avatarURL)
            }
            return .anonymous(
                name: message.senderDisplayName,
                avatarURL: message.senderAvatarURL
            )
        }
        guard attachment.uploader != 0 else { return GallerySenderInfo(name: "", avatarURL: nil) }
        let id = String(attachment.uploader)
        return context.account.postbox.read { tx in
            let profile = tx.getProfile(userId: id)
            let name = [profile?.displayName, profile?.username]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? id
            return GallerySenderInfo(name: name, avatarURL: profile?.avatarUrl)
        }
    }

    func loadSenderInfo(for attachment: Mezon_Api_ChannelAttachment) async -> GallerySenderInfo? {
        guard attachment.uploader == MezonConstants.anonymousUserId, attachment.messageID != 0 else {
            return nil
        }
        if anonymousMessage(for: attachment) != nil { return senderInfo(for: attachment) }
        guard let token = await context.getToken() else { return nil }
        do {
            let response = try await context.account.network.listChannelMessages(
                clanId: clanId,
                channelId: channelId,
                messageId: attachment.messageID,
                direction: 2,
                limit: 25,
                topicId: topicId,
                token: token
            )
            // Cache by message, since multiple anonymous personas share one sender ID.
            for message in response.messages where message.channelID == channelId && message.topicID == topicId {
                fetchedMessages[message.messageID] = MessageRecord(from: message)
            }
            guard anonymousMessage(for: attachment) != nil else { return nil }
            return senderInfo(for: attachment)
        } catch {
            return nil
        }
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
