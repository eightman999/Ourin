import Foundation

/// Simple named synchronization primitive for SakuraScript syncobject waits/signals.
/// This is a best-effort in-process implementation; cross-process sync is out of scope.
final class SyncCenter {
    static let shared = SyncCenter()
    private init() {}

    private var lock = NSLock()
    private var events: [String: DispatchSemaphore] = [:]

    private func semaphore(for name: String) -> DispatchSemaphore {
        lock.lock(); defer { lock.unlock() }
        if let s = events[name] { return s }
        let s = DispatchSemaphore(value: 0)
        events[name] = s
        return s
    }

    /// Wait on named syncobject. Returns the actual delay applied (<= timeout).
    func wait(name: String, timeout: TimeInterval) -> TimeInterval {
        guard !name.isEmpty else { return 0 }
        let sem = semaphore(for: name)
        let start = Date()
        if timeout.isInfinite {
            while sem.wait(timeout: .now() + 3600) == .timedOut { /* loop hourly until signaled */ }
        } else {
            _ = sem.wait(timeout: .now() + timeout)
        }
        return max(0, Date().timeIntervalSince(start))
    }

    /// Signal named syncobject.
    func signal(name: String) {
        guard !name.isEmpty else { return }
        semaphore(for: name).signal()
    }

    /// Set a named syncobject to the signaled state.
    ///
    /// The in-process primitive is semaphore-like, so setting it releases
    /// one waiter. This is the useful equivalent of SSP's set operation for
    /// the primitive used by Ourin.
    func set(name: String) {
        signal(name: name)
    }

    /// Reset a named syncobject to the unsignaled state.
    ///
    /// Replacing the semaphore discards a pending signal before the next
    /// wait. A waiter that already acquired the previous semaphore is not
    /// interrupted, matching the best-effort in-process boundary here.
    func reset(name: String) {
        guard !name.isEmpty else { return }
        lock.lock()
        events.removeValue(forKey: name)
        lock.unlock()
    }
}
