import Foundation

final class ProfileView: PostboxView {
    let userId: String
    let record: ProfileRecord?

    init(userId: String, record: ProfileRecord?) {
        self.userId = userId
        self.record = record
    }

    func immutableView() -> ProfileView {
        return self
    }
}

final class MutableProfileView: MutablePostboxView {
    let userId: String
    private var record: ProfileRecord?

    init(userId: String, record: ProfileRecord?) {
        self.userId = userId
        self.record = record
    }

    func immutableView() -> PostboxView {
        return ProfileView(userId: userId, record: record)
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        if transaction.updatedProfileUserIds.contains(userId) {
            self.record = transaction.getProfile(userId: userId)
            return true
        }
        return false
    }
}
