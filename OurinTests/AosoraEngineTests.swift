import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct AosoraEngineTests {
    private static let privateLibrary = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/engines/aosora/libaosora.dylib")

    private func request(_ event: String) -> String {
        "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: local\r\nID: \(event)\r\n\r\n"
    }

    private func fixture(at root: URL) throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shiori/aosora_fixture.c")
        let library = root.appendingPathComponent("aosora_fixture.dylib")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = ["-dynamiclib", source.path, "-o", library.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        try PropertyListSerialization.data(fromPropertyList: ["OurinShioriABI": "aosora"],
            format: .xml, options: 0).write(to: library.appendingPathExtension("plist"))
        return library
    }

    @Test(arguments: [false, true])
    func longInstanceIDAndZeroLoadFailure(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try fixture(at: root)
        let rejected = root.appendingPathComponent("reject")
        try FileManager.default.createDirectory(at: rejected, withIntermediateDirectories: true)
        #expect(ShioriLoader(moduleURL: library, xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
            loadDirectory: rejected) == nil)
        for _ in 0..<2 {
            let loader = try #require(ShioriLoader(moduleURL: library,
                xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
            #expect(loader.request(request("OnBoot"))?.contains("Value: aosora-long-id") == true)
            loader.unload()
            #expect(loader.request(request("OnBoot")) == nil)
        }
    }

    private func dictionary(at root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "main.as\n".write(to: root.appendingPathComponent("ghost.asproj"), atomically: true, encoding: .utf8)
        let source = """
        function OnBoot { return "aosora-real-boot"; }
        function OnAITalk { return "aosora-real-talk"; }
        function OnClose { return "aosora-real-close"; }
        function OnRemember { Save.Data.count = 37; return "remembered"; }
        function OnRecall { return Save.Data.count; }
        """
        try source.write(to: root.appendingPathComponent("main.as"), atomically: true, encoding: .utf8)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: privateLibrary.path),
        "Optional personal Aosora build is absent; never fetched or redistributed by tests"), arguments: [false, true])
    func actualEngineLifecycleAndSave(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try dictionary(at: root)
        let loader = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
        #expect(loader.request(request("OnBoot"))?.contains("aosora-real-boot") == true)
        if !isolated {
            // The upstream TextSystem is process-global. Rejection must preserve the first session.
            #expect(ShioriLoader(moduleURL: Self.privateLibrary, xpcServiceName: nil, loadDirectory: root) == nil)
            #expect(loader.request(request("OnBoot"))?.contains("aosora-real-boot") == true)
        }
        #expect(loader.request(request("OnRemember"))?.contains("remembered") == true)
        #expect(loader.request(request("OnClose"))?.contains("aosora-real-close") == true)
        loader.unload()
        let second = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
        #expect(second.request(request("OnRecall"))?.contains("Value: 37\r\n") == true)
        second.unload()
        try "function Broken { !! invalid }".write(to: root.appendingPathComponent("main.as"), atomically: true, encoding: .utf8)
        #expect(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root) == nil)
        try FileManager.default.removeItem(at: root.appendingPathComponent("main.as"))
        #expect(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root) == nil)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: privateLibrary.path),
        "Optional personal Aosora build is absent"))
    func windowsNameUsesProductionFactory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appendingPathComponent("ghost/master")
        try dictionary(at: master.appendingPathComponent("shiori"))
        let prior = ProcessInfo.processInfo.environment["OURIN_AOSORA_ENGINE"]
        setenv("OURIN_AOSORA_ENGINE", Self.privateLibrary.path, 1)
        defer {
            if let prior { setenv("OURIN_AOSORA_ENGINE", prior, 1) }
            else { unsetenv("OURIN_AOSORA_ENGINE") }
        }
        let name = "shiori\\aosora.dll"
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: name, ghostRoot: master))
        #expect(runtime.kind == .native)
        try #require(runtime.load(context: .init(ghostURL: root, ghostRoot: master, moduleName: name)))
        defer { runtime.unload() }
        let response = runtime.request(method: "GET", id: "OnBoot", headers: [:], refs: [], timeout: 5)
        #expect(response?.status == 200)
        #expect(response?.value?.contains("aosora-real-boot") == true)
    }
}
