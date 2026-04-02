import UIKit
import AsyncDisplayKit

final class ChannelAppCellNode: ASCellNode {

    private let cardNode = ASDisplayNode()
    private let logoNode = ASImageNode()
    private let nameNode = ASTextNode2()
    private let statusDot = ASDisplayNode()

    init(app: Mezon_Api_ChannelAppResponse) {
        super.init()
        automaticallyManagesSubnodes = true
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

        if !app.appLogo.isEmpty {
            let proxyURL = ImgproxyURL.create(from: app.appLogo)
            if let cached = ImageCache.shared.cachedImage(forURL: proxyURL) {
                logoNode.image = cached
            } else {
                ImageCache.shared.loadImage(urlString: proxyURL) { [weak self] image in
                    guard let self, let image else { return }
                    self.logoNode.image = image
                }
            }
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


final class ChannelAppHorizontalCellNode: ASCellNode {

    private let scrollNode: ASScrollNode
    private var itemNodes: [ChannelAppIconNode] = []

    init(apps: [Mezon_Api_ChannelAppResponse]) {
        let limit = 10
        let displayApps = apps.count > limit ? Array(apps.prefix(limit)) : apps
        scrollNode = ASScrollNode()
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
        selectionStyle = .none

        scrollNode.scrollableDirections = [.left, .right]
        scrollNode.automaticallyManagesContentSize = true
        scrollNode.automaticallyManagesSubnodes = true

        itemNodes = displayApps.map { ChannelAppIconNode(app: $0) }
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


final class ChannelAppIconNode: ASDisplayNode {

    private let logoContainerNode = ASDisplayNode()
    private let logoImageNode = ASImageNode()
    private let nameNode = ASTextNode2()

    init(app: Mezon_Api_ChannelAppResponse) {
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

        if !app.appLogo.isEmpty {
            let proxyURL = ImgproxyURL.create(from: app.appLogo)
            if let cached = ImageCache.shared.cachedImage(forURL: proxyURL) {
                logoImageNode.image = cached
            } else {
                let id = app.appName
                ImageCache.shared.loadImage(urlString: proxyURL) { [weak self] image in
                    guard let self, let image, self.nameNode.attributedText?.string == id else { return }
                    self.logoImageNode.image = image
                }
            }
        } else {
            logoImageNode.image = UIImage(named: "Channel/channelApp")?.withRenderingMode(.alwaysTemplate)
            logoImageNode.tintColor = t.textDisabled
            logoImageNode.contentMode = .center
            logoContainerNode.borderColor = t.textDisabled.cgColor
        }
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


