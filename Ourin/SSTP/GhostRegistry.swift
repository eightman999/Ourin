import Foundation

/// ゴースト名からハンドラへの簡易レジストリ
public final class GhostRegistry {
    public static let shared = GhostRegistry()
    /// ゴースト名とそのパスの対応表
    private var ghosts: [String: String] = [:]
    private let lock = NSLock()
    private static let testGhostsKey = "GhostRegistry.testGhosts"
    private init() {}

    /// ゴーストの登録
    public func register(name: String, path: String) {
        if isRunningTests {
            var current = testGhosts
            current[name] = path
            testGhosts = current
            return
        }
        lock.lock()
        ghosts[name] = path
        lock.unlock()
    }

    /// ゴースト名からパスを取得
    public func path(for name: String) -> String? {
        snapshot()[name]
    }

    /// 登録済みゴーストが1件以上あるか
    public func hasEntries() -> Bool {
        !snapshot().isEmpty
    }

    /// 大文字小文字を無視してゴースト名が存在するか
    public func contains(name: String) -> Bool {
        snapshot().keys.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// 登録済みゴースト名の一覧
    public func allNames() -> [String] {
        snapshot().keys.sorted()
    }

    /// 登録済みゴースト情報一覧（name -> path）
    public func allEntries() -> [String: String] {
        snapshot()
    }

    /// テスト用途: 全登録を削除
    public func clear() {
        if isRunningTests {
            Thread.current.threadDictionary.removeObject(forKey: Self.testGhostsKey)
            return
        }
        lock.lock()
        ghosts.removeAll()
        lock.unlock()
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var testGhosts: [String: String] {
        get {
            Thread.current.threadDictionary[Self.testGhostsKey] as? [String: String] ?? [:]
        }
        set {
            Thread.current.threadDictionary[Self.testGhostsKey] = newValue
        }
    }

    private func snapshot() -> [String: String] {
        if isRunningTests {
            return testGhosts
        }
        lock.lock()
        let current = ghosts
        lock.unlock()
        return current
    }
}
