import Foundation
import Testing
import Darwin
@testable import Ourin

/// Actual upstream Gohst handlers and shiorigo parser/builder, not a protocol stub.
struct GoShioriEngineTests {
    private static var executable: URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return ProcessInfo.processInfo.environment["OURIN_GO_SHIORI_EXECUTABLE"]
            .map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/shiorigo/gohst-shiolink")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build optional real Gohst engine: python3 engines/shiorigo/build.py"))
    func upstreamGohstThroughFactoryBootNotifyCloseAndProcessRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-GoShiori-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "[SHIOLINK]\nexecutable=\(Self.executable.path)\narguments=[]\ncharmode=UTF-8\n"
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "SHIOLINK.dll"))
        defer { runtime.unload() }
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "SHIOLINK.dll")
        for _ in 0..<2 {
            #expect(runtime.load(context: context))
            #expect(runtime.kind == .shiolink)
            #expect(runtime.request(method: "GET", id: "version", timeout: 2)?.value == "1.00")
            #expect(runtime.request(method: "GET", id: "name", timeout: 2)?.value == "gohst")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == #"\1\s[10]\0\s[1]これは Go で栞を作るサンプルだから、\w2過度な期待はしないよーに。\e"#)
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", refs: ["桜鈴 🌸"], timeout: 2)?.status == 204)
            // The upstream initial talk threshold is 15 seconds. The fresh
            // process's first 14 events must remain silent on every restart.
            for _ in 0..<14 {
                #expect(runtime.request(method: "GET", id: "OnSecondChange", timeout: 2)?.status == 204)
            }
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 2)?.value == #"\1\s[10]\0\s[5]じゃ、\w2えんいー！\_w[500]\e"#)
            let adapter = try #require(runtime as? ShiolinkAdapter)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            // Upstream OnUnload is intentionally a no-op and has no save file.
            #expect(try FileManager.default.contentsOfDirectory(atPath: master.path) == ["SHIOLINK.ourin.ini"])
        }
    }
}
