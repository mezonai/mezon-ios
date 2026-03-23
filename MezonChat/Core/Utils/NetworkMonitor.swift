import Foundation
import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mezon.networkMonitor")

    private(set) var isConnected: Bool = true

    static let statusDidChangeNotification = Notification.Name("NetworkMonitorStatusDidChange")

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                guard self?.isConnected != connected else { return }
                self?.isConnected = connected
                NotificationCenter.default.post(
                    name: NetworkMonitor.statusDidChangeNotification,
                    object: nil,
                    userInfo: ["isConnected": connected]
                )
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
