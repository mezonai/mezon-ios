import Foundation
import Combine

@MainActor
class BaseViewModel: ObservableObject {
    var cancellables = Set<AnyCancellable>()

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
}
