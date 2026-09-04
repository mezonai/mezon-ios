import AsyncDisplayKit
import UIKit

enum ChannelEventIcon {
    private static let upcomingImage = makeImage(
        tintColor: UIColor(red: 168 / 255, green: 85 / 255, blue: 247 / 255, alpha: 1)
    )
    private static let ongoingImage = makeImage(
        tintColor: UIColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 1)
    )

    static func normalizedStatus(_ status: Int32?) -> Int32? {
        switch status {
        case ClanEventStatusValue.upcoming, ClanEventStatusValue.ongoing:
            return status
        default:
            return nil
        }
    }

    static func image(for status: Int32?) -> UIImage? {
        switch normalizedStatus(status) {
        case ClanEventStatusValue.upcoming:
            return upcomingImage
        case ClanEventStatusValue.ongoing:
            return ongoingImage
        default:
            return nil
        }
    }

    private static func makeImage(tintColor: UIColor) -> UIImage? {
        guard let source = UIImage(named: "Channel/Event"),
              let sourceImage = source.cgImage else {
            return nil
        }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return source
        }

        let width = sourceImage.width
        let height = sourceImage.height
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let outputImage: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return nil
            }
            context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            let bytes = buffer.bindMemory(to: UInt8.self)
            let targetRed = red * 255
            let targetGreen = green * 255
            let targetBlue = blue * 255
            let whiteThreshold: CGFloat = 120
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let pixelAlpha = CGFloat(bytes[offset + 3])
                guard pixelAlpha > 0 else { continue }
                let unpremultiply = 255 / pixelAlpha
                let sourceRed = min(255, CGFloat(bytes[offset]) * unpremultiply)
                let sourceGreen = min(255, CGFloat(bytes[offset + 1]) * unpremultiply)
                let sourceBlue = min(255, CGFloat(bytes[offset + 2]) * unpremultiply)
                let sourceWhite = min(sourceRed, sourceGreen, sourceBlue)
                let whiteMix = min(
                    1,
                    max(0, (sourceWhite - whiteThreshold) / (255 - whiteThreshold))
                )
                let premultiply = pixelAlpha / 255
                bytes[offset] = UInt8(
                    ((targetRed * (1 - whiteMix) + 255 * whiteMix) * premultiply).rounded()
                )
                bytes[offset + 1] = UInt8(
                    ((targetGreen * (1 - whiteMix) + 255 * whiteMix) * premultiply).rounded()
                )
                bytes[offset + 2] = UInt8(
                    ((targetBlue * (1 - whiteMix) + 255 * whiteMix) * premultiply).rounded()
                )
            }
            return context.makeImage()
        }
        guard let outputImage else { return source }
        return UIImage(
            cgImage: outputImage,
            scale: source.scale,
            orientation: source.imageOrientation
        )
    }
}

final class ChannelItemCellNode: ASCellNode {

    private let iconNode = ASTextNode2()
    private let iconImgNode = ASImageNode()
    private let eventIconNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let badgeNode = ASTextNode2()
    private let badgeBackground = ASDisplayNode()
    private let unreadDot = ASDisplayNode()
    private let selectionNode = ASDisplayNode()
    var onLongPress: (() -> Void)?

    private let channel: Mezon_Api_ChannelDescription
    private let cellSelected: Bool
    private let isVoiceActive: Bool
    private var eventStatus: Int32?
    let channelId: Int64

    init(
        channel: Mezon_Api_ChannelDescription,
        isSelected: Bool,
        isVoiceActive: Bool = false,
        eventStatus: Int32? = nil
    ) {
        self.channel = channel
        self.cellSelected = isSelected
        self.isVoiceActive = isVoiceActive
        self.eventStatus = ChannelEventIcon.normalizedStatus(eventStatus)
        self.channelId = channel.channelID
        super.init()
        automaticallyManagesSubnodes = true
        neverShowPlaceholders = true
        selectionStyle = .none
        clipsToBounds = true
        setupContent()
    }

    private static let voiceTypes: Set<Int32> = [
        MezonConstants.ChannelType.mezonVoice.rawValue,
        MezonConstants.ChannelType.streaming.rawValue,
        MezonConstants.ChannelType.app.rawValue,
    ]

    private func setupContent() {
        let t = UIColor.theme
        let chType = ChannelType(rawValue: channel.type) ?? .unknown
        let isVoiceType = Self.voiceTypes.contains(channel.type)
        let isUnread = !isVoiceType && (
            channel.countMessUnread > 0
            || (channel.hasLastSentMessage
                && channel.lastSeenMessage.timestampSeconds
                    < channel.lastSentMessage.timestampSeconds))
        let unread = isVoiceType ? 0 : channel.countMessUnread

        let voiceActiveGreen = UIColor(red: 22/255, green: 163/255, blue: 74/255, alpha: 1)
        let iconColor: UIColor
        if isVoiceActive {
            iconColor = voiceActiveGreen
        } else if isUnread {
            iconColor = t.channelUnread
        } else {
            iconColor = t.channelNormal
        }
        if chType.isSystemImage {
            var iconName = chType.icon
            if chType == .voice && isVoiceActive {
                iconName = "Chat/SpeakerIcon"
            }
            if chType == .text && channel.channelPrivate == 1 {
                iconName = "Channel/channelPrivate"
            }
            if chType == .text && channel.ageRestricted == 1 {
                iconName = "Channel/channelWarning"
            }
            let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
            iconImgNode.image = image?.withRenderingMode(.alwaysTemplate)
            iconImgNode.tintColor = iconColor
            iconImgNode.isHidden = false
            iconNode.isHidden = true
        } else {
            iconNode.attributedText = NSAttributedString(
                string: chType.icon,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14.sf, weight: .regular),
                    .foregroundColor: iconColor,
                ])
            iconNode.isHidden = false
            iconImgNode.isHidden = true
        }

        eventIconNode.image = ChannelEventIcon.image(for: eventStatus)
        eventIconNode.contentMode = .scaleAspectFit
        eventIconNode.isHidden = eventIconNode.image == nil

        let nameStr = channel.channelLabel.isEmpty ? "channel" : channel.channelLabel
        let nameColor =
            isUnread ? t.channelUnread : t.channelNormal
        let nameWeight: UIFont.Weight = isUnread ? .semibold : .medium
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: nameStr,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: nameWeight),
                .foregroundColor: nameColor,
            ])

        if unread > 0 {
            let text = unread > 99 ? "99+" : "\(unread)"
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            badgeNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 10.sf, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: para,
                ])
            badgeBackground.backgroundColor = .systemRed
            badgeBackground.clipsToBounds = true
            badgeBackground.isHidden = false
            badgeNode.isHidden = false
        } else {
            badgeBackground.isHidden = true
            badgeNode.isHidden = true
        }

        unreadDot.backgroundColor = .white
        unreadDot.cornerRadius = 3.swh
        unreadDot.isHidden = !(isUnread && !cellSelected)

        selectionNode.isHidden = !cellSelected
        let theme = ThemeManager.shared.current
        let isLight =
            theme == .light
            || (theme == .system && UIScreen.main.traitCollection.userInterfaceStyle != .dark)
        selectionNode.backgroundColor =
            cellSelected ? (isLight ? t.secondaryWeight : t.secondaryLight) : .clear
        selectionNode.cornerRadius = 16.swh
        backgroundColor = .clear

        isUserInteractionEnabled = true
    }

    func applyEventStatus(_ status: Int32?) {
        let normalized = ChannelEventIcon.normalizedStatus(status)
        guard eventStatus != normalized else { return }
        eventStatus = normalized
        eventIconNode.image = ChannelEventIcon.image(for: normalized)
        eventIconNode.isHidden = eventIconNode.image == nil
        setNeedsLayout()
    }

    func applyListSelectionState(selected: Bool) {
        let t = UIColor.theme
        let isVoiceType = Self.voiceTypes.contains(channel.type)
        let isUnread = !isVoiceType && (
            channel.countMessUnread > 0
                || (channel.hasLastSentMessage
                    && channel.lastSeenMessage.timestampSeconds
                        < channel.lastSentMessage.timestampSeconds))
        unreadDot.isHidden = !(isUnread && !selected)
        selectionNode.isHidden = !selected
        let theme = ThemeManager.shared.current
        let isLight =
            theme == .light
            || (theme == .system && UIScreen.main.traitCollection.userInterfaceStyle != .dark)
        selectionNode.backgroundColor =
            selected ? (isLight ? t.secondaryWeight : t.secondaryLight) : .clear
        selectionNode.cornerRadius = 16.swh
        setNeedsLayout()
    }

    override func didLoad() {
        super.didLoad()
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        view.addGestureRecognizer(lp)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            onLongPress?()
        }
    }

    override func layout() {
        super.layout()
        badgeBackground.cornerRadius = badgeBackground.bounds.height / 2
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        iconNode.style.preferredSize = CGSize(width: 14.swh, height: 14.swh)
        iconImgNode.style.preferredSize = CGSize(width: 12.swh, height: 12.swh)
        let iconChild: ASLayoutElement = iconNode.isHidden ? iconImgNode : iconNode
        eventIconNode.style.preferredSize = CGSize(width: 16.swh, height: 16.swh)

        let leadingChild: ASLayoutElement
        let contentSpacing: CGFloat
        if eventIconNode.isHidden {
            leadingChild = iconChild
            contentSpacing = 10.sw
        } else {
            leadingChild = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: 6.sw,
                justifyContent: .start,
                alignItems: .center,
                children: [iconChild, eventIconNode]
            )
            contentSpacing = 8.sw
        }

        let badgeInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2.swh, left: 6.swh, bottom: 2.swh, right: 6.swh),
            child: badgeNode)
        let badge = ASBackgroundLayoutSpec(child: badgeInset, background: badgeBackground)
        badge.style.minSize = CGSize(width: 20.swh, height: 20.swh)

        unreadDot.style.preferredSize = CGSize(width: 6.swh, height: 6.swh)

        let spacer = ASLayoutSpec()
        spacer.style.flexGrow = 1
        nameNode.style.flexShrink = 1
        nameNode.style.flexGrow = 0

        var children: [ASLayoutElement] = [leadingChild, nameNode]
        if !badgeNode.isHidden {
            children.append(contentsOf: [spacer, badge])
        }

        let row = ASStackLayoutSpec(
            direction: .horizontal, spacing: contentSpacing, justifyContent: .start, alignItems: .center,
            children: children)

        let inset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sh, left: 12.sw, bottom: 8.sh, right: 12.sw),
            child: row
        )

        inset.style.minHeight = ASDimensionMake(36.sh)
        let contentWithBackground = ASBackgroundLayoutSpec(child: inset, background: selectionNode)

        let paddedContent = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw),
            child: contentWithBackground)

        if !unreadDot.isHidden {
            unreadDot.style.layoutPosition = CGPoint(x: -3.swh, y: 15.sh)
            let absDot = ASAbsoluteLayoutSpec(children: [unreadDot])
            return ASOverlayLayoutSpec(child: paddedContent, overlay: absDot)
        } else {
            return paddedContent
        }
    }
}

struct VoiceMemberDisplay: Equatable {
    let name: String
    let username: String
    let avatarURL: String?
}

final class VoiceAvatarNode: ASDisplayNode, ASNetworkImageNodeDelegate {

    private static let decodedImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 512
        return cache
    }()

    private let imgNode = ASNetworkImageNode()
    private let initNode = ASTextNode2()
    private let proxiedURL: URL?
    private let originalURL: URL?

    private var didLoadImage = false
    private var usingFallback = false
    private var retryCount = 0
    private static let maxRetries = 4

    private func cachedAvatarImage() -> UIImage? {
        if let p = proxiedURL, let img = Self.decodedImageCache.object(forKey: p.absoluteString as NSString) { return img }
        if let o = originalURL, let img = Self.decodedImageCache.object(forKey: o.absoluteString as NSString) { return img }
        return nil
    }

    private func storeAvatarImage(_ image: UIImage) {
        if let p = proxiedURL { Self.decodedImageCache.setObject(image, forKey: p.absoluteString as NSString) }
        if let o = originalURL { Self.decodedImageCache.setObject(image, forKey: o.absoluteString as NSString) }
    }

    init(member m: VoiceMemberDisplay, size s: CGFloat) {
        if let av = m.avatarURL, !av.isEmpty {
            let absolute = ImgproxyURL.absoluteResourceURL(from: av)
            let px = max(1, Int((s * UIScreen.main.scale).rounded(.up)))
            proxiedURL = URL(string: ImgproxyURL.create(from: absolute, width: px, height: px))
            originalURL = URL(string: absolute)
        } else {
            proxiedURL = nil
            originalURL = nil
        }
        super.init()
        automaticallyManagesSubnodes = true
        style.preferredSize = CGSize(width: s, height: s)
        cornerRadius = s / 2
        clipsToBounds = true
        let avatarSeed = m.username.isEmpty ? m.name : m.username
        backgroundColor = UIColor.avatarColor(for: avatarSeed)

        let initial = String(avatarSeed.prefix(1)).uppercased()
        let fontSize: CGFloat = s < 22 ? 9 : 11
        initNode.maximumNumberOfLines = 1
        initNode.attributedText = NSAttributedString(
            string: initial,
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
            ])

        imgNode.style.preferredSize = CGSize(width: s, height: s)
        imgNode.cornerRadius = s / 2
        imgNode.clipsToBounds = true
        imgNode.contentMode = .scaleAspectFill
        imgNode.placeholderFadeDuration = 0
        imgNode.delegate = self

        let initialURL = proxiedURL ?? originalURL
        if let initialURL {
            usingFallback = (proxiedURL == nil)
            if let cached = cachedAvatarImage() {
                imgNode.image = cached
                didLoadImage = true
            } else {
                imgNode.url = initialURL
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleNetworkStatusChanged(_:)),
                    name: NetworkMonitor.statusDidChangeNotification,
                    object: nil
                )
            }
        } else {
            imgNode.isHidden = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let center = ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: initNode)
        return ASOverlayLayoutSpec(child: center, overlay: imgNode)
    }

    private func reloadAvatar() {
        guard !didLoadImage else { return }
        guard let target = usingFallback ? originalURL : proxiedURL else { return }
        imgNode.url = nil
        imgNode.url = target
    }

    @objc private func handleNetworkStatusChanged(_ notification: Notification) {
        let connected = (notification.userInfo?["isConnected"] as? Bool) ?? NetworkMonitor.shared.isConnected
        guard connected, !didLoadImage else { return }
        retryCount = 0
        DispatchQueue.main.async { [weak self] in
            self?.reloadAvatar()
        }
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didLoad image: UIImage) {
        guard imageNode === imgNode else { return }
        if image.size.width >= 0.5, image.size.height >= 0.5 {
            didLoadImage = true
            storeAvatarImage(image)
        }
    }

    @objc func imageNode(_ imageNode: ASNetworkImageNode, didFailWithError error: Error) {
        guard imageNode === imgNode, !didLoadImage else { return }
        if !usingFallback, let originalURL, originalURL != proxiedURL {
            usingFallback = true
            retryCount = 0
            DispatchQueue.main.async { [weak self] in
                self?.reloadAvatar()
            }
            return
        }
        guard retryCount < Self.maxRetries else { return }
        retryCount += 1
        let delay = Double(retryCount) * 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reloadAvatar()
        }
    }
}

final class VoiceMemberExpandedCellNode: ASCellNode {

    private static let avatarSize: CGFloat = 22

    private let avatarNode: VoiceAvatarNode
    private let nameNode = ASTextNode2()

    init(member: VoiceMemberDisplay) {
        avatarNode = VoiceAvatarNode(member: member, size: Self.avatarSize)
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail
        nameNode.attributedText = NSAttributedString(
            string: member.name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .regular),
                .foregroundColor: UIColor.theme.channelNormal,
            ])
    }

    override func layout() {
        super.layout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        nameNode.style.flexShrink = 1
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .center,
            children: [avatarNode, nameNode]
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2, left: 40, bottom: 2, right: 12),
            child: row
        )
    }
}

final class VoiceChannelMembersCollapsedCellNode: ASCellNode {

    private static let avatarSize: CGFloat = 20
    private static let maxVisible = 5

    private var avatarNodes: [ASDisplayNode] = []
    private var overflowNode: ASTextNode2?
    private var overflowBg: ASDisplayNode?

    init(members: [VoiceMemberDisplay], totalCount: Int) {
        super.init()
        automaticallyManagesSubnodes = true
        selectionStyle = .none
        backgroundColor = .clear

        let visible = Array(members.prefix(Self.maxVisible))
        for m in visible {
            avatarNodes.append(VoiceAvatarNode(member: m, size: Self.avatarSize))
        }

        if totalCount > Self.maxVisible {
            let text = "+\(totalCount - Self.maxVisible)"
            let font = UIFont.systemFont(ofSize: 10, weight: .bold)
            let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
            let badgeWidth = max(Self.avatarSize, ceil(textWidth) + 8)

            let bg = ASDisplayNode()
            bg.style.preferredSize = CGSize(width: badgeWidth, height: Self.avatarSize)
            bg.cornerRadius = Self.avatarSize / 2
            bg.clipsToBounds = true
            bg.backgroundColor = UIColor.theme.primary
            bg.borderWidth = 1
            bg.borderColor = UIColor.theme.textDisabled.cgColor
            overflowBg = bg

            let node = ASTextNode2()
            node.maximumNumberOfLines = 1
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            para.minimumLineHeight = Self.avatarSize
            para.maximumLineHeight = Self.avatarSize
            node.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: UIColor.theme.channelNormal,
                    .paragraphStyle: para,
                    .baselineOffset: (Self.avatarSize - font.lineHeight) / 2,
                ])
            node.style.preferredSize = CGSize(width: badgeWidth, height: Self.avatarSize)
            overflowNode = node
        }
    }

    override func layout() {
        super.layout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let s = Self.avatarSize
        var children: [ASLayoutElement] = avatarNodes
        if let overflow = overflowNode, let bg = overflowBg {
            children.append(ASBackgroundLayoutSpec(child: overflow, background: bg))
        }
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: -3,
            justifyContent: .start,
            alignItems: .center,
            children: children
        )
        return ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 2, left: 38, bottom: 2, right: 12),
            child: row
        )
    }
}
