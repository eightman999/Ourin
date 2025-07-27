import Foundation
import Network

/// SSTP/1.xM を扱う TCP リスナー
public final class SSTPListener {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    /// 受信処理用のキュー
    private let queue = DispatchQueue(label: "ourin.sstp.listener")

    public init(port: UInt16 = 9801) {
        self.port = NWEndpoint.Port(rawValue: port) ?? 9801
    }

    /// localhost で待ち受けを開始
    public func start() throws {
        var params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: port)
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener?.start(queue: queue)
    }

    /// 停止処理
    public func stop() {
        listener?.cancel()
        listener = nil
    }

    /// 1 接続ごとの受信処理
    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        read(on: conn, data: Data())
    }

    private func read(on conn: NWConnection, data: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, isComplete, error in
            var buffer = data
            if let chunk = chunk { buffer.append(chunk) }
            if let _ = error { conn.cancel(); return }
            if let resp = HTTPBridge.tryHandle(data: buffer) {
                self?.send(conn, data: resp)
                return
            }
            if let range = buffer.range(of: Data([13,10,13,10])) { // \r\n\r\n
                let header = buffer.subdata(in: 0..<range.lowerBound)
                let body = buffer.subdata(in: range.upperBound..<buffer.count)
                let headerText = String(data: header, encoding: .utf8) ?? ""
                let req = SSTPParser.parseRequest(text: headerText, body: body)
                if req.headers["Charset"] == nil {
                    let resp = "SSTP/1.4 400 Bad Request\r\nCharset: UTF-8\r\n\r\n"
                    self?.send(conn, text: resp)
                } else {
                    let resp = SSTPDispatcher.dispatch(request: req)
                    self?.send(conn, text: resp)
                }
            } else if isComplete {
                conn.cancel()
            } else {
                self?.read(on: conn, data: buffer)
            }
        }
    }

    private func send(_ conn: NWConnection, text: String) {
        send(conn, data: text.data(using: .utf8) ?? Data())
    }

    private func send(_ conn: NWConnection, data: Data) {
        conn.send(content: data, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }
}
