import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct KawariEngineTests {
    private static var module: URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return ProcessInfo.processInfo.environment["OURIN_KAWARI_ENGINE"]
            .map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/kawari/libkawari_shiori.dylib")
    }

    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("engines/kawari/example/kawarirc.kis")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: module.path),
                   "Build the real KAWARI engine: bash engines/kawari/build.sh"), arguments: [false, true])
    func realEngineLifecycleAndPersistence(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-華和梨-\(UUID().uuidString)")
        let dictionary = root.appendingPathComponent("ghost/master/辞書")
        try FileManager.default.createDirectory(at: dictionary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture, to: dictionary.appendingPathComponent("kawarirc.kis"))
        let module = Self.module
        for pass in 0..<2 {
            let loader = try #require(ShioriLoader(moduleURL: module,
                xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: dictionary))
            defer { loader.unload() }
            func request(_ id: String, ref: String? = nil, method: String = "GET") throws -> ShioriRuntimeResponse {
                let wire = ShioriWireCodec.makeRequest(method: method, id: id,
                    headers: ["SecurityLevel": "local"], refs: ref.map { [$0] } ?? [])
                let answer = try #require(loader.request(wire))
                return try #require(ShioriWireCodec.parseResponse(answer))
            }
            #expect(try request("OnBoot").value == #"\0桜鈴・華和梨起動\e"#)
            #expect(try request("OnEcho", ref: "表ソ・日本語😀").value == "表ソ・日本語😀")
            #expect(try request("OnUnknown", method: "NOTIFY").status == 204)
            if pass == 0 {
                #expect(try request("OnSet", ref: "保存値・桜鈴😀").value == "saved")
            } else {
                #expect(try request("OnRead").value == "保存値・桜鈴😀")
            }
            #expect(try request("OnClose").value == #"\0華和梨終了\-"#)
            loader.unload()
            #expect(loader.request("GET SHIORI/3.0\r\n\r\n") == nil)
            #expect(FileManager.default.fileExists(atPath: dictionary.appendingPathComponent("state.kis").path))
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: module.path),
                   "Build the real KAWARI engine: bash engines/kawari/build.sh"))
    func productionFactoryUsesGhostLocalPortAndNestedDictionary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Kawari-Factory-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        let dictionary = master.appendingPathComponent("辞書")
        try FileManager.default.createDirectory(at: dictionary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture, to: dictionary.appendingPathComponent("kawarirc.kis"))
        let localModule = dictionary.appendingPathComponent("libkawari.dylib")
        try FileManager.default.copyItem(at: Self.module, to: localModule)
        try FileManager.default.copyItem(at: Self.module.appendingPathExtension("plist"),
                                         to: localModule.appendingPathExtension("plist"))
        let moduleName = "辞書\\kawari.dll"
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: moduleName)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        #expect(runtime.kind == .native)
        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == #"\0桜鈴・華和梨起動\e"#)
        #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["別processの華和梨😀"], timeout: 5)?.value == "別processの華和梨😀")
        runtime.unload()
        #expect(!runtime.isLoaded)
    }
}
