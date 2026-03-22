import Foundation
import Network
import OSLog

/// HTTP 経由で SSTP メッセージを受信する簡易サーバ。
public final class SstpHttpServer {
    private var listener: NWListener?
    public var onRequest: ((String) -> String)?
    private let logger = CompatLogger(subsystem: "Ourin", category: "SSTP_HTTP")

    private var config: Config = Config()

    public struct Config {
        var timeout: TimeInterval = 5
        var maxSize: Int = 64 * 1024
    }

    public init() {}

    public func updateConfig(_ config: Config) {
        self.config = config
    }

    /// サーバーが稼働中かどうかを返す
    public var isRunning: Bool {
        return listener != nil
    }

    public func start(host: String = "127.0.0.1", port: UInt16 = 9810) throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: .global())
            self.handle(conn: conn)
        }
        listener?.start(queue: .main)
        logger.info("listen \(host):\(port)")
    }

    public func stop() { listener?.cancel(); listener = nil }

    private func handle(conn: NWConnection) {
        var buffer = Data()
        let deadline = DispatchTime.now() + config.timeout
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if buffer.count > self.config.maxSize { self.sendErrorResponse(conn, status: 413); return }
                if DispatchTime.now() > deadline { self.sendErrorResponse(conn, status: 408); return }
                if isComplete || error != nil { conn.cancel(); return }
                if let headerEnd = buffer.range(of: Data([13,10,13,10])) {
                    let header = buffer.subdata(in: 0..<headerEnd.upperBound)
                    let headersText = String(data: header, encoding: .utf8) ?? ""
                    let headerLines = headersText.split(separator: "\n").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    guard let requestLine = headerLines.first,
                          let request = Self.parseRequestLine(requestLine) else {
                        self.sendErrorResponse(conn, status: 400)
                        return
                    }
                    guard request.method == "POST" else {
                        self.sendErrorResponse(conn, status: 405)
                        return
                    }
                    guard request.path == "/api/sstp/v1" else {
                        self.sendErrorResponse(conn, status: 404)
                        return
                    }

                    var contentLength = 0
                    var hasContentLength = false
                    var originHeader: String?
                    for line in headerLines.dropFirst() {
                        if line.lowercased().hasPrefix("content-length:") {
                            let v = line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
                            contentLength = Int(v) ?? 0
                            hasContentLength = true
                        } else if line.lowercased().hasPrefix("origin:") {
                            let v = line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
                            originHeader = v
                        }
                    }
                    guard hasContentLength else {
                        self.sendErrorResponse(conn, status: 411)
                        return
                    }
                    if let originHeader, !Self.isAcceptedOrigin(originHeader) {
                        self.sendErrorResponse(conn, status: 403)
                        return
                    }
                    let bodyStart = headerEnd.upperBound
                    if buffer.count - bodyStart >= contentLength {
                        let body = buffer.subdata(in: bodyStart..<bodyStart+contentLength)
                        if let sstp = Self.decode(body) {
                            let start = Date()
                            let routedSstp = Self.injectSecurityHeaders(into: sstp, origin: originHeader)
                            let respSstp = self.onRequest?(routedSstp) ?? "SSTP/1.1 204 No Content\r\n\r\n"
                            let duration = Date().timeIntervalSince(start)
                            let lines = [
                                "HTTP/1.1 200 OK\r",
                                "Content-Type: text/plain; charset=UTF-8\r",
                                "Content-Length: \(respSstp.utf8.count)\r",
                                "\r",
                                respSstp
                            ]
                            let http = lines.joined()
                            self.logger.info("http size=\(buffer.count) duration=\(duration)")
                            ServerMetrics.shared.record(duration: duration, error: false)
                            conn.send(content: http.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                            return
                        }
                    }
                }
                readMore()
            }
        }
        readMore()
    }

    private static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .shiftJIS)
    }

    private static func injectSecurityHeaders(into sstp: String, origin: String?) -> String {
        guard let origin, !origin.isEmpty else { return sstp }
        let level = isLocalOrigin(origin) ? "local" : "external"
        let headers = "SecurityOrigin: \(origin)\r\nSecurityLevel: \(level)\r\n"
        if let range = sstp.range(of: "\r\n\r\n") {
            var result = sstp
            result.insert(contentsOf: headers, at: range.lowerBound)
            return result
        }
        return sstp + "\r\n" + headers + "\r\n"
    }

    private static func isLocalOrigin(_ origin: String) -> Bool {
        guard let url = URL(string: origin), let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func isAcceptedOrigin(_ origin: String) -> Bool {
        let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == "null" { return true }
        return isLocalOrigin(trimmed)
    }

    struct HttpRequestLine {
        let method: String
        let path: String
    }

    static func parseRequestLine(_ line: String) -> HttpRequestLine? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        guard String(parts[2]).hasPrefix("HTTP/1.") else { return nil }
        guard let url = URL(string: target), let path = url.path.isEmpty ? nil : url.path else {
            return HttpRequestLine(method: method, path: target)
        }
        return HttpRequestLine(method: method, path: path)
    }

    private func sendErrorResponse(_ conn: NWConnection, status: Int) {
        let statusText: String
        switch status {
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 408: statusText = "Request Timeout"
        case 411: statusText = "Length Required"
        case 413: statusText = "Payload Too Large"
        default: statusText = "Bad Request"
        }
        let resp = "HTTP/1.1 \(status) \(statusText)\r\nContent-Length: 0\r\n\r\n"
        logger.fault("http error status=\(status)")
        ServerMetrics.shared.record(duration: 0, error: true)
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
