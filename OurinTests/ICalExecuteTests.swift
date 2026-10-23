import Foundation
import Network
import Testing
@testable import Ourin

private final class CapturingICalRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    private let lock = NSLock()
    private var storage: [(method: String, id: String, refs: [String])] = []

    var requests: [(method: String, id: String, refs: [String])] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(method: String, id: String, headers: [String: String], refs: [String], timeout: TimeInterval) -> ShioriRuntimeResponse? {
        lock.lock(); storage.append((method, id, refs)); lock.unlock()
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }

    func clear() {
        lock.lock(); storage.removeAll(); lock.unlock()
    }
}

/// パスごとに固定の応答を返す、テスト用のローカル HTTP サーバ。
private final class LocalHTTPServer: @unchecked Sendable {
    struct Route {
        var status = 200
        var body: String
        var delay: TimeInterval = 0
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "jp.ourin.tests.httpserver")
    private let lock = NSLock()
    private var routes: [String: Route] = [:]
    private var connections: [NWConnection] = []
    private var hits: [String: Int] = [:]

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func setRoute(_ path: String, _ route: Route) {
        lock.lock(); routes[path] = route; lock.unlock()
    }

    func hitCount(_ path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return hits[path] ?? 0
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
        lock.lock(); let current = connections; connections.removeAll(); lock.unlock()
        current.forEach { $0.forceCancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock(); connections.append(connection); lock.unlock()
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            self.lock.lock()
            let route = self.routes[path] ?? Route(status: 404, body: "not found")
            self.hits[path, default: 0] += 1
            self.lock.unlock()
            self.queue.asyncAfter(deadline: .now() + route.delay) {
                let body = Data(route.body.utf8)
                let head = "HTTP/1.1 \(route.status) X\r\nContent-Type: text/calendar\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}

private let sampleICS = """
BEGIN:VCALENDAR
X-WR-CALNAME:テスト
X-WR-TIMEZONE:Asia/Tokyo
BEGIN:VEVENT
UID:daily
SUMMARY:朝会
DTSTART:20260901T090000
DTEND:20260901T093000
RRULE:FREQ=DAILY
END:VEVENT
BEGIN:VEVENT
UID:once
SUMMARY:100% 休み
DTSTART;VALUE=DATE:20260902
END:VEVENT
END:VCALENDAR
"""

@Suite(.serialized, .eventBridgeIsolated)
struct ICalExecuteTests {
    private func waitFor(_ runtime: CapturingICalRuntime, id: String, timeout: TimeInterval = 8) async throws -> (method: String, id: String, refs: [String])? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let hit = runtime.requests.first(where: { $0.id == id }) { return hit }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    /// サーバとゴーストを用意して `body` を実行する。
    @MainActor
    private func withGhost(_ body: (GhostManager, CapturingICalRuntime, LocalHTTPServer, UInt16) async throws -> Void) async throws {
        EventBridge.shared.stop()
        let server = try LocalHTTPServer()
        let port = try await server.start()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-ical-execute-test"))
        let runtime = CapturingICalRuntime()
        manager.shioriRuntime = runtime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
            server.stop()
            _ = manager.shutdown()
        }
        try await body(manager, runtime, server, port)
    }

    @Test @MainActor
    func icalGetParsesTheCalendarAndNotifiesOnTheAsyncEvent() async throws {
        try await withGhost { manager, runtime, server, port in
            server.setRoute("/cal.ics", .init(body: sampleICS))
            let url = "http://127.0.0.1:\(port)/cal.ics"
            manager.runScript("\\![execute,ical-get,\(url),--async=OnMyCalendar,--from=20260901,--to=20260903,--expand]\\e")

            let complete = try #require(try await waitFor(runtime, id: "OnMyCalendar"))
            #expect(complete.method == "NOTIFY")
            let sep = "\u{1}"
            // R0: カレンダー名 / TZ / 暦法 / 返却件数 / 総数 / 期間の開始 / 終了。
            #expect(complete.refs[0] == ["テスト", "Asia/Tokyo", "GREGORIAN", "4", "2", "2026,9,1,,,", "2026,9,3,,,"].joined(separator: sep))
            // 9/1〜9/3 の daily 3 回と、9/2 の休みで 4 件。
            #expect(complete.refs.count == 5)
            let first = complete.refs[1].components(separatedBy: sep)
            #expect(first[0] == "daily")
            #expect(first[3] == "朝会")
            #expect(first[10] == "0")
            #expect(first[11] == "2026,9,1,,,")
            // % はさくらスクリプトとして解釈されないようエスケープされる。
            #expect(complete.refs.contains { $0.contains("100\\% 休み") })
        }
    }

    @Test @MainActor
    func failuresUseTheHTTPFailureLayoutAndTheParseReason() async throws {
        try await withGhost { manager, runtime, server, port in
            server.setRoute("/missing.ics", .init(status: 404, body: "no"))
            server.setRoute("/html", .init(body: "<html>not a calendar</html>"))
            manager.runScript("\\![execute,ical-get,http://127.0.0.1:\(port)/missing.ics,--async=OnCalA]\\![execute,ical-get,http://127.0.0.1:\(port)/html,--async=OnCalB]\\e")

            let notFound = try #require(try await waitFor(runtime, id: "OnCalAFailure"))
            // OnExecuteHTTPFailure と同じ並び: R0=method R1=asyncID R2=url R3=data R4=結果。
            #expect(notFound.refs[0] == "GET")
            #expect(notFound.refs[1] == "OnCalA")
            #expect(notFound.refs[2] == "http://127.0.0.1:\(port)/missing.ics")
            #expect(notFound.refs[4] == "404")

            let parse = try #require(try await waitFor(runtime, id: "OnCalBFailure"))
            #expect(parse.refs[4] == "parse")
            // 失敗しても完了イベントは出ない。
            #expect(runtime.requests.first { $0.id == "OnCalA" || $0.id == "OnCalB" } == nil)
        }
    }

    @Test @MainActor
    func sameURLWhileDownloadingFailsWithDownloadingAndCancelStopsIt() async throws {
        try await withGhost { manager, runtime, server, port in
            server.setRoute("/slow.ics", .init(body: sampleICS, delay: 1.5))
            let url = "http://127.0.0.1:\(port)/slow.ics"
            manager.runScript("\\![execute,ical-get,\(url),--async=OnSlow]\\e")
            try await Task.sleep(nanoseconds: 400_000_000)
            manager.runScript("\\![execute,ical-get,\(url),--async=OnSlow]\\e")

            let duplicate = try #require(try await waitFor(runtime, id: "OnSlowFailure"))
            #expect(duplicate.refs[4] == "downloading")
            // 最初の取得は続いており、完了する。
            _ = try #require(try await waitFor(runtime, id: "OnSlow", timeout: 10))
            #expect(server.hitCount("/slow.ics") == 1)

            // 完了後は、同じ URL を再び取得できる。cancel で中断すると cancelled で失敗する。
            runtime.clear()
            manager.runScript("\\![execute,ical-get,\(url),--async=OnAgain]\\e")
            try await Task.sleep(nanoseconds: 400_000_000)
            manager.runScript("\\![cancel,ical,\(url)]\\e")
            let cancelled = try #require(try await waitFor(runtime, id: "OnAgainFailure"))
            #expect(cancelled.refs[4] == "cancelled")
        }
    }

    @Test @MainActor
    func unreachableURLFails() async throws {
        try await withGhost { manager, runtime, _, _ in
            manager.runScript("\\![execute,ical-get,not a url,--async=OnBad]\\e")
            // 空白入りの文字列は URL として組み立てられるが、取得できずに失敗する（完了イベントは出ない）。
            let failure = try #require(try await waitFor(runtime, id: "OnBadFailure"))
            #expect(failure.refs[1] == "OnBad")
            #expect(!failure.refs[4].isEmpty)
            #expect(runtime.requests.first { $0.id == "OnBad" } == nil)
        }
    }
}
