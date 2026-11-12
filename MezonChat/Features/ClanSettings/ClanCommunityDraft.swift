import Foundation
import SwiftProtobuf

struct ClanCommunityDraft: Equatable {
    static let descriptionLimit = 300
    static let aboutLimit = 3000
    static let vanityURLLimit = 32
    static let bannerByteLimit = 10_000_000

    var banner: String
    var description: String
    var about: String
    var shortURL: String
    var hashtags: [String]

    init(clan: Mezon_Api_ClanDesc) {
        banner = clan.communityBanner
        description = clan.description_p
        about = clan.about
        shortURL = clan.shortURL
        hashtags = ClanCommunityHashtags.parse(clan.hashtags)
        if !clan.isCommunity && hashtags.isEmpty {
            hashtags = ClanCommunityHashtags.defaultSelection
        }
    }

    init(banner: String, description: String, about: String, shortURL: String, hashtags: [String]) {
        self.banner = banner
        self.description = description
        self.about = about
        self.shortURL = shortURL
        self.hashtags = hashtags
    }

    static func limited(_ text: String, to limit: Int) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit)))
    }

    static func normalizedShortURL(_ text: String) -> String {
        let allowed = text.unicodeScalars.filter {
            (65...90).contains($0.value) || (97...122).contains($0.value) || (48...57).contains($0.value) || $0.value == 45
        }
        return String(String.UnicodeScalarView(allowed.prefix(vanityURLLimit))).lowercased()
    }

    var sanitized: Self {
        Self(
            banner: banner.trimmingCharacters(in: .whitespacesAndNewlines),
            description: Self.limited(description.trimmingCharacters(in: .whitespacesAndNewlines), to: Self.descriptionLimit),
            about: Self.limited(about.trimmingCharacters(in: .whitespacesAndNewlines), to: Self.aboutLimit),
            shortURL: Self.normalizedShortURL(shortURL),
            hashtags: ClanCommunityHashtags.normalized(hashtags)
        )
    }

    var isValid: Bool {
        let draft = sanitized
        return !draft.banner.isEmpty && !draft.description.isEmpty && !draft.about.isEmpty && !draft.shortURL.isEmpty
            && (ClanCommunityHashtags.minimumCount...ClanCommunityHashtags.maximumCount).contains(draft.hashtags.count)
    }

    func mergingUneditedFields(from incoming: Self, saved: Self) -> Self {
        Self(
            banner: banner == saved.banner ? incoming.banner : banner,
            description: description == saved.description ? incoming.description : description,
            about: about == saved.about ? incoming.about : about,
            shortURL: shortURL == saved.shortURL ? incoming.shortURL : shortURL,
            hashtags: hashtags == saved.hashtags ? incoming.hashtags : hashtags
        )
    }

    func updateRequest(clanId: Int64, current: Mezon_Api_ClanDesc) -> Mezon_Api_UpdateClanDescRequest {
        let draft = sanitized
        var request = Self.communityRequest(clanId: clanId, current: current, enabled: true)
        request.communityBanner = Google_Protobuf_StringValue(draft.banner)
        request.description_p = Google_Protobuf_StringValue(draft.description)
        request.about = Google_Protobuf_StringValue(draft.about)
        request.shortURL = Google_Protobuf_StringValue(draft.shortURL)
        request.hashtags = Google_Protobuf_StringValue(draft.hashtags.joined(separator: ","))
        return request
    }

    static func disableRequest(clanId: Int64, current: Mezon_Api_ClanDesc) -> Mezon_Api_UpdateClanDescRequest {
        communityRequest(clanId: clanId, current: current, enabled: false)
    }

    private static func communityRequest(clanId: Int64, current: Mezon_Api_ClanDesc, enabled: Bool) -> Mezon_Api_UpdateClanDescRequest {
        var request = Mezon_Api_UpdateClanDescRequest()
        request.clanID = clanId
        request.preventAnonymous = current.preventAnonymous
        request.welcomeChannelID = current.welcomeChannelID
        request.status = current.status
        request.isCommunity = Google_Protobuf_BoolValue(enabled)
        return request
    }

    func apply(to clan: inout Mezon_Api_ClanDesc) {
        clan.isCommunity = true
        clan.communityBanner = banner
        clan.description_p = description
        clan.about = about
        clan.shortURL = shortURL
        clan.hashtags = hashtags.joined(separator: ",")
    }
}

enum ClanCommunityHashtags {
    static let minimumCount = 1
    static let maximumCount = 6
    static let defaultSelection = ["Community"]
    static let options = [
        "Gaming", "Technology", "Education", "Entertainment", "Music",
        "Art", "Crypto", "Anime", "Sports", "Community"
    ]

    static func parse(_ raw: String) -> [String] {
        DiscoverClanHashtags.parse(raw)
    }

    static func normalized(_ tags: [String]) -> [String] {
        DiscoverClanHashtags.normalized(tags)
    }

    static func toggling(_ tag: String, in selected: [String]) -> [String] {
        let selected = normalized(selected)
        if selected.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            guard selected.count > minimumCount else { return selected }
            return selected.filter { $0.caseInsensitiveCompare(tag) != .orderedSame }
        }
        guard selected.count < maximumCount else { return selected }
        return selected + [tag]
    }
}
