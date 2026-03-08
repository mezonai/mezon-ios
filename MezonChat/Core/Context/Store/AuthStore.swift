import Foundation
import Combine
import SwiftProtobuf

@MainActor
final class AuthStore: ObservableObject {

    static func sessionKey(userId: String) -> String { "auth.session.\(userId)" }

    @Published private(set) var session: MezonSession?

    @Published private(set) var user: User?

    @Published private(set) var account: Mezon_Api_Account?

    @Published private(set) var isLoggedIn: Bool = false

    init() {}

    func setSession(_ session: MezonSession) {
        self.session = session
        self.isLoggedIn = true
    }

    func setUser(_ user: User) {
        self.user = user
    }

    func setAccount(_ apiAccount: Mezon_Api_Account) {
        self.account = apiAccount
        self.user = mapApiAccountToUser(apiAccount)
        MezonPostbox.shared.saveAccount(apiAccount)
    }

    func restoreAccount(_ apiAccount: Mezon_Api_Account) {
        self.account = apiAccount
        self.user = mapApiAccountToUser(apiAccount)
    }

    func logout() {
        session = nil
        user = nil
        account = nil
        isLoggedIn = false
    }

    private func mapApiAccountToUser(_ api: Mezon_Api_Account) -> User {
        let u = api.user
        let avatarURL: URL? = u.avatarURL.isEmpty ? nil : URL(string: u.avatarURL)
        return User(
            id: "\(u.id)",
            username: u.username.isEmpty ? "me" : u.username,
            displayName: u.displayName.isEmpty ? u.username : u.displayName,
            avatarURL: avatarURL,
            status: u.online ? .online : .offline,
            bio: u.aboutMe.isEmpty ? nil : u.aboutMe,
            email: api.email.isEmpty ? nil : api.email,
            phoneNumber: u.phoneNumber.isEmpty ? nil : u.phoneNumber,
            isBot: false
        )
    }
}
