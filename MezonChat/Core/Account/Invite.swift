import Foundation
import SwiftProtobuf

struct ClanInviteInfo: Decodable {
    let clan_id: String?
    let clan_name: String?
    let clan_logo: String?
    let channel_id: String?
    let channel_label: String?
    let member_count: Int?
    let expiry_time_seconds: Int?
    let banner: String?
    let community_banner: String?
    let is_community: Bool?
    let user_joined: Bool?
}

