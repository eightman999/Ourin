import Foundation

/// ゴースト名からハンドラへの簡易レジストリ
public final class GhostRegistry {
    public static let shared = GhostRegistry()
    /// ゴースト名とそのパスの対応表
    private var ghosts: [String: String] = [:]
    private init() {}

    /// ゴーストの登録
    public func register(name: String, path: String) {
        ghosts[name] = path
    }

    /// ゴースト名からパスを取得
    public func path(for name: String) -> String? {
        ghosts[name]
    }

    /// 登録済みゴーストが1件以上あるか
    public func hasEntries() -> Bool {
        !ghosts.isEmpty
    }

    /// 大文字小文字を無視してゴースト名が存在するか
    public func contains(name: String) -> Bool {
        ghosts.keys.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// 登録済みゴースト名の一覧
    public func allNames() -> [String] {
        ghosts.keys.sorted()
    }

    /// 登録済みゴースト情報一覧（name -> path）
    public func allEntries() -> [String: String] {
        ghosts
    }

    /// テスト用途: 全登録を削除
    public func clear() {
        ghosts.removeAll()
    }
}
