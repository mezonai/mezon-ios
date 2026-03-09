import Combine
import Foundation

protocol NotificationsRepository {
    func fetchNotifications(clanID: Int64) -> AnyPublisher<[Notifications], Error>
}
