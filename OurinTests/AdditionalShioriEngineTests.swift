import Foundation
import Testing
@testable import Ourin

/// Actual MIT compatibility libraries and authored dictionaries; no mocked engine.
@Suite(.serialized)
struct AdditionalShioriEngineTests {
    private static let products = ["akari", "ese-shiori", "niseshiori", "shino", "hisui", "yuhna"]
    private static let stateFiles = ["akari": "akari-vars.json", "ese-shiori": "ese-shiori-state.json",
                                     "niseshiori": "nise-shiori-state.json", "shino": "shino-state.json",
                                     "hisui": "hisui-state.json", "yuhna": "yuhna-state.json"]

    private func dictionary(_ product: String, at master: URL) throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/additional-shiori/\(product)")
        try FileManager.default.createDirectory(at: master.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: master)
    }

    private func request(_ event: String, method: String = "GET") -> String {
        "\(method) SHIORI/3.0\r\nCharset: UTF-8\r\nSender: OurinTests\r\nID: \(event)\r\n\r\n"
    }

    @Test(arguments: products, [false, true])
    func bundledEngineLifecycleAndPersistence(product: String, isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let master = root.appendingPathComponent("nested/日本語辞書")
        defer { try? FileManager.default.removeItem(at: root) }
        try dictionary(product, at: master)
        let engine = try #require(BundledShioriEngine.recognize(moduleName: product + ".dll", ghostRoot: master))
        #expect(engine.shioriABI == "ukagaka-int32")
        let library = try #require(BundledShioriEngine.bundledURL(for: engine))
        func load() throws -> ShioriLoader {
            try #require(ShioriLoader(moduleURL: library,
                xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
                shiori2Compatibility: false, loadDirectory: master))
        }
        let first = try load()
        defer { first.unload() }
        #expect(first.request(request("OnBoot"))?.contains("boot:\(product)") == true)
        #expect(first.request(request("OnAITalk"))?.contains("talk:\(product)") == true)
        #expect(first.request(request("OnRemember"))?.contains("Value: remember") == true)
        #expect(first.request(request("OnRecall"))?.contains("Value: 37\r\n") == true)
        #expect(first.request(request("OnUndefinedOurinFixture", method: "NOTIFY"))?.contains("SHIORI/3.0 204") == true)
        #expect(first.request(request("OnClose"))?.contains("close:\(product)") == true)
        first.unload()
        let state = master.appendingPathComponent(try #require(Self.stateFiles[product]))
        #expect(FileManager.default.fileExists(atPath: state.path))
        let second = try load()
        defer { second.unload() }
        // Before any event can reassign the value, confirm the saved state was read.
        #expect(second.request(request("OnRecall"))?.contains("Value: 37\r\n") == true)
        #expect(second.request(request("OnBoot"))?.contains("boot:\(product)") == true)
    }

    @Test(arguments: products)
    func windowsNameUsesProductionNativeRuntimeAndNestedDictionary(product: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let master = root.appendingPathComponent("ghost/master")
        defer { try? FileManager.default.removeItem(at: root) }
        try dictionary(product, at: master.appendingPathComponent("shiori"))
        let name = "shiori\\\(product).dll"
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: name, ghostRoot: master))
        #expect(runtime.kind == .native)
        try #require(runtime.load(context: .init(ghostURL: root, ghostRoot: master, moduleName: name)))
        defer { runtime.unload() }
        let response = runtime.request(method: "GET", id: "OnBoot", headers: [:], refs: [], timeout: 5)
        #expect(response?.status == 200)
        #expect(response?.value?.contains("boot:\(product)") == true)
    }

    @Test(arguments: products, [false, true])
    func secondSameEngineLoadCannotCorruptActiveDictionary(product: String, isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstMaster = root.appendingPathComponent("first")
        let secondMaster = root.appendingPathComponent("second")
        try dictionary(product, at: firstMaster)
        try dictionary(product, at: secondMaster)
        let engine = try #require(BundledShioriEngine.recognize(moduleName: product + ".dll", ghostRoot: firstMaster))
        let library = try #require(BundledShioriEngine.bundledURL(for: engine))
        let first = try #require(ShioriLoader(moduleURL: library,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
            shiori2Compatibility: false, loadDirectory: firstMaster))
        defer { first.unload() }
        #expect(first.request(request("OnRemember"))?.contains("Value: remember") == true)
        let second = ShioriLoader(moduleURL: library,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
            shiori2Compatibility: false, loadDirectory: secondMaster)
        // Upstream singleton engines reject the second session in a shared process.
        // If an OS gives XPC a separate process, its state must remain independent.
        if let second {
            defer { second.unload() }
            #expect(isolated)
            #expect(second.request(request("OnRecall"))?.contains("Value: 37\r\n") != true)
        }
        #expect(first.request(request("OnRecall"))?.contains("Value: 37\r\n") == true)
    }

    @Test
    func genericShioriNameDoesNotGuessBetweenTextDictionaryEngines() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try dictionary("niseshiori", at: root)
        #expect(BundledShioriEngine.recognize(moduleName: "shiori.dll", ghostRoot: root) == nil)
        #expect(BundledShioriEngine.recognize(moduleName: "shiori\\AKARI.DLL", ghostRoot: root) == .akari)
        #expect(BundledShioriEngine.recognize(moduleName: "libese-shiori.dylib", ghostRoot: root) == .eseShiori)
    }
}
