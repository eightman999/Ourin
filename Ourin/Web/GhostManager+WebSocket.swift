import Foundation

// MARK: - WebSocket (\![execute,websocket] / \![send,websocket] / \![close,websocket] / \![cancel,websocket])
//
// UKADOC 2.8.05 の WebSocket 系コマンド。接続ごとの状態と UKADOC のイベント
// （Open / Receive / Reconnect / Close / Failure / _SSLInfo）は WebSocketConnection が扱う。
// Ourin 独自拡張として、送信結果を OnExecuteWebSocketSend（R0=送信内容 R1=URL R2="binary"）、
// 送信失敗を OnExecuteWebSocketError（R0=理由 R1=URL）でも通知する。
extension GhostManager {

    /// \![execute,websocket,URL,オプション...] — `--async`、`--header`、`--timeout` は http 系と同じ。
    func executeWebSocket(params: [String]) {
        let options = HTTPCommandOptions(arguments: Array(params.dropFirst()))
        let rawURL = params.first ?? ""
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            Self.emitWebSocketEvent(
                WebSocketConnection.eventName(.failure, customEventID: options.customEventID),
                params: ["Reference0": options.asyncID, "Reference1": rawURL, "Reference2": "invalid url"]
            )
            return
        }
        let key = url.absoluteString

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 同じ URL の接続があれば張り替える（古い接続は userbreak で閉じる）。
            self.webSocketConnections.removeValue(forKey: key)?.cancel()
            let connection = WebSocketConnection(
                url: url,
                asyncID: options.asyncID,
                customEventID: options.customEventID,
                headers: options.headers,
                timeout: options.timeout
            ) { [weak self] name, params in
                Self.emitWebSocketEvent(name, params: params)
                // Close / Failure の後は接続表から外す。
                if name == WebSocketConnection.eventName(.close, customEventID: options.customEventID)
                    || name == WebSocketConnection.eventName(.failure, customEventID: options.customEventID) {
                    DispatchQueue.main.async {
                        guard let self, let current = self.webSocketConnections[key], !current.isActive else { return }
                        self.webSocketConnections.removeValue(forKey: key)
                    }
                }
            }
            self.webSocketConnections[key] = connection
            connection.start()
        }
    }

    /// \![send,websocket,URL,data1,data2,...] / \![send,websocket-binary,URL,base64]
    func sendWebSocket(params: [String], binary: Bool) {
        guard params.count >= 2, let url = URL(string: params[0]) else { return }
        let key = url.absoluteString
        // テキストは data を2つ以上指定すると CRLF で結合する（UKADOC）。
        let payload = binary ? params[1] : params.dropFirst().joined(separator: "\r\n")

        DispatchQueue.main.async { [weak self] in
            // セッションが存在しない場合（接続前・切断後）はタグを無視する。
            guard let self, let connection = self.webSocketConnections[key] else { return }
            let completion: (Error?) -> Void = { error in
                if let error {
                    EventBridge.shared.notify(.OnExecuteWebSocketError, refs: [
                        "reason": error.localizedDescription,
                        "url": key
                    ])
                } else {
                    var sendParams = ["payload": payload, "url": key]
                    if binary { sendParams["dataType"] = "binary" }
                    EventBridge.shared.notify(.OnExecuteWebSocketSend, refs: sendParams)
                }
            }
            if binary {
                guard let data = Data(base64Encoded: payload) else { return }
                connection.send(data: data, completion: completion)
            } else {
                connection.send(text: payload, completion: completion)
            }
        }
    }

    /// \![close,websocket,URL(,status_code)] — Close フレームで正常に切断する。
    func closeWebSocket(params: [String]) {
        guard let url = URL(string: params.first ?? "") else { return }
        let code = params.count >= 2 ? Int(params[1].trimmingCharacters(in: .whitespaces)) ?? 1000 : 1000
        DispatchQueue.main.async { [weak self] in
            self?.webSocketConnections[url.absoluteString]?.close(code: code)
        }
    }

    /// \![cancel,websocket,URL] — Close フレームを送らずに強制中断する（再接続待ち中も含む）。
    func cancelWebSocket(params: [String]) {
        guard let url = URL(string: params.first ?? "") else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webSocketConnections.removeValue(forKey: url.absoluteString)?.cancel()
        }
    }

    /// ゴースト終了時にすべての接続を中断する（UKADOC: Close の R2 は "userbreak"）。
    func cancelAllWebSockets() {
        let connections = webSocketConnections.values
        webSocketConnections.removeAll()
        connections.forEach { $0.cancel() }
    }

    private static func emitWebSocketEvent(_ name: String, params: [String: String]) {
        if let id = EventID(rawValue: name) {
            EventBridge.shared.notify(id, params: params)
        } else {
            EventBridge.shared.notifyCustom(name, params: params)
        }
    }
}
