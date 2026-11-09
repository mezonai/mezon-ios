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

    enum Chat {
        static let screen = makeAccessibilityID("chat.screen")
        static let messageMenu = makeAccessibilityID("message.menu")
        static let replyAction = makeAccessibilityID("message.action.reply")
        static let replyBanner = makeAccessibilityID("mention.reply.target")
        static let replyReference = makeAccessibilityID("replied_message.item")
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
