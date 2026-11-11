import Foundation


enum ComposerContentPayloadBuilder {

    struct BuiltPayload {
        let displayText: String
        let mk: [[String: Any]]
        let ej: [[String: Any]]
    }

    struct EditSource {
        let text: String
        fileprivate let insertions: [(at: Int, length: Int)]

        func editRange(fromDisplay range: NSRange) -> NSRange {
            let displayEnd = NSMaxRange(range)
            let start = range.location + insertions.reduce(0) { $1.at <= range.location ? $0 + $1.length : $0 }
            let end = displayEnd + insertions.reduce(0) { $1.at < displayEnd ? $0 + $1.length : $0 }
            return NSRange(location: start, length: max(0, end - start))
        }
    }

    private enum MatchKind {
        case emoji(String)
        case link(String)
        case voiceLink
        case codeBlock
        case inlineCode
        case bold
        case italic
        case strike
    }

    private struct Match {
        let kind: MatchKind
        let start: Int
        let end: Int
        let marker: Int
    }

    private struct ScanHit {
        let match: Match
        let next: Int
    }

    private static let backtick: UInt16 = 0x60
    private static let colon: UInt16 = 0x3A
    private static let newline: UInt16 = 0x0A
    private static let asterisk: UInt16 = 0x2A
    private static let underscore: UInt16 = 0x5F
    private static let tilde: UInt16 = 0x7E
    private static let maxStyledLineLength = 10_000
    private static let maxStyleDepth = 16

    static func build(
        rawInput: String,
        emojiIdByColon: [String: String],
        protectedRanges: [NSRange] = []
    ) -> BuiltPayload {
        let units = Array(rawInput.utf16)
        let n = units.count
        var matches = scanStructure(units, emojiIdByColon: emojiIdByColon)

        var protectedEnd = [Int](repeating: 0, count: n)
        func protect(_ start: Int, _ end: Int) {
            let lo = max(0, start)
            let hi = min(n, end)
            guard lo < hi else { return }
            for k in lo..<hi where protectedEnd[k] < hi {
                protectedEnd[k] = hi
            }
        }
        for m in matches {
            protect(m.start, m.end)
        }
        for r in protectedRanges where r.location != NSNotFound {
            protect(r.location, NSMaxRange(r))
        }

        var lineStart = 0
        while lineStart < n {
            var lineEnd = lineStart
            while lineEnd < n, units[lineEnd] != newline {
                lineEnd += 1
            }
            if lineEnd > lineStart, lineEnd - lineStart <= maxStyledLineLength {
                scanStyles(units, start: lineStart, end: lineEnd, protectedEnd: protectedEnd, depth: 0, into: &matches)
            }
            lineStart = lineEnd + 1
        }

        var removed = [Bool](repeating: false, count: n)
        for m in matches where m.marker > 0 {
            for k in m.start..<(m.start + m.marker) {
                removed[k] = true
            }
            for k in (m.end - m.marker)..<m.end {
                removed[k] = true
            }
        }

        var displayUnits: [UInt16] = []
        displayUnits.reserveCapacity(n)
        var displayOffset = [Int](repeating: 0, count: n + 1)
        for k in 0..<n {
            displayOffset[k] = displayUnits.count
            if !removed[k] {
                displayUnits.append(units[k])
            }
        }
        displayOffset[n] = displayUnits.count

        var mk: [[String: Any]] = []
        var ej: [[String: Any]] = []
        for m in matches {
            let s = displayOffset[m.start]
            let e = displayOffset[m.end]
            switch m.kind {
            case .emoji(let emojiId):
                ej.append(["emojiid": emojiId, "s": s, "e": e])
            case .link(let type):
                mk.append([
                    "type": type,
                    "s": s,
                    "e": e,
                    "channelId": "",
                    "clanId": "",
                    "channelLabel": "",
                ])
            case .voiceLink:
                mk.append(["type": "vk", "s": s, "e": e])
            case .codeBlock:
                mk.append(["type": "pre", "s": s, "e": e])
            case .inlineCode:
                mk.append(["type": "c", "s": s, "e": e])
            case .bold:
                mk.append(["type": "b", "s": s, "e": e])
            case .italic:
                mk.append(["type": "i", "s": s, "e": e])
            case .strike:
                mk.append(["type": "st", "s": s, "e": e])
            }
        }
        mk.sort {
            let sa = ($0["s"] as? Int) ?? 0
            let sb = ($1["s"] as? Int) ?? 0
            return sa < sb
        }

        return BuiltPayload(
            displayText: String(decoding: displayUnits, as: UTF16.self),
            mk: mk,
            ej: ej
        )
    }


    private static func scanStructure(_ u: [UInt16], emojiIdByColon: [String: String]) -> [Match] {
        var out: [Match] = []
        var i = 0
        while i < u.count {
            if let hit = emojiHit(u, at: i, emojiIdByColon: emojiIdByColon)
                ?? linkHit(u, at: i)
                ?? codeBlockHit(u, at: i)
                ?? inlineCodeHit(u, at: i) {
                out.append(hit.match)
                i = hit.next
                continue
            }
            i += 1
        }
        return out
    }

    private static func emojiHit(_ u: [UInt16], at i: Int, emojiIdByColon: [String: String]) -> ScanHit? {
        guard !emojiIdByColon.isEmpty, u[i] == colon, i + 1 < u.count else { return nil }
        var j = i + 1
        while j < u.count, u[j] != colon {
            j += 1
        }
        guard j < u.count, j > i + 1 else { return nil }
        if i >= 4, String(decoding: u[(i - 4)..<i], as: UTF16.self) == "http" { return nil }
        if i >= 5, String(decoding: u[(i - 5)..<i], as: UTF16.self) == "https" { return nil }
        let key = String(decoding: u[i...j], as: UTF16.self)
        guard let emojiId = emojiIdByColon[key] else { return nil }
        return ScanHit(match: Match(kind: .emoji(emojiId), start: i, end: j + 1, marker: 0), next: j + 1)
    }

    private static let httpUnits = Array("http://".utf16)
    private static let httpsUnits = Array("https://".utf16)
    private static let linkStopUnits: Set<UInt16> = [0x20, 0x0A, 0x0D, 0x09]
    private static let linkTrailingUnits: Set<UInt16> = [0x2C, 0x2E, 0x21, 0x3F, 0x3B, 0x3A, 0x2A, 0x5F, 0x7E]

    private static func hasPrefix(_ u: [UInt16], at i: Int, _ prefix: [UInt16]) -> Bool {
        guard i + prefix.count <= u.count else { return false }
        for (offset, unit) in prefix.enumerated() where u[i + offset] != unit {
            return false
        }
        return true
    }

    private static func linkHit(_ u: [UInt16], at i: Int) -> ScanHit? {
        let schemeLength: Int
        if hasPrefix(u, at: i, httpsUnits) {
            schemeLength = httpsUnits.count
        } else if hasPrefix(u, at: i, httpUnits) {
            schemeLength = httpUnits.count
        } else {
            return nil
        }
        var scanEnd = i + schemeLength
        while scanEnd < u.count, !linkStopUnits.contains(u[scanEnd]) {
            scanEnd += 1
        }
        if i >= 2, u[i - 2] == 0x5D, u[i - 1] == 0x28,
           let close = u[(i + schemeLength)..<scanEnd].firstIndex(of: 0x29) {
            scanEnd = close
        }
        var end = scanEnd
        let minEnd = i + schemeLength
        while end > minEnd, linkTrailingUnits.contains(u[end - 1]) {
            end -= 1
        }
        let link = String(decoding: u[i..<end], as: UTF16.self)
        let kind: MatchKind = link.hasPrefix(googleMeetPrefix) ? .voiceLink : .link(classifyLink(link))
        return ScanHit(match: Match(kind: kind, start: i, end: end, marker: 0), next: scanEnd)
    }

    private static func isTripleBacktick(_ u: [UInt16], _ k: Int) -> Bool {
        k >= 0 && k + 2 < u.count && u[k] == backtick && u[k + 1] == backtick && u[k + 2] == backtick
    }

    private static func hasTripleBacktick(_ u: [UInt16], from start: Int) -> Bool {
        var k = start
        while k + 2 < u.count {
            if isTripleBacktick(u, k) { return true }
            k += 1
        }
        return false
    }

    private static func codeBlockHit(_ u: [UInt16], at i: Int) -> ScanHit? {
        guard isTripleBacktick(u, i) else { return nil }
        var j = i + 3
        while j + 2 < u.count, !isTripleBacktick(u, j) {
            j += 1
        }
        guard isTripleBacktick(u, j), j > i + 3 else { return nil }
        return ScanHit(match: Match(kind: .codeBlock, start: i, end: j + 3, marker: 3), next: j + 3)
    }

    private static func inlineCodeHit(_ u: [UInt16], at i: Int) -> ScanHit? {
        guard u[i] == backtick, !isTripleBacktick(u, i) else { return nil }
        var j = i + 1
        while j < u.count, u[j] != backtick {
            j += 1
        }
        guard j < u.count else { return nil }
        if isTripleBacktick(u, j), hasTripleBacktick(u, from: j + 3) { return nil }
        guard u[(i + 1)..<j].contains(where: { !isWhitespace($0) }) else { return nil }
        return ScanHit(match: Match(kind: .inlineCode, start: i, end: j + 1, marker: 1), next: j + 1)
    }


    private static func isWhitespace(_ unit: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func surrogatePairScalar(lead: UInt16, trail: UInt16) -> Unicode.Scalar? {
        Unicode.Scalar(0x10000 + ((UInt32(lead) - 0xD800) << 10) + (UInt32(trail) - 0xDC00))
    }

    private static func isAlphanumeric(before pos: Int, in u: [UInt16]) -> Bool {
        guard pos > 0, pos <= u.count else { return false }
        let last = u[pos - 1]
        let scalar: Unicode.Scalar?
        if UTF16.isTrailSurrogate(last), pos >= 2, UTF16.isLeadSurrogate(u[pos - 2]) {
            scalar = surrogatePairScalar(lead: u[pos - 2], trail: last)
        } else {
            scalar = Unicode.Scalar(last)
        }
        guard let scalar else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func isAlphanumeric(at pos: Int, in u: [UInt16]) -> Bool {
        guard pos >= 0, pos < u.count else { return false }
        let first = u[pos]
        let scalar: Unicode.Scalar?
        if UTF16.isLeadSurrogate(first), pos + 1 < u.count, UTF16.isTrailSurrogate(u[pos + 1]) {
            scalar = surrogatePairScalar(lead: first, trail: u[pos + 1])
        } else {
            scalar = Unicode.Scalar(first)
        }
        guard let scalar else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func styleRunEnd(_ u: [UInt16], _ pos: Int, _ end: Int, _ protectedEnd: [Int]) -> Int {
        let ch = u[pos]
        var k = pos
        while k < end, u[k] == ch, protectedEnd[k] == 0 {
            k += 1
        }
        return k
    }

    private static func isValidStyleMarker(_ ch: UInt16, _ length: Int) -> Bool {
        switch ch {
        case asterisk: return (1...3).contains(length)
        case underscore: return length == 1
        case tilde: return length == 2
        default: return false
        }
    }

    private static func needsWordBoundary(_ ch: UInt16, _ length: Int) -> Bool {
        length == 1 && (ch == asterisk || ch == underscore)
    }

    private static func canOpenStyle(_ u: [UInt16], _ pos: Int, _ runEnd: Int, _ end: Int) -> Bool {
        let ch = u[pos]
        let length = runEnd - pos
        guard isValidStyleMarker(ch, length) else { return false }
        guard runEnd < end, !isWhitespace(u[runEnd]) else { return false }
        if needsWordBoundary(ch, length), isAlphanumeric(before: pos, in: u) { return false }
        return true
    }

    private static func canCloseStyle(_ u: [UInt16], openEnd: Int, close: Int, closeEnd: Int) -> Bool {
        guard close > openEnd, !isWhitespace(u[close - 1]) else { return false }
        guard u[openEnd..<close].contains(where: { !isWhitespace($0) }) else { return false }
        if needsWordBoundary(u[close], closeEnd - close), isAlphanumeric(at: closeEnd, in: u) { return false }
        return true
    }

    private static func mayCloseStyle(_ u: [UInt16], _ pos: Int, _ runEnd: Int) -> Bool {
        guard pos > 0, !isWhitespace(u[pos - 1]) else { return false }
        if needsWordBoundary(u[pos], runEnd - pos), isAlphanumeric(at: runEnd, in: u) { return false }
        return true
    }

    private static func findStyleClose(
        _ u: [UInt16],
        open: Int,
        length: Int,
        end: Int,
        protectedEnd: [Int],
        depth: Int
    ) -> Int? {
        guard depth < maxStyleDepth else { return nil }
        let ch = u[open]
        let openEnd = open + length
        var j = openEnd
        while j < end {
            if protectedEnd[j] != 0 {
                j = min(protectedEnd[j], end)
                continue
            }
            guard u[j] == ch else {
                j += 1
                continue
            }
            let runEnd = styleRunEnd(u, j, end, protectedEnd)
            let runLength = runEnd - j
            if runLength == length {
                if canCloseStyle(u, openEnd: openEnd, close: j, closeEnd: runEnd) {
                    return j
                }
                if canOpenStyle(u, j, runEnd, end) {
                    return nil
                }
                j = runEnd
            } else if ch == asterisk {
                if canOpenStyle(u, j, runEnd, end) {
                    guard let nestedClose = findStyleClose(
                        u, open: j, length: runLength, end: end, protectedEnd: protectedEnd, depth: depth + 1
                    ) else { return nil }
                    j = nestedClose + runLength
                    continue
                }
                if mayCloseStyle(u, j, runEnd) {
                    return nil
                }
                j = runEnd
            } else {
                j = runEnd
            }
        }
        return nil
    }

    private static func scanStyles(
        _ u: [UInt16],
        start: Int,
        end: Int,
        protectedEnd: [Int],
        depth: Int,
        into out: inout [Match]
    ) {
        guard depth < maxStyleDepth else { return }
        var i = start
        while i < end {
            if protectedEnd[i] != 0 {
                i = min(protectedEnd[i], end)
                continue
            }
            let ch = u[i]
            guard ch == asterisk || ch == underscore || ch == tilde else {
                i += 1
                continue
            }
            let runEnd = styleRunEnd(u, i, end, protectedEnd)
            let length = runEnd - i
            if canOpenStyle(u, i, runEnd, end),
               let close = findStyleClose(u, open: i, length: length, end: end, protectedEnd: protectedEnd, depth: depth) {
                let matchEnd = close + length
                if ch == asterisk, length == 3 {
                    out.append(Match(kind: .bold, start: i, end: matchEnd, marker: 3))
                    out.append(Match(kind: .italic, start: i, end: matchEnd, marker: 3))
                } else if ch == asterisk, length == 2 {
                    out.append(Match(kind: .bold, start: i, end: matchEnd, marker: 2))
                } else if ch == tilde {
                    out.append(Match(kind: .strike, start: i, end: matchEnd, marker: 2))
                } else {
                    out.append(Match(kind: .italic, start: i, end: matchEnd, marker: 1))
                }
                scanStyles(u, start: runEnd, end: close, protectedEnd: protectedEnd, depth: depth + 1, into: &out)
                i = matchEnd
                continue
            }
            i = runEnd
        }
    }


    private struct FormatKey: Hashable {
        let type: String
        let start: Int
        let end: Int
    }

    private struct EditMarker {
        let start: Int
        let end: Int
        let marker: String
        let rank: Int
    }

    private struct StyledRange {
        let start: Int
        let end: Int
        var bold = false
        var italic = false
        var strike = false

        var keys: [FormatKey] {
            var out: [FormatKey] = []
            if bold { out.append(FormatKey(type: "b", start: start, end: end)) }
            if italic { out.append(FormatKey(type: "i", start: start, end: end)) }
            if strike { out.append(FormatKey(type: "st", start: start, end: end)) }
            return out
        }

        func keeping(_ allowed: Set<FormatKey>) -> StyledRange? {
            var kept = self
            kept.bold = bold && allowed.contains(FormatKey(type: "b", start: start, end: end))
            kept.italic = italic && allowed.contains(FormatKey(type: "i", start: start, end: end))
            kept.strike = strike && allowed.contains(FormatKey(type: "st", start: start, end: end))
            return kept.bold || kept.italic || kept.strike ? kept : nil
        }

        func markers(italicMarker: String) -> [EditMarker] {
            var out: [EditMarker] = []
            if strike {
                out.append(EditMarker(start: start, end: end, marker: "~~", rank: 5))
            }
            if bold, italic {
                out.append(EditMarker(start: start, end: end, marker: "***", rank: 4))
            } else if bold {
                out.append(EditMarker(start: start, end: end, marker: "**", rank: 3))
            } else if italic {
                out.append(EditMarker(start: start, end: end, marker: italicMarker, rank: 2))
            }
            return out
        }
    }

    private static let formatTypes: Set<String> = ["b", "i", "st", "c", "pre"]

    static func editSource(text: String, tokens: [ContentToken]) -> EditSource {
        let units = Array(text.utf16)
        let n = units.count
        var codeMarkers: [EditMarker] = []
        var codeKeys = Set<FormatKey>()
        var styled: [StyledRange] = []
        var protectedDisplay: [NSRange] = []

        for token in tokens {
            guard token.start >= 0, token.end <= n, token.start < token.end else { continue }
            switch token.kind {
            case .inlineCode:
                codeMarkers.append(EditMarker(start: token.start, end: token.end, marker: "`", rank: 0))
                codeKeys.insert(FormatKey(type: "c", start: token.start, end: token.end))
            case .codeBlock:
                codeMarkers.append(EditMarker(start: token.start, end: token.end, marker: "```", rank: 1))
                codeKeys.insert(FormatKey(type: "pre", start: token.start, end: token.end))
            case .bold, .italic, .strikethrough:
                let index: Int
                if let existing = styled.firstIndex(where: { $0.start == token.start && $0.end == token.end }) {
                    index = existing
                } else {
                    styled.append(StyledRange(start: token.start, end: token.end))
                    index = styled.count - 1
                }
                switch token.kind {
                case .bold: styled[index].bold = true
                case .italic: styled[index].italic = true
                default: styled[index].strike = true
                }
            case .mention, .hashtag, .emoji, .mezonChannelLink:
                protectedDisplay.append(NSRange(location: token.start, length: token.end - token.start))
            case .link:
                break
            }
        }

        let codeOnly = assemble(units, markers: codeMarkers)
        var candidates = styled
        for _ in 0..<2 where !candidates.isEmpty {
            let expected = codeKeys.union(candidates.flatMap(\.keys))
            var reproduced = Set<FormatKey>()
            for italicMarker in ["*", "_"] {
                let source = assemble(units, markers: codeMarkers + candidates.flatMap { $0.markers(italicMarker: italicMarker) })
                let parsed = parsedFormats(of: source, protectedDisplay: protectedDisplay)
                guard parsed.text == text else { continue }
                if parsed.formats == expected {
                    return source
                }
                reproduced.formUnion(parsed.formats)
            }
            let reduced = candidates.compactMap { $0.keeping(reproduced) }
            if reduced.flatMap(\.keys) == candidates.flatMap(\.keys) {
                break
            }
            candidates = reduced
        }
        return codeOnly
    }

    private static func parsedFormats(of source: EditSource, protectedDisplay: [NSRange]) -> (text: String, formats: Set<FormatKey>) {
        let protectedRaw = protectedDisplay.map { source.editRange(fromDisplay: $0) }
        let built = build(rawInput: source.text, emojiIdByColon: [:], protectedRanges: protectedRaw)
        let formats = Set(built.mk.compactMap { item -> FormatKey? in
            guard let type = item["type"] as? String, formatTypes.contains(type),
                  let s = item["s"] as? Int, let e = item["e"] as? Int else { return nil }
            return FormatKey(type: type, start: s, end: e)
        })
        return (built.displayText, formats)
    }

    private static func assemble(_ units: [UInt16], markers: [EditMarker]) -> EditSource {
        let sorted = markers.sorted {
            ($0.start, -$0.end, -$0.rank) < ($1.start, -$1.end, -$1.rank)
        }
        var pointSet: Set<Int> = [0, units.count]
        for m in sorted {
            pointSet.insert(m.start)
            pointSet.insert(m.end)
        }
        let points = pointSet.sorted()
        var out: [UInt16] = []
        out.reserveCapacity(units.count + sorted.count * 6)
        var insertions: [(at: Int, length: Int)] = []
        for (index, cursor) in points.enumerated() {
            for m in sorted.reversed() where m.end == cursor {
                let markerUnits = Array(m.marker.utf16)
                out.append(contentsOf: markerUnits)
                insertions.append((at: cursor, length: markerUnits.count))
            }
            guard index + 1 < points.count else { break }
            for m in sorted where m.start == cursor {
                let markerUnits = Array(m.marker.utf16)
                out.append(contentsOf: markerUnits)
                insertions.append((at: cursor, length: markerUnits.count))
            }
            out.append(contentsOf: units[cursor..<points[index + 1]])
        }
        return EditSource(text: String(decoding: out, as: UTF16.self), insertions: insertions)
    }


    private static let googleMeetPrefix = "https://meet.google.com/"
    private static let youtubeRegex = try! NSRegularExpression(
        pattern: #"(?:youtube\.com\/(?:watch\?v=|embed\/|v\/|e\/|shorts\/)|youtu\.be\/)"#
    )
    private static let facebookRegex = try! NSRegularExpression(
        pattern: #"(?:facebook\.com\/(?:reel\/|watch\?v=|[\w.]+\/videos\/(?:[\w.]+\/)?))([\w-]+)"#
    )
    private static let tiktokRegex = try! NSRegularExpression(
        pattern: #"(?:tiktok\.com\/@[^/]+\/video\/\d+|vm\.tiktok\.com\/[a-zA-Z0-9]+|tiktok\.com\/t\/[a-zA-Z0-9]+)"#
    )

    private static func classifyLink(_ url: String) -> String {
        if url.hasPrefix(googleMeetPrefix) { return "vk" }
        let range = NSRange(url.startIndex..., in: url)
        if youtubeRegex.firstMatch(in: url, range: range) != nil { return "lk_yt" }
        if facebookRegex.firstMatch(in: url, range: range) != nil { return "lk_fb" }
        if tiktokRegex.firstMatch(in: url, range: range) != nil { return "lk_tt" }
        return "lk"
    }
}
