import Foundation

/// バルーンの設定ファイルを読み込むローダー。
/// `charset,Shift_JIS` が指定されている場合は CP932 として扱う。
public struct DescriptorLoader {
    /// 指定ディレクトリから descript.txt を読み込み、
    /// balloons*.txt があれば上書き合成する。
    public static func load(from root: URL) throws -> [String: String] {
        let main = try parse(file: root.appendingPathComponent("descript.txt"))
        var result = main
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in items where url.lastPathComponent.hasPrefix("balloons") && url.pathExtension == "txt" {
                let sub = (try? parse(file: url)) ?? [:]
                for (k,v) in sub { result[k] = v }
            }
        }
        return result
    }

    /// 単一ファイルを解析して連想配列へ変換する。
    /// SSP と同様に、まず `charset,` 行を検出してから宣言エンコーディングで再デコードする
    /// （Shift_JIS ファイルが UTF-8 として誤デコードされるのを防ぐ二段読み）。
    private static func parse(file: URL) throws -> [String: String] {
        let raw = try Data(contentsOf: file)
        let str = decode(raw: raw)
        var dict: [String:String] = [:]
        for line in str.components(separatedBy: .newlines) {
            guard let comma = line.firstIndex(of: ",") else { continue }
            let key = String(line[..<comma]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { dict[key] = value }
        }
        return dict
    }

    /// raw バイト列をデコードする。先頭の `charset,XXX` 行で宣言されたエンコーディングを優先し、
    /// 宣言が無ければ UTF-8 → Shift_JIS の順でフォールバックする。
    /// 検出パスでは ASCII 互換の isoLatin1（1:1 バイト写像・絶対失敗しない）を使う。
    private static func decode(raw: Data) -> String {
        if let detected = String(data: raw, encoding: .isoLatin1) {
            let declared = detected
                .components(separatedBy: .newlines)
                .lazy
                .compactMap { line -> String? in
                    guard let comma = line.firstIndex(of: ",") else { return nil }
                    let key = String(line[..<comma]).trimmingCharacters(in: .whitespaces).lowercased()
                    guard key == "charset" else { return nil }
                    return String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces).lowercased()
                }
                .first
            if let declared {
                if isShiftJIS(declared), let s = String(data: raw, encoding: .shiftJIS) {
                    return s
                }
                if declared.contains("utf"), let s = String(data: raw, encoding: .utf8) {
                    return s
                }
            }
        }
        if let s = String(data: raw, encoding: .utf8) { return s }
        if let s = String(data: raw, encoding: .shiftJIS) { return s }
        return String(data: raw, encoding: .isoLatin1) ?? ""
    }

    private static func isShiftJIS(_ charset: String) -> Bool {
        let c = charset.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        return c == "shiftjis" || c == "sjis" || c == "cp932" || c == "mskanji" || c == "windows31j"
    }
}

private extension String.Encoding {
    /// Windows 互換の Shift_JIS コードページ (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
}
