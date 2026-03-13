import Foundation
import SwiftProtobuf

extension MezonEngine {

    @MainActor
    final class Peers {
        private let engine: MezonEngine
        private var postbox: Postbox { engine.account.postbox }

        init(engine: MezonEngine) { self.engine = engine }

        func profileView(userId: String) -> Signal<ProfileRecord?, NoError> {
            Signal { [weak self] subscriber in
                guard let self else { return EmptyDisposable }
                let record = self.postbox.read { tx in tx.getProfile(userId: userId) }
                subscriber.putNext(record)
                subscriber.putCompletion()
                return EmptyDisposable
            }
        }
    }
}
