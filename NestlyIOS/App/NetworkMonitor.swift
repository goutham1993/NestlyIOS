import Network
import Observation

/// Bumps every refetch when connectivity comes back (spec §4.1).
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                if self?.isOnline != online { self?.isOnline = online }
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}
