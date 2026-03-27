import UIKit

extension NSAttributedString.Key {
    static let mezonLink = NSAttributedString.Key("mezon.link")
    static let mezonMention = NSAttributedString.Key("mezon.mention")
    static let mezonHashtag = NSAttributedString.Key("mezon.hashtag")
}

enum RichTextSegment {
    case text(NSAttributedString)
    case codeBlock(String)
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
                bodyFont: .systemFont(ofSize: 14.sf),
                bodyColor: t.textStrong,
                mentionFont: .systemFont(ofSize: 14.sf, weight: .semibold),
                mentionColor: t.textLink,
                mentionBgColor: t.midnightBlue,
                roleMentionColor: t.textRoleLink,
                roleMentionBgColor: t.darkMossGreen,
                linkColor: t.textLink,
                codeBgColor: t.tertiary,
                codeFont: UIFont(name: "Menlo", size: 13.sf) ?? .monospacedSystemFont(ofSize: 13.sf, weight: .regular),
                boldFont: .systemFont(ofSize: 14.sf, weight: .bold),
                emojiSize: 20.sf
            )
        }
    }

    static func build(from content: ParsedContent, style: Style? = nil) -> NSAttributedString {
        var s = style ?? .fromTheme()
        if content.isOnlyEmoji {
            s = Style(
                bodyFont: s.bodyFont, bodyColor: s.bodyColor,
                mentionFont: s.mentionFont, mentionColor: s.mentionColor,
                mentionBgColor: s.mentionBgColor, roleMentionColor: s.roleMentionColor,
                roleMentionBgColor: s.roleMentionBgColor, linkColor: s.linkColor,
                codeBgColor: s.codeBgColor, codeFont: s.codeFont, boldFont: s.boldFont,
                emojiSize: 48.sf
            )
        }
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
                result.append(NSAttributedString(attachment: attachment))

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
                attrs[.font] = s.mentionFont
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

    static func buildSegments(from content: ParsedContent, style: Style? = nil) -> [RichTextSegment] {
        let s = style ?? .fromTheme()
        let text = content.text

        guard !text.isEmpty else { return [] }

        let codeBlockTokens = content.tokens
            .filter { if case .codeBlock = $0.kind { return true }; return false }
            .sorted { $0.start < $1.start }

        guard !codeBlockTokens.isEmpty else {
            return [.text(build(from: content, style: s))]
        }

        var segments: [RichTextSegment] = []
        var lastIndex = 0

        for token in codeBlockTokens {
            if token.start > lastIndex {
                let beforeContent = sliceContent(content, from: lastIndex, to: token.start)
                let attrText = build(from: beforeContent, style: s)
                if attrText.length > 0 {
                    segments.append(.text(attrText))
                }
            }

            var codeText = String(text[
                text.index(text.startIndex, offsetBy: token.start)..<text.index(text.startIndex, offsetBy: min(token.end, text.count))
            ])
            if codeText.hasPrefix("```") && codeText.hasSuffix("```") {
                codeText = String(codeText.dropFirst(3).dropLast(3))
            }
            if let firstNewline = codeText.firstIndex(of: "\n") {
                let firstLine = codeText[codeText.startIndex..<firstNewline]
                let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.contains(" ") && trimmed.count < 20 {
                    codeText = String(codeText[firstNewline...])
                }
            }
            codeText = codeText.trimmingCharacters(in: .newlines)
            segments.append(.codeBlock(codeText))

            lastIndex = token.end
        }

        if lastIndex < text.count {
            let afterContent = sliceContent(content, from: lastIndex, to: text.count)
            let attrText = build(from: afterContent, style: s)
            if attrText.length > 0 {
                segments.append(.text(attrText))
            }
        }

        return segments
    }

    private static func sliceContent(_ content: ParsedContent, from: Int, to: Int) -> ParsedContent {
        let text = content.text
        let start = text.index(text.startIndex, offsetBy: from)
        let end = text.index(text.startIndex, offsetBy: min(to, text.count))
        let slicedText = String(text[start..<end])

        let slicedTokens = content.tokens.compactMap { token -> ContentToken? in
            if case .codeBlock = token.kind { return nil }
            guard token.start >= from && token.end <= to else { return nil }
            return ContentToken(start: token.start - from, end: token.end - from, kind: token.kind)
        }

        return ParsedContent(text: slicedText, tokens: slicedTokens, embeds: [])
    }

    private static func bodyAttributes(_ s: Style) -> [NSAttributedString.Key: Any] {
        [
            .font: s.bodyFont,
            .foregroundColor: s.bodyColor
        ]
    }
}

final class EmojiTextAttachment: NSTextAttachment {
    static let imageDidLoad = Notification.Name("EmojiTextAttachment.imageDidLoad")

    let emojiId: String
    let emojiSize: CGFloat

    init(emojiId: String, emojiSize: CGFloat) {
        self.emojiId = emojiId
        self.emojiSize = emojiSize
        super.init(data: nil, ofType: nil)
        let font = UIFont.systemFont(ofSize: 15.sf)
        let yOffset = (font.ascender + font.descender - emojiSize) / 2
        self.bounds = CGRect(x: 0, y: yOffset, width: emojiSize, height: emojiSize)
        self.image = makePlaceholder()
        loadEmojiImage()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func loadEmojiImage() {
        guard let url = MezonConfig.emojiImageURL(emojiId: emojiId) else { return }
        let key = url.absoluteString

        if let cached = ImageCache.shared.image(forKey: key) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.image = self.resized(cached)
                NotificationCenter.default.post(name: EmojiTextAttachment.imageDidLoad, object: self)
            }
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, !data.isEmpty else { return }
            guard let img = UIImage.decodeImage(from: data) else { return }
            ImageCache.shared.setImage(img, data: data, forKey: key)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.image = self.resized(img)
                NotificationCenter.default.post(name: EmojiTextAttachment.imageDidLoad, object: self)
            }
        }.resume()
    }

    private func resized(_ img: UIImage) -> UIImage {
        let sz = CGSize(width: emojiSize, height: emojiSize)
        return UIGraphicsImageRenderer(size: sz).image { _ in
            img.draw(in: CGRect(origin: .zero, size: sz))
        }
    }

    private func makePlaceholder() -> UIImage {
        let sz = CGSize(width: emojiSize, height: emojiSize)
        return UIGraphicsImageRenderer(size: sz).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: sz))
        }
    }
}
