import Foundation

/// 文字セットラベルに応じてデータをデコードするユーティリティ。
public enum EncodingNormalizer {
    /// Charset ヘッダが存在する場合はそれを利用し、UTF‑8 または CP932 として解釈する。
    public static func decode(_ data: Data, charset: String?) -> String? {
        if let cs = charset { return EncodingAdapter.decode(data, charset: cs) }
        if let utf = String(data: data, encoding: .utf8) { return utf }
        return String(data: data, encoding: .shiftJIS)
    }
}
