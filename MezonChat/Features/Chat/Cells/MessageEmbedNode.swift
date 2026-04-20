import UIKit
import AsyncDisplayKit

final class MessageEmbedNode: ASDisplayNode {

    private var embedNodes: [EmbedItemNode] = []
    private var cachedTotalSize: CGSize = .zero
    var onEmbedImageTapped: ((String) -> Void)?

    override init() {
        super.init()
    }

    func configure(embeds: [ParsedEmbed]) {
        embedNodes.forEach { $0.removeFromSupernode() }
        embedNodes = embeds.map { EmbedItemNode(embed: $0) }
        for node in embedNodes {
            node.onEmbedImageTapped = { [weak self] url in
                self?.onEmbedImageTapped?(url)
            }
            addSubnode(node)
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard !embedNodes.isEmpty else {
            cachedTotalSize = .zero
            return .zero
        }
        let spacing: CGFloat = 8
        var totalH: CGFloat = 0
        for (i, node) in embedNodes.enumerated() {
            if i > 0 { totalH += spacing }
            let sz = node.measureSize(maxWidth: maxWidth)
            _ = sz
            totalH += node.cachedSize.height
        }
        cachedTotalSize = CGSize(width: maxWidth, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let spacing: CGFloat = 8
        var y: CGFloat = 0
        for (i, node) in embedNodes.enumerated() {
            if i > 0 { y += spacing }
            node.frame = CGRect(x: 0, y: y, width: node.cachedSize.width, height: node.cachedSize.height)
            y += node.cachedSize.height
        }
    }
}

final class EmbedItemNode: ASDisplayNode {

    private let colorBarNode = ASDisplayNode()
    private let contentBgNode = ASDisplayNode()
    private var authorIconNode: TransformImageNode?
    private var authorNameNode: ASTextNode2?
    private var titleNode: ASTextNode2?
    private var descriptionNode: ASTextNode2?
    private var fieldNodes: [ASTextNode2] = []
    private var imageNode: TransformImageNode?
    private var thumbnailNode: TransformImageNode?
    private var footerIconNode: TransformImageNode?
    private var footerTextNode: ASTextNode2?

    private let embed: ParsedEmbed
    var onEmbedImageTapped: ((String) -> Void)?

    private static let colorBarWidth: CGFloat = 4
    private static let thumbnailSize: CGFloat = 50
    private static let contentInsetH: CGFloat = 10
    private static let contentInsetV: CGFloat = 10
    private static let embedImageProxyDimension: Int = 200
    private static let embedImageMinDisplayHeight: CGFloat = 260
    private static let embedImageMaxDisplayHeight: CGFloat = 400

    fileprivate(set) var cachedSize: CGSize = .zero

    private var cachedAuthorIconSize: CGSize = .zero
    private var cachedAuthorNameSize: CGSize = .zero
    private var cachedTitleSize: CGSize = .zero
    private var cachedDescSize: CGSize = .zero
    private var cachedFieldSizes: [CGSize] = []
    private var cachedImageSize: CGSize = .zero
    private var cachedThumbSize: CGSize = .zero
    private var cachedFooterIconSize: CGSize = .zero
    private var cachedFooterTextSize: CGSize = .zero
    private var cachedContentColumnH: CGFloat = 0

    init(embed: ParsedEmbed) {
        self.embed = embed
        super.init()

        let t = UIColor.theme

        if let hex = embed.color, !hex.isEmpty {
            colorBarNode.backgroundColor = UIColor(embedHex: hex)
        } else {
            colorBarNode.backgroundColor = .systemIndigo
        }
        colorBarNode.cornerRadius = 2
        addSubnode(colorBarNode)

        contentBgNode.backgroundColor = t.secondaryLight
        contentBgNode.cornerRadius = 4
        insertSubnode(contentBgNode, at: 0)

        if let authorName = embed.authorName, !authorName.isEmpty {
            let node = ASTextNode2()
            node.attributedText = NSAttributedString(
                string: authorName,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: t.textStrong,
                ]
            )
            node.maximumNumberOfLines = 1
            authorNameNode = node
            addSubnode(node)

            if let iconURL = embed.authorIconURL, !iconURL.isEmpty {
                let icon = TransformImageNode()
                icon.setSignal(remoteImageSignal(url: iconURL, resizeMode: .fill), attemptSynchronously: false)
                let layout = icon.asyncLayout()
                let apply = layout(TransformImageArguments(
                    corners: ImageCorners(radius: 14),
                    imageSize: CGSize(width: 28, height: 28),
                    boundingSize: CGSize(width: 28, height: 28),
                    intrinsicInsets: .zero
                ))
                apply()
                authorIconNode = icon
                addSubnode(icon)
            }
        }

        if let title = embed.title, !title.isEmpty {
            let node = ASTextNode2()
            let attrs: [NSAttributedString.Key: Any]
            if embed.url != nil {
                attrs = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: UIColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
            } else {
                attrs = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: t.textStrong,
                ]
            }
            node.attributedText = NSAttributedString(string: title, attributes: attrs)
            node.maximumNumberOfLines = 3
            titleNode = node
            addSubnode(node)
        }

        if let desc = embed.description, !desc.isEmpty {
            let node = ASTextNode2()
            node.attributedText = NSAttributedString(
                string: desc,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: t.text,
                ]
            )
            node.maximumNumberOfLines = 10
            descriptionNode = node
            addSubnode(node)
        }

        fieldNodes = []
        for field in embed.fields {
            let node = ASTextNode2()
            let mas = NSMutableAttributedString()
            if !field.name.isEmpty {
                mas.append(NSAttributedString(
                    string: field.name + "\n",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                        .foregroundColor: t.textStrong,
                    ]
                ))
            }
            mas.append(NSAttributedString(
                string: field.value,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13),
                    .foregroundColor: t.text,
                ]
            ))
            node.attributedText = mas
            node.maximumNumberOfLines = 0
            fieldNodes.append(node)
            addSubnode(node)
        }

        if let imageURL = embed.imageURL, !imageURL.isEmpty {
            let node = TransformImageNode()
            node.contentAnimations = [.firstUpdate]
            let d = Self.embedImageProxyDimension
            let embedProxyURL = ImgproxyURL.attachmentURL(from: imageURL, width: d, height: d)
            let hasMem = ImageCache.shared.memoryImage(forKey: embedProxyURL) != nil
            node.setSignal(remoteImageSignal(url: embedProxyURL, resizeMode: .fillLeading), attemptSynchronously: hasMem)
            imageNode = node
            addSubnode(node)
        }

        if let thumbURL = embed.thumbnailURL, !thumbURL.isEmpty {
            let node = TransformImageNode()
            let thumbProxy = ImgproxyURL.attachmentURL(from: thumbURL, width: Int(Self.thumbnailSize) * Int(UIScreen.main.scale), height: Int(Self.thumbnailSize) * Int(UIScreen.main.scale), resizeType: "fill")
            let hasThumbMem = ImageCache.shared.memoryImage(forKey: thumbProxy) != nil
            node.setSignal(remoteImageSignal(url: thumbProxy, resizeMode: .fill), attemptSynchronously: hasThumbMem)
            let layout = node.asyncLayout()
            let apply = layout(TransformImageArguments(
                corners: ImageCorners(radius: 4),
                imageSize: CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize),
                boundingSize: CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize),
                intrinsicInsets: .zero
            ))
            apply()
            thumbnailNode = node
            addSubnode(node)
        }

        if let footerText = embed.footerText, !footerText.isEmpty {
            let node = ASTextNode2()
            var text = footerText
            if let ts = embed.timestamp, !ts.isEmpty {
                let dateStr = Self.formatTimestamp(ts)
                if !dateStr.isEmpty { text += " • \(dateStr)" }
            }
            node.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: t.textDisabled,
                ]
            )
            node.maximumNumberOfLines = 1
            footerTextNode = node
            addSubnode(node)

            if let iconURL = embed.footerIconURL, !iconURL.isEmpty {
                let icon = TransformImageNode()
                icon.setSignal(remoteImageSignal(url: iconURL, resizeMode: .fill), attemptSynchronously: false)
                let layout = icon.asyncLayout()
                let apply = layout(TransformImageArguments(
                    corners: ImageCorners(radius: 12),
                    imageSize: CGSize(width: 24, height: 24),
                    boundingSize: CGSize(width: 24, height: 24),
                    intrinsicInsets: .zero
                ))
                apply()
                footerIconNode = icon
                addSubnode(icon)
            }
        }
    }

    override func didLoad() {
        super.didLoad()
        if embed.url != nil, let titleNode = titleNode {
            titleNode.view.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTitleTap))
            titleNode.view.addGestureRecognizer(tap)
        }
        if let imageNode {
            imageNode.isUserInteractionEnabled = true
            imageNode.view.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleEmbedMainImageTap))
            imageNode.view.addGestureRecognizer(tap)
        }
    }

    @objc private func handleTitleTap() {
        guard let urlStr = embed.url, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func handleEmbedMainImageTap() {
        guard let url = embed.imageURL, !url.isEmpty else { return }
        onEmbedImageTapped?(url)
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let barW = Self.colorBarWidth
        let inH = Self.contentInsetH
        let inV = Self.contentInsetV
        let spacing: CGFloat = 6

        let thumbW = thumbnailNode != nil ? Self.thumbnailSize + 10 : 0
        let contentMaxW = maxWidth - barW - inH * 2 - thumbW

        var contentH: CGFloat = 0


        if let authorNameNode {
            cachedAuthorNameSize = authorNameNode.measure(CGSize(width: contentMaxW - 36, height: 30))
            cachedAuthorIconSize = authorIconNode != nil ? CGSize(width: 28, height: 28) : .zero
            let rowH = max(cachedAuthorIconSize.height, cachedAuthorNameSize.height)
            contentH += rowH + spacing
        }


        if let titleNode {
            cachedTitleSize = titleNode.measure(CGSize(width: contentMaxW, height: .greatestFiniteMagnitude))
            contentH += cachedTitleSize.height + spacing
        }


        if let descriptionNode {
            cachedDescSize = descriptionNode.measure(CGSize(width: contentMaxW, height: .greatestFiniteMagnitude))
            contentH += cachedDescSize.height + spacing
        }

        cachedFieldSizes = fieldNodes.map {
            $0.measure(CGSize(width: contentMaxW, height: .greatestFiniteMagnitude))
        }
        for sz in cachedFieldSizes {
            contentH += sz.height + spacing
        }

        if let footerTextNode {
            cachedFooterTextSize = footerTextNode.measure(CGSize(width: contentMaxW - 30, height: 30))
            cachedFooterIconSize = footerIconNode != nil ? CGSize(width: 24, height: 24) : .zero
            let rowH = max(cachedFooterIconSize.height, cachedFooterTextSize.height)
            contentH += rowH + spacing
        }

        if contentH > 0 { contentH -= spacing }
        cachedContentColumnH = contentH


        cachedThumbSize = thumbnailNode != nil ? CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize) : .zero
        let mainRowH = max(contentH, cachedThumbSize.height)

        var totalH = inV + mainRowH + inV


        if let imageNode {
            let imgContentW = maxWidth - barW - inH * 2
            let finalW = max(imgContentW, 100)
            let metaW = max(CGFloat(embed.imageWidth ?? 400), 1)
            let metaH = max(CGFloat(embed.imageHeight ?? 200), 1)
            let aspect = metaW / metaH
            var finalH = floor(finalW / aspect)
            finalH = min(Self.embedImageMaxDisplayHeight, max(Self.embedImageMinDisplayHeight, finalH))
            cachedImageSize = CGSize(width: finalW, height: finalH)

            let args = TransformImageArguments(
                corners: ImageCorners(radius: 4),
                imageSize: cachedImageSize,
                boundingSize: cachedImageSize,
                intrinsicInsets: .zero
            )
            let layout = imageNode.asyncLayout()
            let apply = layout(args)
            apply()

            totalH += 8 + finalH
        }

        cachedSize = CGSize(width: maxWidth, height: totalH)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let barW = Self.colorBarWidth
        let inH = Self.contentInsetH
        let inV = Self.contentInsetV
        let spacing: CGFloat = 6
        let w = bounds.width
        let h = bounds.height

        contentBgNode.frame = bounds
        colorBarNode.frame = CGRect(x: 0, y: 0, width: barW, height: h)

        var y = inV
        let contentX = barW + inH

        let thumbW = thumbnailNode != nil ? Self.thumbnailSize + 10 : 0
        let contentMaxW = w - barW - inH * 2 - thumbW

        if let authorNameNode {
            var ax = contentX
            if let authorIconNode {
                authorIconNode.frame = CGRect(x: ax, y: y, width: cachedAuthorIconSize.width, height: cachedAuthorIconSize.height)
                ax += cachedAuthorIconSize.width + 8
            }
            let rowH = max(cachedAuthorIconSize.height, cachedAuthorNameSize.height)
            authorNameNode.frame = CGRect(x: ax, y: y + (rowH - cachedAuthorNameSize.height) / 2, width: cachedAuthorNameSize.width, height: cachedAuthorNameSize.height)
            y += rowH + spacing
        }

        if let titleNode {
            titleNode.frame = CGRect(x: contentX, y: y, width: cachedTitleSize.width, height: cachedTitleSize.height)
            y += cachedTitleSize.height + spacing
        }

        if let descriptionNode {
            descriptionNode.frame = CGRect(x: contentX, y: y, width: cachedDescSize.width, height: cachedDescSize.height)
            y += cachedDescSize.height + spacing
        }

        for (node, sz) in zip(fieldNodes, cachedFieldSizes) {
            node.frame = CGRect(x: contentX, y: y, width: sz.width, height: sz.height)
            y += sz.height + spacing
        }

        if let footerTextNode {
            var fx = contentX
            if let footerIconNode {
                footerIconNode.frame = CGRect(x: fx, y: y, width: cachedFooterIconSize.width, height: cachedFooterIconSize.height)
                fx += cachedFooterIconSize.width + 6
            }
            let rowH = max(cachedFooterIconSize.height, cachedFooterTextSize.height)
            footerTextNode.frame = CGRect(x: fx, y: y + (rowH - cachedFooterTextSize.height) / 2, width: cachedFooterTextSize.width, height: cachedFooterTextSize.height)
            y += rowH + spacing
        }


        if let thumbnailNode {
            thumbnailNode.frame = CGRect(x: w - inH - Self.thumbnailSize, y: inV, width: Self.thumbnailSize, height: Self.thumbnailSize)
        }

        if let imageNode {
            imageNode.frame = CGRect(x: contentX, y: y + 2, width: cachedImageSize.width, height: cachedImageSize.height)
        }
    }

    private static func formatTimestamp(_ ts: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: ts) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: ts) {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df.string(from: date)
        }
        return ""
    }
}

private extension UIColor {
    convenience init(embedHex hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.hasPrefix("0x") { hex = String(hex.dropFirst(2)) }

        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)

        let r, g, b: CGFloat
        if hex.count == 6 {
            r = CGFloat((rgb >> 16) & 0xFF) / 255
            g = CGFloat((rgb >> 8) & 0xFF) / 255
            b = CGFloat(rgb & 0xFF) / 255
        } else {
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
