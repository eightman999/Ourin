import Foundation
import OSLog

/// 簡易メトリクス集計
public final class ServerMetrics {
    public static let shared = ServerMetrics()
    private init() {}

    private var count: Int = 0
    private var error: Int = 0
    private var totalTime: TimeInterval = 0
    private let queue = DispatchQueue(label: "Ourin.metrics")

    public func record(duration: TimeInterval, error: Bool) {
        queue.async {
            self.count += 1
            self.totalTime += duration
            if error { self.error += 1 }
        }
    }

    public var averageLatency: TimeInterval {
        queue.sync { count > 0 ? totalTime / Double(count) : 0 }
    }

    public var errorRate: Double {
        queue.sync { count > 0 ? Double(error) / Double(count) : 0 }
    }
}
