import Foundation
import SwiftProtobuf

@MainActor
final class MezonEngine {
    let account: Account

    init(account: Account) {
        self.account = account
    }

    lazy var auth = Auth(engine: self)
    lazy var clans = Clans(engine: self)
    lazy var channels = Channels(engine: self)
    lazy var messages = Messages(engine: self)
    lazy var notifications = Notifications(engine: self)
    lazy var peers = Peers(engine: self)
    lazy var clanData = ClanData(engine: self)
    lazy var data = EngineData(postbox: account.postbox)
}

@MainActor
final class MezonEngineUnauthorized {
    let network: MezonHTTPClient

    init(network: MezonHTTPClient) {
        self.network = network
    }

    lazy var auth = UnauthorizedAuth(network: network)
}
