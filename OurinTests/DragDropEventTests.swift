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
    func fileDroppingAndDirectoryReferencesCarryScope() {
        let file = URL(fileURLWithPath: "/tmp/example.txt")
        let directory = URL(fileURLWithPath: "/tmp/example-directory", isDirectory: true)

        #expect(DragDropReceiverView.fileDroppingReferences(for: [file], scopeID: 2) == [
            "filePath": "/tmp/example.txt",
            "scopeID": "2"
        ])
        #expect(DragDropReceiverView.directoryDropReferences(for: [directory], scopeID: 2) == [
            "dirPath": "/tmp/example-directory",
            "scopeID": "2"
        ])
    }

    @Test
    func directoryDropsDoNotEnterFileEventReferences() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-drag-drop-classification-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("directory", isDirectory: true)
        let file = root.appendingPathComponent("example.txt")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: root) }

        let classified = DragDropReceiverView.classifyFileURLs([file, directory])

        #expect(classified.files == [file])
        #expect(classified.directories == [directory])
    }

    @Test
    func urlDropReferencesUseUrlAndScopeAndDownloadedEventsUseFileFirst() {
        #expect(EventReferenceTable.specs["OnURLDrop"]?.references == ["url", "scopeID"])
        #expect(EventReferenceTable.specs["OnURLDragDropping"]?.references == ["url", "scopeID"])
        #expect(EventReferenceTable.specs["OnURLDropping"]?.references == ["url", "scopeID"])
        #expect(EventReferenceTable.specs["OnURLDropped"]?.references == ["filePath", "url", "scopeID"])
        #expect(EventReferenceTable.specs["OnURLDropFailure"]?.references == ["filePath", "reason", "url", "scopeID"])
        #expect(EventReferenceTable.specs["OnURLQuery"]?.references == ["url", "scopeID", "mimeType", "plannedAction"])
    }

    @Test
    func urlDropPolicyValidatesTransportAndQueryAction() {
        let narURL = URL(string: "https://example.com/ghost.nar")!
        let textURL = URL(string: "https://example.com/page.html")!

        #expect(URLDropPolicy.remoteURL(from: narURL.absoluteString, allowInsecureHTTP: false) == narURL)
        #expect(URLDropPolicy.remoteURL(from: "http://example.com/ghost.nar", allowInsecureHTTP: false) == nil)
        #expect(URLDropPolicy.remoteURL(from: "http://example.com/ghost.nar", allowInsecureHTTP: true)?.scheme == "http")
        #expect(URLDropPolicy.remoteURL(from: "https://user:password@example.com/ghost.nar", allowInsecureHTTP: true) == nil)
        #expect(URLDropPolicy.remoteURL(from: "https://127.0.0.1/ghost.nar", allowInsecureHTTP: true, resolveHost: false) != nil)
        #expect(URLDropPolicy.remoteURL(from: "https://127.0.0.1/ghost.nar", allowInsecureHTTP: true) == nil)
        #expect(URLDropPolicy.remoteURL(from: "https://localhost/ghost.nar", allowInsecureHTTP: true) == nil)
        #expect(URLDropPolicy.remoteURL(from: "https://[::1]/ghost.nar", allowInsecureHTTP: true) == nil)
        #expect(URLDropPolicy.remoteURL(from: "https://[::ffff:127.0.0.1]/ghost.nar", allowInsecureHTTP: true) == nil)
        #expect(URLDropPolicy.remoteURL(from: "https://[::127.0.0.1]/ghost.nar", allowInsecureHTTP: true) == nil)
        #expect(URLDropPolicy.plannedAction(for: narURL) == "nar")
        #expect(URLDropPolicy.plannedAction(for: textURL) == "unknown")
        #expect(URLDropPolicy.queryReferences(for: narURL, scopeID: 1) == [
            "url": "https://example.com/ghost.nar",
            "scopeID": "1",
            "mimeType": "application/x-nar",
            "plannedAction": "nar"
        ])
    }

    @Test
    func urlDropFailureReasonsUseStandardReasonVocabulary() {
        #expect(URLDropFailureReason.httpStatus(404) == "404")
        #expect(URLDropFailureReason.forDownload(error: URLError(.timedOut)) == "timeout")
        #expect(URLDropFailureReason.forDownload(error: URLError(.cancelled)) == "artificial")
        #expect(URLDropFailureReason.forDownload(error: URLError(.cannotConnectToHost)) == "fileio")
        #expect(URLDropFailureReason.forDownload(error: URLDropDownloadError.responseTooLarge) == "fileio")
        #expect(URLDropFailureReason.forInstallation(error: NarInstaller.Error.unzipFailed("corrupt")) == "extraction")
        #expect(URLDropFailureReason.forInstallation(error: NarInstaller.Error.installTxtNotFound) == "invalid type")
        #expect(URLDropFailureReason.forInstallation(error: NarInstaller.Error.directoryConflict("ghost")) == "unsupported")
        #expect(URLDropFailureReason.forInstallation(error: NarInstaller.Error.updateMD5Mismatch("ghost.nar")) == "md5 miss")
        #expect(URLDropFailureReason.forInstallation(error: NarInstaller.Error.notZip) == "unsupported")
    }

    @Test @MainActor
    func urlDropQueriesOnlyTargetGhostBeforeUnknownActionStops() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-url-drop-query-test"))
        let runtime = DragDropEventRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        let url = "https://example.com/page.html"
        manager.handleURLDropEvent(ShioriEvent(
            id: .OnURLDrop,
            refs: ["url": url, "scopeID": "1"]
        ))

        #expect(runtime.requests.map(\.id) == ["OnURLDrop", "OnURLQuery"])
        #expect(runtime.requests.last?.refs == [url, "1", "text/html", "unknown"])
    }

    @Test @MainActor
    func privateNarURLIsRejectedDuringBackgroundPreflight() async {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-private-url-drop-test"))
        let runtime = DragDropEventRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            manager.shutdown()
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.handleURLDropEvent(ShioriEvent(
            id: .OnURLDrop,
            refs: ["url": "https://127.0.0.1/ghost.nar", "scopeID": "1"]
        ))
        #expect(runtime.requests.map(\.id) == ["OnURLDrop", "OnURLQuery"])

        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(runtime.requests.map(\.id) == ["OnURLDrop", "OnURLQuery"])
    }

    @Test @MainActor
    func invalidURLDropIsRejectedBeforeStandardFailureLifecycle() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-invalid-url-drop-test"))
        let runtime = DragDropEventRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.handleURLDropEvent(ShioriEvent(
            id: .OnURLDrop,
            refs: ["url": "file:///tmp/secret.nar", "scopeID": "1"]
        ))

        #expect(runtime.requests.isEmpty)
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
