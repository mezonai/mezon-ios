#if DEBUG
import Foundation

extension AppContext {
    static var preview: AppContext {
        let ctx = AppContext()
        ctx.currentUser = User(
            id: "preview_user",
            username: "preview",
            displayName: "Preview User",
            avatarURL: nil,
            status: .online,
            bio: nil
        )
        ctx.isLoggedIn = true
        return ctx
    }
}
#endif
