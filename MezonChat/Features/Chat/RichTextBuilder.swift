import UIKit


extension String {

    func mezon_utf16Substring(from start: Int, to end: Int) -> String {
        guard start < end, start >= 0, end <= utf16.count else { return "" }
        let si = String.Index(utf16Offset: start, in: self)
        let ei = String.Index(utf16Offset: end, in: self)
        return String(self[si..<ei])
    }
}

extension NSAttributedString.Key {
    static let mezonLink = NSAttributedString.Key("mezon.link")
    static let mezonMention = NSAttributedString.Key("mezon.mention")
    static let mezonRoleMention = NSAttributedString.Key("mezon.roleMention")
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

        let headingFonts: [UIFont]
        let emojiSize: CGFloat

        let emojiImgproxyFitSide: Int

        private static func defaultHeadingFonts() -> [UIFont] {
            [
                .systemFont(ofSize: 24.sf, weight: .bold),
                .systemFont(ofSize: 22.sf, weight: .bold),
                .systemFont(ofSize: 20.sf, weight: .bold),
                .systemFont(ofSize: 18.sf, weight: .bold),
                .systemFont(ofSize: 16.sf, weight: .bold),
                .systemFont(ofSize: 14.sf, weight: .bold)
            ]
        }
        static func buzz(from base: Style) -> Style {
            let red = UIColor(red: 0.93, green: 0.11, blue: 0.14, alpha: 1.0)
            let bf = base.boldFont
            let mentionBg = red.withAlphaComponent(0.14)
            let codeDesc = base.codeFont.fontDescriptor.withSymbolicTraits([.traitBold])
            let codeBuzz = codeDesc.map { UIFont(descriptor: $0, size: base.codeFont.pointSize) } ?? bf
            return Style(
                bodyFont: bf,
                bodyColor: red,
                mentionFont: bf,
                mentionColor: red,
                mentionBgColor: mentionBg,
                roleMentionColor: red,
                roleMentionBgColor: mentionBg,
                linkColor: red,
                codeBgColor: base.codeBgColor,
                codeFont: codeBuzz,
                boldFont: bf,
                headingFonts: base.headingFonts,
                emojiSize: base.emojiSize,
                emojiImgproxyFitSide: base.emojiImgproxyFitSide
            )
        }

        static func fromTheme() -> Style {
            let t = UIColor.theme
            let body = UIFont.systemFont(ofSize: 14.sf)
            let bodyBold = UIFont.systemFont(ofSize: 14.sf, weight: .bold)
            return Style(
                bodyFont: body,
                bodyColor: t.textStrong,
                mentionFont: .systemFont(ofSize: 14.sf, weight: .semibold),
                mentionColor: t.textLink,
                mentionBgColor: t.midnightBlue,
                roleMentionColor: t.textRoleLink,
                roleMentionBgColor: t.darkMossGreen,
                linkColor: t.textLink,
                codeBgColor: t.tertiary,
                codeFont: body,
                boldFont: bodyBold,
                headingFonts: defaultHeadingFonts(),
                emojiSize: 20.sf,
                emojiImgproxyFitSide: 50
            )
        }
    }

    static func build(from content: ParsedContent, style: Style? = nil, buzzStyled: Bool = false) -> NSAttributedString {
        var s = style ?? .fromTheme()
        if content.isOnlyEmoji {
            s = Style(
                bodyFont: s.bodyFont, bodyColor: s.bodyColor,
                mentionFont: s.mentionFont, mentionColor: s.mentionColor,
                mentionBgColor: s.mentionBgColor, roleMentionColor: s.roleMentionColor,
                roleMentionBgColor: s.roleMentionBgColor, linkColor: s.linkColor,
                codeBgColor: s.codeBgColor, codeFont: s.codeFont, boldFont: s.boldFont,
                headingFonts: s.headingFonts,
                emojiSize: 48.sf,
                emojiImgproxyFitSide: 100
            )
        }
        if buzzStyled {
            s = Style.buzz(from: s)
        }
        let text = content.text

        guard !text.isEmpty else {
            return NSAttributedString()
        }

        guard !content.tokens.isEmpty else {
            return attributedPlainTextWithMarkdownHeadings(text, style: s)
        }

        let result = NSMutableAttributedString()
        var lastUTF16 = 0
        let utf16Len = text.utf16.count

        for token in content.tokens.sorted(by: { $0.start < $1.start }) {
            guard token.start >= 0, token.end <= utf16Len, token.start < token.end else { continue }

            if lastUTF16 < token.start {
                let plainText = text.mezon_utf16Substring(from: lastUTF16, to: token.start)
                if !plainText.isEmpty {
                    result.append(attributedPlainTextWithMarkdownHeadings(plainText, style: s))
                }
            }

            let rawText = text.mezon_utf16Substring(from: token.start, to: token.end)

            switch token.kind {
            case .emoji(let emojiId):
                let attachment = EmojiTextAttachment(
                    emojiId: emojiId,
                    emojiSize: s.emojiSize,
                    baselineFont: s.bodyFont,
                    imgproxyFitSide: s.emojiImgproxyFitSide
                )
                result.append(NSAttributedString(attachment: attachment))

            case .mention(let userId, let roleId, _):
                var attrs = bodyAttributes(s)
                attrs[.font] = s.mentionFont
                let isRoleMention = roleId != nil && userId == nil
                attrs[.foregroundColor] = isRoleMention ? s.roleMentionColor : s.mentionColor
                attrs[.backgroundColor] = isRoleMention ? s.roleMentionBgColor : s.mentionBgColor
                if isRoleMention {
                    attrs[.mezonRoleMention] = (roleId ?? "") as NSString
                } else {
                    attrs[.mezonMention] = (userId ?? "") as NSString
                }
                let displayText = rawText.isEmpty ? "@unknown" : rawText
                result.append(NSAttributedString(string: displayText, attributes: attrs))

            case .hashtag(let channelId, let clanId, let channelLabel, let channelType, let channelPrivate, let ageRestricted):
                let chType = channelType ?? MezonConstants.ChannelType.channel.rawValue
                let chPriv = channelPrivate ?? 0
                let chAge = ageRestricted ?? 0
                let iconName = Mezon_Api_ChannelDescription.channelListIconAssetName(
                    type: chType, channelPrivate: chPriv, ageRestricted: chAge
                )
                let namePart: String
                if let label = channelLabel, !label.isEmpty {
                    namePart = label.hasPrefix("#") ? String(label.dropFirst()) : label
                } else if rawText.isEmpty {
                    namePart = "channel"
                } else {
                    namePart = rawText.hasPrefix("#") ? String(rawText.dropFirst()) : rawText
                }
                var tagAttrs = bodyAttributes(s)
                tagAttrs[.font] = s.mentionFont
                tagAttrs[.foregroundColor] = s.mentionColor
                tagAttrs[.backgroundColor] = s.mentionBgColor
                tagAttrs[.mezonHashtag] = [
                    "c": channelId ?? "",
                    "g": clanId ?? "",
                ] as NSDictionary
                if let att = RichTextBuilder.hashtagIconAttachment(named: iconName, tint: s.mentionColor, font: s.mentionFont) {
                    let iconStr = NSMutableAttributedString(attachment: att)
                    iconStr.addAttributes(tagAttrs, range: NSRange(location: 0, length: iconStr.length))
                    result.append(iconStr)
                    result.append(NSAttributedString(string: "\u{2009}", attributes: tagAttrs))
                    result.append(NSAttributedString(string: namePart, attributes: tagAttrs))
                } else {
                    result.append(NSAttributedString(string: "#\(namePart)", attributes: tagAttrs))
                }

            case .inlineCode:
                var attrs = bodyAttributes(s)
                attrs[.font] = s.codeFont
                attrs[.backgroundColor] = s.codeBgColor
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.lineHeightMultiple = 1.4
                attrs[.paragraphStyle] = paraStyle
                attrs[.baselineOffset] = 1
                var displayText = rawText
                if displayText.hasPrefix("`") && displayText.hasSuffix("`") {
                    displayText = String(displayText.dropFirst().dropLast())
                }
                let thin = "\u{2009}"
                result.append(NSAttributedString(string: "\(thin)\(displayText)\(thin)", attributes: attrs))

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

            lastUTF16 = token.end
        }

        if lastUTF16 < utf16Len {
            let remaining = text.mezon_utf16Substring(from: lastUTF16, to: utf16Len)
            if !remaining.isEmpty {
                result.append(attributedPlainTextWithMarkdownHeadings(remaining, style: s))
            }
        }

        return result
    }

    static func buildSegments(from content: ParsedContent, style: Style? = nil, buzzStyled: Bool = false) -> [RichTextSegment] {
        var s = style ?? .fromTheme()
        if buzzStyled {
            s = Style.buzz(from: s)
        }
        let text = content.text

        guard !text.isEmpty else { return [] }

        let codeBlockTokens = content.tokens
            .filter { if case .codeBlock = $0.kind { return true }; return false }
            .sorted { $0.start < $1.start }

        guard !codeBlockTokens.isEmpty else {
            return [.text(build(from: content, style: s, buzzStyled: false))]
        }

        var segments: [RichTextSegment] = []
        var lastIndex = 0

        let utf16Len = text.utf16.count

        for token in codeBlockTokens {
            if token.start > lastIndex {
                let beforeContent = sliceContent(content, from: lastIndex, to: token.start)
                let attrText = build(from: beforeContent, style: s, buzzStyled: false)
                if attrText.length > 0 {
                    segments.append(.text(attrText))
                }
            }

            let end = min(token.end, utf16Len)
            var codeText = text.mezon_utf16Substring(from: token.start, to: end)
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

        if lastIndex < utf16Len {
            let afterContent = sliceContent(content, from: lastIndex, to: utf16Len)
            let attrText = build(from: afterContent, style: s, buzzStyled: false)
            if attrText.length > 0 {
                segments.append(.text(attrText))
            }
        }

        return segments
    }

    private static func sliceContent(_ content: ParsedContent, from: Int, to: Int) -> ParsedContent {
        let text = content.text
        let utf16Len = text.utf16.count
        let clampedFrom = max(0, min(from, utf16Len))
        let clampedTo = max(clampedFrom, min(to, utf16Len))
        let slicedText = text.mezon_utf16Substring(from: clampedFrom, to: clampedTo)

        let slicedTokens = content.tokens.compactMap { token -> ContentToken? in
            if case .codeBlock = token.kind { return nil }
            guard token.start >= clampedFrom && token.end <= clampedTo else { return nil }
            return ContentToken(start: token.start - clampedFrom, end: token.end - clampedFrom, kind: token.kind)
        }

        return ParsedContent(text: slicedText, tokens: slicedTokens, embeds: [])
    }

    private static func bodyAttributes(_ s: Style) -> [NSAttributedString.Key: Any] {
        [
            .font: s.bodyFont,
            .foregroundColor: s.bodyColor
        ]
    }

    private static func hashtagIconAttachment(named assetName: String, tint: UIColor, font: UIFont) -> NSTextAttachment? {
        let side = max(ceil(font.capHeight), 12)
        let raw = UIImage(named: assetName) ?? UIImage(systemName: "speaker.wave.2.fill")
        guard let base = raw else { return nil }
        let tpl = base.withRenderingMode(.alwaysTemplate)
        let colored = tpl.withTintColor(tint, renderingMode: .alwaysOriginal)
        let att = NSTextAttachment()
        att.image = colored
        let y = (font.capHeight - side) / 2 + font.descender * 0.35
        att.bounds = CGRect(x: 0, y: y, width: side, height: side)
        return att
    }


    private static func attributedPlainTextWithMarkdownHeadings(_ plain: String, style s: Style) -> NSAttributedString {
        guard !plain.isEmpty else { return NSAttributedString() }
        let lines = plain.components(separatedBy: "\n")
        var hasHeadingLine = false
        for line in lines {
            if headingMatch(in: line) != nil {
                hasHeadingLine = true
                break
            }
        }
        if !hasHeadingLine {
            return NSAttributedString(string: plain, attributes: bodyAttributes(s))
        }
        let out = NSMutableAttributedString()
        for (idx, line) in lines.enumerated() {
            let isLast = idx == lines.count - 1
            let newline = isLast ? "" : "\n"
            if let match = headingMatch(in: line) {
                var attrs = bodyAttributes(s)
                attrs[.font] = headingFont(level: match.level, fonts: s.headingFonts, fallback: s.bodyFont)
                out.append(NSAttributedString(string: match.text + newline, attributes: attrs))
            } else {
                out.append(NSAttributedString(string: line + newline, attributes: bodyAttributes(s)))
            }
        }
        return out
    }

    private struct HeadingLineMatch {
        let level: Int
        let text: String
    }

    private static func headingMatch(in line: String) -> HeadingLineMatch? {
        let ns = line as NSString
        guard let re = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: []),
              let m = re.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges == 3 else { return nil }
        let hashR = m.range(at: 1)
        let textR = m.range(at: 2)
        guard hashR.location != NSNotFound, textR.location != NSNotFound else { return nil }
        let level = ns.substring(with: hashR).count
        let headingBody = ns.substring(with: textR).trimmingCharacters(in: .whitespacesAndNewlines)
        return HeadingLineMatch(level: level, text: headingBody)
    }

    private static func headingFont(level: Int, fonts: [UIFont], fallback: UIFont) -> UIFont {
        let idx = max(0, min(level - 1, 5))
        guard idx < fonts.count else { return fallback }
        return fonts[idx]
    }

}

final class EmojiTextAttachment: NSTextAttachment {

    let emojiId: String
    let emojiSize: CGFloat
    let imgproxyFitSide: Int


    private static let horizontalMargin: CGFloat = 2

    init(emojiId: String, emojiSize: CGFloat, baselineFont: UIFont, imgproxyFitSide: Int) {
        self.emojiId = emojiId
        self.emojiSize = emojiSize
        self.imgproxyFitSide = imgproxyFitSide
        super.init(data: nil, ofType: nil)
        let yOffset = (baselineFont.ascender + baselineFont.descender - emojiSize) / 2
        let w = emojiSize + Self.horizontalMargin * 2
        self.bounds = CGRect(x: 0, y: yOffset, width: w, height: emojiSize)


        self.image = makePlaceholder()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makePlaceholder() -> UIImage {
        let w = emojiSize + Self.horizontalMargin * 2
        let sz = CGSize(width: w, height: emojiSize)
        return UIGraphicsImageRenderer(size: sz).image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: sz))
        }
    }
}
