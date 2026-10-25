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
