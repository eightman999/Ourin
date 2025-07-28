import Foundation

private extension String.Encoding {
    /// Windows 互換の Shift_JIS コードページ (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
}

/// SJIS 受理→UTF-8 正規化ユーティリティ
enum PluginEncodingNormalizer {
    /// 文字コードラベルから `String.Encoding` を得る
    static func encoding(from label: String) -> String.Encoding {
        let lower = label.lowercased()
        if lower == "utf-8" || lower == "utf8" { return .utf8 }
        if ["shift_jis", "windows-31j", "cp932", "ms932", "sjis"].contains(lower) {
            return .shiftJIS
        }
        return .utf8
    }

    /// 指定エンコーディングから UTF-8 文字列へ変換する
    static func utf8String(from data: Data, encoding: String.Encoding) -> String? {
        String(data: data, encoding: encoding)
    }
}
