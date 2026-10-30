import Foundation
import CryptoKit
import Testing
@testable import Ourin

@Suite(.serialized)
@MainActor
struct EmoRustDistributionTests {
    private static let products = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("build/engines/emo-rs-lua54")
    private static let distribution = products.appendingPathComponent("distribution/emo-gs")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: distribution.appendingPathComponent("OURIN-ORIGINAL-FILES.json").path)
        && FileManager.default.fileExists(atPath: products.appendingPathComponent("libemo.dylib").path),
        "Build emo-rs --lua lua54 and stage_distribution.py for the real original NAR"))
    func originalDistributionTalksAndPersistsThroughNativeFactory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-えも-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: Self.distribution, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = root.appendingPathComponent("ghost/master")
        for name in ["libemo.dylib", "libemo.dylib.plist"] {
            try FileManager.default.copyItem(at: Self.products.appendingPathComponent(name), to: master.appendingPathComponent(name))
        }
        let manifest = try JSONDecoder().decode([String:String].self,
            from: Data(contentsOf: root.appendingPathComponent("OURIN-ORIGINAL-FILES.json")))
        func verifyOriginalFiles() throws {
            for (file, expected) in manifest {
                let data = try Data(contentsOf: root.appendingPathComponent(file))
                #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expected)
            }
        }
        try verifyOriginalFiles()
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "emo.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        let manager = GhostManager(ghostURL: root)
        defer { _ = manager.shutdown() }
        let dispatcher = ShioriDispatcher()
        dispatcher.ghostManager = manager
        dispatcher.useRuntime(runtime)
        for (index, reference) in ["first-persistent-value", "second-transient-value"].enumerated() {
            try #require(runtime.load(context: context))
            if index == 0 {
                #expect(runtime.request(method: "GET", id: "OnFirstBoot", timeout: 5)?.value?.contains("はじめましてや") == true)
            }
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value?.contains("起動したで") == true)
            #expect(runtime.request(method: "GET", id: "OnMouseDoubleClick", refs: ["0", "0", "0", "0", "Head"], timeout: 5)?.value?.contains("ダブルクリックで位置調整") == true)
            #expect(runtime.request(method: "GET", id: "OnTranslate", refs: ["桜鈴 🌸"], timeout: 5)?.value == "桜鈴 🌸")
            // The real ghost initializes its wait state during a talking tick.
            // Exercise the production dispatcher instead of supplying a test-only Status header.
            manager.isPlaying = true
            #expect(dispatcher.sendGet(id: .OnSecondChange, params: ["Reference0":"1"]).isEmpty)
            manager.isPlaying = false
            let idle = dispatcher.sendGet(id: .OnSecondChange, params: ["Reference0":"2"])
            #expect(idle.isEmpty)
            #expect(runtime.request(method: "GET", id: "OnOurinPersistenceProbe", refs: [reference], timeout: 5)?.status == 204)
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.status == 204)
            runtime.unload()
            let save = try String(contentsOf: master.appendingPathComponent("profile/emo/save/save.lua"), encoding: .utf8)
            #expect(save.contains("first-persistent-value"))
            #expect(!save.contains("second-transient-value"))
            try verifyOriginalFiles()
        }
    }
}
