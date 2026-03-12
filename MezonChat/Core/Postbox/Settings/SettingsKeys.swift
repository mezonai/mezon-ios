import Foundation

enum SettingsKeys {

    static let account         = "account"

    static let clans           = "clans"
    static let selectedClanId  = "selectedClanId"
    static func selectedChannelId(clanId: Int64) -> String {
        "selectedChannel_\(clanId)"
    }

    static let theme           = "theme"
    static let language        = "language"

    static let notificationSettings = "notificationSettings"
    static let muteUntil       = "muteUntil"
}
