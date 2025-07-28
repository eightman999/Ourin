import Foundation

// SHIORI イベントパイプラインへの簡易ブリッジ実装。
// docs/OURIN_SHIORI_EVENTS_3.0M_SPEC.md に沿ったイベント名を使用する。

/// FMO など既存のホスト機能を利用して SHIORI パイプラインへ橋渡しを行う仮実装
/// SHIORI/3.0M 互換イベントへ橋渡しするスタブ実装
public enum BridgeToSHIORI {
    /// Resource 用のテスト返値を保持するマップ
    private static var resourceMap: [String: String] = [:]

    /// テスト用に返値を登録する
    /// - Parameters:
    ///   - key: Resource 名
    ///   - value: 応答として返す文字列
    public static func setResource(_ key: String, value: String) {
        resourceMap[key] = value
    }

    /// テスト用登録値をすべて消去
    public static func reset() {
        resourceMap.removeAll()
    }

    /// SHIORI 互換イベントを処理するスタブ
    /// - Parameters:
    ///   - event: イベント名
    ///   - references: 参照引数
    /// - Returns: 登録済み値または固定文字列
    public static func handle(event: String, references: [String]) -> String {
        if event == "Resource", let key = references.first {
            return resourceMap[key] ?? "\\h\\s0Placeholder"
        }
        return "\\h\\s0Placeholder"
    }
}
