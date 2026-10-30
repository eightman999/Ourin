import Foundation
import Testing
import Darwin
@testable import Ourin

/// Executes real pinned MiyoJS, its legacy SHIOLINK implementation and bundled Node.
struct MiyoJSEngineTests {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let plugin = ProcessInfo.processInfo.environment["OURIN_MIYOJS_PLUGIN"]
        .map { URL(fileURLWithPath: $0) }
        ?? repository.appendingPathComponent("build/engines/script-plugins/miyojs")
    private static let executable = plugin.appendingPathComponent("bin/miyojs")

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Stage MiyoJS plugin with engines/package-script-engines.py"))
    func realMiyoDictionaryUnicodeSaveAndProcessReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-MiyoJS-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master/日本語 エンジン")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtures = Self.repository.appendingPathComponent("engines/miyojs/fixtures")
        for name in ["miyo.yaml", "probe.js"] {
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: master.appendingPathComponent(name))
        }
        try "[SHIOLINK]\nmodule=miyojs.dll\nexecutable=\(Self.executable.path)\narguments=[\".\"]\ncharmode=UTF-8\n"
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"),
                                              moduleName: "日本語 エンジン\\miyojs.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        #expect(runtime.kind == .shiolink)
        defer { runtime.unload() }
        for expected in [1, 2] {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 3)?.value == "2.0.3")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 3)?.value == "桜鈴 🌸 \(expected)")
            #expect(runtime.request(method: "GET", id: "OnMouseDoubleClick", refs: ["表・ソ・日本語 🌸"], timeout: 3)?.value == "表・ソ・日本語 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", refs: ["通知"], timeout: 3)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 3)?.value == #"\h\s[0]MiyoJS終了。\e"#)
            let adapter = try #require(runtime as? ShiolinkAdapter)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            #expect(try String(contentsOf: master.appendingPathComponent("count.txt"), encoding: .utf8) == String(expected))
        }
        for name in ["miyo.yaml", "probe.js"] {
            #expect(try Data(contentsOf: fixtures.appendingPathComponent(name)) == Data(contentsOf: master.appendingPathComponent(name)))
        }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Stage MiyoJS plugin with engines/package-script-engines.py"))
    func malformedDictionaryFailsLoadWithoutRetainingChild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-MiyoJS-invalid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "OnBoot: [unclosed\n".write(to: root.appendingPathComponent("miyo.yaml"), atomically: true, encoding: .utf8)
        try "[SHIOLINK]\nmodule=miyojs.dll\nexecutable=\(Self.executable.path)\narguments=[\".\"]\ncharmode=UTF-8\n"
            .write(to: root.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: root, moduleName: "miyojs.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        #expect(!runtime.load(context: context))
        #expect(!runtime.isLoaded)
    }
}
