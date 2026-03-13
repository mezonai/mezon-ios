import Foundation

struct AuthRecord: PostboxCoding, Equatable {
    let userId: String
    let token: String
    let refreshToken: String?

    let expiresAt: Date?
    let createdAt: Date

    let sessionData: Data?

    init(
        userId: String,
        token: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        createdAt: Date = Date(),
        sessionData: Data? = nil
    ) {
        self.userId      = userId
        self.token       = token
        self.refreshToken = refreshToken
        self.expiresAt   = expiresAt
        self.createdAt   = createdAt
        self.sessionData = sessionData
    }

    var isValid: Bool {
        guard let exp = expiresAt else { return true }
        return exp > Date()
    }
}
