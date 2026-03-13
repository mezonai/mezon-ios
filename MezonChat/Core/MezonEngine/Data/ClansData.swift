import Foundation

extension MezonEngine.EngineData.Item {

    struct ClanList: PostboxViewDataItem {
        typealias Result = [ClanRecord]

        var key: PostboxViewKey { .clanList }

        func extract(view: PostboxView) -> [ClanRecord] {
            guard let view = view as? ClanListView else { return [] }
            return view.clans
        }
    }
}
