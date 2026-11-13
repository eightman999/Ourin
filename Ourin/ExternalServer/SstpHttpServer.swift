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

    // 仕様(SSTP/1.xM)では HTTP も SSTP と同じ 9801 を多重化して使う。
    // 単体起動時の既定も 9801 に揃える（通常は UnifiedSstpListener 経由で adopt される）。
    public func start(host: String = "127.0.0.1", port: UInt16 = 9801) throws {
        listener = try SstpTcpServer.makeListener(host: host, port: port)
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: .global())
            self.handle(conn: conn)
        }
        listener?.start(queue: .main)
        logger.info("listen \(host):\(port)")
    }

    public func stop() { listener?.cancel(); listener = nil }

    /// 多重化リスナーから、先頭バイトを読み取り済みの接続を引き継いで HTTP として処理する。
    func adopt(conn: NWConnection, initialBuffer: Data) {
        handle(conn: conn, initialBuffer: initialBuffer)
    }

    private func handle(conn: NWConnection, initialBuffer: Data = Data()) {
        var buffer = initialBuffer
        let deadline = DispatchTime.now() + config.timeout
        // ヘッダ＋本文が揃っていれば処理して true を返す。途中なら false（追加読込が必要）。
        func tryProcess() -> Bool {
            let body: Data
            let originHeader: String?
            switch Self.evaluateRequest(buffer, maxSize: self.config.maxSize) {
            case .incomplete:
                return false
            case .error(let status):
                self.sendErrorResponse(conn, status: status)
                return true
            case .ready(let readyBody, let origin):
                body = readyBody
                originHeader = origin
            }
            guard let sstp = Self.decode(body) else { return false }
            let start = Date()
            let routedSstp = Self.injectSecurityHeaders(into: sstp, origin: originHeader)
            let respSstp = self.onRequest?(routedSstp) ?? "SSTP/1.1 204 No Content\r\n\r\n"
            let duration = Date().timeIntervalSince(start)
            let lines = [
                "HTTP/1.1 200 OK\r\n",
                "Content-Type: text/plain; charset=UTF-8\r\n",
                "Content-Length: \(respSstp.utf8.count)\r\n",
                "\r\n",
                respSstp
            ]
            let http = lines.joined()
            self.logger.info("http size=\(buffer.count) duration=\(duration)")
            ServerMetrics.shared.record(duration: duration, error: false)
            conn.send(content: http.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
            return true
        }
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if DispatchTime.now() > deadline { self.sendErrorResponse(conn, status: 408); return }
                if tryProcess() { return }
                if isComplete || error != nil { conn.cancel(); return }
                readMore()
            }
        }
        if tryProcess() { return }
        readMore()
    }

    enum HttpRequestEvaluation: Equatable {
        /// ヘッダまたは本文が未着で追加読込が必要
        case incomplete
        /// HTTP エラーステータスで応答して切断する
        case error(Int)
        case ready(body: Data, origin: String?)
    }

    /// 受信バッファを HTTP SSTP 要求として検証し、本文を切り出す。
    static func evaluateRequest(_ buffer: Data, maxSize: Int) -> HttpRequestEvaluation {
        if buffer.count > maxSize { return .error(413) }
        guard let headerEnd = buffer.range(of: Data([13,10,13,10])) else { return .incomplete }
        let header = buffer.subdata(in: 0..<headerEnd.upperBound)
        let headersText = String(data: header, encoding: .utf8) ?? ""
        let headerLines = splitHeaderLines(headersText)
        guard let requestLine = headerLines.first,
              let request = parseRequestLine(requestLine) else {
            return .error(400)
        }
        guard request.method == "POST" else { return .error(405) }
        guard request.path == "/api/sstp/v1" else { return .error(404) }

        var contentLengthValues: [String] = []
        var originHeader: String?
        for line in headerLines.dropFirst() {
            guard let field = splitHeaderField(line) else { continue }
            switch field.name.lowercased() {
            case "content-length": contentLengthValues.append(field.value)
            case "origin": originHeader = field.value
            default: break
            }
        }
        let contentLength: Int
        switch validateContentLength(contentLengthValues, maxSize: maxSize) {
        case .valid(let length): contentLength = length
        case .missing: return .error(411)
        case .invalid: return .error(400)
        case .tooLarge: return .error(413)
        }
        if let originHeader, !isAcceptedOrigin(originHeader) { return .error(403) }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= contentLength else { return .incomplete }
        return .ready(body: buffer.subdata(in: bodyStart..<bodyStart+contentLength), origin: originHeader)
    }

    /// `Name: value` を名前と値に分ける。値が空（`Content-Length:`）でも範囲外アクセスしない。
    static func splitHeaderField(_ line: String) -> (name: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let name = line[..<colon].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (name, value)
    }

    private static func decode(_ data: Data) -> String? {
        // 宣言された Charset を尊重しつつ、未指定時は UTF-8→Shift_JIS の順でフォールバック
        // （CP932受理設定がfalseの場合はShift_JISフォールバックをスキップする）
        EncodingNormalizer.decode(data, charset: EncodingAdapter.declaredCharset(in: data))
    }

    /// HTTP の Origin から判定した SecurityOrigin / SecurityLevel を SSTP 本文へ入れる。
    /// 本文に既にある SecurityOrigin / SecurityLevel は送信者が自由に書けるため、すべて取り除いてから入れる。
    /// （残すと先頭値を読む経路と後勝ちで読む経路で判定が食い違い、localhost を偽装できる）
    static func injectSecurityHeaders(into sstp: String, origin: String?) -> String {
        guard let origin, !origin.isEmpty else { return sstp }
        let level = isLocalOrigin(origin) ? "local" : "external"
        let injected = ["SecurityOrigin: \(origin)", "SecurityLevel: \(level)"]
        // SSTPParser.parseRequest と同じ規則（LF のみも CRLF に正規化して分割）で行を解釈する。
        let normalized = sstp.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let lines = normalized.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        var headerLines: [String] = []
        var bodyLines: [String]? = nil
        for (index, line) in lines.enumerated() {
            if index == 0 { headerLines.append(line); continue }
            if line.isEmpty {
                bodyLines = Array(lines[(index + 1)...])
                break
            }
            if !isSecurityHeaderLine(line) { headerLines.append(line) }
        }
        // 最終ヘッダの後ろに 1 行ずつ追加し、空行でヘッダを閉じる。本文はそのまま残す。
        var result = (headerLines + injected).joined(separator: "\r\n") + "\r\n\r\n"
        if let bodyLines { result += bodyLines.joined(separator: "\r\n") }
        return result
    }

    private static func isSecurityHeaderLine(_ line: String) -> Bool {
        guard let idx = line.firstIndex(of: ":") else { return false }
        let key = line[..<idx].trimmingCharacters(in: .whitespaces)
        return key.caseInsensitiveCompare("SecurityOrigin") == .orderedSame
            || key.caseInsensitiveCompare("SecurityLevel") == .orderedSame
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

    enum ContentLengthValidation: Equatable {
        case valid(Int)
        case missing
        case invalid
        case tooLarge
    }

    /// Content-Length ヘッダ値を検証する。
    /// 負数・非数値・値の食い違う重複は 400、`maxSize` 超過は 413 とし、
    /// 本文切り出しの Range が不正にならないことを保証する。
    static func validateContentLength(_ values: [String], maxSize: Int) -> ContentLengthValidation {
        guard let first = values.first else { return .missing }
        guard values.allSatisfy({ $0 == first }),
              !first.isEmpty,
              first.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return .invalid
        }
        guard let length = Int(first) else { return .tooLarge }
        guard length <= maxSize else { return .tooLarge }
        return .valid(length)
    }

    struct HttpRequestLine {
        let method: String
        let path: String
    }

    /// ヘッダ部を行に分割する。
    /// `.split(separator: "\n")` は CRLF ("\r\n") を単一の Character として扱うため、
    /// HTTP の CRLF ヘッダでは一切分割されず Content-Length を見落として常に 411 になる。
    /// `components(separatedBy: .newlines)` は CR/LF/CRLF を正しく分割する（SurfaceTableParser と同じ手法）。
    static func splitHeaderLines(_ headersText: String) -> [String] {
        headersText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
