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
}
