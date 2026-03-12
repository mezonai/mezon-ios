import Foundation

struct ClanListView: PostboxView {
    let clans: [ClanRecord]
}

final class MutableClanListView: MutablePostboxView {

    private(set) var clans: [ClanRecord]

    init(initial: [ClanRecord]) {
        self.clans = initial
    }

    func replay(transaction: PostboxTransaction) -> Bool {
        guard transaction.updatedClans else { return false }
        clans = transaction.clanTable.getAllClans()
        return true
    }

    func immutableView() -> ClanListView {
        ClanListView(clans: clans)
    }
}
