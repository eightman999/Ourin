import Foundation

/// SSTP メッセージの解析・生成を行うユーティリティ
public enum SSTPParser {
    /// 生のリクエスト文字列と任意のボディを解析する
    public static func parseRequest(text: String, body: Data = Data()) -> SSTPRequest {
        let lines = text.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return SSTPRequest(body: body) }
        let comps = first.split(separator: " ")
        var req = SSTPRequest(body: body)
        if comps.count >= 2 {
            req.method = String(comps[0])
            req.version = String(comps[1])
        }
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                req.headers[key] = value
            }
        }
        return req
    }
}
