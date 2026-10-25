import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct KagariEngineTests {
    private func compileKagariFixture(into root: URL) throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shiori/kagari_fixture.c")
        let module = root.appendingPathComponent("kagari_fixture.dylib")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-dynamiclib", source.path, "-o", module.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["OurinShioriABI": "kagari"],
            format: .xml,
            options: 0
        )
        try plist.write(to: module.appendingPathExtension("plist"))
        return module
    }

    @Test(arguments: [false, true])
    func kagariABIUsesInstanceIDAndGhostDirectory(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ghost = root.appendingPathComponent("ghost/shiori")
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try compileKagariFixture(into: root)
        let loader = try #require(ShioriLoader(moduleURL: module, xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: ghost))
        let boot = loader.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n")
        #expect(boot?.contains("Value: kagari-fixture-boot") == true)
        #expect(loader.request("NOTIFY SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnNotify\r\n\r\n")?.contains("204 No Content") == true)
        loader.unload()
        #expect(loader.request("GET SHIORI/3.0\r\n\r\n") == nil)
    }

    @Test(arguments: [false, true])
    func kagariEngineLifecycleFromAppBundle(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try #require(BundledShioriEngine.bundledURL(for: .kagari))
        let lua = """
        return {
          load = function(path) return true end,
          unload = function() return true end,
          request = function(r)
            return 'SHIORI/3.0 200 OK\\r\\nCharset: UTF-8\\r\\nValue: kagari-real-engine\\r\\n\\r\\n'
          end
        }
        """
        try lua.write(to: root.appendingPathComponent("index.lua"), atomically: true, encoding: .utf8)
        for _ in 0..<2 {
            let loader = try #require(ShioriLoader(moduleURL: module,
                xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
            #expect(loader.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n")?.contains("Value: kagari-real-engine") == true)
            loader.unload()
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent("index.lua"))
        #expect(ShioriLoader(moduleURL: module,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root) == nil)
    }
    @Test
    func productionFactoryResolvesBundledKagariAndUsesDictionaryDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let master = root.appendingPathComponent("ghost/master")
        let directory = master.appendingPathComponent("engine")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lua = """
        return {
          load = function(path) return true end,
          unload = function() return true end,
          request = function(r)
            return 'SHIORI/3.0 200 OK\\r\\nCharset: UTF-8\\r\\nValue: factory-kagari\\r\\n\\r\\n'
          end
        }
        """
        try lua.write(to: directory.appendingPathComponent("index.lua"), atomically: true, encoding: .utf8)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "engine\\kagari.dll"))
        defer { runtime.unload() }
        #expect(runtime.kind == .native)
        #expect(runtime.load(context: .init(ghostURL: root, ghostRoot: master, moduleName: "engine\\kagari.dll")))
        #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "factory-kagari")
    }

}
