import Foundation
import AppKit
import UniformTypeIdentifiers
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

    @Test
    func otherObjectDropReferencesPreserveNameAndCustomUTI() {
        let item = NSPasteboardItem()
        let type = NSPasteboard.PasteboardType("com.example.virtual-object")
        item.setString("仮想コンピュータ", forType: type)

        let refs = DragDropReceiverView.otherObjectDropReferences(for: [item], scopeID: 1)

        #expect(refs == [
            "scopeID": "1",
            "name": "仮想コンピュータ",
            "objectID": "com.example.virtual-object"
        ])
    }

    @Test
    func genericDraggedTypesAreRegisteredForNonFileObjects() {
        let registered = Set(DragDropReceiverView.registeredDraggedTypes.map(\.rawValue))
        #expect(registered.contains(UTType.item.identifier))
        #expect(registered.contains(UTType.data.identifier))
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

    @Test @MainActor
    func backgroundDispatchIsSerializedOnMainQueue() async {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-background-event-bridge-test"))
        let runtime = DragDropEventRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        await Task.detached {
            EventBridge.shared.dispatch(ShioriEvent(
                id: .OnFileDropEx,
                refs: ["filePath": "/tmp/background.txt", "scopeID": "0", "mimeType": "text/plain"]
            ))
        }.value

        #expect(runtime.requests.first?.method == "GET")
        #expect(runtime.requests.first?.id == "OnFileDropEx")
        #expect(runtime.requests.first?.refs == ["/tmp/background.txt", "0", "text/plain"])
    }

    @Test @MainActor
    func stoppingBridgeDropsQueuedObserverNotifications() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-event-bridge-lifecycle-test"))
        let runtime = DragDropEventRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        EventBridge.shared.start(enableAutoEvents: false)
        EventBridge.shared.dispatch(ShioriEvent(
            id: .OnScreenSaverStart,
            params: ["Reference0": "queued-before-stop"],
            delivery: .notify,
            ignoreResponseScript: true
        ))

        // stop() は observer の停止だけでなく、次の起動へ持ち越せない
        // 通知キューも破棄する。
        EventBridge.shared.stop()
        EventBridge.shared.start(enableAutoEvents: true)
        EventBridge.shared.stop()

        #expect(runtime.requests.contains {
            $0.id == "OnScreenSaverStart" && $0.refs == ["queued-before-stop"]
        } == false)
    }
}
