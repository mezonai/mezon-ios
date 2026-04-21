import UIKit

private enum ClanTemplateChannelKind {
    static let text = MezonConstants.ChannelType.channel.rawValue
    static let voice = MezonConstants.ChannelType.mezonVoice.rawValue
}

struct ClanTemplateChannelDef {
    let name: String
    let channelType: Int32
    let isPrivate: Bool

    static func text(_ name: String, isPrivate: Bool = false) -> ClanTemplateChannelDef {
        ClanTemplateChannelDef(name: name, channelType: ClanTemplateChannelKind.text, isPrivate: isPrivate)
    }

    static func voice(_ name: String) -> ClanTemplateChannelDef {
        ClanTemplateChannelDef(name: name, channelType: ClanTemplateChannelKind.voice, isPrivate: false)
    }
}

struct ClanTemplateCategoryDef {
    let categoryName: String
    let channels: [ClanTemplateChannelDef]
}

enum ClanCreationTemplate: Int, CaseIterable {
    case gaming = 0
    case friends = 1
    case studyGroup = 2
    case schoolClub = 3
    case localCommunity = 4
    case artistsAndCreators = 5

    var iconSystemName: String {
        switch self {
        case .gaming: return "gamecontroller.fill"
        case .friends: return "person.2.fill"
        case .studyGroup: return "book.fill"
        case .schoolClub: return "ruler.fill"
        case .localCommunity: return "bubble.left.and.bubble.right.fill"
        case .artistsAndCreators: return "paintpalette.fill"
        }
    }

    var iconTint: UIColor {
        switch self {
        case .gaming: return UIColor(red: 0.35, green: 0.55, blue: 1, alpha: 1)
        case .friends: return UIColor(red: 0.4, green: 0.85, blue: 0.45, alpha: 1)
        case .studyGroup: return UIColor(red: 1, green: 0.75, blue: 0.35, alpha: 1)
        case .schoolClub: return UIColor(red: 0.6, green: 0.75, blue: 1, alpha: 1)
        case .localCommunity: return UIColor(red: 0.95, green: 0.45, blue: 0.55, alpha: 1)
        case .artistsAndCreators: return UIColor(red: 0.85, green: 0.5, blue: 0.95, alpha: 1)
        }
    }

    var postCreateCategoryPlans: [ClanTemplateCategoryDef] {
        typealias G = ClanTemplateCategoryDef
        switch self {
        case .gaming:
            return [
                G(categoryName: "", channels: [.text("clips-highlights"), .text("looking-for-group")]),
                G(categoryName: "Private Channels", channels: [.text("admin-chat", isPrivate: true)]),
                G(categoryName: "Voice Channels", channels: [.voice("Lobby"), .voice("Gaming")]),
            ]
        case .friends:
            return [
                G(categoryName: "", channels: [.text("memes"), .text("photos")]),
                G(categoryName: "Private Channels", channels: [.text("private-chat", isPrivate: true)]),
                G(categoryName: "Voice Channels", channels: [.voice("Lounge"), .voice("Stream Room")]),
            ]
        case .studyGroup:
            return [
                G(categoryName: "", channels: [.text("homework-help"), .text("session-planning"), .text("off-topic")]),
                G(categoryName: "Private Channels", channels: [.text("private-chat", isPrivate: true)]),
                G(categoryName: "Voice Channels", channels: [.voice("Lounge"), .voice("Study Room 1"), .voice("Study Room 2")]),
            ]
        case .schoolClub:
            return [
                G(categoryName: "", channels: [.text("meeting-plans"), .text("off-topic")]),
                G(categoryName: "Private Channels", channels: [.text("private-chat", isPrivate: true)]),
                G(categoryName: "Voice Channels", channels: [.voice("Lounge"), .voice("Meeting Room 1"), .voice("Meeting Room 2")]),
            ]
        case .localCommunity:
            return [
                G(categoryName: "", channels: [.text("events"), .text("introductions"), .text("resources")]),
                G(categoryName: "Private Channels", channels: [.text("private-chat", isPrivate: true)]),
                G(categoryName: "Voice Channels", channels: [.voice("Lounge"), .voice("Meeting Room")]),
            ]
        case .artistsAndCreators:
            return [
                G(categoryName: "", channels: [.text("showcase"), .text("ideas-and-feedback")]),
                G(categoryName: "Private Channels", channels: [.text("private-chat", isPrivate: true)]),
                G(categoryName: "Voice Channels", channels: [.voice("Lounge"), .voice("Community Hangout"), .voice("Stream Room")]),
            ]
        }
    }
}

enum ClanCreationNameRules {
    static let maxLength = 64

    static func isValid(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxLength else { return false }
        for ch in t {
            if ch.isLetter || ch.isNumber { continue }
            if ch == " " || ch == "_" || ch == "-" { continue }
            return false
        }
        return true
    }
}
