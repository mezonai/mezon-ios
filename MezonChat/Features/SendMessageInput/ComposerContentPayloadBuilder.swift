import Foundation


enum ComposerContentPayloadBuilder {

    struct BuiltPayload {
        let displayText: String
        let mk: [[String: Any]]
        let ej: [[String: Any]]
    }

    static func build(rawInput: String, emojiIdByColon: [String: String]) -> BuiltPayload {
        let normalized = rawInput
        let bolds = processBold(normalized)
        let pt = processText(normalized, emojiIdByColon: emojiIdByColon)
        let display = removeBackticks(stripBoldWrappers(normalized))

        var mk: [[String: Any]] = []
        mk.append(contentsOf: pt.links)
        mk.append(contentsOf: pt.voiceRooms)
        mk.append(contentsOf: pt.markdowns)
        mk.append(contentsOf: bolds)
        mk.sort {
            let sa = ($0["s"] as? Int) ?? 0
            let sb = ($1["s"] as? Int) ?? 0
            return sa < sb
        }

        return BuiltPayload(displayText: display, mk: mk, ej: pt.emojis)
    }


    private static func stripBoldWrappers(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\*\*([\s\S]*?)\*\*"#, options: []) else { return text }
        var result = text
        for _ in 0..<500 {
            let ns = result as NSString
            let full = NSRange(location: 0, length: ns.length)
            let new = regex.stringByReplacingMatches(in: result, options: [], range: full, withTemplate: "$1")
            if new == result { break }
            result = new
        }
        return result
    }


    private static func removeBackticks(_ text: String) -> String {
        let chars = Array(text.utf16)
        guard !chars.isEmpty else { return "" }
        var result: [UInt16] = []
        var i = 0
        while i < chars.count {
            if i + 2 < chars.count, chars[i] == 0x60, chars[i + 1] == 0x60, chars[i + 2] == 0x60 {
                var j = i + 3
                var content: [UInt16] = []
                while j + 2 < chars.count,
                      !(chars[j] == 0x60 && chars[j + 1] == 0x60 && chars[j + 2] == 0x60) {
                    content.append(chars[j])
                    j += 1
                }
                if j + 2 < chars.count,
                   chars[j] == 0x60, chars[j + 1] == 0x60, chars[j + 2] == 0x60 {
                    result.append(contentsOf: content)
                    i = j + 3
                    continue
                }
            }

            if chars[i] == 0x60,
               !(i + 2 < chars.count && chars[i + 1] == 0x60 && chars[i + 2] == 0x60) {
                let j = i + 1
                var tempJ = j
                while tempJ < chars.count, chars[tempJ] != 0x60 {
                    tempJ += 1
                }
                if tempJ < chars.count, chars[tempJ] == 0x60 {
                    let markdown = Array(chars[j..<tempJ])
                    var allow = true
                    if tempJ + 2 < chars.count,
                       chars[tempJ] == 0x60, chars[tempJ + 1] == 0x60, chars[tempJ + 2] == 0x60 {
                        var k = tempJ + 3
                        var hasClosingTriple = false
                        while k + 2 < chars.count {
                            if chars[k] == 0x60, chars[k + 1] == 0x60, chars[k + 2] == 0x60 {
                                hasClosingTriple = true
                                break
                            }
                            k += 1
                        }
                        if hasClosingTriple { allow = false }
                    }
                    let mdStr = markdown.withUnsafeBufferPointer { buf in
                        String(decoding: buf, as: UTF16.self)
                    }
                    if allow, !mdStr.contains("``"), mdStr.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
                        result.append(contentsOf: markdown)
                        i = tempJ + 1
                        continue
                    }
                }
            }

            result.append(chars[i])
            i += 1
        }
        return result.withUnsafeBufferPointer { buf in
            String(decoding: buf, as: UTF16.self)
        }
    }

    private static func getCleanLen(_ str: String) -> Int {
        var s = str
        guard let tripleR = try? NSRegularExpression(pattern: "```([\\s\\S]*?)```", options: []),
              let singleR = try? NSRegularExpression(pattern: "`([^`]+)`", options: []) else {
            return (str as NSString).length
        }
        for _ in 0..<200 {
            let ns = s as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = tripleR.firstMatch(in: s, options: [], range: full) {
                let inner = ns.substring(with: m.range(at: 1))
                s = ns.replacingCharacters(in: m.range, with: inner)
                continue
            }
            if let m = singleR.firstMatch(in: s, options: [], range: full) {
                let inner = ns.substring(with: m.range(at: 1))
                s = ns.replacingCharacters(in: m.range, with: inner)
                continue
            }
            break
        }
        return (s as NSString).length
    }

    private static func getCleanLenBold(_ str: String) -> Int {
        var s = str
        guard let r = try? NSRegularExpression(pattern: #"\*\*(.*?)\*\*"#, options: []) else {
            return (str as NSString).length
        }
        for _ in 0..<200 {
            let ns = s as NSString
            let full = NSRange(location: 0, length: ns.length)
            guard let m = r.firstMatch(in: s, options: [], range: full) else { break }
            let inner = ns.substring(with: m.range(at: 1))
            s = ns.replacingCharacters(in: m.range, with: inner)
        }
        return (s as NSString).length
    }


    private static func processBold(_ inputString: String) -> [[String: Any]] {
        var bolds: [[String: Any]] = []
        let boldPrefix = "**"
        let ns = inputString as NSString
        let len = ns.length
        let bpLen = (boldPrefix as NSString).length
        var i = 0
        var cleanedPosition = 0

        while i < len {
            let start = ns.range(of: boldPrefix, range: NSRange(location: i, length: len - i)).location
            if start == NSNotFound { break }
            let end = ns.range(of: boldPrefix, range: NSRange(location: start + bpLen, length: len - (start + bpLen))).location
            if end == NSNotFound { break }

            let boldText = ns.substring(with: NSRange(location: start + bpLen, length: end - (start + bpLen)))
            let segmentBefore = ns.substring(with: NSRange(location: i, length: start - i))

            cleanedPosition += getCleanLen(segmentBefore)

            if boldText.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
                let boldTextCleanLen = getCleanLen(boldText)
                let startIndex = cleanedPosition
                let endIndex = startIndex + boldTextCleanLen
                bolds.append(["type": "b", "s": startIndex, "e": endIndex])
                cleanedPosition += boldTextCleanLen
            }

            i = end + bpLen
        }
        return bolds
    }


    private struct ProcessTextResult {
        var emojis: [[String: Any]] = []
        var links: [[String: Any]] = []
        var markdowns: [[String: Any]] = []
        var voiceRooms: [[String: Any]] = []
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

    private static func processText(_ inputString: String, emojiIdByColon: [String: String]) -> ProcessTextResult {
        var result = ProcessTextResult()
        let ns = inputString as NSString
        let len = ns.length
        var shift = 0
        var i = 0

        let httpLen = (("http://" as NSString).length)
        let httpsLen = (("https://" as NSString).length)

        while i < len {
            var handled = false


            if i < len, ns.character(at: i) == 0x003A, i + 1 < len {
                let colonIdx = i
                var j = i + 1
                while j < len, ns.character(at: j) != 0x003A {
                    j += 1
                }
                if j < len, ns.character(at: j) == 0x003A {
                    let shortname = ns.substring(with: NSRange(location: i + 1, length: j - i - 1))
                    if !shortname.isEmpty {
                        let endindex = j + 1
                        let pre4 = colonIdx >= 4 ? ns.substring(with: NSRange(location: colonIdx - 4, length: 4)) : ""
                        let pre5 = colonIdx >= 5 ? ns.substring(with: NSRange(location: colonIdx - 5, length: 5)) : ""
                        let key = ":\(shortname):"
                        if pre4 != "http", pre5 != "https", let emojiId = emojiIdByColon[key] {
                            result.emojis.append(["emojiid": emojiId, "s": colonIdx - shift, "e": endindex - shift])
                            i = endindex
                            handled = true
                        }
                    }
                }
            }

            if !handled, i < len {
                let tail = ns.substring(from: i)
                if tail.hasPrefix("https://") || tail.hasPrefix("http://") {
                    let startindex = i
                    let https = tail.hasPrefix("https://")
                    var i2 = i + (https ? httpsLen : httpLen)
                    let stop: Set<unichar> = [0x20, 0x0A, 0x0D, 0x09]
                    while i2 < len, !stop.contains(ns.character(at: i2)) {
                        i2 += 1
                    }
                    var endindex = i2
                    let trailing: Set<unichar> = [0x2C, 0x2E, 0x21, 0x3F, 0x3B, 0x3A]
                    let minEnd = startindex + (https ? httpsLen : httpLen)
                    while endindex > minEnd, trailing.contains(ns.character(at: endindex - 1)) {
                        endindex -= 1
                    }
                    let link = ns.substring(with: NSRange(location: startindex, length: endindex - startindex))
                    if link.hasPrefix(googleMeetPrefix) {
                        result.voiceRooms.append([
                            "type": "vk",
                            "s": startindex - shift,
                            "e": endindex - shift,
                        ])
                    } else {
                        let linkType = classifyLink(link)
                        result.links.append([
                            "type": linkType,
                            "s": startindex - shift,
                            "e": endindex - shift,
                            "channelId": "",
                            "clanId": "",
                            "channelLabel": "",
                        ])
                    }
                    i = i2
                    handled = true
                }
            }


            if !handled, i + 2 < len,
               ns.character(at: i) == 0x60, ns.character(at: i + 1) == 0x60, ns.character(at: i + 2) == 0x60 {
                let startindex = i
                var i2 = i + 3
                while i2 + 2 < len,
                      !(ns.character(at: i2) == 0x60 && ns.character(at: i2 + 1) == 0x60 && ns.character(at: i2 + 2) == 0x60) {
                    i2 += 1
                }
                if i2 + 2 < len,
                   ns.character(at: i2) == 0x60, ns.character(at: i2 + 1) == 0x60, ns.character(at: i2 + 2) == 0x60 {
                    let markdown = ns.substring(with: NSRange(location: i + 3, length: i2 - (i + 3)))
                    i2 += 3
                    let endindex = i2
                    let contentCleanLen = getCleanLenBold(markdown)
                    let s = startindex - shift
                    let e = s + contentCleanLen
                    if !markdown.isEmpty {
                        result.markdowns.append(["type": "pre", "s": s, "e": e])
                    }
                    shift += 6 + (markdown.utf16.count - contentCleanLen)
                    i = endindex
                    handled = true
                }
            }


            if !handled, i < len, ns.character(at: i) == 0x60,
               !(i + 2 < len && ns.character(at: i + 1) == 0x60 && ns.character(at: i + 2) == 0x60) {
                let startindex = i
                var i3 = i + 1
                while i3 < len, ns.character(at: i3) != 0x60 {
                    i3 += 1
                }
                if i3 < len, ns.character(at: i3) == 0x60 {
                    let markdown = ns.substring(with: NSRange(location: i + 1, length: i3 - (i + 1)))
                    let endindex = i3 + 1
                    var allow = true
                    if i3 + 2 < len,
                       ns.character(at: i3) == 0x60, ns.character(at: i3 + 1) == 0x60, ns.character(at: i3 + 2) == 0x60 {
                        var k = i3 + 3
                        var hasClosingTriple = false
                        while k + 2 < len {
                            if ns.character(at: k) == 0x60, ns.character(at: k + 1) == 0x60, ns.character(at: k + 2) == 0x60 {
                                hasClosingTriple = true
                                break
                            }
                            k += 1
                        }
                        if hasClosingTriple { allow = false }
                    }
                    if allow, !markdown.contains("``"), markdown.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
                        let contentCleanLen = getCleanLenBold(markdown)
                        let s = startindex - shift
                        let e = s + contentCleanLen
                        result.markdowns.append(["type": "c", "s": s, "e": e])
                        shift += 2 + (markdown.utf16.count - contentCleanLen)
                        i = endindex
                        handled = true
                    }
                }
            }

            if !handled, i + 1 < len, ns.character(at: i) == 0x2A, ns.character(at: i + 1) == 0x2A {
                shift += 2
                i += 2
                handled = true
            }

            if !handled {
                i += 1
            }
        }

        return result
    }
}
