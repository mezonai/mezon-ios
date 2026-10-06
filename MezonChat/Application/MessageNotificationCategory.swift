import Foundation
import UserNotifications

enum MessageNotificationCategory {

    static let identifier = "MEZON_MESSAGE"
    static let viewActionIdentifier = "MEZON_MESSAGE_VIEW"
    static let replyActionIdentifier = "MEZON_MESSAGE_REPLY"
    static let likeActionIdentifier = "MEZON_MESSAGE_LIKE"
    static let muteOneHourActionIdentifier = "MEZON_MESSAGE_MUTE_1H"

    private static let appGroupIdentifier = "group.mezon.mobile"
    private static let notificationsMutedUntilKey = "notificationsMutedUntil"
    private static let muteDuration: TimeInterval = 60 * 60

    static func register() {
        let view = UNNotificationAction(
            identifier: viewActionIdentifier,
            title: L(L10n.NotificationActions.view),
            options: [.foreground]
        )
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
        let muteOneHour = UNNotificationAction(
            identifier: muteOneHourActionIdentifier,
            title: L(L10n.NotificationActions.muteOneHour),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [view, reply, like, muteOneHour],
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

    static func isMuteOneHourAction(_ response: UNNotificationResponse) -> Bool {
        response.actionIdentifier == muteOneHourActionIdentifier
    }

    static func isBackgroundAction(_ response: UNNotificationResponse) -> Bool {
        isReplyAction(response) || isLikeAction(response) || isMuteOneHourAction(response)
    }

    static func muteNotificationsForOneHour() {
        let mutedUntil = Date().addingTimeInterval(muteDuration).timeIntervalSince1970
        UserDefaults(suiteName: appGroupIdentifier)?.set(mutedUntil, forKey: notificationsMutedUntilKey)
    }

    static var areNotificationsMuted: Bool {
        guard let mutedUntil = UserDefaults(suiteName: appGroupIdentifier)?.double(forKey: notificationsMutedUntilKey) else {
            return false
        }
        return Date().timeIntervalSince1970 < mutedUntil
    }
}
