import Foundation
import Combine

protocol ClanRepository {
    func fetchJoinedClans() -> AnyPublisher<[Clan], Error>
    func fetchClan(id: String) -> AnyPublisher<Clan, Error>
    func joinClan(inviteCode: String) -> AnyPublisher<Clan, Error>
    func leaveClan(id: String) -> AnyPublisher<Void, Error>
}
