import Foundation
import Testing
import Darwin
@testable import Ourin

/// Actual upstream ModuleMain + IronPython, with its original SHIORI 2.2 sample.
struct KanahebiEngineTests {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static var products: URL {
        ProcessInfo.processInfo.environment["OURIN_KANAHEBI_PRODUCTS"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/kanahebi")
    }
    private static let dotnet = ProcessInfo.processInfo.environment["OURIN_KANAHEBI_DOTNET"] ?? "/opt/homebrew/bin/dotnet"
    private static var available: Bool {
        FileManager.default.isExecutableFile(atPath: dotnet) &&
            FileManager.default.fileExists(atPath: products.appendingPathComponent("KanahebiHost.dll").path)
    }

    private func fixture(upstream: Bool) throws -> (URL, ShioriRuntimeLoadContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Kanahebi-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master/会話 engine")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            let script = upstream ? Self.products.appendingPathComponent("upstream-sample-main.py")
                : Self.repository.appendingPathComponent("engines/kanahebi/example/main.py")
            try FileManager.default.copyItem(at: script, to: master.appendingPathComponent("main.py"))
            let arguments = String(data: try JSONEncoder().encode([Self.products.appendingPathComponent("KanahebiHost.dll").path]), encoding: .utf8)!
            try "[SHIOLINK]\nmodule=Kanahebi.dll\nexecutable=\(Self.dotnet)\narguments=\(arguments)\ncharmode=UTF-8\n"
                .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
            return (root, .init(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"), moduleName: "会話 engine/Kanahebi.dll"))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    @Test(.enabled(if: available, "Build optional local host: python3 engines/kanahebi/build.py (.NET SDK 10.0.401)"))
    func unchangedUpstreamSHIORI22SampleSpeaksJapanese() throws {
        let (root, context) = try fixture(upstream: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        for _ in 0..<2 {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "\\0\\s[5]起動しちゃったねー。\\e")
            #expect(runtime.request(method: "GET", id: "OnMouseDoubleClick", refs: ["0", "0", "0", "0", "", "0", "mouse"], timeout: 5)?.value == "\\0\\s[20]つつくなよお。\\e")
            #expect(runtime.request(method: "GET", id: "OnUnknown", timeout: 5)?.status == 204)
            #expect(runtime.request(method: "NOTIFY", id: "OnBoot", timeout: 5)?.status == 204)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
        }
    }

    @Test(.enabled(if: available, "Build optional real Kanahebi IronPython host"))
    func realPythonScriptPrintsEchoesUnicodeAndPersists() throws {
        let (root, context) = try fixture(upstream: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        for count in [1, 2] {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 5)?.value == "Kanahebi/IronPython-3.4.2")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "桜鈴 🌸 \(count)")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["日本語 🌸"], timeout: 5)?.value == "日本語 🌸")
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.value == "終了します。")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            let save = try String(contentsOf: context.ghostRoot.appendingPathComponent("会話 engine/boots.txt"), encoding: .utf8)
            #expect(save == "\(count)")
        }
    }

    @Test(.enabled(if: available, "Build optional real Kanahebi IronPython host"))
    func invalidPythonFailsInsteadOfReturningSyntheticSuccess() throws {
        let (root, context) = try fixture(upstream: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "def invalid syntax !!!".write(to: context.ghostRoot.appendingPathComponent("会話 engine/main.py"), atomically: true, encoding: .utf8)
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        #expect(!adapter.load(context: context))
        #expect(!adapter.isLoaded)
        #expect(adapter.lastError != nil)
        let pid = try #require(adapter.lastProcessIdentifier)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test(.enabled(if: available, "Build optional real Kanahebi IronPython host"))
    func eofInsideRequestExitsWithoutBusyLoop() throws {
        let (root, context) = try fixture(upstream: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        let child = Process(), input = Pipe()
        child.executableURL = URL(fileURLWithPath: Self.dotnet)
        child.arguments = [Self.products.appendingPathComponent("KanahebiHost.dll").path]
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
    }
}
