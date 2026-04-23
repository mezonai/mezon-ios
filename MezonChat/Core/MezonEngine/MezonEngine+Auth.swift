import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Auth {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }

        init(engine: MezonEngine) { self.engine = engine }

        func getAccount(token: String) async throws -> Mezon_Api_Account {
            try await network.getAccount(token: token)
        }

        func sessionRefresh(session: MezonSession) async throws -> MezonSession {
            try await SessionRefreshManager.shared.refresh(session: session)
        }

        func sessionLogout(session: MezonSession, deviceId: String, platform: String) async throws {
            try await network.sessionLogout(session: session, deviceId: deviceId, platform: platform)
        }

        @discardableResult
        func confirmLogin(loginId: String, token: String) async throws -> MezonSession? {
            try await network.confirmLogin(loginId: loginId, token: token)
        }
    }

}

@MainActor
final class UnauthorizedAuth {
    private let network: MezonHTTPClient

    init(network: MezonHTTPClient) { self.network = network }

    func authenticateEmail(email: String, password: String) async throws -> MezonSession {
        try await network.authenticateEmail(email: email, password: password)
    }

    func authenticateEmailOTPRequest(email: String) async throws -> OTPRequestResponse {
        try await network.authenticateEmailOTPRequest(email: email)
    }

    func authenticateSMSOTPRequest(phone: String) async throws -> OTPRequestResponse {
        try await network.authenticateSMSOTPRequest(phone: phone)
    }

    func confirmAuthenticateOTP(reqId: String, otp: String) async throws -> MezonSession {
        try await network.confirmAuthenticateOTP(reqId: reqId, otp: otp)
    }
}
