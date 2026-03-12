import Foundation

protocol MezonEngineDataItem {
    associatedtype Result
}

protocol PostboxViewDataItem: MezonEngineDataItem {
    var key: PostboxViewKey { get }
    func extract(view: PostboxView) -> Result
}

extension MezonEngine {

    @MainActor
    final class EngineData {
        struct Item {}

        private let postbox: Postbox

        init(postbox: Postbox) {
            self.postbox = postbox
        }

        func subscribe<T: PostboxViewDataItem>(_ item: T) -> Signal<T.Result, NoError> {
            return postbox.combinedView(keys: [item.key])
                |> map { combined -> T.Result in
                    guard let view = combined.views[item.key] else {
                        fatalError("Missing view for key \(item.key)")
                    }
                    return item.extract(view: view)
                }
        }

        func get<T: PostboxViewDataItem>(_ item: T) -> Signal<T.Result, NoError> {
            return subscribe(item) |> take(1)
        }

        func subscribe<T0: PostboxViewDataItem, T1: PostboxViewDataItem>(
            _ t0: T0, _ t1: T1
        ) -> Signal<(T0.Result, T1.Result), NoError> {
            return postbox.combinedView(keys: [t0.key, t1.key])
                |> map { combined -> (T0.Result, T1.Result) in
                    let r0 = t0.extract(view: combined.views[t0.key]!)
                    let r1 = t1.extract(view: combined.views[t1.key]!)
                    return (r0, r1)
                }
        }

        func subscribe<T0: PostboxViewDataItem, T1: PostboxViewDataItem, T2: PostboxViewDataItem>(
            _ t0: T0, _ t1: T1, _ t2: T2
        ) -> Signal<(T0.Result, T1.Result, T2.Result), NoError> {
            return postbox.combinedView(keys: [t0.key, t1.key, t2.key])
                |> map { combined -> (T0.Result, T1.Result, T2.Result) in
                    let r0 = t0.extract(view: combined.views[t0.key]!)
                    let r1 = t1.extract(view: combined.views[t1.key]!)
                    let r2 = t2.extract(view: combined.views[t2.key]!)
                    return (r0, r1, r2)
                }
        }
    }
}
