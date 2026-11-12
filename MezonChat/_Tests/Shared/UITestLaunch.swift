import Foundation

enum UITestLaunch {
    static let chatMetadataArgument = "--uitesting-chat-metadata"
    static let exposesChatMetadata = ProcessInfo.processInfo.arguments.contains(chatMetadataArgument)
    static let skipUpdateCheckArgument = "--uitesting-skip-update-check"
    static let skipsUpdateCheck = ProcessInfo.processInfo.arguments.contains(skipUpdateCheckArgument)
    static let loginArgument = "--uitesting-login"
    static let resetSessionArgument = "--uitesting-reset-session"
    static let loginModeEnvironmentKey = "UITEST_LOGIN_MODE"
}
