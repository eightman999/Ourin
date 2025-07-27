import Foundation

/// CP932 系のラベルも受け付けて UTF-8 文字列へ変換するユーティリティ
public enum EncodingAdapter {
    /// Charset ラベルを基に Data を文字列へデコードする
    public static func decode(_ data: Data, charset: String) -> String? {
        let cs = charset.lowercased()
        let encoding: String.Encoding
        if ["shift_jis", "windows-31j", "cp932", "ms932", "sjis"].contains(cs) {
            encoding = .shiftJIS
        } else {
            encoding = .utf8
        }
        return String(data: data, encoding: encoding)
    }
}
