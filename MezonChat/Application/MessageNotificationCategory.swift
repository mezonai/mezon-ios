import Foundation
import UserNotifications

enum MessageNotificationCategory {

    static let identifier = "MEZON_MESSAGE"
    static let viewActionIdentifier = "MEZON_MESSAGE_VIEW"
    static let replyActionIdentifier = "MEZON_MESSAGE_REPLY"
    static let likeActionIdentifier = "MEZON_MESSAGE_LIKE"
    static let muteActionIdentifier = "MEZON_MESSAGE_MUTE_15M"
    private static let legacyMuteActionIdentifier = "MEZON_MESSAGE_MUTE_1H"

    private static let appGroupIdentifier = "group.mezon.mobile"
    private static let activeUserKey = "notificationMuteActiveUser"
    private static let muteKeyPrefix = "notificationMuteUntil"

    static func register() {
        let reply = UNTextInputNotificationAction(
            identifier: replyActionIdentifier,
            title: L(L10n.NotificationActions.reply),
            options: [],
            textInputButtonTitle: L(L10n.NotificationActions.send),
            textInputPlaceholder: L(L10n.NotificationActions.placeholder)
        )
        let like = UNNotificationAction(
            identifier: likeActionIdentifier,
            title: L(L10n.NotificationActions.like),
            options: []
        )
        let mute = UNNotificationAction(
            identifier: muteActionIdentifier,
            title: L(L10n.NotificationActions.mute15Minutes),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [mute, reply, like],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func isReplyAction(_ response: UNNotificationResponse) -> Bool {
        response.actionIdentifier == replyActionIdentifier
    }

    static func isLikeAction(_ response: UNNotificationResponse) -> Bool {
        response.actionIdentifier == likeActionIdentifier
    }

    static func isMuteAction(_ response: UNNotificationResponse) -> Bool {
        response.actionIdentifier == muteActionIdentifier || response.actionIdentifier == legacyMuteActionIdentifier
    }

    static func muteDuration(for response: UNNotificationResponse) -> Int32 {
        response.actionIdentifier == legacyMuteActionIdentifier ? 3600 : 900
    }

    static func isBackgroundAction(_ response: UNNotificationResponse) -> Bool {
        isReplyAction(response) || isLikeAction(response) || isMuteAction(response)
    }

    static func setActiveUser(_ userId: String?) {
        let shared = UserDefaults(suiteName: appGroupIdentifier)
        if let userId, !userId.isEmpty {
            shared?.set(userId, forKey: activeUserKey)
        } else {
            shared?.removeObject(forKey: activeUserKey)
        }
    }

    static func setMute(channelId: Int64, userId: String?, durationSeconds: Int32) {
        guard channelId != 0, let userId, !userId.isEmpty,
              let shared = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let key = "\(muteKeyPrefix).\(userId).\(channelId)"
        if durationSeconds == 0 {
            shared.removeObject(forKey: key)
        } else {
            let expiry = durationSeconds < 0 ? Double.greatestFiniteMagnitude : Date().timeIntervalSince1970 + Double(durationSeconds)
            shared.set(expiry, forKey: key)
        }
    }

    static func updateMuteFromServer(channelId: Int64, userId: String?, muteTimeSeconds: Int32) {
        guard channelId != 0, let userId, !userId.isEmpty,
              let shared = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let key = "\(muteKeyPrefix).\(userId).\(channelId)"
        if muteTimeSeconds == 0 {
            shared.removeObject(forKey: key)
        } else {
            let expiry: TimeInterval
            if muteTimeSeconds < 0 {
                expiry = Double.greatestFiniteMagnitude
            } else if muteTimeSeconds > 100_000_000 {
                expiry = Double(muteTimeSeconds)
            } else {
                expiry = Date().timeIntervalSince1970 + Double(muteTimeSeconds)
            }
            shared.set(expiry, forKey: key)
        }
    }

    static func isMuted(channelId: Int64?) -> Bool {
        guard let channelId, channelId != 0,
              let shared = UserDefaults(suiteName: appGroupIdentifier),
              let userId = shared.string(forKey: activeUserKey), !userId.isEmpty else { return false }
        return Date().timeIntervalSince1970 < shared.double(forKey: "\(muteKeyPrefix).\(userId).\(channelId)")
    }
}
