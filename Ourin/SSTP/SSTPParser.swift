import Foundation

/// SSTP メッセージの解析・生成を行うユーティリティ
public enum SSTPParser {
    /// 生のリクエスト文字列と任意のボディを解析する
    public static func parseRequest(text: String, body: Data = Data()) -> SSTPRequest {
        // SSTP/1.xM は CRLF を規定するが、一部デファクトツールは LF のみ送信する。
        // ヘッダ終端（空行）を検出できず 408 タイムアウトになるのを防ぐため、
        // 先頭に CR の無い LF を CRLF に正規化してから分割する（寛容な受信）。
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let lines = normalized.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return SSTPRequest(body: body) }
        let comps = first.split(separator: " ")
        var req = SSTPRequest(body: body)
        if comps.count >= 2 {
            req.method = String(comps[0])
            req.version = String(comps[1])
        }
        var sawBlankLine = false
        var bodyLines: [String] = []
        for line in lines.dropFirst() {
            // 空行（ヘッダ終端）以降は本文として保持する。従来はここで break して破棄していた。
            if sawBlankLine {
                bodyLines.append(line)
                continue
            }
            if line.isEmpty {
                sawBlankLine = true
                continue
            }
            if let idx = line.firstIndex(of: ":") {
                let key = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                // IfGhost/Script の対応付けや重複 Option のため受信順のまま追加する
                req.appendHeader(key, value)
            }
        }
        // 明示的な body 引数が無く、空行以降に内容があればそれを本文として取り込む。
        // 終端 CRLF 由来の末尾空行は除去する（標準的な「ヘッダのみ」リクエストでは body は空のまま）。
        if body.isEmpty && !bodyLines.isEmpty {
            while let last = bodyLines.last, last.isEmpty { bodyLines.removeLast() }
            if !bodyLines.isEmpty {
                req.body = Data(bodyLines.joined(separator: "\r\n").utf8)
            }
        }
        return req
    }
}
