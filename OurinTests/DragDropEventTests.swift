import Foundation
import Testing
@testable import Ourin

private final class DragDropEventRuntime: GhostShioriRuntime {
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
struct DragDropEventTests {
    @Test
    func fileDropReferencesUsePathScopeAndMimeOrder() {
        let refs = DragDropReceiverView.fileDropReferences(
            for: [
                URL(fileURLWithPath: "/tmp/example.txt"),
                URL(fileURLWithPath: "/tmp/example.png")
            ],
            scopeID: 2
        )

        #expect(refs["filePath"] == "/tmp/example.txt\u{01}/tmp/example.png")
        #expect(refs["scopeID"] == "2")
        #expect(refs["mimeType"] == "text/plain\u{01}image/png")
    }

    @Test @MainActor
    func dragDropEventDispatchPreservesGetDelivery() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-drag-drop-event-test"))
        let runtime = DragDropEventRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        EventBridge.shared.dispatch(ShioriEvent(
            id: .OnFileDropEx,
            refs: ["filePath": "/tmp/example.txt", "scopeID": "0", "mimeType": "text/plain"]
        ))

        #expect(runtime.requests.first?.method == "GET")
        #expect(runtime.requests.first?.id == "OnFileDropEx")
        #expect(runtime.requests.first?.refs == ["/tmp/example.txt", "0", "text/plain"])
    }
}
