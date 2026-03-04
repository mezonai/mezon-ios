import Foundation
import SwiftProtobuf

extension MezonSession {
    init(from proto: Mezon_Api_Session) {
        self.token        = proto.token
        self.refreshToken = proto.refreshToken
        self.created      = proto.created
        self.apiURL       = proto.apiURL.isEmpty ? nil : proto.apiURL
        self.wsURL        = proto.wsURL.isEmpty  ? nil : proto.wsURL
        self.userId       = proto.userID != 0 ? String(proto.userID) : nil
        self.username     = nil
        self.idToken      = proto.idToken.isEmpty ? nil : proto.idToken
        self.isRemember   = proto.isRemember
        self.expiresAt    = Date().addingTimeInterval(3600)
    }
}
