import Foundation
import Network

/// SSTP over HTTP を実現する簡易ブリッジ
public enum HTTPBridge {
    /// HTTPデータを解析して SSTP として処理できる場合は応答を返す
    public static func tryHandle(data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let range = text.range(of: "\r\n\r\n") else { return nil }
        let headerText = String(text[..<range.lowerBound])
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else { return nil }
        guard let request = parseRequestLine(requestLine) else { return nil }
        guard request.method == "POST", request.path == "/api/sstp/v1" else { return nil }

        var originHeader: String?
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("origin:") {
                let value = line.split(separator: ":", maxSplits: 1)[safe: 1]
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                originHeader = value
            }
        }
        if let originHeader, !isAcceptedOrigin(originHeader) {
            return Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n".utf8)
        }

        let body = String(text[range.upperBound...])
        // ボディ部を SSTP とみなして解析
        var req = SSTPParser.parseRequest(text: body)
        if let originHeader, !originHeader.isEmpty {
            req.headers["SecurityOrigin"] = originHeader
            req.headers["SecurityLevel"] = isLocalOrigin(originHeader) ? "local" : "external"
        }
        let resp = SSTPDispatcher.dispatch(request: req)
        // 互換のため常に HTTP 200 を返す
        let http = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(resp.utf8.count)\r\n\r\n\(resp)"
        return Data(http.utf8)
    }

    private static func parseRequestLine(_ line: String) -> (method: String, path: String)? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3, String(parts[2]).hasPrefix("HTTP/1.") else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        if let url = URL(string: target), !url.path.isEmpty {
            return (method, url.path)
        }
        return (method, target)
    }

    private static func isAcceptedOrigin(_ origin: String) -> Bool {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == "null" { return true }
        return isLocalOrigin(trimmed)
    }

    private static func isLocalOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
