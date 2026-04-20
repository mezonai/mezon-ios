import Foundation

enum ClanInviteLinkParser {
    static func firstInviteCode(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if let range = lowered.range(of: "mezon://invite/") {
            let after = trimmed[range.upperBound...]
            let id = prefixDigits(String(after))
            if !id.isEmpty { return id }
        }

        let ns = trimmed as NSString
        let regex = try? NSRegularExpression(
            pattern: #"https?://[^\s]+/invite/(\d+)"#,
            options: [.caseInsensitive]
        )
        if let r = regex?.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length)),
           r.numberOfRanges >= 2 {
            let code = ns.substring(with: r.range(at: 1))
            if !code.isEmpty { return code }
        }

        if let range = lowered.range(of: "/invite/") {
            let after = trimmed[range.upperBound...]
            let id = prefixDigits(String(after))
            if !id.isEmpty { return id }
        }

        return nil
    }

    private static func prefixDigits(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isNumber { out.append(ch) } else if !out.isEmpty { break }
        }
        return out
    }
}
