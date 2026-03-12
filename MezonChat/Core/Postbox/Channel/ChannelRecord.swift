import Foundation
import SwiftProtobuf

struct ChannelRecord: PostboxCoding, Equatable {

    let id: Int64
    let clanId: Int64

    let label: String
    let type: Int32

    let categoryId: Int64
    let categoryName: String
    let parentId: Int64

    let position: Int32

    init(proto: Mezon_Api_ChannelDescription) {
        self.id           = proto.channelID
        self.clanId       = proto.clanID
        self.label        = proto.channelLabel
        self.type         = Int32(proto.type)
        self.categoryId   = proto.categoryID
        self.categoryName = proto.categoryName
        self.parentId     = proto.parentID
        self.position     = 0
    }

    var isTopLevel: Bool { parentId == 0 }
}
