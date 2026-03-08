import Foundation
import Combine
import SwiftProtobuf

@MainActor
final class MessagesViewModel: BaseViewModel {

    @Published private(set) var directMessages: [Mezon_Api_ChannelDescription] = []
    @Published private(set) var isEmpty: Bool = true

    private let sharedContext: SharedAccountContext

    init(sharedContext: SharedAccountContext) {
        self.sharedContext = sharedContext
        super.init()
    }

    func fetchDirectMessages() async {
        guard let token = sharedContext.session?.token else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let channels = try await MezonHTTPClient.shared.listDirectMessageChannels(token: token)
            directMessages = channels.sorted { ch1, ch2 in
                let t1 = ch1.hasLastSentMessage ? ch1.lastSentMessage.timestampSeconds : 0
                let t2 = ch2.hasLastSentMessage ? ch2.lastSentMessage.timestampSeconds : 0
                return t1 > t2
            }
            isEmpty = directMessages.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.network.error("fetchDirectMessages: \(error)")
        }
    }
}
