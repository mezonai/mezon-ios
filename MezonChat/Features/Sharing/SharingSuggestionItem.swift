import Foundation

struct SharingSuggestionItem: Hashable, Sendable {
    let channelID: Int64
    let userID: Int64
    let clanID: Int64
    let type: Int32
    let displayName: String
    let avatarURL: String?
    let channelAvatar: String
    let channelPrivate: Int32
    let ageRestricted: Int32
    let clanName: String?
    let clanLogo: String?
    var username: String = ""

    var identity: String {
        channelID != 0 ? "channel_\(channelID)" : "user_\(userID)"
    }

    var needsDirectMessageChannel: Bool {
        channelID == 0 && userID != 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    static func == (lhs: SharingSuggestionItem, rhs: SharingSuggestionItem) -> Bool {
        lhs.identity == rhs.identity
    }
}

/// Only immutable presentation data crosses to the ranking task, never controller state.
struct SharingSearchCandidate: Sendable {
    let item: SharingSuggestionItem
    var username: String = ""
}

enum SharingSearchRanking {
    private static let locale = Locale(identifier: "en_US_POSIX")
    private static let unmatchedRank = 15

    static func ranked(
        _ candidates: [SharingSearchCandidate], query: String
    ) async -> [SharingSuggestionItem] {
        await Task.detached(priority: .userInitiated) {
            rank(candidates, query: query)
        }.value
    }

    static func rank(
        _ candidates: [SharingSearchCandidate], query: String
    ) -> [SharingSuggestionItem] {
        let query = normalized(query)
        guard !query.isEmpty else { return candidates.map(\.item) }
        let queryWords = words(in: query)
        // Fixed buckets preserve API order for ties and avoid O(n log n) sorting.
        var buckets = Array(repeating: [SharingSuggestionItem](), count: unmatchedRank + 1)
        for candidate in candidates {
            let name = normalized(candidate.item.displayName)
            var rank = match(name, query: query, queryWords: queryWords).map { $0 * 2 } ?? unmatchedRank
            if rank != 0, !candidate.username.isEmpty {
                let username = normalized(candidate.username)
                if username != name, let match = match(username, query: query, queryWords: queryWords) {
                    rank = min(rank, match * 2 + 1)
                }
            }
            // Clan context never outranks a matching destination name or username.
            if rank == unmatchedRank, let clanName = candidate.item.clanName,
               let match = match(normalized(clanName), query: query, queryWords: queryWords) {
                rank = 10 + match
            }
            buckets[rank].append(candidate.item)
        }
        var result: [SharingSuggestionItem] = []
        result.reserveCapacity(candidates.count)
        for bucket in buckets { result.append(contentsOf: bucket) }
        return result
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .replacingOccurrences(of: "đ", with: "d")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func words(in text: String) -> [Substring] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    private static func match(_ text: String, query: String, queryWords: [Substring]) -> Int? {
        guard !text.isEmpty else { return nil }
        if text == query { return 0 }
        if text.hasPrefix(query) { return 1 }

        var searchStart = text.startIndex
        var containsQuery = false
        while let range = text.range(of: query, range: searchStart..<text.endIndex) {
            containsQuery = true
            if range.lowerBound == text.startIndex { return 1 }
            let previous = text[text.index(before: range.lowerBound)]
            if !previous.isLetter && !previous.isNumber { return 2 }
            searchStart = range.upperBound
        }

        // Ordered word prefixes support "ng van" -> "Nguyễn Văn", without fuzzy matching.
        if queryWords.count > 1 {
            let textWords = words(in: text)
            var nextWord = 0
            var matchedWords = 0
            for queryWord in queryWords {
                while nextWord < textWords.count && !textWords[nextWord].hasPrefix(queryWord) {
                    nextWord += 1
                }
                guard nextWord < textWords.count else { break }
                matchedWords += 1
                nextWord += 1
            }
            if matchedWords == queryWords.count { return 3 }
        }
        return containsQuery ? 4 : nil
    }
}

enum SharingImageProxy {
    static let avatarPixels = 50

    static func resolvedAssetURLString(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if let u = URL(string: t), u.scheme != nil { return t }
        if t.hasPrefix("//") { return "https:\(t)" }
        let base = MezonConfig.baseImgURL
        if t.hasPrefix("/") { return "\(base)\(t)" }
        return "\(base)/\(t)"
    }

    static func proxiedAvatarURLString(_ raw: String) -> String {
        let abs = resolvedAssetURLString(raw)
        guard !abs.isEmpty else { return "" }
        return ImgproxyURL.create(from: abs, width: avatarPixels, height: avatarPixels)
    }
}
