import Foundation
import Testing
import Darwin
@testable import Ourin

/// Actual mruby SDK executing aktk's published callback interface.
struct AktkEngineTests {
    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private static var executable: URL {
        ProcessInfo.processInfo.environment["OURIN_AKTK_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/aktk/aktk-shiolink")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build optional real mruby engine: python3 engines/aktk/build.py"))
    func explicitAktkPortRunsRubyJapaneseExceptionsSaveAndReload() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        #expect(runtime.kind == .shiolink)
        for count in 1...2 {
            #expect(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 2)?.value == "0.1")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == "\\0\\s[0]mruby起動 \(count)。\\e")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["桜鈴 🌸"], timeout: 2)?.value == "桜鈴 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnNotify", timeout: 2)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnRaise", timeout: 2)?.status == 500)
            #expect(runtime.request(method: "GET", id: "OnWrongType", timeout: 2)?.status == 500)
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["例外後も継続"], timeout: 2)?.value == "例外後も継続")
            let adapter = try #require(runtime as? ShiolinkAdapter)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            let saved = try String(contentsOf: context.ghostRoot.appendingPathComponent("state.txt"), encoding: .utf8)
            #expect(saved == String(count))
        }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build optional real mruby engine"))
    func invalidRubySourceFailsWithoutLeakingChild() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try "raise 'expected bad dictionary'\n".write(to: context.ghostRoot.appendingPathComponent("index.rb"), atomically: true, encoding: .utf8)
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        #expect(!adapter.load(context: context))
        #expect(!adapter.isLoaded)
        let pid = try #require(adapter.lastProcessIdentifier)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    private func fixture() throws -> (URL, ShioriRuntimeLoadContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Aktk-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: Self.repository.appendingPathComponent("engines/aktk/example/index.rb"), to: master.appendingPathComponent("index.rb"))
            try "[SHIOLINK]\nmodule=aktk.dll\nexecutable=\(Self.executable.path)\narguments=[]\ncharmode=UTF-8\n"
                .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        return (root, .init(ghostURL: root, ghostRoot: master, moduleName: "aktk.dll"))
    }
}
