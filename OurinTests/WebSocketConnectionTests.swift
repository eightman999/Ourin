import Foundation
import Network
import Testing
@testable import Ourin

/// テスト用のローカル WebSocket サーバ（Network framework）。
private final class LocalWebSocketServer: @unchecked Sendable {
    enum OnConnect {
        /// テキスト（改行入り）とバイナリを1回ずつ送る。
        case greet
        /// Close フレームを送らずに接続を切る（エラー切断）。
        case dropAbruptly
        /// 何もしない。
        case idle
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "jp.ourin.tests.wsserver")
    private var connections: [NWConnection] = []
    private let lock = NSLock()
    private var acceptedCount = 0
    var onConnect: (Int) -> OnConnect

    init(onConnect: @escaping (Int) -> OnConnect) throws {
        self.onConnect = onConnect
        let parameters = NWParameters.tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
    }

    var accepted: Int {
        lock.lock(); defer { lock.unlock() }
        return acceptedCount
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: self?.listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.lock()
        let current = connections
        connections.removeAll()
        lock.unlock()
        current.forEach { $0.forceCancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        acceptedCount += 1
        let index = acceptedCount
        connections.append(connection)
        lock.unlock()
        let action = onConnect(index)
        connection.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let self else { return }
            switch action {
            case .greet:
                self.send(connection, text: "hello\nworld")
                self.send(connection, data: Data([0x01, 0x02, 0x03]))
            case .dropAbruptly:
                self.queue.asyncAfter(deadline: .now() + 0.2) { connection.forceCancel() }
            case .idle:
                break
            }
            self.receive(connection)
        }
        connection.start(queue: queue)
    }

    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] _, _, _, error in
            guard error == nil else { return }
            self?.receive(connection)
        }
    }

    private func send(_ connection: NWConnection, text: String) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func send(_ connection: NWConnection, data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
        let context = NWConnection.ContentContext(identifier: "binary", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }
}

/// 受け取ったイベントを記録する。
private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(name: String, params: [String: String])] = []

    func record(_ name: String, _ params: [String: String]) {
        lock.lock(); storage.append((name, params)); lock.unlock()
    }

    var events: [(name: String, params: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func names() -> [String] { events.map(\.name) }

    func first(_ name: String) -> [String: String]? {
        events.first { $0.name == name }?.params
    }
}

private func waitForWebSocket(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { break }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}

@Suite(.serialized)
struct WebSocketConnectionTests {
    @Test
    func asyncEventNamesFollowUkadoc() {
        typealias C = WebSocketConnection
        #expect(C.eventName(.open, customEventID: nil) == "OnExecuteWebSocketOpen")
        #expect(C.eventName(.open, customEventID: "OnChat") == "OnChatOpen")
        #expect(C.eventName(.receive, customEventID: "OnChat") == "OnChat")
        #expect(C.eventName(.reconnect, customEventID: "OnChat") == "OnChatReconnect")
        #expect(C.eventName(.close, customEventID: "OnChat") == "OnChatClose")
        #expect(C.eventName(.failure, customEventID: "OnChat") == "OnChatFailure")
        // _SSLInfo は --async で置き換えない。
        #expect(C.eventName(.sslInfo, customEventID: "OnChat") == "OnExecuteWebSocket_SSLInfo")
        #expect(C.receiveText("a\r\nb\nc\rd") == "a\u{1}b\u{1}c\u{1}d")
    }

    @Test
    func openReceiveAndNormalClose() async throws {
        let server = try LocalWebSocketServer { _ in .greet }
        let port = try await server.start()
        defer { server.stop() }
        let recorder = EventRecorder()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/chat"))
        let connection = WebSocketConnection(url: url, asyncID: "chat", customEventID: nil) { recorder.record($0, $1) }
        connection.start()

        try await waitUntil { recorder.names().filter { $0 == "OnExecuteWebSocketReceive" }.count >= 2 }
        let open = try #require(recorder.first("OnExecuteWebSocketOpen"))
        #expect(open["Reference0"] == "chat")
        #expect(open["Reference1"] == url.absoluteString)
        #expect(open["Reference2"] == "200")

        let receives = recorder.events.filter { $0.name == "OnExecuteWebSocketReceive" }.map(\.params)
        #expect(receives.contains { $0["Reference2"] == "1" && $0["Reference3"] == "hello\u{1}world" })
        #expect(receives.contains { $0["Reference2"] == "2" && $0["Reference3"] == Data([1, 2, 3]).base64EncodedString() })

        connection.close()
        try await waitUntil { recorder.first("OnExecuteWebSocketClose") != nil }
        #expect(recorder.first("OnExecuteWebSocketClose")?["Reference2"] == "1000")
        #expect(recorder.first("OnExecuteWebSocketFailure") == nil)
    }

    @Test
    func initialConnectFailureSendsFailureWithoutClose() async throws {
        // サーバを止めて、使われていないポートへ接続させる。
        let server = try LocalWebSocketServer { _ in .idle }
        let port = try await server.start()
        server.stop()
        let recorder = EventRecorder()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/"))
        let connection = WebSocketConnection(url: url, asyncID: "x", customEventID: "OnTest") { recorder.record($0, $1) }
        connection.start()

        try await waitUntil { recorder.first("OnTestFailure") != nil }
        let failure = try #require(recorder.first("OnTestFailure"))
        #expect(failure["Reference0"] == "x")
        #expect(!(failure["Reference2"] ?? "").isEmpty)
        #expect(recorder.first("OnTestClose") == nil)
        #expect(recorder.first("OnTestOpen") == nil)
    }

    @Test
    func errorDisconnectReconnectsAutomatically() async throws {
        let saved = WebSocketConnection.reconnectDelays
        WebSocketConnection.reconnectDelays = [0.1, 0.1, 0.1, 0.1, 0.1]
        defer { WebSocketConnection.reconnectDelays = saved }

        // 1本目だけエラー切断し、2本目は維持する。
        let server = try LocalWebSocketServer { $0 == 1 ? .dropAbruptly : .idle }
        let port = try await server.start()
        defer { server.stop() }
        let recorder = EventRecorder()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/"))
        let connection = WebSocketConnection(url: url, asyncID: "", customEventID: nil) { recorder.record($0, $1) }
        connection.start()

        try await waitUntil { recorder.first("OnExecuteWebSocketReconnect") != nil }
        #expect(recorder.names().filter { $0 == "OnExecuteWebSocketOpen" }.count == 1)
        #expect(recorder.first("OnExecuteWebSocketReconnect")?["Reference2"] == "200")
        #expect(recorder.first("OnExecuteWebSocketClose") == nil)

        connection.cancel()
        try await waitUntil { recorder.first("OnExecuteWebSocketClose") != nil }
        #expect(recorder.first("OnExecuteWebSocketClose")?["Reference2"] == "userbreak")
    }

    @Test
    func reconnectGivesUpAfterFiveAttempts() async throws {
        let saved = WebSocketConnection.reconnectDelays
        WebSocketConnection.reconnectDelays = [0.05, 0.05, 0.05, 0.05, 0.05]
        defer { WebSocketConnection.reconnectDelays = saved }

        let server = try LocalWebSocketServer { _ in .dropAbruptly }
        let port = try await server.start()
        let recorder = EventRecorder()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/"))
        let connection = WebSocketConnection(url: url, asyncID: "", customEventID: nil) { recorder.record($0, $1) }
        connection.start()

        // 開いた直後にサーバごと止め、以降の再接続をすべて失敗させる。
        try await waitUntil { recorder.first("OnExecuteWebSocketOpen") != nil }
        server.stop()
        try await waitForWebSocket(timeout: 15) { recorder.first("OnExecuteWebSocketFailure") != nil }
        #expect(recorder.first("OnExecuteWebSocketFailure")?["Reference2"] == "reconnect failed")
        #expect(recorder.first("OnExecuteWebSocketClose") == nil)
        #expect(!connection.isActive)
    }

    @Test
    func cancelBeforeOpenSendsUserbreakClose() async throws {
        let server = try LocalWebSocketServer { _ in .idle }
        let port = try await server.start()
        defer { server.stop() }
        let recorder = EventRecorder()
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/"))
        let connection = WebSocketConnection(url: url, asyncID: "", customEventID: nil) { recorder.record($0, $1) }
        connection.start()
        try await waitUntil { recorder.first("OnExecuteWebSocketOpen") != nil }
        connection.cancel()
        try await waitUntil { recorder.first("OnExecuteWebSocketClose") != nil }
        #expect(recorder.first("OnExecuteWebSocketClose")?["Reference2"] == "userbreak")
        #expect(!connection.isActive)
    }
}
