import Foundation

/// `shiori.cache`用のbounded runtime cache。
/// SHIORI応答を記憶するものではなく、ゴースト切替中だけruntimeを保持する。
final class ShioriRuntimeCache {
    struct Entry {
        let key: String
        let runtime: GhostShioriRuntime
        let context: ShioriRuntimeLoadContext
        var lastUsed: UInt64
    }

    private let lock = NSLock()
    private let capacity: Int
    private var clock: UInt64 = 0
    private var entries: [String: Entry] = [:]

    init(capacity: Int = 2) {
        self.capacity = max(1, capacity)
    }

    static func key(for context: ShioriRuntimeLoadContext) -> String {
        let c = context.communication
        return [
            context.ghostURL.standardizedFileURL.path,
            context.ghostRoot.standardizedFileURL.path,
            context.moduleName.lowercased(),
            c.version ?? "",
            c.encoding ?? "",
            c.forceEncoding ?? "",
            c.escapeUnknown ? "escape" : "plain"
        ].joined(separator: "\u{1f}")
    }

    func store(runtime: GhostShioriRuntime, context: ShioriRuntimeLoadContext) {
        let key = Self.key(for: context)
        var evicted: Entry?
        lock.lock()
        clock &+= 1
        if let replaced = entries.updateValue(
            Entry(key: key, runtime: runtime, context: context, lastUsed: clock),
            forKey: key
        ), replaced.runtime !== runtime {
            evicted = replaced
        }
        if entries.count > capacity,
           let oldest = entries.values.min(by: { $0.lastUsed < $1.lastUsed }) {
            entries.removeValue(forKey: oldest.key)
            evicted = oldest
        }
        lock.unlock()
        if let evicted { Self.destroy(evicted.runtime, reason: "cache") }
    }

    func take(context: ShioriRuntimeLoadContext) -> GhostShioriRuntime? {
        let key = Self.key(for: context)
        lock.lock()
        let entry = entries.removeValue(forKey: key)
        lock.unlock()
        return entry?.runtime
    }

    func removeAll() {
        lock.lock()
        let removed = Array(entries.values)
        entries.removeAll()
        lock.unlock()
        for entry in removed {
            Self.destroy(entry.runtime, reason: "shutdown")
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    private static func destroy(_ runtime: GhostShioriRuntime, reason: String) {
        _ = runtime.request(
            method: "NOTIFY",
            id: "OnDestroy",
            headers: ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"],
            refs: [reason],
            timeout: 1.0
        )
        runtime.unload()
    }
}
