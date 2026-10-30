import Foundation
import Testing
import Darwin
@testable import Ourin

/// Optional real Rosalind/Roslyn host: scripts compile in the upstream engine.
struct RosalindEngineTests {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static var products: URL {
        ProcessInfo.processInfo.environment["OURIN_ROSALIND_PRODUCTS"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/rosalind")
    }
    private static let dotnet = ProcessInfo.processInfo.environment["OURIN_ROSALIND_DOTNET"] ?? "/opt/homebrew/bin/dotnet"
    private static var available: Bool {
        FileManager.default.isExecutableFile(atPath: dotnet) &&
            FileManager.default.fileExists(atPath: products.appendingPathComponent("Rosalind.NET.CSharp.dll").path)
    }

    private func fixture() throws -> (URL, ShioriRuntimeLoadContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Rosalind-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master/会話 engine")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            let template = try String(contentsOf: Self.repository.appendingPathComponent("engines/rosalind/example/Ghost.csx"), encoding: .utf8)
            let scriptPath = Self.products.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            try template.replacingOccurrences(of: "@ROSALIND_PRODUCTS@", with: scriptPath)
                .write(to: master.appendingPathComponent("Ghost.csx"), atomically: true, encoding: .utf8)
            let arguments = String(data: try JSONEncoder().encode([Self.products.appendingPathComponent("Rosalind.NET.CSharp.dll").path]), encoding: .utf8)!
            try "[SHIOLINK]\nexecutable=\(Self.dotnet)\narguments=\(arguments)\ncharmode=UTF-8\n"
                .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
            return (root, .init(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"), moduleName: "会話 engine/SHIOLINK.dll"))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    @Test(.enabled(if: available, "Build optional real host: python3 engines/rosalind/build.py (.NET SDK 10.0.401)"))
    func realCSharpScriptTalksAndPersistsAcrossProcesses() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: context.moduleName))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        for count in [1, 2] {
            #expect(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 5)?.value == "0.1.6")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "桜鈴 🌸 \(count)")
            #expect(runtime.request(method: "GET", id: "OnMouseDoubleClick",
                refs: ["日本語 🌸", "0", "0", "0", "", "0", "mouse"], timeout: 5)?.value == "日本語 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 200)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.value == "終了します。")
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            let save = context.ghostRoot.appendingPathComponent("会話 engine/savedata.json")
            let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: save)) as? [String: Any])
            #expect((json["Boots"] as? Int) == count)
        }
    }

    @Test(.enabled(if: available, "Build optional real Rosalind host"))
    func eofInsideRequestSavesAndExitsWithoutBusyLoop() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        let child = Process(), input = Pipe()
        child.executableURL = URL(fileURLWithPath: Self.dotnet)
        child.arguments = [Self.products.appendingPathComponent("Rosalind.NET.CSharp.dll").path]
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
        #expect(FileManager.default.fileExists(atPath: master.appendingPathComponent("savedata.json").path))
    }
}
