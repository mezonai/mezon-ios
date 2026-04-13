import UIKit
import AsyncDisplayKit

final class MessageReactionsNode: ASDisplayNode {

    private var pillNodes: [ReactionPillNode] = []
    private var currentReactions: [ParsedReaction] = []
    var onReactionTapped: ((ParsedReaction) -> Void)?
    var onReactionLongPressed: ((ParsedReaction) -> Void)?
    var onAddReactionTapped: (() -> Void)?
    var onStripBackgroundLongPressed: (() -> Void)?

    private static let maxVisiblePills = 20
    private static let addButtonDiameter: CGFloat = 28

    private var overflowNode: ASTextNode2?
    private var showAddButton = false

    private let addReactionButtonNode = ASButtonNode()

    private struct LayoutRow {
        var frames: [(index: Int, frame: CGRect)]
        var height: CGFloat
    }
    private var cachedRows: [LayoutRow] = []
    private var cachedTotalSize: CGSize = .zero

    override init() {
        super.init()
        automaticallyManagesSubnodes = false
        isUserInteractionEnabled = true

        let t = UIColor.theme
        addReactionButtonNode.backgroundColor = .clear
        addReactionButtonNode.tintColor = t.textDisabled
        addReactionButtonNode.clipsToBounds = true
        addReactionButtonNode.contentMode = .center
        let iconSize = CGSize(width: 20, height: 20)
        if let pdf = UIImage(named: "Chat/FaceIcon")?.withRenderingMode(.alwaysTemplate) {
            let resized = UIGraphicsImageRenderer(size: iconSize).image { _ in
                pdf.draw(in: CGRect(origin: .zero, size: iconSize))
            }.withRenderingMode(.alwaysTemplate)
            addReactionButtonNode.setImage(resized, for: .normal)
        }
        addReactionButtonNode.addTarget(self, action: #selector(addReactionControlTapped), forControlEvents: .touchUpInside)
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.32
        long.cancelsTouchesInView = false
        view.addGestureRecognizer(long)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let loc = gesture.location(in: view)
        if addButtonHit(at: loc) { return }
        pillAt(location: loc).map { onReactionTapped?($0) }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let loc = gesture.location(in: view)
        if addButtonHit(at: loc) {
            onAddReactionTapped?()
            return
        }
        if let pill = pillAt(location: loc) {
            onReactionLongPressed?(pill)
            return
        }
        onStripBackgroundLongPressed?()
    }

    @objc private func addReactionControlTapped() {
        onAddReactionTapped?()
    }

    private func addButtonHit(at location: CGPoint) -> Bool {
        guard showAddButton, !addReactionButtonNode.isHidden, addReactionButtonNode.supernode === self else { return false }
        return addReactionButtonNode.frame.contains(location)
    }

    private func syncAddReactionSubnode() {
        addReactionButtonNode.removeFromSupernode()
        guard showAddButton else {
            addReactionButtonNode.isHidden = true
            return
        }
        addSubnode(addReactionButtonNode)
        addReactionButtonNode.isHidden = false
    }

    private func pillAt(location: CGPoint) -> ParsedReaction? {
        for (i, pill) in pillNodes.enumerated() {
            if pill.frame.contains(location), i < currentReactions.count {
                return currentReactions[i]
            }
        }
        return nil
    }

    func configure(reactions: [ParsedReaction], showAddButton: Bool) {
        self.showAddButton = showAddButton
        pillNodes.forEach { $0.removeFromSupernode() }
        overflowNode?.removeFromSupernode()
        overflowNode = nil

        let visible = Array(reactions.prefix(Self.maxVisiblePills))
        currentReactions = visible

        pillNodes = visible.map { ReactionPillNode(reaction: $0) }
        pillNodes.forEach { addSubnode($0) }

        if reactions.count > Self.maxVisiblePills {
            let node = ASTextNode2()
            let remaining = reactions.count - Self.maxVisiblePills
            node.attributedText = NSAttributedString(
                string: "+\(remaining)",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                    .foregroundColor: UIColor.theme.textDisabled,
                ]
            )
            overflowNode = node
            addSubnode(node)
        }

        syncAddReactionSubnode()
        setNeedsLayout()
    }

    func updateReactions(_ newReactions: [ParsedReaction], showAddButton: Bool) {
        self.showAddButton = showAddButton
        let visible = Array(newReactions.prefix(Self.maxVisiblePills))

        let oldMap = Dictionary(uniqueKeysWithValues: currentReactions.enumerated().map { ($1.emojiId, (index: $0, reaction: $1)) })

        let oldKeys = Set(oldMap.keys)
        let newKeys = Set(visible.map { $0.emojiId })

        let removedKeys = oldKeys.subtracting(newKeys)
        for key in removedKeys {
            if let entry = oldMap[key] {
                pillNodes[entry.index].removeFromSupernode()
            }
        }

        var newPillNodes: [ReactionPillNode] = []
        for reaction in visible {
            if let oldEntry = oldMap[reaction.emojiId] {
                let oldNode = pillNodes[oldEntry.index]
                if oldEntry.reaction != reaction {
                    oldNode.update(reaction: reaction)
                }
                newPillNodes.append(oldNode)
            } else {
                let newNode = ReactionPillNode(reaction: reaction)
                addSubnode(newNode)
                newPillNodes.append(newNode)
            }
        }

        pillNodes = newPillNodes
        currentReactions = visible

        overflowNode?.removeFromSupernode()
        overflowNode = nil
        if newReactions.count > Self.maxVisiblePills {
            let node = ASTextNode2()
            let remaining = newReactions.count - Self.maxVisiblePills
            node.attributedText = NSAttributedString(
                string: "+\(remaining)",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                    .foregroundColor: UIColor.theme.textDisabled,
                ]
            )
            overflowNode = node
            addSubnode(node)
        }

        syncAddReactionSubnode()
        setNeedsLayout()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        if pillNodes.isEmpty, overflowNode == nil, !showAddButton {
            cachedTotalSize = .zero
            cachedRows = []
            return .zero
        }

        let spacing: CGFloat = 6.sw
        let addDiameter = Self.addButtonDiameter.sh
        var rows: [LayoutRow] = []
        var currentRowFrames: [(index: Int, frame: CGRect)] = []
        var currentX: CGFloat = 0
        var currentRowMaxH: CGFloat = 0
        var totalY: CGFloat = 0

        func flushRowIfNeeded(for neededWidth: CGFloat) {
            if currentX + neededWidth > maxWidth && !currentRowFrames.isEmpty {
                rows.append(LayoutRow(frames: currentRowFrames, height: currentRowMaxH))
                totalY += currentRowMaxH + spacing
                currentRowFrames = []
                currentX = 0
                currentRowMaxH = 0
            }
        }

        for (i, pill) in pillNodes.enumerated() {
            let pillSize = pill.calculatedSize(maxWidth: maxWidth)
            let neededWidth = currentRowFrames.isEmpty ? pillSize.width : pillSize.width + spacing
            flushRowIfNeeded(for: neededWidth)
            let x = currentRowFrames.isEmpty ? 0 : currentX + spacing
            currentRowFrames.append((index: i, frame: CGRect(x: x, y: totalY, width: pillSize.width, height: pillSize.height)))
            currentX = x + pillSize.width
            currentRowMaxH = max(currentRowMaxH, pillSize.height)
        }

        let overflowIndex = pillNodes.count
        if let overflowNode {
            let overflowSize = overflowNode.measure(CGSize(width: maxWidth, height: 28.sh))
            let neededWidth = currentRowFrames.isEmpty ? overflowSize.width : overflowSize.width + spacing
            flushRowIfNeeded(for: neededWidth)
            let x = currentRowFrames.isEmpty ? 0 : currentX + spacing
            currentRowFrames.append((index: overflowIndex, frame: CGRect(x: x, y: totalY, width: overflowSize.width, height: overflowSize.height)))
            currentX = x + overflowSize.width
            currentRowMaxH = max(currentRowMaxH, overflowSize.height)
        }

        let addIndex = overflowIndex + (overflowNode != nil ? 1 : 0)
        if showAddButton {
            let addSize = CGSize(width: addDiameter, height: addDiameter)
            let neededWidth = currentRowFrames.isEmpty ? addSize.width : addSize.width + spacing
            flushRowIfNeeded(for: neededWidth)
            let x = currentRowFrames.isEmpty ? 0 : currentX + spacing
            currentRowFrames.append((index: addIndex, frame: CGRect(x: x, y: totalY, width: addSize.width, height: addSize.height)))
            currentX = x + addSize.width
            currentRowMaxH = max(currentRowMaxH, addSize.height)
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
        let w = bounds.width
        if w > 1, cachedRows.isEmpty, !pillNodes.isEmpty {
            _ = measureSize(maxWidth: w)
        }
        let overflowIndex = pillNodes.count
        let addIndex = overflowIndex + (overflowNode != nil ? 1 : 0)
        var addFrame: CGRect?
        for row in cachedRows {
            for entry in row.frames {
                if entry.index < pillNodes.count {
                    pillNodes[entry.index].frame = entry.frame
                } else if let overflowNode, entry.index == overflowIndex {
                    overflowNode.frame = entry.frame
                } else if entry.index == addIndex {
                    addFrame = entry.frame
                }
            }
        }

        if showAddButton, let rect = addFrame {
            addReactionButtonNode.frame = rect
            let r = min(rect.width, rect.height) / 2
            addReactionButtonNode.cornerRadius = r
            addReactionButtonNode.isHidden = false
        } else {
            addReactionButtonNode.isHidden = true
        }
    }
}

final class ReactionPillNode: ASDisplayNode {

    private let emojiImageNode: ASDisplayNode = {
        let node = ASDisplayNode { UIImageView() }
        node.clipsToBounds = true
        return node
    }()
    private let emojiFallbackNode = ASTextNode2()
    private let countNode = ASTextNode2()

    private var pendingImage: UIImage?
    private var imageTask: URLSessionDataTask?
    private static let emojiSize: CGFloat = 20
    private static let pillHeight: CGFloat = 28

    private var cachedCountSize: CGSize = .zero
    private(set) var emojiId: String

    init(reaction: ParsedReaction) {
        self.emojiId = reaction.emojiId
        super.init()
        automaticallyManagesSubnodes = false

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

        let url = MezonConfig.emojiResourceURL(emojiId: reaction.emojiId, imgproxyFitSide: 100)
        if let url = url {
            emojiFallbackNode.isHidden = true
            loadEmojiImage(url: url)
        } else {
            emojiImageNode.isHidden = true
        }
    }

    override func didLoad() {
        super.didLoad()
        if let pendingImage {
            (emojiImageNode.view as? UIImageView)?.image = pendingImage
        }
    }

    deinit {
        imageTask?.cancel()
    }

    private func applyImage(_ image: UIImage) {
        pendingImage = image
        if emojiImageNode.isNodeLoaded {
            (emojiImageNode.view as? UIImageView)?.image = image
        }
    }

    func update(reaction: ParsedReaction) {
        let t = UIColor.theme
        countNode.attributedText = NSAttributedString(
            string: "\(reaction.count)",
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf, weight: .semibold),
                .foregroundColor: t.textStrong,
            ]
        )
        if reaction.isMe {
            backgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 0.2)
            borderWidth = 1
            borderColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 0.6).cgColor
        } else {
            backgroundColor = t.secondary
            borderWidth = 0
            borderColor = nil
        }
        setNeedsLayout()
    }

    func calculatedSize(maxWidth: CGFloat) -> CGSize {
        cachedCountSize = countNode.measure(CGSize(width: maxWidth, height: Self.pillHeight))
        let width = 6.sw + Self.emojiSize + 4.sw + ceil(cachedCountSize.width) + 6.sw
        return CGSize(width: width, height: Self.pillHeight.sh)
    }

    private func loadEmojiImage(url: URL) {
        imageTask?.cancel()
        imageTask = ReactionEmojiImageLoader.load(from: url) { [weak self] image in
            guard let self else { return }
            if let image {
                self.applyImage(image)
                self.emojiImageNode.isHidden = false
                self.emojiFallbackNode.isHidden = true
            } else {
                self.emojiImageNode.isHidden = true
                self.emojiFallbackNode.isHidden = false
            }
        }
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
