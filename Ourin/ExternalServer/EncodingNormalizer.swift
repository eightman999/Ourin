import Foundation

/// 文字セットラベルに応じてデータをデコードするユーティリティ。
public enum EncodingNormalizer {
    /// 外部SSTP入力でCP932(Shift_JIS)フォールバックを受理するかどうか。
    /// 既定は true（現行挙動と完全に同一）。設定画面の「CP932 受理」トグルで変更できる。
    public static var acceptsCP932: Bool {
        UserDefaults.standard.object(forKey: "OurinAcceptCP932") as? Bool ?? true
    }

    /// Charset ヘッダが存在する場合はそれを利用し、UTF‑8 または CP932 として解釈する。
    /// charset未指定時、acceptsCP932がfalseならUTF-8のみ受理しShift_JISフォールバックはスキップする。
    public static func decode(_ data: Data, charset: String?) -> String? {
        if let cs = charset { return EncodingAdapter.decode(data, charset: cs) }
        if let utf = String(data: data, encoding: .utf8) { return utf }
        guard acceptsCP932 else { return nil }
        return String(data: data, encoding: .shiftJIS)
    }
}
