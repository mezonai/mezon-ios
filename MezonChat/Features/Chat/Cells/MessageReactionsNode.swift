import UIKit
import AsyncDisplayKit

final class MessageReactionsNode: ASDisplayNode {

    private var pillNodes: [ReactionPillNode] = []

    private struct LayoutRow {
        var frames: [(index: Int, frame: CGRect)]
        var height: CGFloat
    }
    private var cachedRows: [LayoutRow] = []
    private var cachedTotalSize: CGSize = .zero

    override init() {
        super.init()
    }

    func configure(reactions: [ParsedReaction]) {
        pillNodes.forEach { $0.removeFromSupernode() }
        pillNodes = reactions.map { ReactionPillNode(reaction: $0) }
        pillNodes.forEach { addSubnode($0) }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        guard !pillNodes.isEmpty else {
            cachedTotalSize = .zero
            cachedRows = []
            return .zero
        }

        let spacing: CGFloat = 6.sw
        var rows: [LayoutRow] = []
        var currentRowFrames: [(index: Int, frame: CGRect)] = []
        var currentX: CGFloat = 0
        var currentRowMaxH: CGFloat = 0
        var totalY: CGFloat = 0

        for (i, pill) in pillNodes.enumerated() {
            let pillSize = pill.calculatedSize(maxWidth: maxWidth)
            let neededWidth = currentRowFrames.isEmpty ? pillSize.width : pillSize.width + spacing

            if currentX + neededWidth > maxWidth && !currentRowFrames.isEmpty {
                rows.append(LayoutRow(frames: currentRowFrames, height: currentRowMaxH))
                totalY += currentRowMaxH + spacing
                currentRowFrames = []
                currentX = 0
                currentRowMaxH = 0
            }

            let x = currentRowFrames.isEmpty ? 0 : currentX + spacing
            currentRowFrames.append((index: i, frame: CGRect(x: x, y: totalY, width: pillSize.width, height: pillSize.height)))
            currentX = x + pillSize.width
            currentRowMaxH = max(currentRowMaxH, pillSize.height)
        }

        if !currentRowFrames.isEmpty {
            rows.append(LayoutRow(frames: currentRowFrames, height: currentRowMaxH))
            totalY += currentRowMaxH
        }

        cachedRows = rows
        cachedTotalSize = CGSize(width: maxWidth, height: totalY)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        for row in cachedRows {
            for entry in row.frames {
                guard entry.index < pillNodes.count else { continue }
                pillNodes[entry.index].frame = entry.frame
            }
        }
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

    private var cachedCountSize: CGSize = .zero

    init(reaction: ParsedReaction) {
        super.init()

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
        addSubnode(emojiImageNode)

        let fallbackText = !reaction.emoji.isEmpty ? reaction.emoji : "?"
        emojiFallbackNode.attributedText = NSAttributedString(
            string: fallbackText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.sf),
            ]
        )
        addSubnode(emojiFallbackNode)

        countNode.attributedText = NSAttributedString(
            string: "\(reaction.count)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
        addSubnode(countNode)

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
        cachedCountSize = countNode.measure(CGSize(width: maxWidth, height: Self.pillHeight))
        let width = 6.sw + Self.emojiSize + 4.sw + ceil(cachedCountSize.width) + 6.sw
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

    override func layout() {
        super.layout()
        let emojiSz = Self.emojiSize
        let insetH: CGFloat = 6.sw
        let spacing: CGFloat = 4.sw
        let centerY = bounds.height / 2

        let emojiX = insetH
        emojiImageNode.frame = CGRect(x: emojiX, y: centerY - emojiSz / 2, width: emojiSz, height: emojiSz)
        emojiFallbackNode.frame = CGRect(x: emojiX, y: centerY - emojiSz / 2, width: emojiSz, height: emojiSz)

        let countX = emojiX + emojiSz + spacing
        countNode.frame = CGRect(x: countX, y: centerY - cachedCountSize.height / 2, width: cachedCountSize.width, height: cachedCountSize.height)
    }
}
