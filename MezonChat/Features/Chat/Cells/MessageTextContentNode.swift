import UIKit
import AsyncDisplayKit

final class MessageTextContentNode: ASDisplayNode {

    private var textNode: ASTextNode2?
    private var emojiLabelNode: ASDisplayNode?

    private var segmentNodes: [(node: ASDisplayNode, size: CGSize)] = []
    private var useSegments = false

    var onMentionTapped: ((String) -> Void)?
    var onHashtagTapped: ((ChannelHashtagTapInfo) -> Void)?
    var onLinkTapped: ((URL) -> Void)?

    private var currentParsedContent: ParsedContent?
    private var currentAttrText: NSAttributedString?
    private var hasEmoji = false
    private var buzzStyled = false

    private var cachedTextSize: CGSize = .zero

    override init() {
        super.init()
    }

    override func didLoad() {
        super.didLoad()

        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    func configure(
        parsedContent: ParsedContent,
        buzzStyled: Bool = false,
        hashtagChannelAccess: ((String, String?) -> Bool)? = nil
    ) {
        currentParsedContent = parsedContent
        self.buzzStyled = buzzStyled

        let hasCodeBlock = parsedContent.tokens.contains {
            if case .codeBlock = $0.kind { return true }
            return false
        }

        let containsEmoji = parsedContent.tokens.contains {
            if case .emoji = $0.kind { return true }
            return false
        }
        let containsChannelHashtag = parsedContent.tokens.contains {
            switch $0.kind {
            case .hashtag, .mezonChannelLink: return true
            default: return false
            }
        }
        hasEmoji = containsEmoji || containsChannelHashtag

        textNode?.removeFromSupernode()
        emojiLabelNode?.removeFromSupernode()
        segmentNodes.forEach { $0.node.removeFromSupernode() }
        segmentNodes = []
        textNode = nil
        emojiLabelNode = nil

        if hasCodeBlock {
            useSegments = true
            let segments = RichTextBuilder.buildSegments(
                from: parsedContent, buzzStyled: buzzStyled, hashtagChannelAccess: hashtagChannelAccess)
            for segment in segments {
                switch segment {
                case .text(let attrText):
                    guard attrText.length > 0 else { continue }
                    if Self.attributedTextNeedsUIKitTextView(attrText) {
                        let node = ASDisplayNode {
                            let v = EmojiTextView()
                            v.attributedText = attrText
                            return v
                        }
                        node.isUserInteractionEnabled = false
                        addSubnode(node)
                        segmentNodes.append((node, .zero))
                    } else {
                        let tn = ASTextNode2()
                        tn.isUserInteractionEnabled = false
                        tn.maximumNumberOfLines = 0
                        tn.attributedText = attrText
                        addSubnode(tn)
                        segmentNodes.append((tn, .zero))
                    }

                case .codeBlock(let code):
                    let container = CodeBlockContainerNode(code: code)
                    addSubnode(container)
                    segmentNodes.append((container, .zero))
                }
            }
            return
        }

        useSegments = false


        let attrText = RichTextBuilder.build(
            from: parsedContent, buzzStyled: buzzStyled, hashtagChannelAccess: hashtagChannelAccess)
        currentAttrText = attrText

        if containsEmoji || containsChannelHashtag {
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
                } else if let emojiView = node.view as? EmojiTextView, let attr = emojiView.attributedText {
                    var w = maxWidth
                    if w > 10000 || w == .infinity { w = UIScreen.main.bounds.width - 80 }
                    let measured = Self.textSize(for: attr, maxWidth: w)
                    size = CGSize(width: w, height: measured.height)
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

        if emojiLabelNode != nil, let attrText = currentAttrText {
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

    private static func attributedTextNeedsUIKitTextView(_ attr: NSAttributedString) -> Bool {
        var found = false
        attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length)) { value, _, stop in
            guard let att = value as? NSTextAttachment else { return }
            if att is EmojiTextAttachment { return }
            found = true
            stop.pointee = true
        }
        return found
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

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)

        if let emojiLabelNode, let emojiView = emojiLabelNode.view as? EmojiTextView,
           let attrText = emojiView.attributedText {
            let localPoint = view.convert(point, to: emojiView.textView)
            if let result = linkAttribute(in: attrText, at: localPoint, containerSize: emojiView.textView.bounds.size) {
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
            if let tn = seg as? ASTextNode2, let attrText = tn.attributedText, attrText.length > 0 {
                let localPoint = view.convert(point, to: tn.view)
                guard tn.bounds.contains(localPoint) else { continue }
                if let result = linkAttribute(in: attrText, at: localPoint, containerSize: tn.bounds.size) {
                    dispatchLinkAction(result)
                    return
                }
            } else if let emojiView = seg.view as? EmojiTextView, let attrText = emojiView.attributedText, attrText.length > 0 {
                let inWrap = view.convert(point, to: seg.view)
                guard seg.bounds.contains(inWrap) else { continue }
                let localPoint = view.convert(point, to: emojiView.textView)
                if let result = linkAttribute(in: attrText, at: localPoint, containerSize: emojiView.textView.bounds.size) {
                    dispatchLinkAction(result)
                    return
                }
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
        if let pay = attrs[.mezonHashtag], let info = ChannelHashtagTapInfo.parse(pay) {
            return (.mezonHashtag, info)
        }
        return nil
    }

    private func dispatchLinkAction(_ result: (key: NSAttributedString.Key, value: Any)) {
        switch result.key {
        case .mezonMention:
            onMentionTapped?("\(result.value)")
        case .mezonLink:
            let stringValue = "\(result.value)"
            if let url = URL(string: stringValue) {
                onLinkTapped?(url)
            }
        case .mezonHashtag:
            if let info = result.value as? ChannelHashtagTapInfo {
                onHashtagTapped?(info)
            }
        default:
            break
        }
    }

}


extension MessageTextContentNode: ASTextNodeDelegate {

    func textNode(_ textNode: ASTextNode!, shouldHighlightLinkAttribute attribute: String!, value: Any!, at point: CGPoint) -> Bool {
        true
    }

    func textNode(_ textNode: ASTextNode!, tappedLinkAttribute attribute: String!, value: Any!, at point: CGPoint, textRange: NSRange) {
        guard let attribute = attribute, let value = value else { return }
        let stringValue = "\(value)"
        if attribute == NSAttributedString.Key.mezonLink.rawValue,
           let url = URL(string: stringValue) {
            onLinkTapped?(url)
        } else if attribute == NSAttributedString.Key.mezonMention.rawValue {
            onMentionTapped?(stringValue)
        } else if attribute == NSAttributedString.Key.mezonHashtag.rawValue,
                  let info = ChannelHashtagTapInfo.parse(value) {
            onHashtagTapped?(info)
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

        let codeFont = UIFont(name: "Menlo", size: 12.sf) ?? .monospacedSystemFont(ofSize: 12.sf, weight: .regular)
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


    let textView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isUserInteractionEnabled = false
        tv.textDragInteraction?.isEnabled = false
        tv.clipsToBounds = false
        return tv
    }()

    private var emojiOverlays: [UIImageView] = []

    var attributedText: NSAttributedString? {
        didSet {
            textView.attributedText = attributedText
            rebuildEmojiOverlays()
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(textView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        textView.layoutIfNeeded()
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

            loadAnimatedEmoji(emojiId: emoji.emojiId, imgproxyFitSide: emoji.imgproxyFitSide, into: imageView)
        }
    }

    private func positionEmojiOverlays() {
        guard let attrText = attributedText, !emojiOverlays.isEmpty else { return }

        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let inset = textView.textContainerInset

        var index = 0
        attrText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attrText.length)) { value, range, _ in
            guard value is EmojiTextAttachment, index < self.emojiOverlays.count else { return }
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            rect.origin.x += inset.left
            rect.origin.y += inset.top
            self.emojiOverlays[index].frame = rect
            index += 1
        }
    }

    private func loadAnimatedEmoji(emojiId: String, imgproxyFitSide: Int, into imageView: UIImageView) {
        guard let url = MezonConfig.emojiResourceURL(emojiId: emojiId, imgproxyFitSide: imgproxyFitSide) else { return }
        let key = url.absoluteString

        if let data = ImageCache.shared.cachedData(forKey: key),
           let animated = UIImage.animatedImage(from: data) {
            imageView.image = animated
            setNeedsLayout()
            return
        }

        if let cached = ImageCache.shared.image(forKey: key) {
            imageView.image = cached
            setNeedsLayout()
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, !data.isEmpty else { return }
            let animated = UIImage.animatedImage(from: data)
            let display = animated ?? UIImage.decodeImage(from: data)
            DispatchQueue.main.async { [weak self] in
                imageView.image = display
                self?.setNeedsLayout()
            }
        }.resume()
    }
}
