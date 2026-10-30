import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct EmoRustEngineTests {
    private static let products = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("build/engines/emo-rs")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: products.appendingPathComponent("libemo.dylib").path),
                   "Build optional real Rust/Lua engine: python3 engines/emo-rs/build.py"))
    func upstreamRustLuaEventsPersistThroughNativeXPCReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-emo-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master/会話 engine")
        try FileManager.default.createDirectory(at: master.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: Self.products.appendingPathComponent("upstream-script"), to: master)
        for name in ["libemo.dylib", "libemo.dylib.plist"] {
            try FileManager.default.copyItem(at: Self.products.appendingPathComponent(name), to: master.appendingPathComponent(name))
        }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "会話 engine/emo.dll"))
        defer { runtime.unload() }
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"), moduleName: "会話 engine/emo.dll")
        let save = master.appendingPathComponent("profile/emo/save/save.lua")
        #expect(!FileManager.default.fileExists(atPath: save.path))
        for reference in ["first-persistent-value", "second-transient-value"] {
            try #require(runtime.load(context: context))
            let boot = try #require(runtime.request(method: "GET", id: "OnBoot", timeout: 5))
            #expect(boot.status == 200)
            #expect(boot.value?.contains("OnBoot:起動トークです。") == true)
            #expect(runtime.request(method: "GET", id: "OnTranslate", refs: ["桜鈴 🌸"], timeout: 5)?.value == "桜鈴 🌸")
            // Upstream records the first unhandled GET into saved no_entry state.
            #expect(runtime.request(method: "GET", id: "OnOurinPersistenceProbe", refs: [reference], timeout: 5)?.status == 204)
            #expect(runtime.request(method: "NOTIFY", id: "OnNotify", timeout: 5)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.status == 204)
            runtime.unload()
            #expect(!runtime.isLoaded)
            let saved = try String(contentsOf: save, encoding: .utf8)
            #expect(saved.contains("first-persistent-value"))
            #expect(!saved.contains("second-transient-value"))
        }
    }
}
