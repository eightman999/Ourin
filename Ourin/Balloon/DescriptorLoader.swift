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

    /// raw バイト列をデコードする。BOM・`charset,XXX` の宣言を優先し、無ければ UTF-8 → Shift_JIS の順に試す。
    private static func decode(raw: Data) -> String {
        EncodingAdapter.decodeTextDefinition(raw) ?? String(data: raw, encoding: .isoLatin1) ?? ""
    }
}

