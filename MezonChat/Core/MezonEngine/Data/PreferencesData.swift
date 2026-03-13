import Foundation

extension MezonEngine.EngineData.Item {

    struct Preferences: PostboxViewDataItem {
        typealias Result = Data?

        let prefKey: String

        init(key: String) {
            self.prefKey = key
        }

        var key: PostboxViewKey { .preferences(key: prefKey) }

        func extract(view: PostboxView) -> Data? {
            guard let view = view as? PreferencesView else { return nil }
            return view.data
        }
    }
}
