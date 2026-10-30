import Foundation
import Testing
import Darwin
@testable import Ourin

@Suite(.serialized)
struct NashiEngineTests {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let executable = ProcessInfo.processInfo.environment["OURIN_NASHI_EXECUTABLE"]
        .map { URL(fileURLWithPath: $0) }
        ?? repository.appendingPathComponent("build/engines/nashi/nashi-shiolink")

    private func ghost(at root: URL, initialValue: Int = 0, cp932: Bool = false) throws -> ShioriRuntimeLoadContext {
        let master = root.appendingPathComponent("ghost/master/日本語 辞書")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        var fixture = try #require(try JSONSerialization.jsonObject(with:
            Data(contentsOf: Self.repository.appendingPathComponent("engines/nashi/fixture.json"))) as? [String: Any])
        fixture["variables"] = [["name": "回数", "value": initialValue]]
        try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys, .prettyPrinted])
            .write(to: master.appendingPathComponent("ghost.json"))
        try "[SHIOLINK]\nmodule=nashi.dll\nexecutable=\(Self.executable.path)\narguments=[]\ncharmode=UTF-8\n"
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        var communication = ShioriCommunicationOptions()
        if cp932 { communication.encoding = "CP932" }
        return .init(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"),
                     moduleName: "日本語 辞書\\nashi.dll", communication: communication)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build real nashi: python3 engines/nashi/build.py"))
    func parallelGhostsRetainSeparateVMsAfterOneUnloadsAndReloads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Nashi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstContext = try ghost(at: root.appendingPathComponent("A"))
        let secondContext = try ghost(at: root.appendingPathComponent("B"), initialValue: 100)
        let first = try #require(ShioriRuntimeFactory.makeRuntime(context: firstContext))
        let second = try #require(ShioriRuntimeFactory.makeRuntime(context: secondContext))
        defer { first.unload(); second.unload() }
        #expect(first.kind == .shiolink)
        #expect(second.kind == .shiolink)
        try #require(first.load(context: firstContext))
        try #require(second.load(context: secondContext))
        let firstPID = try #require((first as? ShiolinkAdapter)?.lastProcessIdentifier)
        let secondPID = try #require((second as? ShiolinkAdapter)?.lastProcessIdentifier)
        #expect(firstPID != secondPID)
        // Upstream metadata is intentionally preserved; package/source version is separate.
        #expect(first.request(method: "GET", id: "version", timeout: 3)?.value == "1.0.0")
        #expect(first.request(method: "GET", id: "OnBoot", timeout: 3)?.value == #"桜鈴 🌸 1\e"#)
        #expect(second.request(method: "GET", id: "OnBoot", timeout: 3)?.value == #"桜鈴 🌸 101\e"#)
        #expect(first.request(method: "GET", id: "OnEcho", refs: ["表ソ・日本語🌸"], timeout: 3)?.value == #"表ソ・日本語🌸\e"#)
        #expect(first.request(method: "NOTIFY", id: "OnIncrement", timeout: 3)?.status == 204)
        #expect(first.request(method: "GET", id: "OnClose", timeout: 3)?.value == #"桜鈴・なし栞終了\-"#)
        first.unload()
        #expect(kill(firstPID, 0) == -1)
        #expect(errno == ESRCH)
        #expect(kill(secondPID, 0) == 0)
        #expect(second.request(method: "GET", id: "OnRead", timeout: 3)?.value == #"保存 101\e"#)
        #expect(second.request(method: "GET", id: "OnBoot", timeout: 3)?.value == #"桜鈴 🌸 102\e"#)
        second.unload()
        for (runtime, context, expected) in [(first, firstContext, 11), (second, secondContext, 102)] {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "OnRead", timeout: 3)?.value == "保存 \(expected)\\e")
            runtime.unload()
            let savedURL = context.ghostRoot.appendingPathComponent("日本語 辞書/nashi_save.json")
            let saved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: savedURL)) as? [String: Any])
            let variables = try #require(saved["vars"] as? [String: Any])
            #expect(variables["回数"] as? Int == expected)
        }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build real nashi: python3 engines/nashi/build.py"))
    func cp932RequestsUseUpstreamConversionAndUTF8Responses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Nashi-CP932-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try ghost(at: root, cp932: true)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        try #require(runtime.load(context: context))
        let response = try #require(runtime.request(method: "GET", id: "OnEcho", refs: ["表ソ・日本語ｶﾅ"], timeout: 3))
        #expect(response.status == 200)
        #expect(response.value == #"表ソ・日本語ｶﾅ\e"#)
        #expect(response.headers?["Charset"] == "UTF-8")
    }
}
