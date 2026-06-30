import Foundation

// MARK: - WebSocket (\![execute,websocket] / \![send,websocket] / \![close,websocket] / \![cancel,websocket])
//
// UKADOC のさくらスクリプト WebSocket 系コマンドを URLSessionWebSocketTask で実装する。
// 受信・状態変化は SHIORI イベントへ通知する（Ourin のイベント写像）:
//   OnExecuteWebSocketOpen     Reference0=URL
//   OnExecuteWebSocketReceive  Reference0=本文（テキスト、またはバイナリ時は Base64）, Reference1=URL, Reference2="binary"（バイナリ時）
//   OnExecuteWebSocketClose    Reference0=URL
//   OnExecuteWebSocketError    Reference0=理由, Reference1=URL
//   OnExecuteWebSocketSend     Reference0=送信内容, Reference1=URL, Reference2="binary"（バイナリ時）
//   OnExecuteWebSocketState    Reference0=状態(open/closing/closed/error), Reference1=URL
//
// 既存の OnExecuteHTTP* と同じ命名規約（OnExecute<種別><段階>）に揃えている。
extension GhostManager {

    /// \![execute,websocket,URL] — 接続を開き受信ループを開始する。
    func executeWebSocket(params: [String]) {
        guard let rawURL = params.first,
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            let bad = params.first ?? ""
            EventBridge.shared.notify(.OnExecuteWebSocketError, params: [
                "Reference0": "invalid_url",
                "Reference1": bad
            ])
            return
        }
        let key = url.absoluteString

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // 既存接続があれば張り替える
            if let existing = self.webSocketTasks[key] {
                existing.cancel(with: .goingAway, reason: nil)
                self.webSocketTasks.removeValue(forKey: key)
            }
            let task = URLSession.shared.webSocketTask(with: url)
            self.webSocketTasks[key] = task
            task.resume()
            // delegate を持たない簡易実装のため、resume 直後に楽観的に Open を通知する。
            EventBridge.shared.notify(.OnExecuteWebSocketOpen, params: ["Reference0": key])
            EventBridge.shared.notify(.OnExecuteWebSocketState, params: [
                "Reference0": "open",
                "Reference1": key
            ])
            self.receiveNextWebSocketMessage(task, key: key)
        }
    }

    /// \![send,websocket,URL,data] / \![send,websocket-binary,URL,base64]
    func sendWebSocket(params: [String], binary: Bool) {
        guard params.count >= 2, let url = URL(string: params[0]) else { return }
        let key = url.absoluteString
        let payload = params[1]

        DispatchQueue.main.async { [weak self] in
            guard let self, let task = self.webSocketTasks[key] else { return }
            let message: URLSessionWebSocketTask.Message
            if binary {
                let data = Data(base64Encoded: payload) ?? Data(payload.utf8)
                message = .data(data)
            } else {
                message = .string(payload)
            }
            task.send(message) { error in
                if let error {
                    EventBridge.shared.notify(.OnExecuteWebSocketError, params: [
                        "Reference0": error.localizedDescription,
                        "Reference1": key
                    ])
                } else {
                    var sendParams: [String: String] = [
                        "Reference0": payload,
                        "Reference1": key
                    ]
                    if binary {
                        sendParams["Reference2"] = "binary"
                    }
                    EventBridge.shared.notify(.OnExecuteWebSocketSend, params: sendParams)
                }
            }
        }
    }

    /// \![close,websocket,URL] — 正常クローズ（close フレーム送出）。
    func closeWebSocket(params: [String]) {
        finishWebSocket(params: params, normal: true)
    }

    /// \![cancel,websocket,URL] — 即時キャンセル（close フレームなし）。
    func cancelWebSocket(params: [String]) {
        finishWebSocket(params: params, normal: false)
    }

    private func finishWebSocket(params: [String], normal: Bool) {
        guard let url = URL(string: params.first ?? "") else { return }
        let key = url.absoluteString
        DispatchQueue.main.async { [weak self] in
            guard let self, let task = self.webSocketTasks[key] else { return }
            self.webSocketTasks.removeValue(forKey: key)
            if normal {
                task.cancel(with: .normalClosure, reason: nil)
            } else {
                task.cancel()
            }
            EventBridge.shared.notify(.OnExecuteWebSocketState, params: [
                "Reference0": normal ? "closed" : "closing",
                "Reference1": key
            ])
            EventBridge.shared.notify(.OnExecuteWebSocketClose, params: ["Reference0": key])
        }
    }

    /// 受信ループ。1メッセージ受信ごとに自身を再スケジュールする。
    private func receiveNextWebSocketMessage(_ task: URLSessionWebSocketTask, key: String) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                // すでに閉じられている場合は何もしない
                guard self.webSocketTasks[key] === task else { return }
                switch result {
                case .failure(let error):
                    EventBridge.shared.notify(.OnExecuteWebSocketError, params: [
                        "Reference0": error.localizedDescription,
                        "Reference1": key
                    ])
                    EventBridge.shared.notify(.OnExecuteWebSocketState, params: [
                        "Reference0": "error",
                        "Reference1": key
                    ])
                    self.webSocketTasks.removeValue(forKey: key)
                case .success(let message):
                    switch message {
                    case .string(let text):
                        EventBridge.shared.notify(.OnExecuteWebSocketReceive, params: [
                            "Reference0": text,
                            "Reference1": key
                        ])
                    case .data(let data):
                        EventBridge.shared.notify(.OnExecuteWebSocketReceive, params: [
                            "Reference0": data.base64EncodedString(),
                            "Reference1": key,
                            "Reference2": "binary"
                        ])
                    @unknown default:
                        break
                    }
                    // 接続が生きていれば次の受信を待つ
                    self.receiveNextWebSocketMessage(task, key: key)
                }
            }
        }
    }
}
