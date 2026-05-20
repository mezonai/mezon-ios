import Foundation
import SwiftProtobuf

@MainActor
protocol AccountContext: AnyObject {
    var sharedContext: SharedAccountContext { get }
    var account: Account { get }
    var engine: MezonEngine { get }
    var rolePermissions: RolePermissionService { get }

    var session: MezonSession? { get }
    var currentUser: User? { get }
    var isLoggedIn: Bool { get }

    var isLoggedInSignal: Signal<Bool, NoError> { get }

    var currentClanId: Int64 { get set }
    var currentChannel: Mezon_Api_ChannelDescription? { get set }

    var sessionEpoch: Int { get }
    func isStillCurrentSession(epoch: Int) -> Bool

    func login(user: User, session: MezonSession)
    func logout()
    func refreshSession() async throws
    func refreshUserProfile() async
    func recoverFromForeground()
    func waitForSessionReady() async
    func getToken() async -> String?
    func getTokenPreferringCachedSkipSessionReadyWait() async -> String?
    func applyCurrentUser(_ user: User)
    func refreshAccountProfile() async
    func applyCachedAccountIfAvailable()
    func updatePresenceStatus(_ status: User.OnlineStatus) async throws
    func fetchCurrentUserStatus() async
    func submitCustomStatus(text: String, minutes: Int32, noClear: Bool) async throws
    func clearPersistedSelectedChannelPreference(forClanId clanId: Int64)
}

extension Notification.Name {
    static let mezonAccountCurrentUserDidChange = Notification.Name("mezon.account.currentUserDidChange")
    static let mezonChannelPinsNeedRefresh = Notification.Name("mezon.channel.pinsNeedRefresh")
    static let mezonUserChannelAddedFromSocket = Notification.Name("mezon.channels.userChannelAddedFromSocket")
    static let mezonChannelDescriptionDidUpdate = Notification.Name("mezon.channels.descriptionDidUpdate")
    static let mezonIncomingPeerCall = Notification.Name("mezon.call.incomingPeer")
    static let mezonCallKitMatchedExistingIncoming = Notification.Name("mezon.call.callKitMatchedExistingIncoming")
    static let mezonCallKitAudioActivated = Notification.Name("mezon.call.callKitAudioActivated")
    static let mezonPeerCallDidConnect = Notification.Name("mezon.call.peerCallDidConnect")
    static let mezonVoIPTokenDidUpdate = Notification.Name("mezon.voip.tokenUpdated")
    static let mezonVoIPMinimalCallChromeActivated = Notification.Name("mezon.voip.minimalCallChromeActivated")
    static let mezonNotificationSettingDidUpdate = Notification.Name("mezon.notification.settingDidUpdate")
}
