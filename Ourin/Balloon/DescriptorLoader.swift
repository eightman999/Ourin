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
    private static func parse(file: URL) throws -> [String: String] {
        let raw = try Data(contentsOf: file)
        var text = String(data: raw, encoding: .utf8)
        if text == nil {
            text = String(data: raw, encoding: .shiftJIS)
        }
        guard let str = text else { throw NSError(domain: "DescriptorLoader", code: -1, userInfo: [NSLocalizedDescriptionKey:"Encoding error"]) }
        var dict: [String:String] = [:]
        for line in str.components(separatedBy: .newlines) {
            guard let comma = line.firstIndex(of: ",") else { continue }
            let key = String(line[..<comma]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { dict[key] = value }
        }
        return dict
    }
}

private extension String.Encoding {
    /// Windows 互換の Shift_JIS コードページ (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
}
