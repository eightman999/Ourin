import Foundation

/// SJIS 受理→UTF-8 正規化ユーティリティ
enum EncodingNormalizer {
    /// 指定エンコーディングから UTF-8 へ変換する
    static func utf8String(from data: Data, encoding: String.Encoding) -> String? {
        if encoding == .utf8 {
            return String(data: data, encoding: .utf8)
        }
        // Shift_JIS 系文字列を UTF-8 へ変換
        if let str = String(data: data, encoding: encoding) {
            return str
        }
        return nil
    }
}
