import Foundation
import Testing
import Darwin
@testable import Ourin

/// Optional local builds execute both the historical x86_64 and native ARM64 SDK variants.
struct DktrtkEngineTests {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static var availableExecutables: [URL] {
        let environment = ProcessInfo.processInfo.environment
        let candidates = environment["OURIN_DKTRTK_EXECUTABLE"].map { [URL(fileURLWithPath: $0)] }
            ?? ["dktrtk", "dktrtk-arm64"].map { repository.appendingPathComponent("build/engines/\($0)/dktrtk-host") }
        return candidates.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func fixture(executable: URL, cp932: Bool = false) throws -> (URL, ShioriRuntimeLoadContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Dktrtk-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master/会話 engine")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            let source = cp932 ? "engines/dktrtk/example-cp932/index.as" : "engines/dktrtk/example/index.as"
            try FileManager.default.copyItem(at: Self.repository.appendingPathComponent(source),
                                             to: master.appendingPathComponent("index.as"))
            let options = cp932 ? "arguments=[\"--wire-charset\",\"CP932\"]\ncharmode=Shift_JIS\n" : "charmode=UTF-8\n"
            try "[SHIOLINK]\nmodule=dktrtk.dll\nexecutable=\(executable.path)\n\(options)"
                .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
            return (root, .init(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"), moduleName: "会話 engine/dktrtk.dll"))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    @Test(arguments: availableExecutables)
    func realAngelScriptExecutesAndPersistsAcrossProcesses(executable: URL) throws {
        let (root, context) = try fixture(executable: executable)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        for count in [1, 2] {
            try #require(runtime.load(context: context))
            #expect(runtime.kind == .shiolink)
            #expect(runtime.request(method: "GET", id: "version", timeout: 5)?.value == "dktrtk/AngelScript")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "桜鈴 🌸 \(count)")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["日本語 🌸"], timeout: 5)?.value == "日本語 🌸")
            #expect(runtime.request(method: "GET", id: "OnMath", timeout: 5)?.value == "計算 9")
            #expect(runtime.request(method: "GET", id: "OnFilesystem", timeout: 5)?.value == "filesystem OK")
            #expect(runtime.request(method: "GET", id: "OnAddons", timeout: 5)?.value == "addons OK")
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.value == "終了します。")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            let path = try String(contentsOf: master.appendingPathComponent("loaded-path.txt"), encoding: .utf8)
            #expect(path == master.path + "/")
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            let save = try Data(contentsOf: master.appendingPathComponent("savedata.bin"))
            #expect(Array(save) == [UInt8(count), 0, 0, 0])
        }
    }

    @Test(arguments: availableExecutables)
    func invalidScriptFailsInsteadOfReturningSyntheticSuccess(executable: URL) throws {
        let (root, context) = try fixture(executable: executable)
        defer { try? FileManager.default.removeItem(at: root) }
        try "invalid script syntax !!!".write(to: context.ghostRoot.appendingPathComponent("会話 engine/index.as"),
                                               atomically: true, encoding: .utf8)
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        #expect(!adapter.load(context: context))
        #expect(!adapter.isLoaded)
        #expect(adapter.lastError != nil)
        let pid = try #require(adapter.lastProcessIdentifier)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test(arguments: availableExecutables)
    func eofInsideRequestRunsRealScriptUnload(executable: URL) throws {
        let (root, context) = try fixture(executable: executable)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        let child = Process(), input = Pipe()
        child.executableURL = executable
        child.currentDirectoryURL = master
        child.standardInput = input
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        try input.fileHandleForWriting.write(contentsOf: Data("*L:\(master.path)/\r\n*S:eof\r\nGET SHIORI/3.0\r\n".utf8))
        try input.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
        try #require(!child.isRunning)
        #expect(child.terminationStatus == 0)
        let save = try Data(contentsOf: master.appendingPathComponent("savedata.bin"))
        #expect(Array(save) == [0, 0, 0, 0])
    }
    @Test(arguments: availableExecutables)
    func cp932WirePreservesJapaneseSaveReloadAndUnicodeLoadPath(executable: URL) throws {
        // Self-authored UTF-8 source; the host explicitly bridges CP932 wire frames.
        let (root, context) = try fixture(executable: executable, cp932: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        let reference = "日本語 表ソ 半角ｶﾅ ①髙"
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        for count in [1, 2] {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "桜鈴 表ソ \(count)")
            if count == 2 {
                #expect(runtime.request(method: "GET", id: "OnRemembered", timeout: 5)?.value == reference)
            }
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: [reference], timeout: 5)?.value == reference)
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", refs: [reference + " 通知"], timeout: 5)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnRemembered", timeout: 5)?.value == reference + " 通知")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: [reference], timeout: 5)?.value == reference)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.value == "終了します。")
            #expect(try String(contentsOf: master.appendingPathComponent("loaded-path.txt"), encoding: .utf8) == master.path + "/")
            runtime.unload()
            let saved = try Data(contentsOf: master.appendingPathComponent("savedata.bin"))
            #expect(saved == Data([UInt8(count), 0, 0, 0]) + Data(reference.utf8))
        }
    }

    @Test(arguments: availableExecutables)
    func cp932RejectsUnrepresentableRequestAndResponse(executable: URL) throws {
        let (root, context) = try fixture(executable: executable, cp932: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        try #require(adapter.load(context: context))
        #expect(adapter.request(method: "GET", id: "OnEcho", refs: ["🌸"], timeout: 5) == nil)
        #expect(!adapter.isLoaded)
        #expect(adapter.lastError != nil)
        try #require(adapter.load(context: context))
        #expect(adapter.request(method: "GET", id: "OnEmoji", timeout: 5) == nil)
        #expect(!adapter.isLoaded)
        #expect(adapter.lastError != nil)
    }

    @Test(arguments: availableExecutables)
    func nonUTF8SourceFailsExplicitlyInsteadOfCorruptingLiteral(executable: URL) throws {
        let (root, context) = try fixture(executable: executable, cp932: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        let invalid = try Data(contentsOf: Self.repository.appendingPathComponent("engines/dktrtk/example-cp932/unsupported-cp932-source.as"))
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        for included in [false, true] {
            if included {
                try "#include \"legacy.as\"\n".write(to: master.appendingPathComponent("index.as"), atomically: true, encoding: .utf8)
                try invalid.write(to: master.appendingPathComponent("legacy.as"))
            } else {
                try invalid.write(to: master.appendingPathComponent("index.as"))
            }
            #expect(!adapter.load(context: context))
            #expect(!adapter.isLoaded)
            #expect(adapter.lastError != nil)
        }
    }

}
