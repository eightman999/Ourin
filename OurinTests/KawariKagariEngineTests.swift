import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct KawariKagariEngineTests {
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

    @Test
    func bundledResolverPrefersKawariMarkerForShioriDLL() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ghostRoot = root.appendingPathComponent("ghost/master")
        let shioriDir = ghostRoot.appendingPathComponent("shiori")
        try FileManager.default.createDirectory(at: shioriDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "kawarirc".write(to: shioriDir.appendingPathComponent("kawarirc.kis"), atomically: true, encoding: .utf8)
        let engine = try #require(BundledShioriEngine.recognize(moduleName: "shiori\\shiori.dll", ghostRoot: ghostRoot))
        #expect(engine == .kawari)
    }

    @Test(arguments: [false, true])
    func kawariEngineOnBootFromAppBundle(isolated: Bool) throws {
        let fixtureSource = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/kawari/minimal")
        try #require(FileManager.default.fileExists(atPath: fixtureSource.appendingPathComponent("kawarirc.kis").path))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ghostRoot = root.appendingPathComponent("ghost/master")
        let shioriDir = ghostRoot.appendingPathComponent("shiori")
        try FileManager.default.createDirectory(at: shioriDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(
            at: fixtureSource.appendingPathComponent("kawarirc.kis"),
            to: shioriDir.appendingPathComponent("kawarirc.kis")
        )

        let resolved = try #require(
            BundledShioriEngine.resolveModuleURL(
                moduleName: "shiori\\shiori.dll",
                ghostURL: ghostRoot.deletingLastPathComponent(),
                ghostRoot: ghostRoot
            )
        )
        let loader = try #require(ShioriLoader(moduleURL: resolved, xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: shioriDir))
        let boot = loader.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n")
        #expect(boot?.contains("200 OK") == true)
        loader.unload()
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
}
