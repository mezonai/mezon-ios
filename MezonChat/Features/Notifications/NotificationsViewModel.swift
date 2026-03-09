import Combine

final class NotificationsViewModel: BaseViewModel {
    private let sharedContext: SharedAccountContext

    @Published var notifications: [Notifications] = []
    @Published var currentCategory: Int32 = 0

    init(sharedContext: SharedAccountContext) {
        self.sharedContext = sharedContext
        super.init()
        setupBindings()
    }

    private func setupBindings() {
        sharedContext.sharedDataStore.notificationsStore.$notificationsCache
            .combineLatest(
                sharedContext.sharedDataStore.clansStore.$selectedClanId, $currentCategory
            )
            .map { notificationsCache, clanId, category -> [Notifications] in
                guard let clanId = clanId else { return [] }
                let key = "\(clanId)_\(category)"
                return notificationsCache[key] ?? []
            }
            .assign(to: \.notifications, on: self)
            .store(in: &cancellables)
    }

    func fetchNotifications(category: Int32) async {
        currentCategory = category
        guard let token = sharedContext.session?.token else { return }
        guard let clanID = sharedContext.sharedDataStore.clansStore.selectedClanId else { return }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }
        do {
            let notificationsFetch = try await MezonHTTPClient.shared.listNotifications(
                clanID: clanID, category: category, token: token)
            await MainActor.run {
                sharedContext.sharedDataStore.notificationsStore.saveFetchedNotifications(
                    notificationsFetch, clanId: clanID, category: category)
            }
        } catch {

        }

    }
}
