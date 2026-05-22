import Foundation

enum MezonConstants {

    static let anonymousUserId: Int64 = 1767478432163172999

    static let waveStickerFilename = "hello"
    static let waveStickerAttachmentSize: Int32 = 374_892
    static let waveStickerWidth: Int32 = 150
    static let waveStickerHeight: Int32 = 150
    static let waveSenderDisplayName = "Mezon"
    static let waveSenderAvatarURL = "https://cdn.mezon.ai/0/1840653409082937344/1782991817428439000/1748500199026_0logo_new.png"
    static let waveStickerURLs: [String] = [
        "https://cdn.mezon.ai/stickers/hellomezon.gif",
        "https://cdn.mezon.ai/stickers/music_boy.gif",
        "https://cdn.mezon.ai/stickers/music_girl.gif",
        "https://cdn.mezon.ai/stickers/d1.gif",
        "https://cdn.mezon.ai/stickers/d2.gif",
        "https://cdn.mezon.ai/stickers/d3.gif",
        "https://cdn.mezon.ai/stickers/d4.gif",
        "https://cdn.mezon.ai/stickers/d5.gif",
        "https://cdn.mezon.ai/stickers/whatsapp.gif",
        "https://cdn.mezon.ai/stickers/zalo.gif",
        "https://cdn.mezon.ai/stickers/mezon.gif",
        "https://cdn.mezon.ai/stickers/telegram.gif",
        "https://cdn.mezon.ai/stickers/mezon.gif",
        "https://cdn.mezon.ai/stickers/slack.gif",
        "https://cdn.mezon.ai/stickers/mezon.gif",
        "https://cdn.mezon.ai/stickers/discord.gif",
        "https://cdn.mezon.ai/stickers/mezon.gif",
        "http://cdn.mezon.ai/landing-page-mezon/2021919345600368640.gif",
    ]

    enum ChannelType: Int32 {
        case channel = 1
        case group = 2
        case dm = 3
        case forum = 5
        case streaming = 6
        case thread = 7
        case app = 8
        case announcement = 9
        case mezonVoice = 10
    }

    enum ChannelStreamMode: Int32 {
        case channel = 2
        case group = 3
        case dm = 4
        case clan = 5
        case thread = 6
    }

    enum MessageCode: Int32 {
        case firstMessage = 4
        case welcome = 5
        case createThread = 6
        case createPin = 7
        case buzz = 8
        case auditLog = 10
        case sendToken = 11
        case ephemeral = 12
        case upcomingEvent = 13
        case updateEphemeral = 14  
        case deleteEphemeral = 15  
        case poll = 18
    }
}
