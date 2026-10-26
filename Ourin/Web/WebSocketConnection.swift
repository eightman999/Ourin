import Foundation

/// `\![execute,websocket]` で開いた 1 本の WebSocket 接続（UKADOC 2.8.05 準拠）。
///
/// UKADOC のイベントと Reference:
///   OnExecuteWebSocketOpen       R0=--async 識別子 R1=URL R2="200"（初回接続時のみ）
///   OnExecuteWebSocketReceive    R0=識別子 R1=URL R2=opcode("1"=テキスト/"2"=バイナリ) R3=データ
///   OnExecuteWebSocketReconnect  R0=識別子 R1=URL R2="200"（エラー切断後の自動再接続成功）
///   OnExecuteWebSocketClose      R0=識別子 R1=URL R2=切断要因（"1000" 等のコード、強制中断は "userbreak"）
///   OnExecuteWebSocketFailure    R0=識別子 R1=URL R2=エラー内容（再接続全失敗は "reconnect failed"）
///   OnExecuteWebSocket_SSLInfo   R0=識別子 R1=URL R2=ステータス R3=TLS バージョン（名前は置き換えない）
/// `--async` が "On" で始まる場合、Open/Reconnect/Close/Failure は ID+接尾辞、Receive は ID そのものになる。
final class WebSocketConnection: NSObject, URLSessionWebSocketDelegate {
    enum Event: String {
        case open = "OnExecuteWebSocketOpen"
        case receive = "OnExecuteWebSocketReceive"
        case reconnect = "OnExecuteWebSocketReconnect"
        case close = "OnExecuteWebSocketClose"
        case failure = "OnExecuteWebSocketFailure"
        case sslInfo = "OnExecuteWebSocket_SSLInfo"
    }

    /// エラー切断後の自動再接続の待ち時間（秒）。UKADOC の「5回」に合わせて 5 要素。
    static var reconnectDelays: [TimeInterval] = [1, 2, 4, 8, 16]

    let url: URL
    let asyncID: String
    let customEventID: String?
    private let headers: [(String, String)]
    private let timeout: TimeInterval?
    /// イベント名と ReferenceN を受け取る送出先。GhostManager が EventBridge へ橋渡しする。
    private let emit: (String, [String: String]) -> Void

    private enum State {
        case connecting
        case open
        case reconnecting
        case closing(code: Int)
        case finished
    }

    private var state: State = .connecting
    private var everOpened = false
    private var reconnectAttempt = 0
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var reconnectWork: DispatchWorkItem?
    private var lastTLSVersion = ""
    private let queue = DispatchQueue(label: "jp.ourin.websocket")

    init(url: URL,
         asyncID: String,
         customEventID: String?,
         headers: [(String, String)] = [],
         timeout: TimeInterval? = nil,
         emit: @escaping (String, [String: String]) -> Void) {
        self.url = url
        self.asyncID = asyncID
        self.customEventID = customEventID
        self.headers = headers
        self.timeout = timeout
        self.emit = emit
    }

    /// イベント名を UKADOC の `--async` 規則で決める。
    static func eventName(_ event: Event, customEventID: String?) -> String {
        guard let customEventID, event != .sslInfo else { return event.rawValue }
        switch event {
        case .open: return customEventID + "Open"
        case .receive: return customEventID
        case .reconnect: return customEventID + "Reconnect"
        case .close: return customEventID + "Close"
        case .failure: return customEventID + "Failure"
        case .sslInfo: return event.rawValue
        }
    }

    /// 受信テキストの改行をバイト値1へ置き換える（UKADOC: Receive の Reference3）。
    static func receiveText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\u{1}")
            .replacingOccurrences(of: "\n", with: "\u{1}")
            .replacingOccurrences(of: "\r", with: "\u{1}")
    }

    var isActive: Bool {
        queue.sync {
            if case .finished = state { return false }
            return true
        }
    }

    func start() {
        queue.async { self.connect() }
    }

    /// \![send,websocket,URL,data1,data2,...]（2つ以上は CRLF で結合）。
    func send(text: String, completion: ((Error?) -> Void)? = nil) {
        queue.async {
            guard case .open = self.state, let task = self.task else { return }
            task.send(.string(text)) { completion?($0) }
        }
    }

    /// \![send,websocket-binary,URL,base64data]
    func send(data: Data, completion: ((Error?) -> Void)? = nil) {
        queue.async {
            guard case .open = self.state, let task = self.task else { return }
            task.send(.data(data)) { completion?($0) }
        }
    }

    /// \![close,websocket,URL(,code)] — Close フレームを送り、応答を待ってから切断する。
    func close(code: Int = 1000) {
        queue.async {
            switch self.state {
            case .finished, .closing:
                return
            case .reconnecting, .connecting:
                // まだ開いていない（または再接続待ち）なら、送る Close フレームが無いので即時に終える。
                self.finish(closeReason: String(code))
            case .open:
                self.state = .closing(code: code)
                let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
                self.task?.cancel(with: closeCode, reason: nil)
                // サーバーが Close に応えない場合でも、最終的に Close を通知して終える。
                self.queue.asyncAfter(deadline: .now() + 5) {
                    if case .closing = self.state { self.finish(closeReason: String(code)) }
                }
            }
        }
    }

    /// \![cancel,websocket,URL] またはゴースト終了 — Close フレームなしで即時に中断する。
    func cancel() {
        queue.async {
            if case .finished = self.state { return }
            self.task?.cancel()
            self.finish(closeReason: "userbreak")
        }
    }

    // MARK: - 接続

    private func connect() {
        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.addValue(value, forHTTPHeaderField: name)
        }
        if let timeout, timeout > 0 {
            request.timeoutInterval = timeout
        }
        let delegateQueue = OperationQueue()
        delegateQueue.underlyingQueue = queue
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard self.task === task, case .open = self.state else { return }
                // 失敗時の処理は didCompleteWithError / didCloseWith に任せる（二重通知を避ける）。
                guard case .success(let message) = result else { return }
                switch message {
                case .string(let text):
                    self.send(.receive, extra: ["1", Self.receiveText(text)])
                case .data(let data):
                    self.send(.receive, extra: ["2", data.base64EncodedString()])
                @unknown default:
                    break
                }
                self.receiveLoop(task)
            }
        }
    }

    private func scheduleReconnectOrFail() {
        guard reconnectAttempt < Self.reconnectDelays.count else {
            send(.failure, extra: ["reconnect failed"])
            finish(closeReason: nil)
            return
        }
        let delay = Self.reconnectDelays[reconnectAttempt]
        reconnectAttempt += 1
        state = .reconnecting
        // 失敗した試行のセッションは捨て、遅延後に新しいセッションで張り直す。
        session?.invalidateAndCancel()
        session = nil
        task = nil
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .reconnecting = self.state else { return }
            self.connect()
        }
        reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 接続を終える。closeReason があれば Close を通知する（Failure 時は通知しない）。
    private func finish(closeReason: String?) {
        if case .finished = state { return }
        state = .finished
        reconnectWork?.cancel()
        reconnectWork = nil
        session?.invalidateAndCancel()
        session = nil
        task = nil
        if let closeReason {
            send(.close, extra: [closeReason])
        }
    }

    private func send(_ event: Event, extra: [String]) {
        var params = ["Reference0": asyncID, "Reference1": url.absoluteString]
        for (offset, value) in extra.enumerated() {
            params["Reference\(offset + 2)"] = value
        }
        emit(Self.eventName(event, customEventID: customEventID), params)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        guard webSocketTask === task else { return }
        let reconnected = everOpened
        everOpened = true
        state = .open
        reconnectAttempt = 0
        if !reconnected {
            if url.scheme?.lowercased() == "wss" {
                send(.sslInfo, extra: ["101", lastTLSVersion])
            }
            send(.open, extra: ["200"])
        } else {
            send(.reconnect, extra: ["200"])
        }
        receiveLoop(webSocketTask)
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        guard webSocketTask === task else { return }
        switch state {
        case .closing(let code):
            finish(closeReason: String(code))
        case .finished:
            return
        default:
            // サーバーからの Close フレームによる正常切断。
            finish(closeReason: String(closeCode.rawValue))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        if let version = metrics.transactionMetrics.reversed().compactMap({ $0.negotiatedTLSProtocolVersion }).first {
            lastTLSVersion = Self.tlsVersionName(version)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task else { return }
        switch state {
        case .finished:
            return
        case .closing(let code):
            finish(closeReason: String(code))
        case .connecting:
            // 初回接続で HTTP 101 Upgrade に失敗した。
            if url.scheme?.lowercased() == "wss", !lastTLSVersion.isEmpty {
                let status = (task.response as? HTTPURLResponse).map { String($0.statusCode) } ?? "0"
                send(.sslInfo, extra: [status, lastTLSVersion])
            }
            send(.failure, extra: [Self.errorText(error, response: task.response)])
            finish(closeReason: nil)
        case .open, .reconnecting:
            // 接続中のエラー切断、または再接続の試行失敗 → 自動再接続（最大 5 回）。
            scheduleReconnectOrFail()
        }
    }

    // MARK: - 補助

    private static func errorText(_ error: Error?, response: URLResponse?) -> String {
        if let http = response as? HTTPURLResponse, http.statusCode != 101 {
            return "HTTP \(http.statusCode)"
        }
        if let urlError = error as? URLError, urlError.code == .timedOut { return "timeout" }
        let text = error?.localizedDescription ?? ""
        return text.isEmpty ? "connection_failed" : text
    }

    static func tlsVersionName(_ value: tls_protocol_version_t) -> String {
        switch value {
        case .TLSv10: return "TLSv1"
        case .TLSv11: return "TLSv1.1"
        case .TLSv12: return "TLSv1.2"
        case .TLSv13: return "TLSv1.3"
        default: return ""
        }
    }
}
