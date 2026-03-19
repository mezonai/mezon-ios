import UIKit
import AsyncDisplayKit

final class MessageReactionsNode: ASDisplayNode {

    private var pillNodes: [ReactionPillNode] = []

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
    }

    func configure(reactions: [ParsedReaction]) {
        pillNodes = reactions.map { ReactionPillNode(reaction: $0) }
        setNeedsLayout()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        guard !pillNodes.isEmpty else {
            return ASLayoutSpec()
        }

        // Flow layout: wrap pills into rows
        let maxW = constrainedSize.max.width
        let spacing: CGFloat = 6.sw

        var rows: [ASStackLayoutSpec] = []
        var currentRowChildren: [ASLayoutElement] = []
        var currentRowWidth: CGFloat = 0

        for pill in pillNodes {
            let pillSize = pill.calculatedSize(maxWidth: maxW)
            let neededWidth = currentRowChildren.isEmpty ? pillSize.width : pillSize.width + spacing

            if currentRowWidth + neededWidth > maxW && !currentRowChildren.isEmpty {
                let row = ASStackLayoutSpec(
                    direction: .horizontal,
                    spacing: spacing,
                    justifyContent: .start,
                    alignItems: .center,
                    children: currentRowChildren
                )
                rows.append(row)
                currentRowChildren = []
                currentRowWidth = 0
            }

            pill.style.preferredSize = pillSize
            currentRowChildren.append(pill)
            currentRowWidth += currentRowChildren.count == 1 ? pillSize.width : pillSize.width + spacing
        }

        if !currentRowChildren.isEmpty {
            let row = ASStackLayoutSpec(
                direction: .horizontal,
                spacing: spacing,
                justifyContent: .start,
                alignItems: .center,
                children: currentRowChildren
            )
            rows.append(row)
        }

        return ASStackLayoutSpec(
            direction: .vertical,
            spacing: spacing,
            justifyContent: .start,
            alignItems: .start,
            children: rows
        )
    }
}

// MARK: - Reaction Pill Node

final class ReactionPillNode: ASDisplayNode {

    private let emojiImageNode = ASImageNode()
    private let emojiFallbackNode = ASTextNode2()
    private let countNode = ASTextNode2()

    private var imageTask: URLSessionDataTask?
    private static let emojiSize: CGFloat = 20
    private static let pillHeight: CGFloat = 28

    init(reaction: ParsedReaction) {
        super.init()
        automaticallyManagesSubnodes = true

        let t = UIColor.theme

        if reaction.isMe {
            backgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 0.2)
            borderWidth = 1
            borderColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 0.6).cgColor
        } else {
            backgroundColor = t.secondary
        }
        cornerRadius = 5.swh
        clipsToBounds = true

        emojiImageNode.contentMode = .scaleAspectFit
        emojiImageNode.clipsToBounds = true

        let fallbackText = !reaction.emoji.isEmpty ? reaction.emoji : "?"
        emojiFallbackNode.attributedText = NSAttributedString(
            string: fallbackText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf),
            ]
        )

        countNode.attributedText = NSAttributedString(
            string: "\(reaction.count)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )

        let url = MezonConfig.emojiImageURL(emojiId: reaction.emojiId)
        if let url = url {
            emojiFallbackNode.isHidden = true
            loadEmojiImage(url: url)
        } else {
            emojiImageNode.isHidden = true
        }
    }

    deinit {
        imageTask?.cancel()
    }

    func calculatedSize(maxWidth: CGFloat) -> CGSize {
        let countSize = countNode.attributedText?.boundingRect(
            with: CGSize(width: maxWidth, height: Self.pillHeight),
            options: .usesLineFragmentOrigin,
            context: nil
        ).size ?? .zero

        let width = 6.sw + Self.emojiSize + 4.sw + ceil(countSize.width) + 6.sw
        return CGSize(width: width, height: Self.pillHeight.sh)
    }

    private func loadEmojiImage(url: URL) {
        if let cached = ImageCache.shared.image(forKey: url.absoluteString) {
            emojiImageNode.image = cached
            return
        }
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage.decodeImage(from: data) else { return }
            ImageCache.shared.setImage(image, data: data, forKey: url.absoluteString)
            DispatchQueue.main.async {
                self?.emojiImageNode.image = image
                self?.emojiFallbackNode.isHidden = true
            }
        }
        imageTask?.resume()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let emojiSz = Self.emojiSize
        emojiImageNode.style.preferredSize = CGSize(width: emojiSz, height: emojiSz)
        emojiFallbackNode.style.preferredSize = CGSize(width: emojiSz, height: emojiSz)

        let emojiNode: ASLayoutElement = emojiImageNode.isHidden ? emojiFallbackNode : emojiImageNode

        let row = ASStackLayoutSpec(
            direction: .horizontal,
            spacing: 4.sw,
            justifyContent: .center,
            alignItems: .center,
            children: [emojiNode, countNode]
        )

        let insets = UIEdgeInsets(top: 0, left: 6.sw, bottom: 0, right: 6.sw)
        let inset = ASInsetLayoutSpec(insets: insets, child: row)
        inset.style.height = ASDimensionMake(Self.pillHeight.sh)
        return inset
    }
}
