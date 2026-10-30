import Foundation
import Testing
import Darwin
@testable import Ourin

/// Real Tcl interpreter and the pinned krht load/request/unload operations.
struct KrhtEngineTests {
    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private static var executable: URL {
        ProcessInfo.processInfo.environment["OURIN_KRHT_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/krht/krht-shiolink")
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build optional real Tcl engine: python3 engines/krht/build.py"))
    func realTclJapaneseStateSaveUnloadAndReload() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "SHIOLINK.dll"))
        defer { runtime.unload() }
        for count in 1...2 {
            #expect(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 2)?.value == "0.1")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == "\\0\\s[0]Tcl起動 \(count)。\\e")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["桜鈴 🌸"], timeout: 2)?.value == "桜鈴 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnNotify", timeout: 2)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 2)?.value == #"\0終了します。\-"#)
            let adapter = try #require(runtime as? ShiolinkAdapter)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            let saved = try String(contentsOf: context.ghostRoot.appendingPathComponent("state.txt"), encoding: .utf8)
            #expect(saved.trimmingCharacters(in: .whitespacesAndNewlines) == String(count))
        }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: executable.path),
                   "Build optional real Tcl engine"))
    func invalidTclSourceFailsLoadAndReapsChild() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try "error {expected invalid source}\n".write(to: context.ghostRoot.appendingPathComponent("index.tcl"), atomically: true, encoding: .utf8)
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        #expect(!adapter.load(context: context))
        #expect(!adapter.isLoaded)
        let pid = try #require(adapter.lastProcessIdentifier)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: executable.deletingLastPathComponent().appendingPathComponent("lib/tcl9.1/init.tcl").path),
                   "Build the source-backed relocatable Tcl runtime"))
    func relocatedRuntimePreservesStateOnPartialRequestEOF() throws {
        let (root, context) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let products = root.appendingPathComponent("runtime 日本語")
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let executable = products.appendingPathComponent("krht-shiolink")
        try FileManager.default.copyItem(at: Self.executable, to: executable)
        try FileManager.default.copyItem(at: Self.executable.deletingLastPathComponent().appendingPathComponent("lib"),
                                        to: products.appendingPathComponent("lib"))
        try "[SHIOLINK]\nmodule=krht.dll\nexecutable=\(executable.path)\ncharmode=UTF-8\n"
            .write(to: context.ghostRoot.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let load = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: context.ghostRoot, moduleName: "krht.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: load))
        defer { runtime.unload() }
        try #require(runtime.load(context: load))
        #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["移動済み 🌸"], timeout: 2)?.value == "移動済み 🌸")
        runtime.unload()

        let child = Process(), input = Pipe()
        child.executableURL = executable
        child.environment = ProcessInfo.processInfo.environment.merging(["TCL_LIBRARY": "/nonexistent-ourin-tcl"]) { _, replacement in replacement }
        child.standardInput = input
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run()
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        try input.fileHandleForWriting.write(contentsOf: Data("*L:\(context.ghostRoot.path)/\r\n*S:eof\r\nGET SHIORI/3.0\r\n".utf8))
        try input.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
        try #require(!child.isRunning)
        #expect(child.terminationStatus == 6)
        #expect(try String(contentsOf: context.ghostRoot.appendingPathComponent("state.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    private static var intelExecutable: URL {
        ProcessInfo.processInfo.environment["OURIN_KRHT_X86_64_EXECUTABLE"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/krht-x86_64/krht-shiolink")
    }
    private static var intelAvailable: Bool {
        guard FileManager.default.isExecutableFile(atPath: intelExecutable.path),
              FileManager.default.fileExists(atPath: intelExecutable.deletingLastPathComponent().appendingPathComponent("lib/tcl9.1/init.tcl").path) else { return false }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        child.arguments = ["-x86_64", "/usr/bin/true"]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try child.run(); child.waitUntilExit(); return child.terminationStatus == 0 }
        catch { return false }
    }

    @Test(.enabled(if: intelAvailable, "Build --arch x86_64 --output build/engines/krht-x86_64; existing Rosetta is required on Apple Silicon"))
    func intelTclJapaneseStateSaveReloadAndRelocation() throws {
        let (root, context) = try fixture(executable: Self.intelExecutable)
        defer { try? FileManager.default.removeItem(at: root) }
        let products = root.appendingPathComponent("Intel runtime 日本語")
        try FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
        let host = products.appendingPathComponent("krht-shiolink")
        try FileManager.default.copyItem(at: Self.intelExecutable, to: host)
        try FileManager.default.copyItem(at: Self.intelExecutable.deletingLastPathComponent().appendingPathComponent("lib"), to: products.appendingPathComponent("lib"))
        try "[SHIOLINK]\nmodule=krht.dll\nexecutable=\(host.path)\ncharmode=UTF-8\n"
            .write(to: context.ghostRoot.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let load = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: context.ghostRoot, moduleName: "krht.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: load))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        for count in 1...2 {
            try #require(runtime.load(context: load))
            #expect(runtime.request(method: "GET", id: "OnArchitecture", timeout: 2)?.value == "9.1.0/x86_64")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == "\\0\\s[0]Tcl起動 \(count)。\\e")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["移動したIntel 🌸"], timeout: 2)?.value == "移動したIntel 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnNotify", timeout: 2)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 2)?.value == #"\0終了します。\-"#)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            #expect(try String(contentsOf: context.ghostRoot.appendingPathComponent("state.txt"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) == String(count))
        }
    }

    @Test(.enabled(if: intelAvailable, "Build optional Intel Tcl runtime; existing Rosetta is required on Apple Silicon"))
    func intelTclPartialRequestEOFExecutesUnload() throws {
        let (root, context) = try fixture(executable: Self.intelExecutable)
        defer { try? FileManager.default.removeItem(at: root) }
        let child = Process(), input = Pipe()
        child.executableURL = Self.intelExecutable
        child.environment = ProcessInfo.processInfo.environment.merging(["TCL_LIBRARY": "/nonexistent-ourin-tcl"]) { _, replacement in replacement }
        child.standardInput = input
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        try input.fileHandleForWriting.write(contentsOf: Data("*L:\(context.ghostRoot.path)/\r\n*S:eof\r\nGET SHIORI/3.0\r\n".utf8))
        try input.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
        try #require(!child.isRunning)
        #expect(child.terminationStatus == 6)
        #expect(try String(contentsOf: context.ghostRoot.appendingPathComponent("state.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    private func fixture(executable: URL? = nil) throws -> (URL, ShioriRuntimeLoadContext) {
        let chosen = executable ?? Self.executable
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Krht-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: Self.repository.appendingPathComponent("engines/krht/example/index.tcl"), to: master.appendingPathComponent("index.tcl"))
            try "[SHIOLINK]\nexecutable=\(chosen.path)\narguments=[]\ncharmode=UTF-8\n"
                .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        return (root, .init(ghostURL: root, ghostRoot: master, moduleName: "SHIOLINK.dll"))
    }
}
