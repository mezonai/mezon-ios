import Foundation
import SwiftProtobuf

extension MezonEngine {

    final class Auth {
        private let engine: MezonEngine
        private var network: MezonHTTPClient { engine.account.network }

        init(engine: MezonEngine) { self.engine = engine }

        @available(iOS 13.0, *)
        @MainActor
        func getAccount(token: String) async throws -> Mezon_Api_Account {
            try await network.getAccount(token: token)
        }

        @available(iOS 13.0, *)
        @MainActor
        func sessionRefresh(session: MezonSession) async throws -> MezonSession {
            try await SessionRefreshManager.shared.refresh(session: session)
        }

        @available(iOS 13.0, *)
        @MainActor
        func sessionLogout(session: MezonSession, deviceId: String, platform: String) async throws {
            try await network.sessionLogout(session: session, deviceId: deviceId, platform: platform)
        }

        @discardableResult
        @available(iOS 13.0, *)
        @MainActor
        func confirmLogin(loginId: String, token: String) async throws -> MezonSession? {
            try await network.confirmLogin(loginId: loginId, token: token)
        }
    }

}

final class UnauthorizedAuth {
    private let network: MezonHTTPClient

    init(network: MezonHTTPClient) { self.network = network }

    @available(iOS 13.0, *)
    @MainActor
    func authenticateEmail(email: String, password: String) async throws -> MezonSession {
        try await network.authenticateEmail(email: email, password: password)
    }

    @available(iOS 13.0, *)
    @MainActor
    func authenticateEmailOTPRequest(email: String) async throws -> OTPRequestResponse {
        try await network.authenticateEmailOTPRequest(email: email)
    }

    @available(iOS 13.0, *)
    @MainActor
    func authenticateSMSOTPRequest(phone: String) async throws -> OTPRequestResponse {
        try await network.authenticateSMSOTPRequest(phone: phone)
    }

    @available(iOS 13.0, *)
    @MainActor
    func confirmAuthenticateOTP(reqId: String, otp: String) async throws -> MezonSession {
        try await network.confirmAuthenticateOTP(reqId: reqId, otp: otp)
    }
}
