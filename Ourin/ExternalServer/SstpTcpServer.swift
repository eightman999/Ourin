import Foundation
import Network
import OSLog

/// TCP 経由で SSTP メッセージを受信する簡易サーバ。
public final class SstpTcpServer {
    private var listener: NWListener?
    public var onRequest: ((String) -> String)?
    private let logger = CompatLogger(subsystem: "Ourin", category: "SSTP_TCP")

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

    public func start(host: String = "127.0.0.1", port: UInt16 = 9801) throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
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
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if buffer.count > self.config.maxSize { self.sendErrorResponse(conn, status: 413); return }
                if DispatchTime.now() > deadline { self.sendErrorResponse(conn, status: 408); return }
                if isComplete || error != nil { conn.cancel(); return }
                if let range = buffer.range(of: Data([13,10,13,10])) {
                    let header = buffer.subdata(in: 0..<range.lowerBound)
                    if let text = Self.decode(header) {
                        let start = Date()
                        let resp = self.onRequest?(text) ?? "SSTP/1.1 204 No Content\r\n\r\n"
                        let duration = Date().timeIntervalSince(start)
                        self.logger.info("tcp request size=\(buffer.count) duration=\(duration)")
                        ServerMetrics.shared.record(duration: duration, error: false)
                        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                        return
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

    private func sendErrorResponse(_ conn: NWConnection, status: Int) {
        let statusText: String
        switch status {
        case 408: statusText = "Request Timeout"
        case 413: statusText = "Payload Too Large"
        default: statusText = "Bad Request"
        }
        let resp = "SSTP/1.1 \(status) \(statusText)\r\n\r\n"
        logger.fault("tcp error status=\(status)")
        ServerMetrics.shared.record(duration: 0, error: true)
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
