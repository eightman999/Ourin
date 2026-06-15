import Foundation

/// CP932 系のラベルも受け付けて UTF-8 文字列へ相互変換するユーティリティ。
/// SHIORI/SSTP の Charset ヘッダに従った受信デコード・送信エンコードに用いる。
public enum EncodingAdapter {
    /// Charset ラベルに対応する `String.Encoding` を返す（既定は UTF-8）。
    public static func encoding(for charset: String) -> String.Encoding {
        let cs = charset.lowercased().trimmingCharacters(in: .whitespaces)
        if ["shift_jis", "shiftjis", "windows-31j", "cp932", "ms932", "sjis", "x-sjis"].contains(cs) {
            return .shiftJIS
        }
        if ["euc-jp", "eucjp"].contains(cs) {
            return .japaneseEUC
        }
        if ["iso-2022-jp", "jis"].contains(cs) {
            return .iso2022JP
        }
        return .utf8
    }

    /// Charset ラベルを基に Data を文字列へデコードする。
    public static func decode(_ data: Data, charset: String) -> String? {
        return String(data: data, encoding: encoding(for: charset))
    }

    /// Charset ラベルに従って文字列を Data へエンコードする（失敗時は UTF-8）。
    public static func encode(_ text: String, charset: String) -> Data {
        return text.data(using: encoding(for: charset)) ?? Data(text.utf8)
    }

    /// メッセージ先頭（最初の空行まで）のヘッダ部から `Charset:` を推定する。
    /// ヘッダ名・値は ASCII 前提なので、本体が Shift_JIS でも安全に読み取れる。
    public static func detectCharset(in data: Data, default def: String = "UTF-8") -> String {
        let headerData: Data
        if let r = data.range(of: Data([13, 10, 13, 10])) {
            headerData = Data(data.prefix(upTo: r.lowerBound))
        } else if let r = data.range(of: Data([10, 10])) {
            headerData = Data(data.prefix(upTo: r.lowerBound))
        } else {
            headerData = data
        }
        guard let header = String(data: headerData, encoding: .ascii)
            ?? String(data: headerData, encoding: .isoLatin1) else { return def }
        for line in header.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.lowercased().hasPrefix("charset:") {
                let value = l.dropFirst("charset:".count).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return def
    }
}
