import Foundation
import UserNotifications

enum MessageNotificationCategory {

    static let identifier = "MEZON_MESSAGE"
    static let viewActionIdentifier = "MEZON_MESSAGE_VIEW"
    static let replyActionIdentifier = "MEZON_MESSAGE_REPLY"

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
        let category = UNNotificationCategory(
            identifier: identifier,
            actions: [view, reply],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func isReplyAction(_ response: UNNotificationResponse) -> Bool {
        response.actionIdentifier == replyActionIdentifier
    }
}
