import Foundation
import Combine

protocol UserRepository {
    func fetchCurrentUser() -> AnyPublisher<User, Error>
    func fetchUser(id: String) -> AnyPublisher<User, Error>
    func fetchUsers(ids: [String]) -> AnyPublisher<[User], Error>
    func searchUsers(query: String) -> AnyPublisher<[User], Error>
    func updateProfile(displayName: String?, bio: String?, avatarURL: URL?) -> AnyPublisher<User, Error>

    func presenceStream() -> AnyPublisher<User, Error>
}
