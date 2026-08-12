import Foundation

/// Entry for rateofuselist.* properties.
public struct RateOfUseEntry {
    public let name: String
    public let sakuraname: String
    public let keroname: String
    public let boottime: Int
    public let bootminute: Int
    public let percent: Int

    public init(name: String, sakuraname: String = "", keroname: String = "",
                boottime: Int = 0, bootminute: Int = 0, percent: Int = 0) {
        self.name = name
        self.sakuraname = sakuraname.isEmpty ? name : sakuraname
        self.keroname = keroname
        self.boottime = boottime
        self.bootminute = bootminute
        self.percent = percent
    }
}

/// 実行中ゴーストの使用統計。`rateofusegraph*` と `rateofuselist.*` が同じ
/// 永続データを見るための共通スナップショット。
struct GhostUsageSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let sakuraname: String
    let keroname: String
    let bootCount: Int
    let activeMinutes: Int
    let talkCount: Int
    let characterCount: Int
    let percent: Int
    let lastUsedAt: Date?
}

/// ゴーストの起動・使用時間を永続化するストア。
///
/// `rateofusegraphballoon` / `rateofusegraphtotal` は Windows 固有の
/// バルーン内部カウンタを再現できないため、Ourin では同じ実使用セッションの
/// 記録を使う。存在しない固定値やダミー URLを返さず、起動中の時間も表示時に
/// 合算する。
final class RateOfUseStore {
    static let shared = RateOfUseStore()

    private static let storageKey = "OurinRateOfUseRecords.v1"

    private struct StoredRecord: Codable {
        var name: String
        var sakuraname: String
        var keroname: String
        var bootCount: Int
        var totalSeconds: TimeInterval
        var talkCount: Int
        var characterCount: Int
        var lastUsedAt: TimeInterval?

        init(name: String, sakuraname: String, keroname: String) {
            self.name = name
            self.sakuraname = sakuraname
            self.keroname = keroname
            self.bootCount = 0
            self.totalSeconds = 0
            self.talkCount = 0
            self.characterCount = 0
            self.lastUsedAt = nil
        }

        enum CodingKeys: String, CodingKey {
            case name, sakuraname, keroname, bootCount, totalSeconds
            case talkCount, characterCount, lastUsedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            sakuraname = try container.decodeIfPresent(String.self, forKey: .sakuraname) ?? name
            keroname = try container.decodeIfPresent(String.self, forKey: .keroname) ?? ""
            bootCount = try container.decodeIfPresent(Int.self, forKey: .bootCount) ?? 0
            totalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .totalSeconds) ?? 0
            talkCount = try container.decodeIfPresent(Int.self, forKey: .talkCount) ?? 0
            characterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount) ?? 0
            lastUsedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .lastUsedAt)
        }
    }

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var records: [String: StoredRecord]
    private var activeSessions: [String: Date] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: StoredRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    func beginSession(identifier: String, name: String, sakuraname: String, keroname: String) {
        let key = normalizedIdentifier(identifier)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var record = records[key] ?? StoredRecord(name: name, sakuraname: sakuraname, keroname: keroname)
        updateMetadata(&record, name: name, sakuraname: sakuraname, keroname: keroname)
        if activeSessions[key] == nil {
            record.bootCount += 1
            activeSessions[key] = Date()
        }
        records[key] = record
        persistLocked()
    }

    func recordTalk(identifier: String, name: String, sakuraname: String, keroname: String, characterCount: Int) {
        let key = normalizedIdentifier(identifier)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var record = records[key] ?? StoredRecord(name: name, sakuraname: sakuraname, keroname: keroname)
        updateMetadata(&record, name: name, sakuraname: sakuraname, keroname: keroname)
        record.talkCount += 1
        record.characterCount += max(0, characterCount)
        record.lastUsedAt = Date().timeIntervalSince1970
        records[key] = record
        persistLocked()
    }

    func endSession(identifier: String) {
        let key = normalizedIdentifier(identifier)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let startedAt = activeSessions.removeValue(forKey: key), var record = records[key] else {
            return
        }
        record.totalSeconds += max(0, Date().timeIntervalSince(startedAt))
        records[key] = record
        persistLocked()
    }

    func snapshots() -> [GhostUsageSnapshot] {
        lock.lock()
        defer { lock.unlock() }

        let raw = records.map { key, record in
            let seconds = effectiveSeconds(for: key, record: record)
            return (key: key, record: record, seconds: seconds)
        }
        let totalSeconds = raw.reduce(0) { $0 + $1.seconds }
        return raw
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
                return lhs.record.name.localizedStandardCompare(rhs.record.name) == .orderedAscending
            }
            .map { item in
                let percent: Int
                if totalSeconds > 0 {
                    percent = Int((item.seconds / totalSeconds * 100).rounded())
                } else if raw.count == 1 {
                    percent = 100
                } else {
                    percent = 0
                }
                return GhostUsageSnapshot(
                    id: item.key,
                    name: item.record.name.isEmpty ? item.key : item.record.name,
                    sakuraname: item.record.sakuraname,
                    keroname: item.record.keroname,
                    bootCount: item.record.bootCount,
                    activeMinutes: Int(item.seconds / 60),
                    talkCount: item.record.talkCount,
                    characterCount: item.record.characterCount,
                    percent: min(100, max(0, percent)),
                    lastUsedAt: item.record.lastUsedAt.map(Date.init(timeIntervalSince1970:))
                )
            }
    }

    func entries() -> [RateOfUseEntry] {
        snapshots().map {
            RateOfUseEntry(
                name: $0.name,
                sakuraname: $0.sakuraname,
                keroname: $0.keroname,
                boottime: $0.bootCount,
                bootminute: $0.activeMinutes,
                percent: $0.percent
            )
        }
    }

    private func normalizedIdentifier(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateMetadata(_ record: inout StoredRecord, name: String, sakuraname: String, keroname: String) {
        if !name.isEmpty { record.name = name }
        if !sakuraname.isEmpty { record.sakuraname = sakuraname }
        if !keroname.isEmpty { record.keroname = keroname }
    }

    private func effectiveSeconds(for key: String, record: StoredRecord) -> TimeInterval {
        record.totalSeconds + (activeSessions[key].map { max(0, Date().timeIntervalSince($0)) } ?? 0)
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Provides history.* properties.
/// Supported keys:
/// - history.ghost.count / history.ghost(name|path).prop / history.ghost.index(n).prop
/// - history.balloon.count / history.balloon(name|path).prop / history.balloon.index(n).prop
/// - history.headline.count / history.headline(name|path).prop / history.headline.index(n).prop
/// - history.plugin.count / history.plugin(name|path|id).prop / history.plugin.index(n).prop
final class HistoryPropertyProvider: PropertyProvider {
    private let ghosts: [Ghost]
    private let balloons: [Balloon]
    private let headlines: [Headline]
    private let plugins: [PropertyPlugin]

    init(ghosts: [Ghost] = [], balloons: [Balloon] = [],
         headlines: [Headline] = [], plugins: [PropertyPlugin] = []) {
        self.ghosts = ghosts
        self.balloons = balloons
        self.headlines = headlines
        self.plugins = plugins
    }

    func get(key: String) -> String? {
        if key == "ghost.count" { return String(ghosts.count) }
        if key == "balloon.count" { return String(balloons.count) }
        if key == "headline.count" { return String(headlines.count) }
        if key == "plugin.count" { return String(plugins.count) }

        if let (index, prop) = parseIndexAccess(key: key, listName: "ghost"), ghosts.indices.contains(index) {
            return ghostProperty(ghosts[index], prop: prop)
        }
        if let (index, prop) = parseIndexAccess(key: key, listName: "balloon"), balloons.indices.contains(index) {
            return balloonProperty(balloons[index], prop: prop)
        }
        if let (index, prop) = parseIndexAccess(key: key, listName: "headline"), headlines.indices.contains(index) {
            return headlineProperty(headlines[index], prop: prop)
        }
        if let (index, prop) = parseIndexAccess(key: key, listName: "plugin"), plugins.indices.contains(index) {
            return pluginProperty(plugins[index], prop: prop)
        }

        if let (identifier, prop) = parseNamedAccess(key: key, listName: "ghost"),
           let ghost = ghosts.first(where: { $0.name == identifier || $0.path == identifier }) {
            return ghostProperty(ghost, prop: prop)
        }
        if let (identifier, prop) = parseNamedAccess(key: key, listName: "balloon"),
           let balloon = balloons.first(where: { $0.name == identifier || $0.path == identifier }) {
            return balloonProperty(balloon, prop: prop)
        }
        if let (identifier, prop) = parseNamedAccess(key: key, listName: "headline"),
           let headline = headlines.first(where: { $0.name == identifier || $0.path == identifier }) {
            return headlineProperty(headline, prop: prop)
        }
        if let (identifier, prop) = parseNamedAccess(key: key, listName: "plugin"),
           let plugin = plugins.first(where: { $0.name == identifier || $0.path == identifier || $0.id == identifier }) {
            return pluginProperty(plugin, prop: prop)
        }

        return nil
    }

    private func ghostProperty(_ ghost: Ghost, prop: String) -> String? {
        switch prop {
        case "name": return ghost.name
        case "sakuraname": return ghost.sakuraname
        case "keroname": return ghost.keroname
        case "craftmanw": return ghost.craftmanw
        case "craftmanurl": return ghost.craftmanurl
        case "path": return ghost.path
        case "icon": return ghost.icon
        case "homeurl": return ghost.homeurl
        case "username": return ghost.username
        default: return nil
        }
    }

    private func balloonProperty(_ balloon: Balloon, prop: String) -> String? {
        switch prop {
        case "name": return balloon.name
        case "path": return balloon.path
        case "craftmanw": return balloon.craftmanw
        case "craftmanurl": return balloon.craftmanurl
        default: return nil
        }
    }

    private func headlineProperty(_ headline: Headline, prop: String) -> String? {
        switch prop {
        case "name": return headline.name
        case "path": return headline.path
        case "craftmanw": return headline.craftmanw
        case "craftmanurl": return headline.craftmanurl
        default: return nil
        }
    }

    private func pluginProperty(_ plugin: PropertyPlugin, prop: String) -> String? {
        switch prop {
        case "name": return plugin.name
        case "path": return plugin.path
        case "id": return plugin.id
        case "craftmanw": return plugin.craftmanw
        case "craftmanurl": return plugin.craftmanurl
        default: return nil
        }
    }

    private func parseNamedAccess(key: String, listName: String) -> (identifier: String, prop: String)? {
        let prefix = "\(listName)("
        guard key.hasPrefix(prefix), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: prefix.count)
        let identifier = String(key[start..<close])
        let tail = String(key[key.index(after: close)...])
        guard tail.first == "." else { return nil }
        return (identifier, String(tail.dropFirst()))
    }

    private func parseIndexAccess(key: String, listName: String) -> (index: Int, prop: String)? {
        let prefix = "\(listName).index("
        guard key.hasPrefix(prefix), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: prefix.count)
        guard let index = Int(String(key[start..<close])) else { return nil }
        let tail = String(key[key.index(after: close)...])
        guard tail.first == "." else { return nil }
        return (index, String(tail.dropFirst()))
    }
}

/// Provides rateofuselist.* properties.
/// Supported keys:
/// - rateofuselist.count
/// - rateofuselist(name).prop
/// - rateofuselist.index(n).prop
final class RateOfUsePropertyProvider: PropertyProvider {
    private let entriesProvider: () -> [RateOfUseEntry]

    init(entries: [RateOfUseEntry] = [], entriesProvider: (() -> [RateOfUseEntry])? = nil) {
        self.entriesProvider = entriesProvider ?? { entries }
    }

    func get(key: String) -> String? {
        let entries = entriesProvider()
        if key == "count" {
            return String(entries.count)
        }

        if let (index, prop) = parseIndex(key: key), entries.indices.contains(index) {
            return value(entries[index], prop: prop)
        }

        if let (name, prop) = parseNamedAccess(key: key),
           let entry = entries.first(where: { $0.name == name || $0.sakuraname == name }) {
            return value(entry, prop: prop)
        }

        return nil
    }

    private func value(_ entry: RateOfUseEntry, prop: String) -> String? {
        switch prop {
        case "name": return entry.name
        case "sakuraname": return entry.sakuraname
        case "keroname": return entry.keroname
        case "boottime": return String(entry.boottime)
        case "bootminute": return String(entry.bootminute)
        case "percent": return String(entry.percent)
        default: return nil
        }
    }

    private func parseNamedAccess(key: String) -> (String, String)? {
        guard key.hasPrefix("("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 1)
        let name = String(key[start..<close])
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        return (name, String(rest.dropFirst()))
    }

    private func parseIndex(key: String) -> (Int, String)? {
        guard key.hasPrefix("index("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 6)
        guard let idx = Int(String(key[start..<close])) else { return nil }
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        return (idx, String(rest.dropFirst()))
    }
}
