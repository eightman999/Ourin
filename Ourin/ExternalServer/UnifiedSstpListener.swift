import Foundation
import Network
import OSLog

/// 9801 単一ポートで HTTP と 生 SSTP を多重化して受信するリスナー。
///
/// SSP 互換: 直 SSTP (`SEND SSTP/1.x ...`) と HTTP (`POST /api/sstp/v1 HTTP/1.1`) は
/// 同一ポート(9801)で待ち受け、先頭リクエスト行の終端トークンで判別する。
///   - `... HTTP/1.x` → HTTP として SstpHttpServer に委譲
///   - それ以外（`... SSTP/1.x`）→ 生 SSTP として SstpTcpServer に委譲
/// これにより、HTTP を別ポート(旧 9810)に逃がす必要がなくなる。
public final class UnifiedSstpListener {
    private var listener: NWListener?
    public var onRequest: ((String) -> String)?
    private let logger = CompatLogger(subsystem: "Ourin", category: "SSTP_UNIFIED")

    private var config = Config()
    public struct Config {
        var timeout: TimeInterval = 5
        var maxSize: Int = 64 * 1024
    }

    /// プロトコル別ハンドラ（リスナーは持たず、引き継いだ接続のみ処理する）
    private let tcp = SstpTcpServer()
    private let http = SstpHttpServer()

    public init() {}

    public func updateConfig(_ config: Config) {
        self.config = config
        tcp.updateConfig(.init(timeout: config.timeout, maxSize: config.maxSize))
        http.updateConfig(.init(timeout: config.timeout, maxSize: config.maxSize))
    }

    /// サーバーが稼働中かどうかを返す
    public var isRunning: Bool { listener != nil }

    public func start(host: String = "127.0.0.1", port: UInt16 = 9801) throws {
        let forward: (String) -> String = { [weak self] raw in
            self?.onRequest?(raw) ?? "SSTP/1.1 204 No Content\r\n\r\n"
        }
        tcp.onRequest = forward
        http.onRequest = forward

        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: .global())
            self.route(conn: conn)
        }
        listener?.start(queue: .main)
        logger.info("unified listen \(host):\(port)")
    }

    public func stop() { listener?.cancel(); listener = nil }

    /// 先頭リクエスト行を覗いて HTTP / 生 SSTP のどちらに委譲するか決める。
    private func route(conn: NWConnection) {
        var buffer = Data()
        let deadline = DispatchTime.now() + config.timeout
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if buffer.count > self.config.maxSize { conn.cancel(); return }
                if DispatchTime.now() > deadline { conn.cancel(); return }
                // 先頭行(最初の CRLF まで)が揃ったら判別する。
                if let lineEnd = buffer.range(of: Data([13, 10])) {
                    let lineData = buffer.subdata(in: 0..<lineEnd.lowerBound)
                    let line = (String(data: lineData, encoding: .utf8) ?? "").uppercased()
                    // HTTP リクエスト行は "<METHOD> <path> HTTP/1.x"。生 SSTP は "<METHOD> SSTP/1.x"。
                    if line.contains(" HTTP/") {
                        self.http.adopt(conn: conn, initialBuffer: buffer)
                    } else {
                        self.tcp.adopt(conn: conn, initialBuffer: buffer)
                    }
                    return
                }
                if isComplete || error != nil { conn.cancel(); return }
                readMore()
            }
        }
        readMore()
    }
}
