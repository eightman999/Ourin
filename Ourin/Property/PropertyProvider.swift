import Foundation

/// プロパティ値の取得・設定を行う基本インタフェース。
public protocol PropertyProvider {
    /// 正規化済みキーに対する値を返す。存在しない場合は `nil`。
    func get(key: String) -> String?
    /// 対応する場合は値を設定する。成功時は `true` を返す。
    func set(key: String, value: String) -> Bool
}

extension PropertyProvider {
    /// 既定では書き込み不可とする。
    public func set(key: String, value: String) -> Bool { return false }
}
