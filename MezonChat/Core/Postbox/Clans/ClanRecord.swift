import Foundation

struct ClanRecord: PostboxCoding, Equatable {

    let id: Int64
    let name: String

    let icon: String?
    let ownerId: String?

    let data: Data

    init(id: Int64, name: String, icon: String? = nil, ownerId: String? = nil, data: Data = Data()) {
        self.id      = id
        self.name    = name
        self.icon    = icon
        self.ownerId = ownerId
        self.data    = data
    }
}
