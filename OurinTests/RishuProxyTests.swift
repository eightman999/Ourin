import Foundation
import Testing
import Darwin
@testable import Ourin

struct RishuProxyTests {
    private func fixture(mode: String = "normal", communication: ShioriCommunicationOptions = .init()) throws -> (URL, ShioriRuntimeLoadContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Rishu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/rishu/rishu_remote.pl")
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("rishu_remote.pl"))
        try mode.write(to: root.appendingPathComponent("mode.txt"), atomically: true, encoding: .utf8)
        return (root, .init(ghostURL: root, ghostRoot: root, moduleName: "rishu_proxy.dll", communication: communication))
    }

    @Test func productionFactoryAndContentLengthRoundTrip() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ShioriRuntimeFactory.kind(for: context.moduleName, ghostRoot: root) == .rishu)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: context.moduleName, ghostRoot: root))
        defer { runtime.unload() }
        #expect(runtime.load(context: context))
        let response = try #require(runtime.request(method: "GET", id: "OnBoot", refs: ["桜鈴"], timeout: 2))
        #expect(response.value == "桜鈴")
        #expect(response.headers?["Reference0"] == "GET")
        #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 2)?.headers?["Reference0"] == "NOTIFY")
        runtime.unload()
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("unloaded.marker").path))
        #expect(!runtime.isLoaded)
    }

    @Test(arguments: [false, true]) func unicodeTransport(escapeUnknown: Bool) throws {
        let options = ShioriCommunicationOptions(encoding: escapeUnknown ? "Shift_JIS" : "UTF-8", escapeUnknown: escapeUnknown)
        let (root, context) = try fixture(communication: options)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = RishuProxyAdapter()
        defer { adapter.unload() }
        #expect(adapter.load(context: context))
        #expect(adapter.request(method: "GET", id: "OnBoot", refs: ["桜鈴 🌸"], timeout: 2)?.value == "桜鈴 🌸")
    }

    @Test(arguments: ["never-connect", "load-hang"])
    func failedStartupReapsSpawnedProcess(mode: String) throws {
        let (root, context) = try fixture(mode: mode)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = RishuProxyAdapter(loadTimeout: 0.75)
        let start = ProcessInfo.processInfo.systemUptime
        #expect(!adapter.load(context: context))
        #expect(ProcessInfo.processInfo.systemUptime - start < 5)
        try assertExited(adapter)
    }

    @Test(arguments: ["hang", "exit", "bad-length", "flood"])
    func malformedOrMissingResponseInvalidatesAndReaps(mode: String) throws {
        let (root, context) = try fixture(mode: mode)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = RishuProxyAdapter()
        #expect(adapter.load(context: context))
        let start = ProcessInfo.processInfo.systemUptime
        #expect(adapter.request(method: "GET", id: "OnBoot", timeout: 0.2) == nil)
        #expect(ProcessInfo.processInfo.systemUptime - start < 5)
        #expect(!adapter.isLoaded)
        try assertExited(adapter)
    }

    @Test func missingScriptAndInterpreterDoNotLaunch() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let absentPerl = RishuProxyAdapter(perlExecutable: root.appendingPathComponent("not-perl"))
        #expect(!absentPerl.load(context: context))
        #expect(absentPerl.lastProcessIdentifier == nil)
        try FileManager.default.removeItem(at: root.appendingPathComponent("rishu_remote.pl"))
        let adapter = RishuProxyAdapter()
        #expect(!adapter.load(context: context))
        #expect(adapter.lastProcessIdentifier == nil)
    }

    private func assertExited(_ adapter: RishuProxyAdapter) throws {
        let pid = try #require(adapter.lastProcessIdentifier)
        let result = kill(pid, 0)
        let error = errno
        #expect(result == -1)
        #expect(error == ESRCH)
    }
}
