import Foundation
import SwiftProtobuf

@MainActor
protocol AccountContext: AnyObject {
    var sharedContext: SharedAccountContext { get }
    var account: Account { get }
    var engine: MezonEngine { get }

    var session: MezonSession? { get }
    var currentUser: User? { get }
    var isLoggedIn: Bool { get }

    var isLoggedInSignal: Signal<Bool, NoError> { get }

    var currentClanId: Int64 { get set }
    var currentChannel: Mezon_Api_ChannelDescription? { get set }

    func login(user: User, session: MezonSession)
    func logout()
    func refreshSession() async throws
    func recoverFromForeground()
}
