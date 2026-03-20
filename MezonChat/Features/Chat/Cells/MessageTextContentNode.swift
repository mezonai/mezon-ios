import UIKit
import AsyncDisplayKit

final class MessageTextContentNode: ASDisplayNode {

    private var textNode: ASTextNode2?
    private var emojiLabelNode: ASDisplayNode?

    var onMentionTapped: ((String) -> Void)?
    var onHashtagTapped: ((String) -> Void)?
    var onLinkTapped: ((URL) -> Void)?

    private var currentParsedContent: ParsedContent?
    private var currentAttrText: NSAttributedString?
    private var hasEmoji = false

    override init() {
        super.init()
        automaticallyManagesSubnodes = true
    }

    override func didLoad() {
        super.didLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleEmojiLoaded), name: EmojiTextAttachment.imageDidLoad, object: nil)

        if hasEmoji, let emojiLabelNode {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleLabelTap(_:)))
            emojiLabelNode.view.addGestureRecognizer(tap)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: EmojiTextAttachment.imageDidLoad, object: nil)
    }

    @objc private func handleEmojiLoaded() {
        guard hasEmoji, let content = currentParsedContent, !content.isPlainText else { return }
        let attrText = RichTextBuilder.build(from: content)
        currentAttrText = attrText
        if let emojiView = emojiLabelNode?.view as? EmojiTextView {
            emojiView.attributedText = attrText
        }
    }

    func configure(parsedContent: ParsedContent) {
        currentParsedContent = parsedContent

        let containsEmoji = parsedContent.tokens.contains {
            if case .emoji = $0.kind { return true }
            return false
        }
        hasEmoji = containsEmoji

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
            textNode = nil
            let node = ASDisplayNode { [weak self] () -> UIView in
                let view = EmojiTextView()
                view.attributedText = self?.currentAttrText ?? attrText
                return view
            }
            emojiLabelNode = node
        } else {
            emojiLabelNode = nil
            let tn = ASTextNode2()
            tn.isUserInteractionEnabled = true
            tn.delegate = self
            tn.maximumNumberOfLines = 0
            tn.linkAttributeNames = [
                NSAttributedString.Key.mezonLink.rawValue,
                NSAttributedString.Key.mezonMention.rawValue,
                NSAttributedString.Key.mezonHashtag.rawValue,
            ]
            tn.attributedText = attrText
            textNode = tn
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if let emojiLabelNode, let attrText = currentAttrText {
            var maxWidth = constrainedSize.max.width
            if maxWidth > 10000 || maxWidth == .infinity {
                maxWidth = UIScreen.main.bounds.width - 80
            }
            let size = Self.textSize(for: attrText, maxWidth: maxWidth)
            emojiLabelNode.style.preferredSize = CGSize(width: maxWidth, height: size.height)
            emojiLabelNode.style.maxWidth = ASDimensionMake(maxWidth)
            return ASWrapperLayoutSpec(layoutElement: emojiLabelNode)
        }
        if let textNode {
            textNode.style.maxWidth = ASDimensionMake(constrainedSize.max.width)
            return ASWrapperLayoutSpec(layoutElement: textNode)
        }
        return ASLayoutSpec()
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

    @objc private func handleLabelTap(_ gesture: UITapGestureRecognizer) {
        guard let emojiView = gesture.view as? EmojiTextView,
              let attrText = emojiView.attributedText else { return }

        let label = emojiView.label
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: label.bounds.size)
        let textStorage = NSTextStorage(attributedString: attrText)

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = label.numberOfLines
        textContainer.lineBreakMode = label.lineBreakMode

        let tapLocation = gesture.location(in: label)
        let charIndex = layoutManager.characterIndex(
            for: tapLocation, in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard charIndex < attrText.length else { return }

        let attrs = attrText.attributes(at: charIndex, effectiveRange: nil)

        if let urlString = attrs[.mezonLink] as? String,
           let url = URL(string: urlString) {
            onLinkTapped?(url)
        } else if let mentionId = attrs[.mezonMention] as? String {
            onMentionTapped?(mentionId)
        } else if let channelId = attrs[.mezonHashtag] as? String {
            onHashtagTapped?(channelId)
        }
    }
}

// MARK: - ASTextNodeDelegate

extension MessageTextContentNode: ASTextNodeDelegate {

    func textNode(_ textNode: ASTextNode, shouldHighlightLinkAttribute attribute: String, value: Any, at point: CGPoint) -> Bool {
        return true
    }

    func textNode(_ textNode: ASTextNode, tappedLinkAttribute attribute: String, value: Any, at point: CGPoint, textRange: NSRange) {
        if attribute == NSAttributedString.Key.mezonLink.rawValue,
           let urlString = value as? String,
           let url = URL(string: urlString) {
            onLinkTapped?(url)
        } else if attribute == NSAttributedString.Key.mezonMention.rawValue,
                  let mentionId = value as? String {
            onMentionTapped?(mentionId)
        } else if attribute == NSAttributedString.Key.mezonHashtag.rawValue,
                  let channelId = value as? String {
            onHashtagTapped?(channelId)
        }
    }
}

// MARK: - EmojiTextView

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
