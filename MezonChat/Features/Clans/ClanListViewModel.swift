import Foundation
import Combine

final class ClanListViewModel: BaseViewModel {

    private let sharedContext: SharedAccountContext

    init(sharedContext: SharedAccountContext) {
        self.sharedContext = sharedContext
        super.init()
    }

    var clansStore: ClansStore { sharedContext.sharedDataStore.clansStore }

    var clans: [Mezon_Api_ClanDesc] { clansStore.clans }

    var selectedClanId: Int64? {
        get { clansStore.selectedClanId }
        set { clansStore.selectedClanId = newValue }
    }

    var isClansLoading: Bool { clansStore.isLoading }

    var clansError: String? { clansStore.error }

    @MainActor
    func loadClans() {
        guard let token = sharedContext.session?.token else { return }
        let store = clansStore
        store.setLoading(true)
        store.setError(nil)
        Task {
            defer { store.setLoading(false) }
            do {
                let result = try await MezonHTTPClient.shared.listClanDescs(token: token)
                store.setClans(result)
                AppLogger.app.debug("[ClanListViewModel] fetched \(result.count) clans → SharedDataStore")
            } catch {
                store.setError(error.localizedDescription)
                AppLogger.app.error("loadClans failed: \(error)")
            }
        }
    }

    func select(clan: Mezon_Api_ClanDesc) {
        clansStore.selectClan(clan)
    }
}
