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
    public static func encode(_ text: String, charset: String, escapeUnknown: Bool = false) -> Data {
        let target = encoding(for: charset)
        if let encoded = text.data(using: target) { return encoded }
        guard escapeUnknown, target != .utf8 else { return Data(text.utf8) }
        let escaped = text.unicodeScalars.map { scalar -> String in
            let value = String(scalar)
            if value.data(using: target) != nil { return value }
            return String(format: "?escape!unicode[0x%X]", scalar.value)
        }.joined()
        return escaped.data(using: target) ?? Data(escaped.utf8)
    }

    /// `shiori.escape_unknown`で往路に退避されたUnicode scalarを復元する。
    public static func restoreEscapedUnicode(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\?escape!unicode\[0x([0-9A-Fa-f]{1,8})\]"#) else {
            return text
        }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed()
        let result = NSMutableString(string: text)
        for match in matches where match.numberOfRanges == 2 {
            let hex = source.substring(with: match.range(at: 1))
            guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else { continue }
            result.replaceCharacters(in: match.range(at: 0), with: String(scalar))
        }
        return result as String
    }

    /// メッセージ先頭（最初の空行まで）のヘッダ部から `Charset:` を推定する。
    /// ヘッダ名・値は ASCII 前提なので、本体が Shift_JIS でも安全に読み取れる。
    public static func detectCharset(in data: Data, default def: String = "UTF-8") -> String {
        var lineBytes: [UInt8] = []
        for byte in data {
            if byte == 10 || byte == 13 {
                if lineBytes.isEmpty {
                    continue
                }
                if let found = charsetValue(inLineBytes: lineBytes) {
                    return found
                }
                lineBytes.removeAll(keepingCapacity: true)
                continue
            }
            lineBytes.append(byte)
        }
        if let found = charsetValue(inLineBytes: lineBytes) {
            return found
        }
        return def
    }

    private static func charsetValue(inLineBytes bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty,
              let line = String(data: Data(bytes), encoding: .ascii)
                ?? String(data: Data(bytes), encoding: .isoLatin1) else { return nil }
        let l = line.trimmingCharacters(in: .whitespaces)
        if l.lowercased().hasPrefix("charset:") {
            let value = l.dropFirst("charset:".count).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return String(value) }
        }
        return nil
    }
}
