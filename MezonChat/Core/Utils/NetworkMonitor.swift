import Foundation
import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.mezon.networkMonitor")

    private(set) var isConnected: Bool = true

    static let statusDidChangeNotification = Notification.Name("NetworkMonitorStatusDidChange")

    private init() {}

    func start() {
        monitor?.cancel()
        let newMonitor = NWPathMonitor()
        monitor = newMonitor
        newMonitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = self.isConnected != connected
                self.isConnected = connected
                if changed {
                    NotificationCenter.default.post(
                        name: NetworkMonitor.statusDidChangeNotification,
                        object: nil,
                        userInfo: ["isConnected": connected]
                    )
                }
            }
        }
        newMonitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
