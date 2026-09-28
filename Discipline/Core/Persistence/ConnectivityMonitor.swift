import Foundation
import Network
import Observation

/// Publishes whether the device currently has a network path, for offline messaging.
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.eltonruhani.discipline.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
