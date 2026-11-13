import Foundation
import Testing
@testable import Ourin

private final class CapturingGateRuntime: GhostShioriRuntime {
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

/// SSTP など外部由来スクリプトから、ファイルを開く・取得する・展開する系のコマンドを実行させない。
@Suite(.serialized, .eventBridgeIsolated)
struct ExternalScriptCommandGateTests {
    @Test
    func pathContainmentRequiresSeparatorBoundary() {
        #expect(GhostManager.isPath("/ghost/foo", inside: "/ghost/foo"))
        #expect(GhostManager.isPath("/ghost/foo/ghost/master/a.txt", inside: "/ghost/foo"))
        #expect(GhostManager.isPath("/ghost/foo/a.txt", inside: "/ghost/foo/"))
        #expect(!GhostManager.isPath("/ghost/foobar/a.txt", inside: "/ghost/foo"))
        #expect(!GhostManager.isPath("/ghost/foo-evil", inside: "/ghost/foo"))
        #expect(!GhostManager.isPath("/ghost/foo", inside: ""))
    }

    @Test
    func externalOpenDeniesLocalFileAndNetworkSubcommands() {
        for sub in ["file", "editor", "explorer", "http", "send", "pictureviewer", "archiveviewer", "FILE"] {
            #expect(!GhostManager.isExternallyAllowedOpenCommand(["open", sub, "/System/Applications/Calculator.app"]))
        }
        #expect(GhostManager.isExternallyAllowedOpenCommand(["open", "browser", "https://example.com/"]))
        #expect(GhostManager.isExternallyAllowedOpenCommand(["open", "inputbox", "OnInput"]))
    }

    @Test
    func externalURLOpenAllowsOnlyWebSchemes() {
        #expect(GhostManager.isExternallyOpenableURL("https://example.com/"))
        #expect(GhostManager.isExternallyOpenableURL("http://example.com/"))
        #expect(GhostManager.isExternallyOpenableURL("example.com"))
        #expect(!GhostManager.isExternallyOpenableURL("file:///System/Applications/Calculator.app"))
        #expect(!GhostManager.isExternallyOpenableURL("FILE:///etc/passwd"))
        #expect(!GhostManager.isExternallyOpenableURL("x-apple.systempreferences:com.apple.preference"))
        #expect(!GhostManager.isExternallyOpenableURL("vnc://127.0.0.1"))
    }

    @Test
    func externallyAllowedExecuteSubcommandsExcludeFileAndNetworkOperations() {
        for sub in ["http-get", "http-post", "http-stream", "rss-get", "install", "extractarchive",
                    "compressarchive", "websocket", "ping", "nslookup", "ical-get", "dumpsurface",
                    "createnar", "createupdatedata", "emptyrecyclebin"] {
            #expect(!GhostManager.externallyAllowedExecuteSubcommands.contains(sub))
        }
        #expect(GhostManager.externallyAllowedExecuteSubcommands.contains("resetwindowpos"))
    }

    @Test @MainActor
    func externalExecuteCompressArchiveIsRefusedWithSecurityWarning() async throws {
        EventBridge.shared.stop()

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ourin-external-gate-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let archive = root.appendingPathComponent("payload.zip")
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: source.appendingPathComponent("payload.txt"))
        defer { try? fileManager.removeItem(at: root) }

        let manager = GhostManager(ghostURL: root)
        let runtime = CapturingGateRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
            _ = manager.shutdown()
        }

        manager.executeSakuraScriptExecuteCommand(
            args: ["execute", "compressarchive", source.path, archive.path, "--event=OnExternalGateCompress"],
            isExternal: true
        )
        for _ in 0..<100 where !runtime.requests.contains(where: { $0.id == "OnSecurityWarning" }) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let warning = runtime.requests.first { $0.id == "OnSecurityWarning" }
        #expect(warning?.refs.first == "external_script_denied")
        #expect(warning?.refs.dropFirst().first == "execute,compressarchive")
        #expect(!runtime.requests.contains { $0.id == "OnExternalGateCompress" })
        #expect(!fileManager.fileExists(atPath: archive.path))
    }

    @Test @MainActor
    func externalOpenFileScriptIsRefusedWithSecurityWarning() async throws {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-external-open-gate-test"))
        let runtime = CapturingGateRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
            _ = manager.shutdown()
        }

        manager.runTranslatedScript(
            #"\![open,file,/System/Applications/Calculator.app,allow-external]\e"#,
            isExternal: true
        )
        for _ in 0..<100 where !runtime.requests.contains(where: { $0.id == "OnSecurityWarning" }) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let warning = runtime.requests.first { $0.id == "OnSecurityWarning" }
        #expect(warning?.refs.first == "external_script_denied")
        #expect(warning?.refs.dropFirst().first == "open,file")
    }
}
