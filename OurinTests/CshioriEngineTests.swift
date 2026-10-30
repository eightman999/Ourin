import Foundation
import Testing
import Darwin
@testable import Ourin

/// Runs the unchanged upstream C example through Ourin's production SHIOLINK adapter.
struct CshioriEngineTests {
    private static var executable: URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return ProcessInfo.processInfo.environment["OURIN_CSHIORI_EXECUTABLE"]
            .map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/cshiori/shiori")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build optional upstream example: python3 engines/cshiori/build.py"))
    func pinnedUpstreamExampleLifecycleAndJapanese() throws {
        let executable = Self.executable
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Cshiori-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "[SHIOLINK]\nexecutable=\(executable.path)\narguments=[]\ncharmode=Shift_JIS\n"
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "SHIOLINK.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "SHIOLINK.dll"))
        defer { runtime.unload() }
        #expect(runtime.kind == .shiolink)
        for _ in 0..<2 {
            #expect(runtime.load(context: context))
            #expect(runtime.isLoaded)
            let version = try #require(runtime.request(method: "GET", id: "version", timeout: 2))
            #expect(version.status == 200)
            #expect(version.value == "0.0.1")
            #expect(runtime.request(method: "GET", id: "name", timeout: 2)?.value == "cshiori")
            #expect(runtime.request(method: "GET", id: "craftmanw", timeout: 2)?.value == "奈良阪某")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == #"\h\s[0]起動。\e"#)
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", refs: ["桜鈴"], timeout: 2)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 2)?.value == #"\h\s[0]終了。\w9\-"#)
            let adapter = try #require(runtime as? ShiolinkAdapter)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 1) == nil)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
        }
    }
}
