import UIKit
import AsyncDisplayKit

enum ChannelAppLogoCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()

    static func image(forURL url: String) -> UIImage? {
        cache.object(forKey: url as NSString)
    }

    static func store(_ image: UIImage, forURL url: String) {
        cache.setObject(image, forKey: url as NSString)
    }

    static func apply(to imageNode: ASImageNode, urlString: String) {
        if let cached = image(forURL: urlString) {
            imageNode.image = cached
            return
        }
        if let cached = ImageCache.shared.cachedImage(forURL: urlString) {
            store(cached, forURL: urlString)
            imageNode.image = cached
            return
        }
        ImageCache.shared.loadImage(urlString: urlString) { [weak imageNode] image in
            guard let imageNode, let image else { return }
            store(image, forURL: urlString)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageNode.image = image
            CATransaction.commit()
        }
    }
}

final class ChannelAppCellNode: ASCellNode {

    private let cardNode = ASDisplayNode()
    private let logoNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let statusDot = ASDisplayNode()

    init(app: Mezon_Api_ChannelAppResponse) {
        super.init()
        automaticallyManagesSubnodes = true
        neverShowPlaceholders = true
        backgroundColor = .clear
        selectionStyle = .none

        let t = UIColor.theme

        cardNode.backgroundColor = t.secondaryLight
        cardNode.cornerRadius = 12.swh
        cardNode.borderWidth = 1
        cardNode.borderColor = t.border.cgColor

        logoNode.style.preferredSize = CGSize(width: 30.swh, height: 30.swh)
        logoNode.cornerRadius = 10.swh
        logoNode.clipsToBounds = true
        logoNode.contentMode = .scaleAspectFit

        let resolvedAppLogoURL = ImgproxyURL.absoluteResourceURL(from: app.appLogo)
        if !resolvedAppLogoURL.isEmpty {
            let proxyURL = ImgproxyURL.create(from: resolvedAppLogoURL, width: 150, height: 150)
            ChannelAppLogoCache.apply(to: logoNode, urlString: proxyURL)
        } else {
            logoNode.image = UIImage(named: "Channel/channelApp")?.withRenderingMode(.alwaysTemplate)
            logoNode.tintColor = t.textDisabled
            logoNode.contentMode = .center
        }

        let name = app.appName.isEmpty ? "App" : app.appName
        nameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: t.textStrong
            ]
        )
        nameNode.maximumNumberOfLines = 1
        nameNode.style.flexShrink = 1

        statusDot.style.preferredSize = CGSize(width: 8.swh, height: 8.swh)
        statusDot.cornerRadius = 4.swh
        statusDot.backgroundColor = UIColor(red: 0.24, green: 0.82, blue: 0.44, alpha: 1)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let contentRow = ASStackLayoutSpec.horizontal()
        contentRow.children = [logoNode, nameNode]
        contentRow.spacing = 8.sw
        contentRow.alignItems = .center
        contentRow.style.flexShrink = 1
        contentRow.style.flexGrow = 1

        let fullRow = ASStackLayoutSpec.horizontal()
        fullRow.children = [contentRow, statusDot]
        fullRow.spacing = 8.sw
        fullRow.alignItems = .center

        let cardInsets = UIEdgeInsets(top: 0, left: 8.sw, bottom: 0, right: 16.sw)
        let insetContent = ASInsetLayoutSpec(insets: cardInsets, child: fullRow)
        let centered = ASCenterLayoutSpec(centeringOptions: .Y, sizingOptions: .minimumX, child: insetContent)
        centered.style.height = ASDimensionMake(42.sh)
        centered.style.flexGrow = 1

        cardNode.style.flexGrow = 1
        let cardSpec = ASBackgroundLayoutSpec(child: centered, background: cardNode)
        cardSpec.style.flexGrow = 1

        let cellInsets = UIEdgeInsets(top: 0, left: 12.sw, bottom: 8.sh, right: 12.sw)
        return ASInsetLayoutSpec(insets: cellInsets, child: cardSpec)
    }
}


final class ChannelAppSkeletonCellNode: ASCellNode {

    private let pillNodes: [ASDisplayNode]

    override init() {
        pillNodes = (0..<5).map { _ in
            let n = ASDisplayNode()
            n.isLayerBacked = true
            n.cornerRadius = 12.swh
            n.backgroundColor = UIColor.theme.secondaryLight
            n.style.preferredSize = CGSize(width: 56.swh, height: 56.swh)
            return n
        }
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none
        for n in pillNodes {
            addSubnode(n)
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 12.sw,
            justifyContent: .start,
            alignItems: .center,
            children: pillNodes
        )
        let rowInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 12.sw, bottom: 0, right: 12.sw),
            child: row
        )
        let cellInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sh, left: 0, bottom: 8.sh, right: 0),
            child: rowInset
        )
        cellInset.style.height = ASDimensionMake(84.sh)
        return cellInset
    }
}


final class ChannelAppHorizontalCellNode: ASCellNode {

    private let scrollNode: ASScrollNode
    private var itemNodes: [ChannelAppIconNode] = []

    init(apps: [Mezon_Api_ChannelAppResponse], onSelect: @escaping (Mezon_Api_ChannelAppResponse) -> Void) {
        let limit = 10
        let displayApps = apps.count > limit ? Array(apps.prefix(limit)) : apps
        scrollNode = ASScrollNode()
        super.init()
        automaticallyManagesSubnodes = true
        neverShowPlaceholders = true
        backgroundColor = .clear
        selectionStyle = .none

        scrollNode.scrollableDirections = [.left, .right]
        scrollNode.automaticallyManagesContentSize = true
        scrollNode.automaticallyManagesSubnodes = true

        itemNodes = displayApps.map { app in
            ChannelAppIconNode(app: app, onTap: { onSelect(app) })
        }
    }

    override func didLoad() {
        super.didLoad()
        scrollNode.view.showsHorizontalScrollIndicator = false
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 20.sw,
            justifyContent: .start,
            alignItems: .start,
            children: itemNodes
        )
        let rowInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 0, left: 12.sw, bottom: 0, right: 12.sw),
            child: row
        )
        scrollNode.layoutSpecBlock = { _, _ in rowInset }

        let cellInset = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 8.sh, left: 0, bottom: 8.sh, right: 0),
            child: scrollNode
        )
        cellInset.style.height = ASDimensionMake(84.sh)
        return cellInset
    }
}


final class ChannelAppIconNode: ASControlNode {

    private let logoContainerNode = ASDisplayNode()
    private let logoImageNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let onTap: () -> Void

    init(app: Mezon_Api_ChannelAppResponse, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init()
        automaticallyManagesSubnodes = true

        let t = UIColor.theme

        logoContainerNode.backgroundColor = t.primary
        logoContainerNode.cornerRadius = 20.swh
        logoContainerNode.clipsToBounds = true
        logoContainerNode.borderWidth = 0.5
        logoContainerNode.borderColor = UIColor.clear.cgColor

        logoImageNode.contentMode = .scaleAspectFit
        logoImageNode.clipsToBounds = true

        let name = app.appName.isEmpty ? "App" : app.appName
        nameNode.attributedText = NSAttributedString(
            string: name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10.sf, weight: .regular),
                .foregroundColor: t.text,
            ]
        )
        nameNode.maximumNumberOfLines = 1
        nameNode.truncationMode = .byTruncatingTail

        let resolvedAppLogoURL = ImgproxyURL.absoluteResourceURL(from: app.appLogo)
        if !resolvedAppLogoURL.isEmpty {
            let proxyURL = ImgproxyURL.create(from: resolvedAppLogoURL, width: 150, height: 150)
            ChannelAppLogoCache.apply(to: logoImageNode, urlString: proxyURL)
        } else {
            logoImageNode.image = UIImage(named: "Channel/channelApp")?.withRenderingMode(.alwaysTemplate)
            logoImageNode.tintColor = t.textDisabled
            logoImageNode.contentMode = .center
            logoContainerNode.borderColor = t.textDisabled.cgColor
        }
    }

    override func didLoad() {
        super.didLoad()
        addTarget(self, action: #selector(handleTap), forControlEvents: .touchUpInside)
    }

    @objc private func handleTap() {
        onTap()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let boxSize = 40.swh
        logoContainerNode.style.preferredSize = CGSize(width: boxSize, height: boxSize)
        logoImageNode.style.preferredSize = CGSize(width: 24.swh, height: 24.swh)

        let logoCenter = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: [],
            child: logoImageNode
        )
        logoCenter.style.preferredSize = CGSize(width: boxSize, height: boxSize)

        let logoBackground = ASBackgroundLayoutSpec(child: logoCenter, background: logoContainerNode)

        nameNode.style.maxWidth = ASDimensionMake(40.sw)

        let column = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 2.sh,
            justifyContent: .start,
            alignItems: .center,
            children: [logoBackground, nameNode]
        )
        column.style.width = ASDimensionMake(40.sw)
        return column
    }
}

extension Mezon_Api_ChannelAppResponse {
    private var hasPlausibleChannelAppWebURL: Bool {
        let u = appURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return false }
        let lower = u.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return true }
        return lower.contains("://")
    }

    var hasListableChannelAppContent: Bool {
        let n = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let logo = appLogo.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty || !logo.isEmpty || hasPlausibleChannelAppWebURL
    }

    func channelAppWebPageURL(webAppData: String) -> URL? {
        let trimmed = appURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme: String
        let lower = trimmed.lowercased()
        if lower.hasPrefix("https://") {
            withScheme = trimmed
        } else if lower.hasPrefix("http://") {
            withScheme = "https://" + String(trimmed.dropFirst("http://".count))
        } else {
            withScheme = "https://" + trimmed
        }
        let encoded = webAppData.addingPercentEncoding(
            withAllowedCharacters: Self.encodeURIComponentAllowed
        ) ?? webAppData
        let sep = withScheme.contains("?") ? "&" : "?"
        return URL(string: withScheme + sep + "data=" + encoded + "&clanId=\(clanID)")
    }

    private static let encodeURIComponentAllowed: CharacterSet = {
        CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~!*'()"
        )
    }()

    static func channelAppsPreservingPreviousLabels(
        newApps: [Mezon_Api_ChannelAppResponse],
        previousApps: [Mezon_Api_ChannelAppResponse]
    ) -> [Mezon_Api_ChannelAppResponse] {
        guard !previousApps.isEmpty else { return newApps }
        var byChannel: [Int64: Mezon_Api_ChannelAppResponse] = [:]
        var byApp: [Int64: Mezon_Api_ChannelAppResponse] = [:]
        var byId: [Int64: Mezon_Api_ChannelAppResponse] = [:]
        for a in previousApps {
            if a.channelID != 0 { byChannel[a.channelID] = a }
            if a.appID != 0 { byApp[a.appID] = a }
            if a.id != 0 { byId[a.id] = a }
        }
        return newApps.map { app in
            let prev: Mezon_Api_ChannelAppResponse?
            if app.channelID != 0, let p = byChannel[app.channelID] {
                prev = p
            } else if app.appID != 0, let p = byApp[app.appID] {
                prev = p
            } else if app.id != 0, let p = byId[app.id] {
                prev = p
            } else {
                prev = nil
            }
            guard let prev else { return app }
            var out = app
            if out.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !prev.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.appName = prev.appName
            }
            if out.appLogo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !prev.appLogo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.appLogo = prev.appLogo
            }
            if out.appURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !prev.appURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.appURL = prev.appURL
            }
            return out
        }
    }
}

extension Mezon_Api_ListChannelAppsResponse {
    static func decodeChannelApps(_ data: Data) -> [Mezon_Api_ChannelAppResponse] {
        guard !data.isEmpty else { return [] }
        if let resp = try? Mezon_Api_ListChannelAppsResponse(serializedBytes: data) {
            return resp.channelApps
        }
        return []
    }

    static func encodeChannelApps(_ apps: [Mezon_Api_ChannelAppResponse]) -> Data {
        var r = Mezon_Api_ListChannelAppsResponse()
        r.channelApps = apps
        return (try? r.serializedData()) ?? Data()
    }
}
