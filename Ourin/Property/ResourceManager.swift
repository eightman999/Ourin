import Foundation
import AppKit

/// Manages SHIORI Resource values that should persist across sessions.
/// Based on https://ssp.shillest.net/ukadoc/manual/list_shiori_resource.html
///
/// SHIORI Resources are simple key-value pairs (not SakuraScript) that control
/// ghost behavior and store user preferences.
///
/// ゴースト別分離: `ghostKey`（通常はゴーストフォルダ名）を渡すと
/// `OurinResource.<ghostKey>.<key>` の名前空間に保存し、複数ゴースト同時起動時の
/// 値の相互汚染を防ぐ。旧グローバルキー（`OurinResource.<key>`）は、最初に
/// ghostKey 付きで初期化されたゴーストが一度だけ引き継ぐ（backfill。
/// `OurinResource.__claimedBy` マーカーで多重移行を防止）。
/// ghostKey 省略時は従来どおりグローバル名前空間を読み書きする（互換維持）。
///
/// 永続化先（ghostKey 付きモード）: SSP 互換の公開フォルダ
/// `data/profile/<ghostKey>/shiori_resources.txt`（`OurinPaths.profileDirectory(for:)` 配下）。
/// 初回起動時、ファイルが存在しなければ UserDefaults からファイルへ一度だけ移行（冪等）。
/// **UserDefaults の既存データは移行後も削除しない**（データ消失防止・旧ビルド互換）。
/// ファイル形式: UTF-8 / LF、1 行 1 エントリの `key,value` プレーンテキスト。
///   - 保存形式の根拠: UKADOC「SHIORI Resource リスト」/本リポジトリ docs/
///     `PROPERTY_Resource_3.0M_SPEC_*` はキー一覧と返答コード規約のみを規定し、
///     ファイルフォーマットは未規定。SHIORI Resource は「短いテキスト（bool値含む）」
///     が前提のため、改行を含まない 1 行 1 エントリ形式が安全かつ相互運用可能。
///   - 読み込みは最初の `,` で key/value を分割（値にカンマが含まれても可）。
public final class ResourceManager {
    private let defaults: UserDefaults
    private let prefix: String
    private static let legacyPrefix = "OurinResource."
    private static let claimMarkerKey = "OurinResource.__claimedBy"

    /// ファイル永続化ストア（ghostKey 付きモードのみ使用）。nil なら UserDefaults のみ。
    private let fileStore: ResourceFileStore?
    /// ファイルから読み込んだ値のメモリキャッシュ（fileStore != nil のとき正）。
    private var cache: [String: String] = [:]

    public convenience init(defaults: UserDefaults = .standard, ghostKey: String? = nil) {
        self.init(defaults: defaults, ghostKey: ghostKey, fileStore: nil)
    }

    /// ファイルストアを明示的に注入するイニシャライザ（テスト用。internal）。
    /// `fileStore` が nil の場合は ghostKey 付きモードで `ProfileResourceFileStore` を既定使用。
    init(defaults: UserDefaults = .standard, ghostKey: String? = nil, fileStore: ResourceFileStore?) {
        self.defaults = defaults
        let trimmed = ghostKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 先に全 stored property を設定（designated init の制約）。
        if trimmed.isEmpty {
            // 旧グローバルモード: UserDefaults のみ（互換維持・ファイルは使わない）
            self.prefix = Self.legacyPrefix
            self.fileStore = nil
        } else {
            self.prefix = Self.legacyPrefix + trimmed + "."
            // backfill（旧グローバル UserDefaults 値 → このゴーストのプレフィックスへ1回限りコピー）。
            // self.cache に依存しないのでインライン実行し、順序（旧グローバル → プレフィックス → ファイル）を保証。
            if defaults.string(forKey: Self.claimMarkerKey) == nil {
                defaults.set(trimmed, forKey: Self.claimMarkerKey)
                for (key, value) in defaults.dictionaryRepresentation() {
                    guard key.hasPrefix(Self.legacyPrefix), key != Self.claimMarkerKey else { continue }
                    guard let str = value as? String else { continue }
                    let sub = String(key.dropFirst(Self.legacyPrefix.count))
                    defaults.set(str, forKey: prefix + sub)
                }
            }
            // テストから明示的注入が無ければ SSP 公開フォルダへ。
            self.fileStore = fileStore ?? ProfileResourceFileStore(ghostKey: trimmed)
        }
        self.cache = [:]
        // 全プロパティ設定後、ファイルモードのマイグレーションを実行。
        migrateUserDefaultsToFileIfNeeded()
    }

    /// 初回起動時に UserDefaults のゴースト別プレフィックス値をファイルへ移行する（冪等）。
    /// - ファイル既存 → ファイル優先（キャッシュへ読み込み、UserDefaults は触らない）。
    /// - ファイル無し → UserDefaults の該当プレフィックス値を全てファイルへ書き出す。
    ///   UserDefaults のエントリは削除しない（データ消失防止）。
    private func migrateUserDefaultsToFileIfNeeded() {
        guard let store = fileStore else { return }
        if let existing = store.load() {
            // ファイル既存 → ファイル優先
            self.cache = existing
            return
        }
        // ファイル無し → UserDefaults から移行（初回のみ・claimMarker は対象外）
        var entries: [String: String] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix(prefix) else { continue }
            guard let str = value as? String else { continue }
            let sub = String(key.dropFirst(prefix.count))
            entries[sub] = str
        }
        self.cache = entries
        try? store.write(entries)
    }

    /// キャッシュをファイルへ永続化する（fileStore があるときのみ）。
    private func persistCacheToFile() {
        guard let store = fileStore else { return }
        try? store.write(cache)
    }

    // MARK: - Generic Accessors

    /// Get a SHIORI resource value.
    public func get(_ key: String) -> String? {
        if fileStore != nil {
            return cache[key]
        }
        return defaults.string(forKey: prefix + key)
    }

    /// Set a SHIORI resource value.
    public func set(_ key: String, value: String) {
        if fileStore != nil {
            cache[key] = value
            persistCacheToFile()
        } else {
            defaults.set(value, forKey: prefix + key)
        }
    }

    /// Remove a SHIORI resource value.
    public func remove(_ key: String) {
        if fileStore != nil {
            cache.removeValue(forKey: key)
            persistCacheToFile()
        } else {
            defaults.removeObject(forKey: prefix + key)
        }
    }

    // MARK: - Commonly Used Resources

    /// User's name (username resource)
    public var username: String? {
        get { get("username") }
        set { if let v = newValue { set("username", value: v) } else { remove("username") } }
    }

    /// Ghost home URL for updates (homeurl resource)
    public var homeurl: String? {
        get { get("homeurl") }
        set { if let v = newValue { set("homeurl", value: v) } else { remove("homeurl") } }
    }

    // MARK: - Character Position Resources

    /// Sakura (scope 0) default X position
    public var sakuraDefaultLeft: Int? {
        get { get("sakura.defaultleft").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaultleft", value: String(v)) } else { remove("sakura.defaultleft") } }
    }

    /// Sakura (scope 0) default Y position
    public var sakuraDefaultTop: Int? {
        get { get("sakura.defaulttop").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaulttop", value: String(v)) } else { remove("sakura.defaulttop") } }
    }

    /// Kero (scope 1) default X position
    public var keroDefaultLeft: Int? {
        get { get("kero.defaultleft").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaultleft", value: String(v)) } else { remove("kero.defaultleft") } }
    }

    /// Kero (scope 1) default Y position
    public var keroDefaultTop: Int? {
        get { get("kero.defaulttop").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaulttop", value: String(v)) } else { remove("kero.defaulttop") } }
    }

    /// Sakura base X coordinate
    public var sakuraDefaultX: Int? {
        get { get("sakura.defaultx").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaultx", value: String(v)) } else { remove("sakura.defaultx") } }
    }

    /// Sakura base Y coordinate
    public var sakuraDefaultY: Int? {
        get { get("sakura.defaulty").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaulty", value: String(v)) } else { remove("sakura.defaulty") } }
    }

    /// Kero base X coordinate
    public var keroDefaultX: Int? {
        get { get("kero.defaultx").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaultx", value: String(v)) } else { remove("kero.defaultx") } }
    }

    /// Kero base Y coordinate
    public var keroDefaultY: Int? {
        get { get("kero.defaulty").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaulty", value: String(v)) } else { remove("kero.defaulty") } }
    }

    // MARK: - Character-specific positions (char*.default*)

    /// Get default left position for character at scope
    public func getCharDefaultLeft(scope: Int) -> Int? {
        switch scope {
        case 0: return sakuraDefaultLeft
        case 1: return keroDefaultLeft
        default: return get("char\(scope).defaultleft").flatMap(Int.init)
        }
    }

    /// Set default left position for character at scope
    public func setCharDefaultLeft(scope: Int, value: Int?) {
        let key = scope == 0 ? "sakura.defaultleft" : scope == 1 ? "kero.defaultleft" : "char\(scope).defaultleft"
        if let v = value { set(key, value: String(v)) } else { remove(key) }
    }

    /// Get default top position for character at scope
    public func getCharDefaultTop(scope: Int) -> Int? {
        switch scope {
        case 0: return sakuraDefaultTop
        case 1: return keroDefaultTop
        default: return get("char\(scope).defaulttop").flatMap(Int.init)
        }
    }

    /// Set default top position for character at scope
    public func setCharDefaultTop(scope: Int, value: Int?) {
        let key = scope == 0 ? "sakura.defaulttop" : scope == 1 ? "kero.defaulttop" : "char\(scope).defaulttop"
        if let v = value { set(key, value: String(v)) } else { remove(key) }
    }

    // MARK: - Balloon positions

    /// Get saved balloon left position for scope
    public func getBalloonLeft(scope: Int) -> Int? {
        let key = scope == 0 ? "balloon0.defaultleft" : "balloon\(scope).defaultleft"
        return get(key).flatMap { Int($0) }
    }

    /// Set saved balloon left position for scope
    public func setBalloonLeft(scope: Int, value: Int?) {
        let key = scope == 0 ? "balloon0.defaultleft" : "balloon\(scope).defaultleft"
        if let v = value { set(key, value: String(v)) } else { remove(key) }
    }

    /// Get saved balloon top position for scope
    public func getBalloonTop(scope: Int) -> Int? {
        let key = scope == 0 ? "balloon0.defaulttop" : "balloon\(scope).defaulttop"
        return get(key).flatMap { Int($0) }
    }

    /// Set saved balloon top position for scope
    public func setBalloonTop(scope: Int, value: Int?) {
        let key = scope == 0 ? "balloon0.defaulttop" : "balloon\(scope).defaulttop"
        if let v = value { set(key, value: String(v)) } else { remove(key) }
    }

    // MARK: - Update Configuration

    /// Whether to use 1-based file numbering for updates (useorigin1 resource)
    public var useOrigin1: Bool {
        get { get("useorigin1") == "1" }
        set { set("useorigin1", value: newValue ? "1" : "0") }
    }

    // MARK: - Helper Methods

    /// Save current window positions from GhostManager
    public func saveWindowPositions(from windows: [Int: NSWindow]) {
        for (scope, window) in windows {
            let frame = window.frame
            setCharDefaultLeft(scope: scope, value: Int(frame.origin.x))
            setCharDefaultTop(scope: scope, value: Int(frame.origin.y))
        }
    }

    /// Restore window positions to GhostManager windows
    public func restoreWindowPositions(to windows: [Int: NSWindow]) {
        for (scope, window) in windows {
            if let x = getCharDefaultLeft(scope: scope),
               let y = getCharDefaultTop(scope: scope) {
                var frame = window.frame
                frame.origin.x = CGFloat(x)
                frame.origin.y = CGFloat(y)
                window.setFrame(frame, display: false)
            }
        }
    }

    /// Clear all stored resources (for debugging/reset)
    public func clearAll() {
        if fileStore != nil {
            // ファイルモード: キャッシュとファイルを空にする。
            // UserDefaults の旧エントリは移行ポリシー（削除しない）に従い触らない。
            cache.removeAll()
            persistCacheToFile()
            return
        }
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - File Persistence

/// SHIORI Resource のファイル永続化インターフェース。
/// テストからモックを注入可能にするためプロトコル化。
protocol ResourceFileStore {
    /// ファイルが存在する場合は全エントリを返す。存在しない/読めない場合は nil。
    func load() -> [String: String]?
    /// 全エントリをファイルへ書き出す（上書き・アトミック）。
    func write(_ entries: [String: String]) throws
}

/// SSP 互換の公開フォルダ `data/profile/<ghost>/shiori_resources.txt` を使う実装。
/// 形式: UTF-8 / LF、1 行 1 エントリの `key,value`。
///   - 値の改行は半角空白へ正規化（SHIORI Resource は短いテキスト前提）。
///   - 読み込みは最初の `,` で key/value を分割（値にカンマが含まれていても可）。
struct ProfileResourceFileStore: ResourceFileStore {
    static let fileName = "shiori_resources.txt"
    let ghostKey: String

    init(ghostKey: String) {
        self.ghostKey = ghostKey
    }

    private func fileURL() throws -> URL {
        try OurinPaths.profileDirectory(for: ghostKey)
            .appendingPathComponent(Self.fileName)
    }

    func load() -> [String: String]? {
        guard let url = try? fileURL(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        var dict: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            // 最初の `,` で分割。値側にカンマが含まれていても保持。
            let parts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            dict[key] = value
        }
        return dict
    }

    func write(_ entries: [String: String]) throws {
        let url = try fileURL()
        var lines: [String] = []
        lines.reserveCapacity(entries.count)
        // ソート順を固定し、再書き込み時の diff を最小化。
        for key in entries.keys.sorted() {
            // 改行混入を防ぐため LF/CR を空白化（1 行 1 エントリの不変量）。
            let value = entries[key]?
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ") ?? ""
            lines.append("\(key),\(value)")
        }
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
