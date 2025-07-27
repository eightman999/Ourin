import Foundation

/// FMO など既存のホスト機能を利用して SHIORI パイプラインへ橋渡しを行う仮実装
public enum BridgeToSHIORI {
    /// 簡易的なスタブ。固定スクリプトを返すだけ
    public static func handle(event: String, references: [String]) -> String {
        return "\\h\\s0Placeholder"
    }
}
