import Foundation
import Testing
@testable import Ourin

/// Exercises the actual separately licensed compatibility engine, not a mock VM.
@Suite(.serialized)
struct MisakaEngineTests {
    private func copyDictionary() throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/misaka")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: root)
        return root
    }

    private func request(_ id: String) -> String {
        "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: \(id)\r\n\r\n"
    }

    @Test(arguments: [false, true])
    func bundledMisakaTalksAndRestoresSavedVariables(isolated: Bool) throws {
        let root = try copyDictionary()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try #require(BundledShioriEngine.bundledURL(for: .misaka))
        func load() throws -> ShioriLoader {
            try #require(ShioriLoader(moduleURL: library,
                                     xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
                                     shiori2Compatibility: false, loadDirectory: root))
        }
        let first = try load()
        #expect(first.request(request("OnBoot"))?.contains("ourin-misaka-1") == true)
        #expect(first.request(request("OnBoot"))?.contains("ourin-misaka-2") == true)
        #expect(first.request(request("OnMouseDoubleClick"))?.contains("ourin-misaka-talk") == true)
        #expect(first.request(request("OnClose"))?.contains("ourin-misaka-close") == true)
        first.unload()
        let saved = root.appendingPathComponent("misaka_vars.json")
        #expect(FileManager.default.fileExists(atPath: saved.path))
        let second = try load()
        defer { second.unload() }
        #expect(second.request(request("OnBoot"))?.contains("ourin-misaka-3") == true)
    }

    @Test
    func windowsMisakaNameLoadsThroughProductionRuntime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dictionary = try copyDictionary()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: dictionary)
        }
        try FileManager.default.copyItem(at: dictionary, to: master)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "misaka.dll", ghostRoot: master))
        try #require(runtime.load(context: .init(ghostURL: root, ghostRoot: master, moduleName: "misaka.dll")))
        defer { runtime.unload() }
        #expect(runtime.kind == .native)
        let response = runtime.request(method: "GET", id: "OnBoot", headers: [:], refs: [], timeout: 5)
        #expect(response?.value?.contains("ourin-misaka-1") == true)
    }
}
