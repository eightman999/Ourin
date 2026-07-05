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
        listener = try Self.makeListener(host: host, port: port)
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: .global())
            self.handle(conn: conn)
        }
        listener?.start(queue: .main)
        logger.info("listen \(host):\(port)")
    }

    /// host を尊重して `NWListener` を生成する。
    /// `127.0.0.1` / `localhost` / `::1` 等の特定アドレス指定時は `requiredLocalEndpoint` で
    /// そのアドレスにのみバインドする（既定は localhost のみ）。`0.0.0.0` / `::` / 空 のときだけ全 IF で待ち受ける。
    static func makeListener(host: String, port: UInt16) throws -> NWListener {
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        let bindsAllInterfaces = trimmed.isEmpty || trimmed == "0.0.0.0" || trimmed == "::" || trimmed == "*"
        let params = NWParameters.tcp
        if bindsAllInterfaces {
            return try NWListener(using: params, on: nwPort)
        }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(trimmed), port: nwPort)
        return try NWListener(using: params)
    }

    public func stop() { listener?.cancel(); listener = nil }

    /// 多重化リスナーから、先頭バイトを読み取り済みの接続を引き継いで生 SSTP として処理する。
    func adopt(conn: NWConnection, initialBuffer: Data) {
        handle(conn: conn, initialBuffer: initialBuffer)
    }

    private func handle(conn: NWConnection, initialBuffer: Data = Data()) {
        var buffer = initialBuffer
        let deadline = DispatchTime.now() + config.timeout
        // バッファに完全なリクエスト（CRLF+空行終端）が揃っていれば処理して true を返す。
        func tryProcess() -> Bool {
            if buffer.count > self.config.maxSize { self.sendErrorResponse(conn, status: 413); return true }
            if buffer.range(of: Data([13,10,13,10])) != nil {
                // ヘッダ終端（空行）が揃ったら処理する。空行以降の本文（SSTP body）も含めて
                // バッファ全体を SSTP スタックへ渡す。ヘッダだけ渡すと body が破棄される
                // （SSTPParser は空行以降を body として取り込む）。
                if let text = Self.decode(buffer) {
                    let start = Date()
                    let resp = self.onRequest?(text) ?? "SSTP/1.1 204 No Content\r\n\r\n"
                    let duration = Date().timeIntervalSince(start)
                    self.logger.info("tcp request size=\(buffer.count) duration=\(duration)")
                    ServerMetrics.shared.record(duration: duration, error: false)
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                    return true
                }
            }
            return false
        }
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if DispatchTime.now() > deadline { self.sendErrorResponse(conn, status: 408); return }
                if tryProcess() { return }
                if isComplete || error != nil { conn.cancel(); return }
                readMore()
            }
        }
        // 引き継いだバッファに既に全リクエストが含まれている場合があるので先に検査する。
        if tryProcess() { return }
        readMore()
    }

    private static func decode(_ data: Data) -> String? {
        // 宣言された Charset を尊重しつつ、未指定時は UTF-8→Shift_JIS の順でフォールバック
        // （CP932受理設定がfalseの場合はShift_JISフォールバックをスキップする）
        let charset = EncodingAdapter.detectCharset(in: data)
        return EncodingAdapter.decode(data, charset: charset)
            ?? String(data: data, encoding: .utf8)
            ?? (EncodingNormalizer.acceptsCP932 ? String(data: data, encoding: .shiftJIS) : nil)
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
