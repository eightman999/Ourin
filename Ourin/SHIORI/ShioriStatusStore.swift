import Foundation

/// Runtime cache for SHIORI-compatible ghost status values.
public final class ShioriStatusStore {
    public static let shared = ShioriStatusStore()

    private let lock = NSLock()
    private var status: String = "online"

    private init() {}

    public var currentStatus: String {
        lock.lock()
        defer { lock.unlock() }
        return status
    }

    public func update(status newStatus: String) {
        let trimmed = newStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        status = trimmed
        lock.unlock()
    }

    public func reset(to newStatus: String = "online") {
        lock.lock()
        status = newStatus
        lock.unlock()
    }
}
