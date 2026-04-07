import Foundation

final class ClanMemberView: PostboxView {
    let clanId: Int64
    let members: [ClanMemberRecord]

    init(clanId: Int64, members: [ClanMemberRecord]) {
        self.clanId = clanId
        self.members = members
    }

    func immutableView() -> ClanMemberView {
        return self
    }
}

final class MutableClanMemberView: MutablePostboxView {
    let clanId: Int64
    private var members: [ClanMemberRecord]

    init(clanId: Int64, members: [ClanMemberRecord]) {
        self.clanId = clanId
        self.members = members
    }

    func immutableView() -> PostboxView {
        return ClanMemberView(clanId: clanId, members: members)
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        if transaction.updatedClanMemberIds.contains(clanId) {
            self.members = transaction.getClanMembers(clanId: clanId)
            return true
        }
        return false
    }
}
