import Foundation

/// FMO など既存のホスト機能を利用して SHIORI パイプラインへ橋渡しを行う仮実装
public enum BridgeToSHIORI {
    /// Resource 用のテスト返値を保持するマップ
    private static var resourceMap: [String: String] = [:]

    /// テスト用に返値を登録する
    public static func setResource(_ key: String, value: String) {
        resourceMap[key] = value
    }

    /// テスト用登録値をすべて消去
    public static func reset() {
        resourceMap.removeAll()
    }

    /// 簡易的なスタブ実装。
    /// 指定されたキーに対応する登録値があればそれを返し、無ければ固定文字列を返す。
    public static func handle(event: String, references: [String]) -> String {
        if event == "Resource", let key = references.first {
            return resourceMap[key] ?? "\\h\\s0Placeholder"
        }
        return "\\h\\s0Placeholder"
    }
}
