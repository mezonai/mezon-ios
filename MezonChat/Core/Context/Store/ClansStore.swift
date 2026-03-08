import Foundation
import Combine
import SwiftProtobuf

@MainActor
final class ClansStore: ObservableObject {

    @Published private(set) var clans: [Mezon_Api_ClanDesc] = []
    @Published var selectedClanId: Int64?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    init() {}

    func setClans(_ items: [Mezon_Api_ClanDesc]) {
        clans = items.sorted { $0.clanOrder < $1.clanOrder }
        if selectedClanId == nil { selectedClanId = clans.first?.clanID }
        MezonPostbox.shared.saveClans(clans, selectedClanId: selectedClanId)
    }

    func restoreClans(_ items: [Mezon_Api_ClanDesc], selectedClanId selId: Int64?) {
        clans = items.sorted { $0.clanOrder < $1.clanOrder }
        selectedClanId = selId ?? clans.first?.clanID
    }

    func setLoading(_ loading: Bool) { isLoading = loading }
    func setError(_ message: String?) { error = message }

    func selectClan(_ clan: Mezon_Api_ClanDesc) {
        selectedClanId = clan.clanID
        MezonPostbox.shared.saveClans(clans, selectedClanId: selectedClanId)
    }

    func clear() {
        clans = []
        selectedClanId = nil
        error = nil
    }
}
