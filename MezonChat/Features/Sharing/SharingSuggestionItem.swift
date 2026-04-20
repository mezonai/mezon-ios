import Foundation

struct SharingSuggestionItem: Hashable {
    let channelID: Int64
    let clanID: Int64
    let type: Int32
    let displayName: String
    let avatarURL: String?
    let channelAvatar: String
    let channelPrivate: Int32
    let ageRestricted: Int32
    let clanName: String?
    let clanLogo: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(channelID)
    }

    static func == (lhs: SharingSuggestionItem, rhs: SharingSuggestionItem) -> Bool {
        lhs.channelID == rhs.channelID
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
