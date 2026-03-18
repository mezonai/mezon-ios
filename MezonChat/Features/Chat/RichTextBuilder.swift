import UIKit

extension NSAttributedString.Key {
    static let mezonLink = NSAttributedString.Key("mezon.link")
    static let mezonMention = NSAttributedString.Key("mezon.mention")
    static let mezonHashtag = NSAttributedString.Key("mezon.hashtag")
}

enum RichTextBuilder {

    struct Style {
        let bodyFont: UIFont
        let bodyColor: UIColor
        let mentionFont: UIFont
        let mentionColor: UIColor
        let mentionBgColor: UIColor
        let roleMentionColor: UIColor
        let roleMentionBgColor: UIColor
        let linkColor: UIColor
        let codeBgColor: UIColor
        let codeFont: UIFont
        let boldFont: UIFont
        let emojiSize: CGFloat

        static func fromTheme() -> Style {
            let t = UIColor.theme
            return Style(
                bodyFont: .systemFont(ofSize: 15.sf),
                bodyColor: t.textStrong,
                mentionFont: .systemFont(ofSize: 15.sf, weight: .semibold),
                mentionColor: t.textLink,
                mentionBgColor: t.midnightBlue,
                roleMentionColor: t.textRoleLink,
                roleMentionBgColor: t.darkMossGreen,
                linkColor: t.textLink,
                codeBgColor: t.tertiary,
                codeFont: UIFont(name: "Menlo", size: 14.sf) ?? .monospacedSystemFont(ofSize: 14.sf, weight: .regular),
                boldFont: .systemFont(ofSize: 15.sf, weight: .bold),
                emojiSize: 20.sf
            )
        }
    }

    static func build(from content: ParsedContent, style: Style? = nil) -> NSAttributedString {
        let s = style ?? .fromTheme()
        let text = content.text

        guard !text.isEmpty else {
            return NSAttributedString()
        }

        guard !content.tokens.isEmpty else {
            return NSAttributedString(string: text, attributes: bodyAttributes(s))
        }

        let result = NSMutableAttributedString()
        var lastIndex = text.startIndex

        for token in content.tokens {
            let tokenStart = text.index(text.startIndex, offsetBy: token.start, limitedBy: text.endIndex) ?? text.endIndex
            let tokenEnd = text.index(text.startIndex, offsetBy: token.end, limitedBy: text.endIndex) ?? text.endIndex

            guard tokenStart <= tokenEnd, tokenStart <= text.endIndex else { continue }

            if lastIndex < tokenStart {
                let plainText = String(text[lastIndex..<tokenStart])
                result.append(NSAttributedString(string: plainText, attributes: bodyAttributes(s)))
            }

            let rawText = tokenEnd <= text.endIndex ? String(text[tokenStart..<tokenEnd]) : ""

            switch token.kind {
            case .emoji(let emojiId):
                let attachment = EmojiTextAttachment(emojiId: emojiId, emojiSize: s.emojiSize)
                let emojiStr = NSMutableAttributedString(attachment: attachment)
                emojiStr.addAttribute(.baselineOffset, value: -4.0, range: NSRange(location: 0, length: emojiStr.length))
                result.append(emojiStr)

            case .mention(let userId, let roleId, _):
                var attrs = bodyAttributes(s)
                attrs[.font] = s.mentionFont
                let isRoleMention = roleId != nil && userId == nil
                attrs[.foregroundColor] = isRoleMention ? s.roleMentionColor : s.mentionColor
                attrs[.backgroundColor] = isRoleMention ? s.roleMentionBgColor : s.mentionBgColor
                attrs[.mezonMention] = (userId ?? roleId ?? "") as NSString
                let displayText = rawText.isEmpty ? "@unknown" : rawText
                result.append(NSAttributedString(string: displayText, attributes: attrs))

            case .hashtag(let channelId, _, let channelLabel):
                var attrs = bodyAttributes(s)
                attrs[.foregroundColor] = s.mentionColor
                attrs[.backgroundColor] = s.mentionBgColor
                attrs[.mezonHashtag] = (channelId ?? "") as NSString
                let displayText: String
                if let label = channelLabel, !label.isEmpty {
                    displayText = "#\(label)"
                } else {
                    displayText = rawText.isEmpty ? "#channel" : rawText
                }
                result.append(NSAttributedString(string: displayText, attributes: attrs))

            case .inlineCode:
                var attrs = bodyAttributes(s)
                attrs[.font] = s.codeFont
                attrs[.backgroundColor] = s.codeBgColor
                var displayText = rawText
                if displayText.hasPrefix("`") && displayText.hasSuffix("`") {
                    displayText = String(displayText.dropFirst().dropLast())
                }
                result.append(NSAttributedString(string: " \(displayText) ", attributes: attrs))

            case .codeBlock:
                var attrs = bodyAttributes(s)
                attrs[.font] = s.codeFont
                attrs[.backgroundColor] = s.codeBgColor
                var displayText = rawText
                if displayText.hasPrefix("```") && displayText.hasSuffix("```") {
                    displayText = String(displayText.dropFirst(3).dropLast(3))
                }
                displayText = displayText.trimmingCharacters(in: .newlines)
                if result.length > 0 {
                    result.append(NSAttributedString(string: "\n", attributes: bodyAttributes(s)))
                }
                result.append(NSAttributedString(string: displayText, attributes: attrs))
                result.append(NSAttributedString(string: "\n", attributes: bodyAttributes(s)))

            case .bold:
                var attrs = bodyAttributes(s)
                attrs[.font] = s.boldFont
                result.append(NSAttributedString(string: rawText, attributes: attrs))

            case .strikethrough:
                var attrs = bodyAttributes(s)
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(NSAttributedString(string: rawText, attributes: attrs))

            case .link:
                var attrs = bodyAttributes(s)
                attrs[.foregroundColor] = s.linkColor
                attrs[.mezonLink] = rawText as NSString
                result.append(NSAttributedString(string: rawText, attributes: attrs))
            }

            lastIndex = tokenEnd
        }

        if lastIndex < text.endIndex {
            let remaining = String(text[lastIndex...])
            result.append(NSAttributedString(string: remaining, attributes: bodyAttributes(s)))
        }

        return result
    }

    private static func bodyAttributes(_ s: Style) -> [NSAttributedString.Key: Any] {
        [
            .font: s.bodyFont,
            .foregroundColor: s.bodyColor
        ]
    }
}

final class EmojiTextAttachment: NSTextAttachment {
    let emojiId: String
    let emojiSize: CGFloat
    private var loadedImage: UIImage?

    init(emojiId: String, emojiSize: CGFloat) {
        self.emojiId = emojiId
        self.emojiSize = emojiSize
        super.init(data: nil, ofType: nil)
        self.bounds = CGRect(x: 0, y: -4, width: emojiSize, height: emojiSize)
        loadEmojiImage()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        return loadedImage ?? makePlaceholder()
    }

    private func loadEmojiImage() {
        guard let url = MezonConfig.emojiImageURL(emojiId: emojiId) else { return }

        if let cached = ImageCache.shared.image(forKey: url.absoluteString) {
            self.loadedImage = cached
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = UIImage(data: data) else { return }
            ImageCache.shared.setImage(image, data: data, forKey: url.absoluteString)
            self.loadedImage = image
        }.resume()
    }

    private func makePlaceholder() -> UIImage {
        let size = CGSize(width: emojiSize, height: emojiSize)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.gray.withAlphaComponent(0.2).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
