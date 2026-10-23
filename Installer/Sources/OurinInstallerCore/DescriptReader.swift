import Foundation

/// SSP 形式の descript.txt（`key,value` 行）を読む。
///
/// Ourin 本体の DescriptParser と同じく、`charset,` 宣言があればそれを優先し、
/// 無ければ UTF-8 → Shift_JIS（CP932）の順に試す。インストーラーは名前と SHIORI
/// だけ分かればよいので、値の加工はしない。
public enum DescriptReader {
    public static let cp932 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))
    )

    public static func read(_ url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> [String: String] {
        guard let text = decode(data) else { return [:] }
        var result: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("//"),
                  let comma = line.firstIndex(of: ",") else { continue }
            let key = line[..<comma].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            // 同じキーが複数あれば先勝ち（SSP と同じ）。
            if result[key] == nil { result[key] = value }
        }
        return result
    }

    static func decode(_ data: Data) -> String? {
        var body = data
        if body.starts(with: [0xEF, 0xBB, 0xBF]) { body = body.dropFirst(3) }

        if let declared = declaredCharset(body) {
            let encoding: String.Encoding?
            switch declared {
            case "utf-8", "utf8": encoding = .utf8
            case "shift_jis", "shift-jis", "sjis", "cp932", "windows-31j", "ms932": encoding = cp932
            case "euc-jp", "euc_jp": encoding = .japaneseEUC
            default: encoding = nil
            }
            if let encoding, let text = String(data: body, encoding: encoding) { return text }
        }
        return String(data: body, encoding: .utf8) ?? String(data: body, encoding: cp932)
    }

    /// 先頭付近の `charset,xxx` を ASCII として拾う。
    private static func declaredCharset(_ data: Data) -> String? {
        let head = data.prefix(1024)
        guard let ascii = String(data: head, encoding: .isoLatin1) else { return nil }
        for line in ascii.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("charset,") {
                return trimmed.dropFirst("charset,".count)
                    .trimmingCharacters(in: .whitespaces).lowercased()
            }
        }
        return nil
    }
}
