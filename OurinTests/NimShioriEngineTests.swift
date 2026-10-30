import Foundation
import Testing
import Darwin
@testable import Ourin

/// Optional real compiler-built shioridll modules, never a replacement ABI stub.
struct NimShioriEngineTests {
    private static var products: URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return ProcessInfo.processInfo.environment["OURIN_NIM_SHIORI_PRODUCTS"]
            .map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/shioridll-nim")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: products.appendingPathComponent("libnimshiori.dylib").path),
                   "Build optional real Nim modules: python3 engines/shioridll-nim/build.py"))
    func nativeFactoryLoadsJapaneseNimModuleAndReloads() throws {
        let (root, master) = try install("libnimshiori.dylib")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "nimshiori.dll"))
        defer { runtime.unload() }
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "nimshiori.dll")
        #expect(runtime.kind == .native)
        for _ in 0..<2 {
            #expect(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 2)?.value == "0.0.1")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == #"\0\s[0]こんにちは、桜鈴。\e"#)
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["桜鈴 🌸"], timeout: 2)?.value == "桜鈴 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnNotify", timeout: 2)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 2)?.value == #"\0終了します。\-"#)
            let loadedPath = try String(contentsOf: master.appendingPathComponent("nim-loaded.path"), encoding: .utf8)
            #expect(URL(fileURLWithPath: loadedPath).standardizedFileURL.path == master.standardizedFileURL.path)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(FileManager.default.fileExists(atPath: master.appendingPathComponent("nim-unloaded.marker").path))
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: products.appendingPathComponent("libupstream-basic.dylib").path),
                   "Build optional unchanged upstream Nim example"))
    func upstreamBasicExampleRunsWithoutEventChanges() throws {
        let (root, master) = try install("libupstream-basic.dylib")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "upstream-basic.dll"))
        defer { runtime.unload() }
        #expect(runtime.load(context: .init(ghostURL: root, ghostRoot: master, moduleName: "upstream-basic.dll")))
        #expect(runtime.request(method: "GET", id: "version", timeout: 2)?.value == "0.0.1")
        #expect(runtime.request(method: "GET", id: "name", timeout: 2)?.value == "nimshiori")
        #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == #"\0\s[0]aaaaaa\e"#)
        runtime.unload()
        #expect(!runtime.isLoaded)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: products.appendingPathComponent("libnimshiori.dylib").path),
                   "Build optional real Nim modules"))
    func nativeNimEntryPointsRunOnFreshForeignThreads() throws {
        let (root, master) = try install("libnimshiori.dylib")
        defer { try? FileManager.default.removeItem(at: root) }
        for _ in 0..<2 {
            let module = try onForeignThread {
                try NativeShioriModule(url: master.appendingPathComponent("libnimshiori.dylib"), loadDirectory: master)
            }
            defer { module.unload() }
            for _ in 0..<10 {
                let response = try onForeignThread {
                    module.request(Data("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n".utf8))
                }
                let data = try #require(response)
                #expect(String(data: data, encoding: .utf8)?.contains("こんにちは、桜鈴。") == true)
            }
            try onForeignThread { module.unload() }
            #expect(FileManager.default.fileExists(atPath: master.appendingPathComponent("nim-unloaded.marker").path))
        }
    }

    /// Every invocation creates a fresh pthread, matching foreign host entry
    /// without assuming that a serial dispatch queue has a stable OS thread.
    private func onForeignThread<T>(_ action: @escaping () throws -> T) throws -> T {
        let operation = ForeignOperation(action)
        let done = DispatchSemaphore(value: 0)
        let thread = Thread {
            operation.result = Result { try operation.action() }
            done.signal()
        }
        thread.qualityOfService = .userInitiated
        thread.start()
        try #require(done.wait(timeout: .now() + 10) == .success)
        return try #require(operation.result).get()
    }

    private final class ForeignOperation<T>: @unchecked Sendable {
        let action: () throws -> T
        var result: Result<T, Error>?
        init(_ action: @escaping () throws -> T) { self.action = action }
    }

    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private static var universalProducts: URL {
        ProcessInfo.processInfo.environment["OURIN_NIM_SHIORI_UNIVERSAL_PRODUCTS"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/shioridll-nim-universal2")
    }
    private static var universalAvailable: Bool {
        FileManager.default.fileExists(atPath: universalProducts.appendingPathComponent("libnimshiori.dylib").path) &&
            FileManager.default.fileExists(atPath: universalProducts.appendingPathComponent("libupstream-basic.dylib").path)
    }
    private static var intelAvailable: Bool {
        guard universalAvailable else { return false }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/arch")
        child.arguments = ["-x86_64", "/usr/bin/true"]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try child.run(); child.waitUntilExit(); return child.terminationStatus == 0 }
        catch { return false }
    }

    @Test(.enabled(if: universalAvailable, "Build --arch universal2 --output build/engines/shioridll-nim-universal2"))
    func universalNimModuleLoadsThroughProductionNativeFactoryAndReloads() throws {
        let (root, master) = try install("libnimshiori.dylib", products: Self.universalProducts)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: "nimshiori.dll"))
        defer { runtime.unload() }
        #expect(runtime.kind == .native)
        for _ in 0..<2 {
            try #require(runtime.load(context: .init(ghostURL: root, ghostRoot: master, moduleName: "nimshiori.dll")))
            #expect(runtime.request(method: "GET", id: "version", timeout: 2)?.value == "0.0.1")
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 2)?.value == #"\0\s[0]こんにちは、桜鈴。\e"#)
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["Universal 桜鈴 🌸"], timeout: 2)?.value == "Universal 桜鈴 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnNotify", timeout: 2)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 2)?.value == #"\0終了します。\-"#)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(FileManager.default.fileExists(atPath: master.appendingPathComponent("nim-unloaded.marker").path))
        }
    }

    @Test(.enabled(if: intelAvailable, "Build Universal2 Nim modules; existing Rosetta is required on Apple Silicon"))
    func intelSliceRunsRealProductionLoaderAndFreshForeignThreads() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Nim-Intel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("native-probe-x86_64")
        try runCLI(executable: URL(fileURLWithPath: "/usr/bin/xcrun"), arguments: ["swiftc", "-target", "x86_64-apple-macos13.0",
            Self.repository.appendingPathComponent("Ourin/USL/NativeShioriModule.swift").path,
            Self.repository.appendingPathComponent("engines/shioridll-nim/probe/NativeProbe.swift").path,
            "-o", executable.path], timeout: 60)
        let output = try runCLI(executable: URL(fileURLWithPath: "/usr/bin/arch"),
                                arguments: ["-x86_64", executable.path, Self.universalProducts.path], timeout: 30)
        #expect(output.contains("PASS NativeShioriModule x86_64"))
        #if arch(arm64)
        #expect(output.contains("translated=1"))
        #endif
    }

    @discardableResult
    private func runCLI(executable: URL, arguments: [String], timeout: TimeInterval) throws -> String {
        let child = Process(), output = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        try child.run()
        try? output.fileHandleForWriting.close()
        defer {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline { usleep(5_000) }
        try #require(!child.isRunning)
        try #require(child.terminationStatus == 0)
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func install(_ name: String, products: URL? = nil) throws -> (URL, URL) {
        let chosen = products ?? Self.products
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Nim-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            try FileManager.default.copyItem(at: chosen.appendingPathComponent(name), to: master.appendingPathComponent(name))
            try FileManager.default.copyItem(at: chosen.appendingPathComponent(name + ".plist"), to: master.appendingPathComponent(name + ".plist"))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        return (root, master)
    }
}
