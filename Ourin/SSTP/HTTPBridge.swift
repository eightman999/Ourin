import Foundation
import Network

/// SSTP over HTTP を実現する簡易ブリッジ
public enum HTTPBridge {
    /// HTTPデータを解析して SSTP として処理できる場合は応答を返す
    public static func tryHandle(data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard text.hasPrefix("POST "), text.contains(" HTTP/1.") else { return nil }
        guard let range = text.range(of: "\r\n\r\n") else { return nil }
        let body = String(text[range.upperBound...])
        // ボディ部を SSTP とみなして解析
        let req = SSTPParser.parseRequest(text: body)
        let resp = SSTPDispatcher.dispatch(request: req)
        // 互換のため常に HTTP 200 を返す
        let http = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(resp.utf8.count)\r\n\r\n\(resp)"
        return Data(http.utf8)
    }
}
