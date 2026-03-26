import UIKit
import AsyncDisplayKit

final class MessageTextContentNode: ASDisplayNode {

    private var textNode: ASTextNode2?
    private var emojiLabelNode: ASDisplayNode?

    private var segmentNodes: [(node: ASDisplayNode, size: CGSize)] = []
    private var useSegments = false

    var onMentionTapped: ((String) -> Void)?
    var onHashtagTapped: ((String) -> Void)?
    var onLinkTapped: ((URL) -> Void)?

    private var currentParsedContent: ParsedContent?
    private var currentAttrText: NSAttributedString?
    private var hasEmoji = false

    private var cachedTextSize: CGSize = .zero

    override init() {
        super.init()
    }

    override func didLoad() {
        super.didLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleEmojiLoaded), name: EmojiTextAttachment.imageDidLoad, object: nil)

        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: EmojiTextAttachment.imageDidLoad, object: nil)
    }

    private var emojiReloadScheduled = false

    @objc private func handleEmojiLoaded() {
        guard hasEmoji, !emojiReloadScheduled else { return }
        emojiReloadScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.hasEmoji, let content = self.currentParsedContent, !content.isPlainText else {
                self?.emojiReloadScheduled = false
                return
            }
            let attrText = RichTextBuilder.build(from: content)
            self.currentAttrText = attrText
            if let emojiView = self.emojiLabelNode?.view as? EmojiTextView {
                emojiView.attributedText = attrText
            }
            self.emojiReloadScheduled = false
        }
    }

    func configure(parsedContent: ParsedContent) {
        currentParsedContent = parsedContent

        let hasCodeBlock = parsedContent.tokens.contains {
            if case .codeBlock = $0.kind { return true }
            return false
        }

        let containsEmoji = parsedContent.tokens.contains {
            if case .emoji = $0.kind { return true }
            return false
        }
        hasEmoji = containsEmoji

        textNode?.removeFromSupernode()
        emojiLabelNode?.removeFromSupernode()
        segmentNodes.forEach { $0.node.removeFromSupernode() }
        segmentNodes = []
        textNode = nil
        emojiLabelNode = nil

        if hasCodeBlock {
            useSegments = true
            let segments = RichTextBuilder.buildSegments(from: parsedContent)
            for segment in segments {
                switch segment {
                case .text(let attrText):
                    guard attrText.length > 0 else { continue }
                    let tn = ASTextNode2()
                    tn.isUserInteractionEnabled = false
                    tn.maximumNumberOfLines = 0
                    tn.attributedText = attrText
                    addSubnode(tn)
                    segmentNodes.append((tn, .zero))

                case .codeBlock(let code):
                    let container = CodeBlockContainerNode(code: code)
                    addSubnode(container)
                    segmentNodes.append((container, .zero))
                }
            }
            return
        }

        useSegments = false

        let attrText: NSAttributedString
        if parsedContent.isPlainText {
            let t = UIColor.theme
            attrText = NSAttributedString(
                string: parsedContent.text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15.sf),
                    .foregroundColor: t.textStrong,
                ]
            )
        } else {
            attrText = RichTextBuilder.build(from: parsedContent)
        }
        currentAttrText = attrText

        if containsEmoji {
            let node = ASDisplayNode { [weak self] () -> UIView in
                let view = EmojiTextView()
                view.attributedText = self?.currentAttrText ?? attrText
                return view
            }
            node.isUserInteractionEnabled = false
            emojiLabelNode = node
            addSubnode(node)
        } else {
            let tn = ASTextNode2()
            tn.isUserInteractionEnabled = false
            tn.maximumNumberOfLines = 0
            tn.attributedText = attrText
            textNode = tn
            addSubnode(tn)
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        if useSegments {
            var totalH: CGFloat = 0
            let spacing: CGFloat = 4.sh
            for i in 0..<segmentNodes.count {
                let node = segmentNodes[i].node
                let size: CGSize
                if let codeNode = node as? CodeBlockContainerNode {
                    size = codeNode.measureSize(maxWidth: maxWidth)
                } else if let textNode = node as? ASTextNode2 {
                    size = textNode.measure(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
                } else {
                    size = .zero
                }
                segmentNodes[i].size = size
                if totalH > 0 { totalH += spacing }
                totalH += size.height
            }
            cachedTextSize = CGSize(width: maxWidth, height: totalH)
            return cachedTextSize
        }

        if let emojiLabelNode, let attrText = currentAttrText {
            var safeMaxW = maxWidth
            if safeMaxW > 10000 || safeMaxW == .infinity {
                safeMaxW = UIScreen.main.bounds.width - 80
            }
            let size = Self.textSize(for: attrText, maxWidth: safeMaxW)
            cachedTextSize = CGSize(width: safeMaxW, height: size.height)
            return cachedTextSize
        }
        if let textNode {
            let size = textNode.measure(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            cachedTextSize = size
            return size
        }
        cachedTextSize = .zero
        return .zero
    }

    override func layout() {
        super.layout()
        let size = bounds.size

        if useSegments {
            var y: CGFloat = 0
            let spacing: CGFloat = 4.sh
            for (node, segSize) in segmentNodes {
                node.frame = CGRect(x: 0, y: y, width: size.width, height: segSize.height)
                y += segSize.height + spacing
            }
            return
        }

        if let emojiLabelNode {
            emojiLabelNode.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: cachedTextSize.height))
        }
        if let textNode {
            textNode.frame = CGRect(origin: .zero, size: cachedTextSize)
        }
    }

    private static func textSize(for attrText: NSAttributedString, maxWidth: CGFloat) -> CGSize {
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let textStorage = NSTextStorage(attributedString: attrText)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: min(ceil(rect.width), maxWidth), height: ceil(rect.height))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        (supernode as? MessageBubbleNode)?.showHighlight(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            (self?.supernode as? MessageBubbleNode)?.showHighlight(false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        (supernode as? MessageBubbleNode)?.showHighlight(false)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)

        if let emojiLabelNode, let emojiView = emojiLabelNode.view as? EmojiTextView,
           let attrText = emojiView.attributedText {
            let localPoint = view.convert(point, to: emojiView.label)
            if let result = linkAttribute(in: attrText, at: localPoint, containerSize: emojiView.label.bounds.size) {
                dispatchLinkAction(result)
                return
            }
        }

        if let textNode, let attrText = textNode.attributedText, attrText.length > 0 {
            let localPoint = view.convert(point, to: textNode.view)
            if let result = linkAttribute(in: attrText, at: localPoint, containerSize: textNode.bounds.size) {
                dispatchLinkAction(result)
                return
            }
        }

        for (seg, _) in segmentNodes {
            guard let tn = seg as? ASTextNode2, let attrText = tn.attributedText, attrText.length > 0 else { continue }
            let localPoint = view.convert(point, to: tn.view)
            guard tn.bounds.contains(localPoint) else { continue }
            if let result = linkAttribute(in: attrText, at: localPoint, containerSize: tn.bounds.size) {
                dispatchLinkAction(result)
                return
            }
        }
    }

    private func linkAttribute(in attrText: NSAttributedString, at point: CGPoint, containerSize: CGSize) -> (key: NSAttributedString.Key, value: Any)? {
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: containerSize)
        let textStorage = NSTextStorage(attributedString: attrText)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let charIndex = layoutManager.characterIndex(
            for: point, in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard charIndex < attrText.length else { return nil }
        let attrs = attrText.attributes(at: charIndex, effectiveRange: nil)

        if let val = attrs[.mezonMention] { return (.mezonMention, val) }
        if let val = attrs[.mezonLink] { return (.mezonLink, val) }
        if let val = attrs[.mezonHashtag] { return (.mezonHashtag, val) }
        return nil
    }

    private func dispatchLinkAction(_ result: (key: NSAttributedString.Key, value: Any)) {
        let stringValue = "\(result.value)"
        switch result.key {
        case .mezonMention:
            onMentionTapped?(stringValue)
        case .mezonLink:
            if let url = URL(string: stringValue) {
                onLinkTapped?(url)
            }
        case .mezonHashtag:
            onHashtagTapped?(stringValue)
        default:
            break
        }
    }

}


extension MessageTextContentNode: ASTextNodeDelegate {

    func textNode(_ textNode: ASTextNode, shouldHighlightLinkAttribute attribute: String, value: Any, at point: CGPoint) -> Bool {
        return true
    }

    func textNode(_ textNode: ASTextNode, tappedLinkAttribute attribute: String, value: Any, at point: CGPoint, textRange: NSRange) {
        let stringValue = "\(value)"
        if attribute == NSAttributedString.Key.mezonLink.rawValue,
           let url = URL(string: stringValue) {
            onLinkTapped?(url)
        } else if attribute == NSAttributedString.Key.mezonMention.rawValue {
            onMentionTapped?(stringValue)
        } else if attribute == NSAttributedString.Key.mezonHashtag.rawValue {
            onHashtagTapped?(stringValue)
        }
    }
}

final class CodeBlockContainerNode: ASDisplayNode {

    private let backgroundNode = ASDisplayNode()
    private let codeTextNode = ASTextNode2()
    private var cachedSize: CGSize = .zero

    private static let padding: CGFloat = 10
    private static let cornerRadius: CGFloat = 6

    init(code: String) {
        super.init()

        let t = UIColor.theme
        backgroundNode.backgroundColor = t.tertiary
        backgroundNode.cornerRadius = Self.cornerRadius
        backgroundNode.clipsToBounds = true

        let codeFont = UIFont(name: "Menlo", size: 13.sf) ?? .monospacedSystemFont(ofSize: 13.sf, weight: .regular)
        codeTextNode.attributedText = NSAttributedString(
            string: code,
            attributes: [
                .font: codeFont,
                .foregroundColor: t.textStrong,
            ]
        )
        codeTextNode.maximumNumberOfLines = 0

        addSubnode(backgroundNode)
        backgroundNode.addSubnode(codeTextNode)
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let pad = Self.padding
        let textMaxW = maxWidth - pad * 2
        let textSize = codeTextNode.measure(CGSize(width: textMaxW, height: .greatestFiniteMagnitude))
        let totalH = textSize.height + pad * 2
        cachedSize = CGSize(width: maxWidth, height: totalH)
        return cachedSize
    }

    override func layout() {
        super.layout()
        let pad = Self.padding
        backgroundNode.frame = bounds
        let textW = bounds.width - pad * 2
        let textH = bounds.height - pad * 2
        codeTextNode.frame = CGRect(x: pad, y: pad, width: textW, height: textH)
    }
}

final class EmojiTextView: UIView {

    let label = UILabel()
    private var emojiOverlays: [UIImageView] = []

    var attributedText: NSAttributedString? {
        didSet {
            label.attributedText = attributedText
            rebuildEmojiOverlays()
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        label.numberOfLines = 0
        label.backgroundColor = .clear
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        positionEmojiOverlays()
    }

    private func rebuildEmojiOverlays() {
        emojiOverlays.forEach { $0.removeFromSuperview() }
        emojiOverlays = []

        guard let attrText = attributedText else { return }

        attrText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attrText.length)) { value, _, _ in
            guard let emoji = value as? EmojiTextAttachment else { return }

            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)
            emojiOverlays.append(imageView)

            loadAnimatedEmoji(emojiId: emoji.emojiId, size: emoji.emojiSize, into: imageView)
        }
    }

    private func positionEmojiOverlays() {
        guard let attrText = attributedText, !emojiOverlays.isEmpty else { return }

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: bounds.size)
        let textStorage = NSTextStorage(attributedString: attrText)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textContainer.lineFragmentPadding = 0

        var index = 0
        attrText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attrText.length)) { value, range, _ in
            guard value is EmojiTextAttachment, index < self.emojiOverlays.count else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            self.emojiOverlays[index].frame = rect
            index += 1
        }
    }

    private func loadAnimatedEmoji(emojiId: String, size: CGFloat, into imageView: UIImageView) {
        guard let url = MezonConfig.emojiImageURL(emojiId: emojiId) else { return }
        let key = url.absoluteString

        if let data = ImageCache.shared.cachedData(forKey: key),
           let animated = UIImage.animatedImage(from: data) {
            imageView.image = animated
            return
        }

        if let cached = ImageCache.shared.image(forKey: key) {
            imageView.image = cached
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, !data.isEmpty else { return }
            let animated = UIImage.animatedImage(from: data)
            let display = animated ?? UIImage.decodeImage(from: data)
            DispatchQueue.main.async {
                imageView.image = display
            }
        }.resume()
    }
}
