import Foundation

final class SstpSessionStore {
    static let shared = SstpSessionStore()

    private let lock = NSLock()
    private var entries: [String: String] = [:]
    private var cookiesBySender: [String: [String: String]] = [:]
    private var quietModeEnabled = false

    private init() {}

    func mergeEntries(_ incoming: [String: String]) {
        guard !incoming.isEmpty else { return }
        lock.lock()
        for (id, script) in incoming {
            entries[id] = script
        }
        lock.unlock()
    }

    func allEntriesHeaderValue() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !entries.isEmpty else { return nil }
        let serialized = entries.keys.sorted().compactMap { key -> String? in
            guard let value = entries[key] else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: ";")
        return serialized.isEmpty ? nil : serialized
    }

    func setCookie(sender: String, name: String, value: String) {
        guard !sender.isEmpty, !name.isEmpty else { return }
        lock.lock()
        var cookies = cookiesBySender[sender] ?? [:]
        cookies[name] = value
        cookiesBySender[sender] = cookies
        lock.unlock()
    }

    func getCookie(sender: String, name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cookiesBySender[sender]?[name]
    }

    func setQuietMode(_ enabled: Bool) {
        lock.lock()
        quietModeEnabled = enabled
        lock.unlock()
    }

    func isQuietModeEnabled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return quietModeEnabled
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        cookiesBySender.removeAll()
        quietModeEnabled = false
        lock.unlock()
    }
}
