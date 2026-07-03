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
    static let mezonSystemAction = NSAttributedString.Key("mezon.systemAction")
}

enum RichTextSegment {
    case text(NSAttributedString)
    case codeBlock(String)
}

enum RichTextBuilder {

    private static func localizedPrivateChannelHashtagLabel() -> String {
        NSLocalizedString(
            "chat.hashtag.privateChannel",
            tableName: nil,
            bundle: .main,
            value: "private-channel",
            comment: ""
        )
    }

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

    static func build(
        from content: ParsedContent,
        style: Style? = nil,
        buzzStyled: Bool = false,
        hashtagChannelAccess: ((String, String?) -> Bool)? = nil
    ) -> NSAttributedString {
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

        let utf16Len = text.utf16.count
        let sortedTokens = content.tokens.sorted(by: { $0.start < $1.start })
        let hasCodeBlock = sortedTokens.contains {
            if case .codeBlock = $0.kind { return true }
            return false
        }
        if hasCodeBlock {
            return buildAttributedStringTokenWalk(
                text: text, sortedTokens: sortedTokens, utf16Len: utf16Len, style: s,
                lineHeadingLevel: nil, lineBodyFont: nil, lineMentionFont: nil,
                hashtagChannelAccess: hashtagChannelAccess,
                buzzStyled: buzzStyled
            )
        }
        return buildAttributedStringWithLineWiseHeadings(
            text: text, sortedTokens: sortedTokens, utf16Len: utf16Len, style: s,
            hashtagChannelAccess: hashtagChannelAccess,
            buzzStyled: buzzStyled
        )
    }

    private static func buildAttributedStringWithLineWiseHeadings(
        text: String,
        sortedTokens: [ContentToken],
        utf16Len: Int,
        style s: Style,
        hashtagChannelAccess: ((String, String?) -> Bool)?,
        buzzStyled: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let ns = text as NSString
        var lineStart = 0
        while lineStart <= utf16Len {
            let restLen = utf16Len - lineStart
            let restRange = NSRange(location: lineStart, length: restLen)
            let nl = ns.range(of: "\n", options: [], range: restRange)
            let lineEnd = nl.location != NSNotFound ? nl.location : utf16Len
            let lineTokens = sortedTokens.filter { $0.start >= lineStart && $0.end <= lineEnd && $0.start < lineEnd }
            let lineStr = text.mezon_utf16Substring(from: lineStart, to: lineEnd)
            let heading = markdownLineHeadingPrefix(line: lineStr, lineStartUTF16: lineStart, lineTokens: lineTokens)
            let lineBodyFont = heading.map { headingFont(level: $0.level, fonts: s.headingFonts, fallback: s.bodyFont) }
            let lineMentionFont = heading.map { headingFont(level: $0.level, fonts: s.headingFonts, fallback: s.mentionFont) }
            let contentStart = lineStart + (heading?.prefixUTF16Length ?? 0)
            let lineAttr = buildAttributedStringTokenWalk(
                text: text,
                sortedTokens: lineTokens,
                utf16Len: utf16Len,
                style: s,
                lineHeadingLevel: heading?.level,
                lineBodyFont: lineBodyFont,
                lineMentionFont: lineMentionFont,
                segmentStartUTF16: contentStart,
                segmentEndUTF16: lineEnd,
                hashtagChannelAccess: hashtagChannelAccess,
                buzzStyled: buzzStyled
            )
            result.append(lineAttr)
            if lineEnd < utf16Len {
                result.append(NSAttributedString(string: "\n", attributes: bodyAttributes(s)))
            }
            if lineEnd >= utf16Len { break }
            lineStart = lineEnd + 1
        }
        return result
    }

    private struct LineHeadingPrefix {
        let level: Int
        let prefixUTF16Length: Int
    }

    private static func markdownLineHeadingPrefix(
        line: String,
        lineStartUTF16: Int,
        lineTokens: [ContentToken]
    ) -> LineHeadingPrefix? {
        let ns = line as NSString
        let len = ns.length
        guard len > 0,
              let re = try? NSRegularExpression(pattern: "^(#{1,6})\\s+", options: []),
              let m = re.firstMatch(in: line, options: [], range: NSRange(location: 0, length: len)),
              m.numberOfRanges >= 2,
              m.range(at: 1).location != NSNotFound else { return nil }
        let fullR = m.range(at: 0)
        let level = ns.substring(with: m.range(at: 1)).count
        let prefixUTF16Length = fullR.length
        let hasTextTail = fullR.location + fullR.length < len
        let hasTokenInTail = lineTokens.contains { $0.start >= lineStartUTF16 + prefixUTF16Length }
        guard hasTextTail || hasTokenInTail else { return nil }
        return LineHeadingPrefix(level: level, prefixUTF16Length: prefixUTF16Length)
    }

    private static func buildAttributedStringTokenWalk(
        text: String,
        sortedTokens: [ContentToken],
        utf16Len: Int,
        style s: Style,
        lineHeadingLevel: Int?,
        lineBodyFont: UIFont?,
        lineMentionFont: UIFont?,
        segmentStartUTF16: Int = 0,
        segmentEndUTF16: Int? = nil,
        hashtagChannelAccess: ((String, String?) -> Bool)? = nil,
        buzzStyled: Bool = false
    ) -> NSAttributedString {
        let endCap = segmentEndUTF16 ?? utf16Len
        let tokensInSegment = sortedTokens.filter { $0.start >= segmentStartUTF16 && $0.end <= endCap && $0.start < endCap }
        let result = NSMutableAttributedString()
        var lastUTF16 = segmentStartUTF16

        for token in tokensInSegment.sorted(by: { $0.start < $1.start }) {
            guard token.start >= 0, token.end <= utf16Len, token.start < token.end else { continue }

            if lastUTF16 < token.start {
                let plainText = text.mezon_utf16Substring(from: lastUTF16, to: token.start)
                if !plainText.isEmpty {
                    if lineHeadingLevel != nil {
                        var attrs = bodyAttributes(s)
                        attrs[.font] = lineBodyFont ?? s.bodyFont
                        result.append(NSAttributedString(string: plainText, attributes: attrs))
                    } else {
                        result.append(attributedPlainTextWithMarkdownHeadings(plainText, style: s))
                    }
                }
            }

            let rawText = text.mezon_utf16Substring(from: token.start, to: token.end)

            switch token.kind {
            case .emoji(let emojiId):
                let baseline = lineBodyFont ?? s.bodyFont
                let attachment = EmojiTextAttachment(
                    emojiId: emojiId,
                    emojiSize: s.emojiSize,
                    baselineFont: baseline,
                    imgproxyFitSide: s.emojiImgproxyFitSide
                )
                let ps = NSMutableParagraphStyle()
                ps.lineSpacing = 0
                ps.paragraphSpacing = 0
                let mas = NSMutableAttributedString(attachment: attachment)
                mas.addAttributes([.font: baseline, .paragraphStyle: ps], range: NSRange(location: 0, length: mas.length))
                result.append(mas)

            case .mention(let userId, let roleId, _):
                var attrs = bodyAttributes(s)
                attrs[.font] = lineMentionFont ?? s.mentionFont
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

            case .hashtag(let channelId, let clanId, let parentId, let channelLabel, let channelType, let channelPrivate, let ageRestricted):
                let hasEmbeddedLabel = !(channelLabel ?? "").isEmpty
                let chType = channelType ?? (hasEmbeddedLabel
                    ? MezonConstants.ChannelType.thread.rawValue
                    : MezonConstants.ChannelType.channel.rawValue)
                let chPriv = channelPrivate ?? 0
                let chAge = ageRestricted ?? 0
                let cid = channelId ?? ""
                let gidForAccess = (clanId ?? "").isEmpty ? nil : clanId
                var accessible = !cid.isEmpty && (hashtagChannelAccess?(cid, gidForAccess) ?? true)
                if !accessible, hasEmbeddedLabel, chPriv == 0,
                   let pid = parentId, !pid.isEmpty, pid != "0",
                   let access = hashtagChannelAccess {
                    accessible = access(pid, gidForAccess)
                }
                let iconName: String
                if accessible {
                    iconName = Mezon_Api_ChannelDescription.channelListIconAssetName(
                        type: chType, channelPrivate: chPriv, ageRestricted: chAge
                    )
                } else {
                    iconName = Mezon_Api_ChannelDescription.channelListIconAssetName(
                        type: MezonConstants.ChannelType.channel.rawValue, channelPrivate: 1, ageRestricted: 0
                    )
                }
                let namePart: String
                if accessible {
                    if let label = channelLabel, !label.isEmpty {
                        namePart = label.hasPrefix("#") ? String(label.dropFirst()) : label
                    } else if rawText.isEmpty {
                        namePart = "channel"
                    } else {
                        namePart = rawText.hasPrefix("#") ? String(rawText.dropFirst()) : rawText
                    }
                } else {
                    namePart = Self.localizedPrivateChannelHashtagLabel()
                }
                let tagFont = lineMentionFont ?? s.mentionFont
                let t = UIColor.theme
                let inaccessibleFg: UIColor = buzzStyled ? s.bodyColor.withAlphaComponent(0.55) : t.textDisabled
                let inaccessibleBg: UIColor = buzzStyled ? s.codeBgColor.withAlphaComponent(0.45) : t.tertiary
                let fg = accessible ? s.mentionColor : inaccessibleFg
                let bg = accessible ? s.mentionBgColor : inaccessibleBg
                var tagAttrs = bodyAttributes(s)
                tagAttrs[.font] = tagFont
                tagAttrs[.foregroundColor] = fg
                tagAttrs[.backgroundColor] = bg
                if accessible {
                    tagAttrs[.mezonHashtag] = [
                        "c": cid,
                        "g": clanId ?? "",
                    ] as NSDictionary
                }
                if let att = RichTextBuilder.hashtagIconAttachment(named: iconName, tint: fg, font: tagFont) {
                    let iconStr = NSMutableAttributedString(attachment: att)
                    iconStr.addAttributes(tagAttrs, range: NSRange(location: 0, length: iconStr.length))
                    result.append(iconStr)
                    result.append(NSAttributedString(string: "\u{00A0}", attributes: tagAttrs))
                    result.append(NSAttributedString(string: namePart, attributes: tagAttrs))
                } else {
                    result.append(NSAttributedString(string: "#\(namePart)", attributes: tagAttrs))
                }

            case .mezonChannelLink(let isVk, let channelId, let clanId):
                let gidForAccess = clanId.isEmpty ? nil : clanId
                let accessible = !channelId.isEmpty && (hashtagChannelAccess?(channelId, gidForAccess) ?? true)
                let chType: Int32 = isVk ? MezonConstants.ChannelType.mezonVoice.rawValue : MezonConstants.ChannelType.channel.rawValue
                let iconName: String
                if accessible {
                    iconName = Mezon_Api_ChannelDescription.channelListIconAssetName(
                        type: chType, channelPrivate: 0, ageRestricted: 0
                    )
                } else {
                    iconName = Mezon_Api_ChannelDescription.channelListIconAssetName(
                        type: MezonConstants.ChannelType.channel.rawValue, channelPrivate: 1, ageRestricted: 0
                    )
                }
                let namePart = accessible
                    ? (isVk ? "Voice" : "Channel")
                    : Self.localizedPrivateChannelHashtagLabel()
                let tagFont = lineMentionFont ?? s.mentionFont
                let t = UIColor.theme
                let inaccessibleFg: UIColor = buzzStyled ? s.bodyColor.withAlphaComponent(0.55) : t.textDisabled
                let inaccessibleBg: UIColor = buzzStyled ? s.codeBgColor.withAlphaComponent(0.45) : t.tertiary
                let fg = accessible ? s.mentionColor : inaccessibleFg
                let bg = accessible ? s.mentionBgColor : inaccessibleBg
                var tagAttrs = bodyAttributes(s)
                tagAttrs[.font] = tagFont
                tagAttrs[.foregroundColor] = fg
                tagAttrs[.backgroundColor] = bg
                if accessible {
                    tagAttrs[.mezonHashtag] = [
                        "c": channelId,
                        "g": clanId,
                    ] as NSDictionary
                }
                if let att = RichTextBuilder.hashtagIconAttachment(named: iconName, tint: fg, font: tagFont) {
                    let iconStr = NSMutableAttributedString(attachment: att)
                    iconStr.addAttributes(tagAttrs, range: NSRange(location: 0, length: iconStr.length))
                    result.append(iconStr)
                    result.append(NSAttributedString(string: "\u{00A0}", attributes: tagAttrs))
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

        if lastUTF16 < endCap {
            let remaining = text.mezon_utf16Substring(from: lastUTF16, to: endCap)
            if !remaining.isEmpty {
                if lineHeadingLevel != nil {
                    var attrs = bodyAttributes(s)
                    attrs[.font] = lineBodyFont ?? s.bodyFont
                    result.append(NSAttributedString(string: remaining, attributes: attrs))
                } else {
                    result.append(attributedPlainTextWithMarkdownHeadings(remaining, style: s))
                }
            }
        }

        return result
    }

    static func buildSegments(
        from content: ParsedContent,
        style: Style? = nil,
        buzzStyled: Bool = false,
        hashtagChannelAccess: ((String, String?) -> Bool)? = nil
    ) -> [RichTextSegment] {
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
            return [.text(build(from: content, style: s, buzzStyled: false, hashtagChannelAccess: hashtagChannelAccess))]
        }

        var segments: [RichTextSegment] = []
        var lastIndex = 0

        let utf16Len = text.utf16.count

        for token in codeBlockTokens {
            var beforeEnd = token.start
            while beforeEnd > lastIndex, text.mezon_utf16Substring(from: beforeEnd - 1, to: beforeEnd) == "\n" {
                beforeEnd -= 1
            }
            if beforeEnd > lastIndex {
                let beforeContent = sliceContent(content, from: lastIndex, to: beforeEnd)
                let attrText = build(from: beforeContent, style: s, buzzStyled: false, hashtagChannelAccess: hashtagChannelAccess)
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
            while lastIndex < utf16Len, text.mezon_utf16Substring(from: lastIndex, to: lastIndex + 1) == "\n" {
                lastIndex += 1
            }
        }

        if lastIndex < utf16Len {
            let afterContent = sliceContent(content, from: lastIndex, to: utf16Len)
            let attrText = build(from: afterContent, style: s, buzzStyled: false, hashtagChannelAccess: hashtagChannelAccess)
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

        return ParsedContent(text: slicedText, tokens: slicedTokens, embeds: [], ogpPreviews: [])
    }

    private static func bodyParagraphStyle() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4.sh
        return p
    }

    private static func bodyAttributes(_ s: Style) -> [NSAttributedString.Key: Any] {
        [
            .font: s.bodyFont,
            .foregroundColor: s.bodyColor,
            .paragraphStyle: bodyParagraphStyle(),
        ]
    }

    static func hashtagIconAttachment(named assetName: String, tint: UIColor, font: UIFont) -> NSTextAttachment? {
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
