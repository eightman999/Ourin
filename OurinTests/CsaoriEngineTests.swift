import Foundation
import Testing
@testable import Ourin

/// Native SHIORI development sample backed by real upstream parser/builder code.
struct CsaoriEngineTests {
    private static var products: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/engines/csaori")
    }
    @Test(.enabled(if: FileManager.default.fileExists(atPath: products.appendingPathComponent("libcsaori-shiori.dylib").path),
                   "Build optional library example: python3 engines/csaori/build.py"))
    func nativeFactoryParsesBuildsAndReloadsInAnotherProcess() throws {
        let (root, master) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "csaori-shiori.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        #expect(runtime.kind == .native)
        for _ in 0..<2 {
            #expect(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 2)?.value == "0.1")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == #"\0\s[0]桜鈴、こんにちは。\e"#)
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["桜鈴 🌸"], timeout: 2)?.value == "桜鈴 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 2)?.status == 204)
            let pid = try String(contentsOf: master.appendingPathComponent("loaded.pid"), encoding: .utf8)
            let loadedPID = try #require(Int32(pid))
            #expect(loadedPID != ProcessInfo.processInfo.processIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(FileManager.default.fileExists(atPath: master.appendingPathComponent("unloaded.marker").path))
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: products.appendingPathComponent("libcsaori-shiori.dylib").path),
                   "Build optional real parser/builder example"))
    func realParserPreservesSparseReferencesAndRejectsInvalidProtocol() throws {
        let (root, master) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = try #require(ShioriLoader(moduleURL: master.appendingPathComponent("libcsaori-shiori.dylib"),
            xpcServiceName: "jp.ourin.shiori", shiori2Compatibility: false, loadDirectory: master))
        defer { loader.unload() }
        let sparse = loader.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnSparse\r\nReference2: 第三 🌸\r\n\r\n")
        #expect(sparse?.contains("Value: 第三 🌸") == true)
        #expect(loader.request("invalid-protocol\r\n\r\n")?.contains("400 Bad Request") == true)
    }

    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-CsaoriEngineTests-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            for name in ["libcsaori-shiori.dylib", "libcsaori-shiori.dylib.plist"] {
                try FileManager.default.copyItem(at: Self.products.appendingPathComponent(name), to: master.appendingPathComponent(name))
            }
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        return (root, master)
    }
}
