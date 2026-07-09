import Foundation
import Testing
@testable import Ourin

/// AUDITS_TODO「\![cancel,http,...] 未実装」の回帰テスト。
/// \![cancel,websocket,URL] と対称の HTTP ストリーミング中断経路を検証する。
@Suite(.serialized)
struct HTTPStreamingCancelTests {
    @Test
    func cancelHTTPStreamingRemovesAndCancelsTrackedTask() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-http-stream-cancel"))
        let url = URL(string: "https://example.invalid/stream")!
        let task = URLSession.shared.dataTask(with: url) { _, _, _ in }
        gm.httpStreamingTasks[url.absoluteString] = task

        gm.cancelHTTPStreaming(params: [url.absoluteString])

        #expect(gm.httpStreamingTasks[url.absoluteString] == nil)
        #expect(task.state == .canceling || task.state == .completed)
    }

    @Test
    func cancelHTTPStreamingOnUnknownURLIsNoOp() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-http-stream-cancel-unknown"))

        // 追跡されていないURLをキャンセルしてもクラッシュしない。
        gm.cancelHTTPStreaming(params: ["https://example.invalid/never-started"])

        #expect(gm.httpStreamingTasks.isEmpty)
    }

    @Test
    func cancelHTTPStreamingWithNoParamsIsNoOp() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-http-stream-cancel-empty"))

        gm.cancelHTTPStreaming(params: [])

        #expect(gm.httpStreamingTasks.isEmpty)
    }
}
