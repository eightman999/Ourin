import Foundation
import Network

/// NetworkObserver.swift
/// Observe network path changes for SHIORI events
final class NetworkObserver {
    static let shared = NetworkObserver()
    private init() {}

    private var monitor: NWPathMonitor?
    private var handler: ((ShioriEvent) -> Void)?
    private var lastStatus: NWPath.Status?
    private var lastExpensive: Bool = false

    /// Start observing network path
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let status = path.status
            if self.lastStatus != status {
                self.lastStatus = status
                let value = status == .satisfied ? "online" : "offline"
                self.handler?(ShioriEvent(id: .OnNetworkStatusChange, params: ["Status": value]))
            }
            if path.isExpensive != self.lastExpensive {
                self.lastExpensive = path.isExpensive
                if path.isExpensive {
                    self.handler?(ShioriEvent(id: .OnNetworkHeavy, params: [:]))
                }
            }
        }
        monitor.start(queue: DispatchQueue.global())
        self.monitor = monitor
    }

    /// Stop monitoring
    func stop() {
        monitor?.cancel(); monitor = nil
    }
}
