enum AccessibilityID {
    static func makeAccessibilityID(_ key: String, id: String? = nil) -> String {
        let base = key.split(separator: ".").joined(separator: "-")
        return id.map { "\(base)-\($0)" } ?? base
    }

    enum Main {
        static let root = makeAccessibilityID("main.root")
    }

    enum Auth {
        static let welcomeStart = makeAccessibilityID("auth.welcome.start")
        static let email = makeAccessibilityID("auth.login.email")
        static let phone = makeAccessibilityID("auth.login.phone")
        static let password = makeAccessibilityID("auth.login.password")
        static let submit = makeAccessibilityID("auth.login.submit")
        static let otpSubmit = makeAccessibilityID("auth.otp.submit")

        static func otpDigit(_ index: Int) -> String {
            makeAccessibilityID("auth.otp.digit", id: String(index))
        }
    }

    enum Clan {
        static let list = makeAccessibilityID("clan.list")

        static func item(_ id: String) -> String {
            makeAccessibilityID("clan.item", id: id)
        }

        static func unreadBadge(_ id: String) -> String {
            makeAccessibilityID("clan.unread.badge", id: id)
        }

        static func channelList(_ id: String) -> String {
            makeAccessibilityID("clan.channel.list", id: id)
        }
    }

    enum Chat {
        static let screen = makeAccessibilityID("chat.screen")
        static let messageMenu = makeAccessibilityID("message.menu")
        static let replyAction = makeAccessibilityID("message.action.reply")
        static let editAction = makeAccessibilityID("message.action.edit")
        static let deleteAction = makeAccessibilityID("message.action.delete")
        static let copyAction = makeAccessibilityID("message.action.copy")
        static let reactionPicker = makeAccessibilityID("message.reaction.picker")
        static func mentionUser(_ id: String) -> String {
            makeAccessibilityID("mention.suggestion.user", id: id)
        }

        static func hashtagChannel(_ id: String) -> String {
            makeAccessibilityID("hashtag.suggestion.channel", id: id)
        }

        static let emojiSearch = makeAccessibilityID("emoji.search")

        static func emojiItem(_ id: String) -> String {
            makeAccessibilityID("emoji.item", id: id)
        }

        static let editCancel = makeAccessibilityID("mention.edit.cancel")
        static let replyBanner = makeAccessibilityID("mention.reply.target")
        static let replyReference = makeAccessibilityID("replied_message.item")
        static let channelDetails = makeAccessibilityID("chat.channel.details")
        static let detailsBack = makeAccessibilityID("channel.details.back")
        static let membersTab = makeAccessibilityID("channel.details.members")
        static let pinAction = makeAccessibilityID("message.action.pin")
        static let unpinAction = makeAccessibilityID("message.action.unpin")

        static func pinnedMessage(_ id: String) -> String {
            makeAccessibilityID("channel.pins.message", id: id)
        }

        static func pinnedMessageUnpin(_ id: String) -> String {
            makeAccessibilityID("channel.pins.unpin", id: id)
        }

        static let pinsTab = makeAccessibilityID("channel.details.pins")
        static let back = makeAccessibilityID("chat.back")
        static let input = makeAccessibilityID("mention.input")
        static let send = makeAccessibilityID("mention.button.send")
        static let messages = makeAccessibilityID("message.list")

        static func quickReaction(_ emojiID: String) -> String {
            makeAccessibilityID("message.quick.reaction", id: emojiID)
        }

        static func reactionCount(_ emojiID: String) -> String {
            makeAccessibilityID("message.reaction.count", id: emojiID)
        }

        static func channelRow(_ id: String) -> String {
            makeAccessibilityID("channel.item", id: id)
        }

        static func messageText(_ id: String) -> String {
            makeAccessibilityID("message.text", id: id)
        }

        static func message(_ id: String) -> String {
            makeAccessibilityID("message.item", id: id)
        }
    }
}
