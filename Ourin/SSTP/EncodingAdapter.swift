import Foundation

/// Charset の名前と `String.Encoding` の相互変換、受信デコード・送信エンコードのユーティリティ。
/// SHIORI / SSTP / SAORI / PLUGIN / HEADLINE の Charset ヘッダと、テキスト定義ファイル（descript.txt など）の
/// `charset,` 宣言に使う。SSP と同じく、日本語以外（中国語・韓国語・欧文など）の文字コードも受け付ける。
public enum EncodingAdapter {
    /// Charset ラベルに対応する `String.Encoding` を返す（知らない名前は UTF-8）。
    public static func encoding(for charset: String) -> String.Encoding {
        knownEncoding(for: charset) ?? .utf8
    }

    /// Windows のコードページ番号の文字コード。
    private static func windowsCodePage(_ number: UInt32) -> String.Encoding? {
        let cf = CFStringConvertWindowsCodepageToEncoding(number)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    private static func cf(_ encoding: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue)))
    }

    /// Charset の名前（IANA 名・Windows のコードページ名・よく使われる別名。大文字小文字・`-` `_` は区別しない）から
    /// `String.Encoding` を引く。知らない名前は nil。
    /// 中国語・韓国語は Windows のコードページ（Big5 は CP950、GB2312 / GBK は CP936、EUC-KR / UHC は CP949）で読む。
    /// どれも元の文字コードの上位互換で、Windows で作られたゴーストはこれで書かれている。
    public static func knownEncoding(for charset: String) -> String.Encoding? {
        let raw = charset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let name = raw.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "")
        switch name {
        case "utf-8", "utf8", "utf-8n", "x-utf-8": return .utf8
        case "shift-jis", "shiftjis", "sjis", "x-sjis", "cp932", "ms932", "windows-31j", "ms-kanji", "csshiftjis", "windows-932":
            return .shiftJIS
        case "euc-jp", "eucjp", "x-euc-jp", "cseucpkdfmtjapanese": return .japaneseEUC
        case "iso-2022-jp", "jis", "csiso2022jp": return .iso2022JP
        case "utf-16", "utf16", "ucs-2", "unicode": return .utf16
        case "utf-16le", "utf16le", "unicodefffe": return .utf16LittleEndian
        case "utf-16be", "utf16be": return .utf16BigEndian
        case "big5", "cp950", "windows-950", "x-x-big5", "csbig5": return cf(.dosChineseTrad)
        case "gb2312", "gbk", "cp936", "windows-936", "x-gbk", "euc-cn", "csgb2312", "gb-2312": return cf(.dosChineseSimplif)
        case "euc-kr", "euckr", "ks-c-5601-1987", "ksc5601", "ks-c-5601", "cp949", "windows-949", "uhc", "cseuckr": return cf(.dosKorean)
        case "latin1", "iso-8859-1": return .isoLatin1
        default: break
        }
        // windows-1252 / cp1252 / 1252 のようなコードページ番号。
        for prefix in ["windows-", "cp", "ms", "x-cp", ""] where name.hasPrefix(prefix) {
            if let number = UInt32(name.dropFirst(prefix.count)), number > 0, let encoding = windowsCodePage(number) { return encoding }
        }
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(raw as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
    }

    /// `String.Encoding` の Charset の名前（Shift_JIS・UTF-8 は SSP と同じ表記、ほかは IANA 名）。
    public static func charsetName(for encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .shiftJIS: return "Shift_JIS"
        case .japaneseEUC: return "EUC-JP"
        case .iso2022JP: return "ISO-2022-JP"
        // 中国語・韓国語は、Windows のコードページで読んでいても一般的な名前で書く。
        case cf(.dosChineseTrad): return "Big5"
        case cf(.dosChineseSimplif): return "GB2312"
        case cf(.dosKorean): return "EUC-KR"
        default:
            let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
            return (CFStringConvertEncodingToIANACharSetName(cfEncoding) as String?) ?? "UTF-8"
        }
    }

    // MARK: - テキスト定義ファイル

    /// テキスト定義ファイル（descript.txt・install.txt・surfaces.txt など）を読む。
    /// BOM があればそれに従い、無ければ `charset,名前`（`charset:名前`）の宣言、それも無ければ UTF-8 → Shift_JIS の順に試す。
    public static func decodeTextDefinition(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { return String(data: data, encoding: .utf16) }
        if let declared = declaredTextCharset(in: data), let text = String(data: data, encoding: declared) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
    }

    /// テキスト定義ファイルの `charset,名前` / `charset:名前` の宣言（先頭 4KB の中）。知らない名前なら nil。
    public static func declaredTextCharset(in data: Data) -> String.Encoding? {
        guard let probe = String(data: data.prefix(4096), encoding: .isoLatin1) else { return nil }
        for rawLine in probe.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.lowercased().hasPrefix("charset") else { continue }
            let rest = line.dropFirst("charset".count).drop { $0 == " " || $0 == "\t" }
            guard let separator = rest.first, separator == "," || separator == ":" else { continue }
            return knownEncoding(for: String(rest.dropFirst()))
        }
        return nil
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

    /// メッセージ先頭（最初の空行まで）のヘッダ部から宣言された `Charset:` を返す。
    /// ヘッダ名・値は ASCII 前提なので、本体が Shift_JIS でも安全に読み取れる。
    public static func declaredCharset(in data: Data) -> String? {
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
        return nil
    }

    /// Charset 未指定時の既定値を含めて文字コードを返す。
    public static func detectCharset(in data: Data, default def: String = "UTF-8") -> String {
        declaredCharset(in: data) ?? def
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
