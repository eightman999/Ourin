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

    private func dictionary(at root: URL, boot: String = "aosora-real-boot", count: Int = 37) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "main.as\n".write(to: root.appendingPathComponent("ghost.asproj"), atomically: true, encoding: .utf8)
        let source = """
        function OnBoot { return "\(boot)"; }
        function OnAITalk { return "aosora-real-talk"; }
        function OnClose { return "aosora-real-close"; }
        function OnRemember { Save.Data.count = \(count); return "remembered"; }
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
        defer { loader.unload() }
        #expect(loader.request(request("OnBoot"))?.contains("aosora-real-boot") == true)
        let otherRoot = root.appendingPathComponent("other-instance")
        try dictionary(at: otherRoot, boot: "aosora-other-boot", count: 91)
        // The official POSIX entrypoint allocates distinct instances. Check both
        // dictionaries and persistent state, including after one is unloaded.
        let other = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: otherRoot))
        defer { other.unload() }
        #expect(other.request(request("OnBoot"))?.contains("aosora-other-boot") == true)
        #expect(loader.request(request("OnBoot"))?.contains("aosora-real-boot") == true)
        #expect(loader.request(request("OnRemember"))?.contains("remembered") == true)
        #expect(other.request(request("OnRemember"))?.contains("remembered") == true)
        #expect(loader.request(request("OnRecall"))?.contains("Value: 37\r\n") == true)
        #expect(other.request(request("OnRecall"))?.contains("Value: 91\r\n") == true)
        #expect(loader.request(request("OnClose"))?.contains("aosora-real-close") == true)
        loader.unload()
        #expect(loader.request(request("OnBoot")) == nil)
        #expect(other.request(request("OnRecall"))?.contains("Value: 91\r\n") == true)
        other.unload()
        let second = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
        defer { second.unload() }
        #expect(second.request(request("OnRecall"))?.contains("Value: 37\r\n") == true)
        second.unload()
        let otherReloaded = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: otherRoot))
        defer { otherReloaded.unload() }
        #expect(otherReloaded.request(request("OnRecall"))?.contains("Value: 91\r\n") == true)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: privateLibrary.path),
        "Optional personal Aosora build is absent; never fetched or redistributed by tests"),
          arguments: [false, true], [false, true])
    func dictionaryErrorsAreReportedWithoutOverwritingSavedState(isolated: Bool, missingScript: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try dictionary(at: root)
        let seed = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
        #expect(seed.request(request("OnRemember"))?.contains("remembered") == true)
        seed.unload()
        let saveURL = root.appendingPathComponent("savedata.asv")
        let savedBefore = try Data(contentsOf: saveURL)
        if missingScript {
            try FileManager.default.removeItem(at: root.appendingPathComponent("main.as"))
        } else {
            try "function Broken { !! invalid }".write(to: root.appendingPathComponent("main.as"),
                atomically: true, encoding: .utf8)
        }
        // Aosora's Shiori::Load is void and its POSIX wrapper still returns an
        // instance ID on dictionary errors. The error contract is the first
        // OnBoot response, not an ABI load failure (the zero-ID fixture above
        // separately verifies genuine ABI rejection).
        let broken = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
        defer { broken.unload() }
        let wire = try #require(broken.request(request("OnBoot")))
        let response = try #require(ShioriWireCodec.parseResponse(wire))
        #expect(response.status == 200)
        #expect(response.headers?["ErrorLevel"] == "error")
        let description = try #require(response.headers?["ErrorDescription"])
        #expect(description.contains("main.as:1"))
        #expect(description.contains(missingScript ? "[S002]" : "[A008]"))
        #expect(response.value?.contains("OnAosoraErrorView") == true)
        let talk = try #require(broken.request(request("OnAITalk")))
        #expect(ShioriWireCodec.parseResponse(talk)?.status == 204)
        broken.unload()
        #expect(try Data(contentsOf: saveURL) == savedBefore)
        try dictionary(at: root)
        let recovered = try #require(ShioriLoader(moduleURL: Self.privateLibrary,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: root))
        defer { recovered.unload() }
        #expect(recovered.request(request("OnBoot"))?.contains("aosora-real-boot") == true)
        #expect(recovered.request(request("OnRecall"))?.contains("Value: 37\r\n") == true)
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

    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static var module: URL {
        ProcessInfo.processInfo.environment["OURIN_AOSORA_ENGINE"]
            .map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/aosora/libaosora.dylib")
    }

    private func makeGhost(in root: URL) throws -> URL {
        let dictionary = root.appendingPathComponent("ghost/master/蒼空")
        try FileManager.default.createDirectory(at: dictionary, withIntermediateDirectories: true)
        let example = Self.repository.appendingPathComponent("engines/aosora/example")
        for file in ["ghost.asproj", "main.as"] {
            try FileManager.default.copyItem(at: example.appendingPathComponent(file), to: dictionary.appendingPathComponent(file))
        }
        return dictionary
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: module.path),
                   "Build real Aosora first: python3 engines/aosora/build.py"), arguments: [false, true])
    func realInterpreterLifecycleAndSaveAcrossReload(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Aosora-\(UUID().uuidString)")
        let dictionary = try makeGhost(in: root)
        defer { try? FileManager.default.removeItem(at: root) }
        for pass in 0..<2 {
            let loader = try #require(ShioriLoader(moduleURL: Self.module,
                xpcServiceName: isolated ? "jp.ourin.shiori" : nil, loadDirectory: dictionary))
            defer { loader.unload() }
            func request(_ id: String, ref: String? = nil, method: String = "GET") throws -> ShioriRuntimeResponse {
                let wire = ShioriWireCodec.makeRequest(method: method, id: id,
                    headers: ["SecurityLevel": "local"], refs: ref.map { [$0] } ?? [])
                let answer = try #require(loader.request(wire))
                return try #require(ShioriWireCodec.parseResponse(answer))
            }
            #expect(try request("OnBoot").value == #"\0蒼空・桜鈴起動\e"#)
            #expect(try request("OnEcho", ref: "表ソ・桜鈴😀").value == "表ソ・桜鈴😀")
            #expect(try request("OnUnknown", method: "NOTIFY").status == 204)
            #expect(loader.request("POST SHIORI/3.0\r\n\r\n")?.contains("400 Bad Request") == true)
            if pass == 0 {
                #expect(try request("OnSet", ref: "保存した蒼空😀").value == "saved")
            } else {
                #expect(try request("OnRead").value == "保存した蒼空😀")
            }
            #expect(try request("OnClose").value == #"蒼空終了\-"#)
            loader.unload()
            #expect(loader.request("GET SHIORI/3.0\r\n\r\n") == nil)
            #expect(FileManager.default.fileExists(atPath: dictionary.appendingPathComponent("savedata.asv").path))
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: module.path),
                   "Build real Aosora first: python3 engines/aosora/build.py"))
    func productionFactoryKeepsNestedWindowsDescriptor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Aosora-Factory-\(UUID().uuidString)")
        let dictionary = try makeGhost(in: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = dictionary.appendingPathComponent("libaosora.dylib")
        try FileManager.default.copyItem(at: Self.module, to: local)
        try FileManager.default.copyItem(at: Self.module.appendingPathExtension("plist"), to: local.appendingPathExtension("plist"))
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"),
                                              moduleName: "蒼空\\aosora.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        #expect(runtime.kind == .native)
        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["Factory・日本語😀"], timeout: 5)?.value == "Factory・日本語😀")
    }
}
