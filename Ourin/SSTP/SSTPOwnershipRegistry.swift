import Foundation

/// Owned SSTPで受理できるIDを、起動中ゴースト単位で保持する。
///
/// UKADOC上、IDはSHIORIへ通知した`uniqueid`またはFMOレコードIDと一致した場合だけ
/// 有効である。単にIDヘッダが存在するだけではOwnedとして扱わない。
final class SSTPOwnershipRegistry {
    struct Entry: Equatable {
        let targetKeys: Set<String>
        let ids: Set<String>

        init(targetKeys: Set<String>, ids: Set<String>) {
            self.targetKeys = Set(targetKeys.map(Self.normalizeTarget))
            self.ids = ids
        }

        fileprivate static func normalizeTarget(_ value: String) -> String {
            let decoded = value.removingPercentEncoding ?? value
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    static let shared = SSTPOwnershipRegistry()

    private let lock = NSLock()
    /// 先頭がプライマリゴースト。ReceiverGhostName未指定時は先頭だけを照合する。
    private var entries: [Entry] = []

    func replaceEntries(_ newEntries: [Entry]) {
        lock.lock()
        entries = newEntries
        lock.unlock()
    }

    func removeAll() {
        replaceEntries([])
    }

    func matches(id rawID: String?, receiverGhostName: String?) -> Bool {
        guard let rawID else { return false }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }

        lock.lock()
        let snapshot = entries
        lock.unlock()

        if let receiverGhostName,
           !receiverGhostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let target = Entry.normalizeTarget(receiverGhostName)
            return snapshot.first(where: { $0.targetKeys.contains(target) })?.ids.contains(id) == true
        }
        return snapshot.first?.ids.contains(id) == true
    }
}
