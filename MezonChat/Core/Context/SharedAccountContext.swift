import Foundation
import Combine

@MainActor
final class SharedAccountContext: ObservableObject {

    let appContext: AppContext
    let sharedDataStore: SharedDataStore

    private var cancellables = Set<AnyCancellable>()

    init(appContext: AppContext, sharedDataStore: SharedDataStore) {
        self.appContext = appContext
        self.sharedDataStore = sharedDataStore
        bindLogout()
    }

    private func bindLogout() {
        appContext.$isLoggedIn
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.sharedDataStore.clear()
            }
            .store(in: &cancellables)
    }

    var session: MezonSession? { appContext.session }

    var currentUser: User? { appContext.currentUser }
}
