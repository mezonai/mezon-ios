import Foundation
import UIKit
import AsyncDisplayKit

public struct GalleryItemInfo {
    public let url: String
    public let sourceURL: String?
    public let image: UIImage?
    public let placeholderURL: String?
    public let senderName: String
    public let senderAvatarURL: String?
    public let timestamp: Date?
    public let isVideo: Bool

    public var stableIdentity: String {
        if let sourceURL, !sourceURL.isEmpty { return sourceURL }
        return url
    }

    public init(url: String, sourceURL: String? = nil, image: UIImage? = nil, placeholderURL: String? = nil, senderName: String = "", senderAvatarURL: String? = nil, timestamp: Date? = nil, isVideo: Bool = false) {
        self.url = url
        self.sourceURL = sourceURL
        self.image = image
        self.placeholderURL = placeholderURL
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.timestamp = timestamp
        self.isVideo = isVideo
    }
}

open class GalleryItemNode: ASDisplayNode {

    private var _index: Int = 0
    public var index: Int {
        get { _index }
        set { _index = newValue }
    }

    public var toggleControlsVisibility: () -> Void = {}
    public var dismiss: () -> Void = {}
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
