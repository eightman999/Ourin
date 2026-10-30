import Foundation
import Testing
import Darwin
@testable import Ourin

struct ShiolinkTests {
    private func fixture(mode: String = "normal") throws -> (URL, ShioriRuntimeLoadContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-SHIOLINK-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master/会話 engine")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/shiolink/helper.c")
        let executable = master.appendingPathComponent("helper")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = [source.path, "-o", executable.path]
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        try "[SHIOLINK]\nexecutable=./helper\narguments=[\"\(mode)\"]\ncharmode=UTF-8\n"
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        return (root, ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"), moduleName: "会話 engine/SHIOLINK.dll"))
    }

    @Test func realProcessRoundTripUnicodeNotifyAndUnload() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        #expect(adapter.load(context: context))
        let response = try #require(adapter.request(method: "GET", id: "OnBoot", refs: ["桜鈴 🌸"], timeout: 1))
        #expect(response.value == "桜鈴 🌸")
        #expect(response.headers?["Reference0"] == context.ghostRoot.appendingPathComponent("会話 engine").path + "/")
        #expect(response.headers?["Reference1"] == "GET")
        #expect(adapter.request(method: "NOTIFY", id: "OnTest", timeout: 1)?.headers?["Reference1"] == "NOTIFY")
        adapter.unload()
        #expect(!adapter.isLoaded)
        #expect(FileManager.default.fileExists(atPath: context.ghostRoot.appendingPathComponent("会話 engine/unloaded.marker").path))
        #expect(adapter.request(method: "GET", id: "OnBoot", timeout: 1) == nil)
    }

    @Test(arguments: [false, true]) func legacySentenceEventsUseSharedShiori2Compatibility(forceUTF8: Bool) throws {
        let (root, original) = try fixture(mode: forceUTF8 ? "shiori2-utf8" : "shiori2")
        let context = ShioriRuntimeLoadContext(ghostURL: original.ghostURL, ghostRoot: original.ghostRoot,
            moduleName: original.moduleName, communication: ShioriCommunicationOptions(
                version: forceUTF8 ? "SHIORI/2.2" : nil, forceEncoding: forceUTF8 ? "UTF-8" : nil))
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        try #require(adapter.load(context: context))
        let greeting = forceUTF8 ? "起動しました 🌸" : "起動しました"
        let boot = try #require(adapter.request(method: "GET", id: "OnBoot", refs: [greeting], timeout: 1))
        #expect(boot.value == greeting)
        #expect(boot.headers?["Reference0"] == "OnBoot")
        #expect(boot.headers?["Charset"] == "UTF-8")
        #expect(adapter.request(method: "NOTIFY", id: "OnSecondChange", timeout: 1)?.status == 204)
        #expect(adapter.request(method: "GET", id: "OnUnsupportedEvent", timeout: 1)?.status == 204)
        let click = adapter.request(method: "GET", id: "OnMouseDoubleClick", refs: ["つついた"], timeout: 1)
        #expect(click?.value == "つついた")
        #expect(click?.headers?["Reference0"] == "OnMouseDoubleClick")
        adapter.unload()
        let (modernRoot, modernContext) = try fixture()
        defer { try? FileManager.default.removeItem(at: modernRoot) }
        try #require(adapter.load(context: modernContext))
        #expect(adapter.request(method: "GET", id: "OnModernEvent", refs: ["桜鈴 🌸"], timeout: 1)?.value == "桜鈴 🌸")
    }

    @Test func productionFactorySelectsAndLoadsShiolink() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ShioriRuntimeFactory.kind(for: context.moduleName, ghostRoot: context.ghostRoot) == .shiolink)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: context.moduleName, ghostRoot: context.ghostRoot))
        defer { runtime.unload() }
        #expect(runtime.kind == .shiolink)
        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "OnBoot", refs: ["factory"], timeout: 1)?.value == "factory")
    }

    @Test func explicitPortKeepsOriginalModuleAndDoesNotAffectOtherModules() throws {
        let (root, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = original.ghostRoot.appendingPathComponent("会話 engine")
        let config = directory.appendingPathComponent("SHIOLINK.ourin.ini")
        let text = try String(contentsOf: config, encoding: .utf8) + "module=PHIORI.DLL\n"
        try text.write(to: config, atomically: true, encoding: .utf8)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: original.ghostRoot,
                                              moduleName: "会話 engine/phiori.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        #expect(runtime.kind == .shiolink)
        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "OnBoot", refs: ["unchanged descriptor"], timeout: 1)?.value == "unchanged descriptor")
        let other = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: original.ghostRoot,
                                            moduleName: "会話 engine/other.dll")
        #expect(ShioriRuntimeFactory.makeRuntime(context: other)?.kind == .native)
        runtime.unload()
        try FileManager.default.moveItem(at: config, to: directory.appendingPathComponent("SHIOLINK.INI"))
        #expect(ShioriRuntimeFactory.makeRuntime(context: context)?.kind == .native)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("SHIOLINK.INI"))
        #expect(ShioriRuntimeFactory.makeRuntime(context: context)?.kind == .native)
    }

    @Test(arguments: ["bad-echo", "load-hang", "startup-hang"])
    func invalidLoadIsBoundedAndChildIsReaped(mode: String) throws {
        let (root, context) = try fixture(mode: mode)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = ShiolinkAdapter(loadTimeout: 0.75)
        // The transport deadline stays short; allow scheduler/Process launch overhead
        // during the full parallel suite while still asserting a finite wall-clock bound.
        let start = ProcessInfo.processInfo.systemUptime
        #expect(!adapter.load(context: context))
        #expect(ProcessInfo.processInfo.systemUptime - start < 5)
        #expect(!adapter.isLoaded)
        try assertChildExited(adapter)
    }

    @Test(arguments: ["hang", "flood", "exit"])
    func brokenResponseInvalidatesSessionAndReapsChild(mode: String) throws {
        let (root, context) = try fixture(mode: mode)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = ShiolinkAdapter()
        #expect(adapter.load(context: context))
        // The transport deadline stays short; allow scheduler/Process launch overhead
        // during the full parallel suite while still asserting a finite wall-clock bound.
        let start = ProcessInfo.processInfo.systemUptime
        #expect(adapter.request(method: "GET", id: "OnBoot", timeout: 0.2) == nil)
        #expect(ProcessInfo.processInfo.systemUptime - start < 5)
        #expect(!adapter.isLoaded)
        try assertChildExited(adapter)
        // Reload starts a fresh child; the failed session cannot leak a stale response.
        #expect(adapter.load(context: context))
        adapter.unload()
    }

    private func assertChildExited(_ adapter: ShiolinkAdapter) throws {
        // A busy machine can time out before the helper reaches main or reads *L.
        // Verify the PID obtained from Process.run, not a helper-created marker.
        let pid = try #require(adapter.lastProcessIdentifier)
        try #require(pid > 0)
        let result = kill(pid, 0)
        let failure = errno
        #expect(result == -1)
        #expect(failure == ESRCH)
    }

    @Test func commonIniQuotedCommandAndOurinPriority() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = context.ghostRoot.appendingPathComponent("会話 engine")
        try "[SHIOLINK]\ncommandline = \"./helper\" normal\ncharmode=UTF-8\n"
            .write(to: dir.appendingPathComponent("SHIOLINK.INI"), atomically: true, encoding: .utf8)
        #expect(try ShiolinkConfiguration.load(context: context).arguments == ["normal"])
        try "[SHIOLINK]\ncommandline = ./helper bad-echo\ncharmode=UTF-8\n"
            .write(to: dir.appendingPathComponent("SHIOLINK.INI"), atomically: true, encoding: .utf8)
        #expect(try ShiolinkConfiguration.load(context: context).arguments == ["normal"])
        try FileManager.default.removeItem(at: dir.appendingPathComponent("SHIOLINK.ourin.ini"))
        #expect(try ShiolinkConfiguration.load(context: context).arguments == ["bad-echo"])
        try "[SHIOLINK]\ncommandline = \"./helper\" normal\ncharmode=UTF-8\n"
            .write(to: dir.appendingPathComponent("SHIOLINK.INI"), atomically: true, encoding: .utf8)
        let adapter = ShiolinkAdapter()
        #expect(adapter.load(context: context))
        adapter.unload()
        #expect(try ShiolinkConfiguration.tokenize("\"/path with space/node\" 'main file.js' \"\"") == ["/path with space/node", "main file.js", ""])
    }

    @Test(arguments: ["commandline=node.exe app.js", "commandline=/bin/echo ok; touch /tmp/no", "executable=/bin/echo\narguments=not-json", "commandline=/bin/echo\ncharmode=UTF-16"])
    func invalidConfigurationCannotLaunch(setting: String) throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try ("[SHIOLINK]\n" + setting).write(to: context.ghostRoot.appendingPathComponent("会話 engine/SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let adapter = ShiolinkAdapter()
        #expect(!adapter.load(context: context))
        #expect(adapter.lastProcessIdentifier == nil)
    }
}
