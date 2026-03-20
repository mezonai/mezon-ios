import UIKit
import AsyncDisplayKit

final class MessageEmbedNode: ASDisplayNode {

    private var embedNodes: [EmbedItemNode] = []

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
    }

    func configure(embeds: [ParsedEmbed]) {
        embedNodes = embeds.map { EmbedItemNode(embed: $0) }
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        guard !embedNodes.isEmpty else { return ASLayoutSpec() }
        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .start,
            alignItems: .stretch,
            children: embedNodes
        )
    }
}

private final class EmbedItemNode: ASDisplayNode {

    private let colorBarNode = ASDisplayNode()
    private let contentBgNode = ASDisplayNode()
    private var authorIconNode: TransformImageNode?
    private var authorNameNode: ASTextNode2?
    private var titleNode: ASTextNode2?
    private var descriptionNode: ASTextNode2?
    private var imageNode: TransformImageNode?
    private var thumbnailNode: TransformImageNode?
    private var footerIconNode: TransformImageNode?
    private var footerTextNode: ASTextNode2?

    private let embed: ParsedEmbed

    private static let colorBarWidth: CGFloat = 4
    private static let thumbnailSize: CGFloat = 50

    init(embed: ParsedEmbed) {
        self.embed = embed
        super.init()
        automaticallyManagesSubnodes = true

        let t = UIColor.theme

        // Color bar
        if let hex = embed.color, !hex.isEmpty {
            colorBarNode.backgroundColor = UIColor(embedHex: hex)
        } else {
            colorBarNode.backgroundColor = .systemIndigo
        }
        colorBarNode.cornerRadius = 2

        // Content background
        contentBgNode.backgroundColor = t.secondaryLight
        contentBgNode.cornerRadius = 4

        // Author
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
            }
        }

        // Title
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
        }

        // Description
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
        }

        // Image
        if let imageURL = embed.imageURL, !imageURL.isEmpty {
            let node = TransformImageNode()
            node.contentAnimations = [.firstUpdate]
            node.setSignal(remoteImageSignal(url: imageURL, resizeMode: .fit), attemptSynchronously: false)
            imageNode = node
        }

        // Thumbnail
        if let thumbURL = embed.thumbnailURL, !thumbURL.isEmpty {
            let node = TransformImageNode()
            node.setSignal(remoteImageSignal(url: thumbURL, resizeMode: .fill), attemptSynchronously: false)
            let layout = node.asyncLayout()
            let apply = layout(TransformImageArguments(
                corners: ImageCorners(radius: 4),
                imageSize: CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize),
                boundingSize: CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize),
                intrinsicInsets: .zero
            ))
            apply()
            thumbnailNode = node
        }

        // Footer
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
    }

    @objc private func handleTitleTap() {
        guard let urlStr = embed.url, let url = URL(string: urlStr) else { return }
        UIApplication.shared.open(url)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let maxW = constrainedSize.max.width

        // Build content column
        var contentChildren: [ASLayoutElement] = []

        // Author row
        if let authorNameNode = authorNameNode {
            if let authorIconNode = authorIconNode {
                authorIconNode.style.preferredSize = CGSize(width: 28, height: 28)
                let row = ASStackLayoutSpec(direction: .horizontal, spacing: 8, justifyContent: .start, alignItems: .center, children: [authorIconNode, authorNameNode])
                contentChildren.append(row)
            } else {
                contentChildren.append(authorNameNode)
            }
        }

        if let titleNode = titleNode {
            contentChildren.append(titleNode)
        }

        if let descriptionNode = descriptionNode {
            contentChildren.append(descriptionNode)
        }

        // Footer row
        if let footerTextNode = footerTextNode {
            if let footerIconNode = footerIconNode {
                footerIconNode.style.preferredSize = CGSize(width: 24, height: 24)
                let row = ASStackLayoutSpec(direction: .horizontal, spacing: 6, justifyContent: .start, alignItems: .center, children: [footerIconNode, footerTextNode])
                contentChildren.append(row)
            } else {
                contentChildren.append(footerTextNode)
            }
        }

        let contentColumn = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 6,
            justifyContent: .start,
            alignItems: .start,
            children: contentChildren
        )
        contentColumn.style.flexShrink = 1
        contentColumn.style.flexGrow = 1

        // Main row: content + optional thumbnail
        var mainRowChildren: [ASLayoutElement] = [contentColumn]
        if let thumbnailNode = thumbnailNode {
            thumbnailNode.style.preferredSize = CGSize(width: Self.thumbnailSize, height: Self.thumbnailSize)
            mainRowChildren.append(thumbnailNode)
        }

        let mainRow = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 10,
            justifyContent: .start,
            alignItems: .start,
            children: mainRowChildren
        )

        // Vertical: main row + optional image
        var verticalChildren: [ASLayoutElement] = [mainRow]

        if let imageNode = imageNode {
            let imgW = CGFloat(embed.imageWidth ?? 400)
            let imgH = CGFloat(embed.imageHeight ?? 200)
            let contentW = maxW - Self.colorBarWidth - 10 - 20
            let ratio = min(contentW / max(imgW, 1), 1.0)
            let finalW = max(floor(imgW * ratio), 100)
            let finalH = max(floor(imgH * ratio), 60)

            imageNode.style.preferredSize = CGSize(width: finalW, height: finalH)
            let args = TransformImageArguments(
                corners: ImageCorners(radius: 4),
                imageSize: CGSize(width: finalW, height: finalH),
                boundingSize: CGSize(width: finalW, height: finalH),
                intrinsicInsets: .zero
            )
            let layout = imageNode.asyncLayout()
            let apply = layout(args)
            apply()
            verticalChildren.append(imageNode)
        }

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .start,
            alignItems: .stretch,
            children: verticalChildren
        )

        let contentInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        let contentInsetSpec = ASInsetLayoutSpec(insets: contentInsets, child: contentStack)

        // Color bar
        colorBarNode.style.width = ASDimensionMake(Self.colorBarWidth)
        colorBarNode.style.flexGrow = 1

        let barAndContent = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 0,
            justifyContent: .start,
            alignItems: .stretch,
            children: [colorBarNode, contentInsetSpec]
        )

        return ASBackgroundLayoutSpec(child: barAndContent, background: contentBgNode)
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
