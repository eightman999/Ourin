import Foundation

/// SSTP/1.x メッセージを表す構造体。メソッド・バージョン・ヘッダを保持する。
public struct SstpMessage {
    public let method: String
    public let version: String
    public let headers: [String:String]
}

public enum SstpParser {
    /// CRLF 区切りの生SSTP文字列を解析する。
    public static func parse(_ raw: String) -> SstpMessage? {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let first = lines.first else { return nil }
        let comps = first.split(separator: " ")
        guard comps.count >= 2 else { return nil }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }
        return SstpMessage(method: String(comps[0]), version: String(comps[1]), headers: headers)
    }
}
