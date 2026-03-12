import Foundation

struct ProfileRecord: PostboxCoding, Equatable {

    let userId: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let status: Int32
    let data: Data

    init(
        userId: String,
        username: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        status: Int32 = 0,
        data: Data = Data()
    ) {
        self.userId      = userId
        self.username    = username
        self.displayName = displayName
        self.avatarUrl   = avatarUrl
        self.status      = status
        self.data        = data
    }
}
