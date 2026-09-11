import Foundation
import UserNotifications

enum MessageNotificationCategory {

    static let identifier = "MEZON_MESSAGE"
    static let viewActionIdentifier = "MEZON_MESSAGE_VIEW"
    static let replyActionIdentifier = "MEZON_MESSAGE_REPLY"
    static let likeActionIdentifier = "MEZON_MESSAGE_LIKE"

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
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [view, reply, like],
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

    static func isBackgroundAction(_ response: UNNotificationResponse) -> Bool {
        isReplyAction(response) || isLikeAction(response)
    }
}
