import Foundation
import Testing
@testable import Ourin

private final class CloseAllRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var requests: [(method: String, id: String, refs: [String])] = []

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        requests.append((method, id, refs))
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

@Suite(.serialized)
struct CloseAllSequenceTests {
    @Test @MainActor
    func closeAllUsesGetAndRunsCompletionAfterEmptyResponse() async throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-close-all-sequence"))
        let runtime = CloseAllRuntime()
        manager.shioriRuntime = runtime
        var completed = false

        #expect(manager.beginCloseSequence(
            eventID: EventID.OnCloseAll.rawValue,
            reason: "user",
            completion: { completed = true }
        ))

        for _ in 0..<20 where !completed {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(runtime.requests.first?.method == "GET")
        #expect(runtime.requests.first?.id == "OnCloseAll")
        #expect(runtime.requests.first?.refs == ["user"])
        #expect(completed)
        _ = manager.shutdown()
    }

    @Test
    func closeAllReferenceLabelsMapToReferenceZeroThroughTwo() {
        let params = EventReferenceTable.params(forEvent: EventID.OnCloseAll.rawValue, refs: [
            "closeReason": "user",
            "menuScope": "0",
            "windowScope": "1"
        ])

        #expect(params["Reference0"] == "user")
        #expect(params["Reference1"] == "0")
        #expect(params["Reference2"] == "1")
    }
}
