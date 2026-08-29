import Foundation
import SwiftProtobuf

final class Account {
    let id: String
    let postbox: Postbox
    let network: MezonHTTPClient
    let socket: MezonSocket

    init(
        id: String,
        postbox: Postbox = .shared,
        network: MezonHTTPClient = .shared,
        socket: MezonSocket = .shared
    ) {
        self.id = id
        self.postbox = postbox
        self.network = network
        self.socket = socket
    }
}

