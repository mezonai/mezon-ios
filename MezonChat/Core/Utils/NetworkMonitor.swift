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
            self?.publishConnectivity(path.status == .satisfied)
        }
        newMonitor.start(queue: queue)
        queue.async { [weak self] in
            guard let self, let mon = self.monitor else { return }
            let connected = mon.currentPath.status == .satisfied
            self.publishConnectivity(connected)
        }
    }

    private func publishConnectivity(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isConnected != connected else { return }
            self.isConnected = connected
            NotificationCenter.default.post(
                name: NetworkMonitor.statusDidChangeNotification,
                object: nil,
                userInfo: ["isConnected": connected]
            )
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
