import Foundation
import Network
import OSLog

/// TCP 経由で SSTP メッセージを受信する簡易サーバ。
public final class SstpTcpServer {
    private var listener: NWListener?
    public var onRequest: ((String) -> String)?
    private let logger = CompatLogger(subsystem: "Ourin", category: "SSTP_TCP")
    private let timeout: TimeInterval = 5
    private let maxSize = 64 * 1024

    public init() {}

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
        let deadline = DispatchTime.now() + timeout
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if buffer.count > self.maxSize { self.send400(conn); return }
                if DispatchTime.now() > deadline { self.send400(conn); return }
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

    private func send400(_ conn: NWConnection) {
        let resp = "SSTP/1.1 400 Bad Request\r\n\r\n"
        logger.fault("tcp error")
        ServerMetrics.shared.record(duration: 0, error: true)
        conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
    }
}
