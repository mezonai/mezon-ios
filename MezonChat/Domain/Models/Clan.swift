import Foundation

struct Clan: Identifiable, Equatable, Codable, Hashable {
    let id: String
    var name: String
    var description: String?
    var iconURL: URL?
    var bannerURL: URL?
    var memberCount: Int
    var isOwner: Bool
    var joinedAt: Date

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Clan, rhs: Clan) -> Bool {
        lhs.id == rhs.id
    }
}
