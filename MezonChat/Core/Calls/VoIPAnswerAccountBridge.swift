import Foundation

@MainActor
enum VoIPAnswerAccountBridge {
    static weak var context: AccountContextImpl? {
        didSet {
            if context != nil {
                CallKitManager.shared.refreshIncomingCallerIdentityIfNeeded()
            }
        }
    }
}
