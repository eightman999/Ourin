import Foundation
import Network
import OSLog

/// HTTP 経由で SSTP メッセージを受信する簡易サーバ。
public final class SstpHttpServer {
    private var listener: NWListener?
    public var onRequest: ((String) -> String)?
    private let logger = Logger(subsystem: "Ourin", category: "SSTP_HTTP")
    private let timeout: TimeInterval = 5
    private let maxSize = 64 * 1024

    public init() {}

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
        let deadline = DispatchTime.now() + timeout
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if buffer.count > self.maxSize { self.send400(conn); return }
                if DispatchTime.now() > deadline { self.send400(conn); return }
                if isComplete || error != nil { conn.cancel(); return }
                if let headerEnd = buffer.range(of: Data([13,10,13,10])) {
                    let header = buffer.subdata(in: 0..<headerEnd.upperBound)
                    let headersText = String(data: header, encoding: .utf8) ?? ""
                    var contentLength = 0
                    for rawLine in headersText.split(separator: "\n") {
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.lowercased().hasPrefix("content-length:") {
                            let v = line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
                            contentLength = Int(v) ?? 0
                        }
                    }
                    let bodyStart = headerEnd.upperBound
                    if buffer.count - bodyStart >= contentLength {
                        let body = buffer.subdata(in: bodyStart..<bodyStart+contentLength)
                        if let sstp = Self.decode(body) {
                            let start = Date()
                            let respSstp = self.onRequest?(sstp) ?? "SSTP/1.1 204 No Content\r\n\r\n"
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

    private func send400(_ conn: NWConnection) {
        let resp = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n"
        logger.fault("http error")
        ServerMetrics.shared.record(duration: 0, error: true)
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
