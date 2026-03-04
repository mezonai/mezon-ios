import Foundation
import Combine

final class ClanListViewModel: BaseViewModel {

    @Published private(set) var clans: [Mezon_Api_ClanDesc] = []
    @Published var selectedClanId: Int64?

    private let context: AppContext

    init(context: AppContext) {
        self.context = context
        super.init()
    }

    @MainActor
    func loadClans() {
        guard let token = context.session?.token else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await MezonHTTPClient.shared.listClanDescs(token: token)
                clans = result.sorted { $0.clanOrder < $1.clanOrder }
                if selectedClanId == nil { selectedClanId = clans.first?.clanID }
            } catch {
                errorMessage = error.localizedDescription
                AppLogger.app.error("loadClans failed: \(error)")
            }
            isLoading = false
        }
    }

    func select(clan: Mezon_Api_ClanDesc) {
        selectedClanId = clan.clanID
    }
}
