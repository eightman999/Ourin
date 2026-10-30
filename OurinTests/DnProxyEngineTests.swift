import Foundation
import Testing
import Darwin
@testable import Ourin

/// Real upstream interfaces, file logger and unchanged crawler C# dictionary sources.
struct DnProxyEngineTests {
    private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static var products: URL {
        ProcessInfo.processInfo.environment["OURIN_DNPROXY_PRODUCTS"].map { URL(fileURLWithPath: $0) }
            ?? repository.appendingPathComponent("build/engines/dnproxy")
    }
    private static let dotnet = ProcessInfo.processInfo.environment["OURIN_DNPROXY_DOTNET"] ?? "/opt/homebrew/bin/dotnet"
    private static var available: Bool {
        FileManager.default.isExecutableFile(atPath: dotnet) &&
            FileManager.default.fileExists(atPath: products.appendingPathComponent("DnProxyHost.dll").path)
    }

    private func fixture(crawler: Bool) throws -> (URL, ShioriRuntimeLoadContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-DNProxy-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master/会話 engine")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        do {
            let args = [Self.products.appendingPathComponent("DnProxyHost.dll").path,
                        Self.products.appendingPathComponent(crawler ? "CrawlerGhost.dll" : "DnProxyProbe.dll").path,
                        crawler ? "Ukagaka.NET.Shiori" : "Ourin.DnProxy.ProbeGhost"]
            let arguments = String(data: try JSONEncoder().encode(args), encoding: .utf8)!
            try "[SHIOLINK]\nexecutable=\(Self.dotnet)\narguments=\(arguments)\ncharmode=UTF-8\n"
                .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
            return (root, .init(ghostURL: root, ghostRoot: root.appendingPathComponent("ghost/master"), moduleName: "会話 engine/SHIOLINK.dll"))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    @Test(.enabled(if: available, "Build optional managed host: python3 engines/dnproxy/build.py (.NET SDK 10.0.401)"))
    func realInterfaceModulePersistsAndUsesUpstreamLogger() throws {
        let (root, context) = try fixture(crawler: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: context.moduleName))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        for count in [1, 2] {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "桜鈴 🌸 \(count)")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["日本語 🌸"], timeout: 5)?.value == "日本語 🌸")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            let path = try String(contentsOf: master.appendingPathComponent("dnproxy-loaded.path"), encoding: .utf8)
            #expect(path == master.path + "/")
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            let save = try String(contentsOf: master.appendingPathComponent("dnproxy-save.json"), encoding: .utf8)
            #expect(save == "\(count)")
            let log = try String(contentsOf: master.appendingPathComponent("log.txt"), encoding: .utf8)
            #expect(log.contains("unload: 桜鈴"))
        }
    }

    @Test(.enabled(if: available, "Build optional unchanged crawler C# dictionary"))
    func upstreamCrawlerTalksWithCP932AndReloads() throws {
        let (root, context) = try fixture(crawler: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: context.moduleName))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        for _ in 0..<2 {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 5)?.value == "DNProxy/2.0.0.0")
            #expect(runtime.request(method: "GET", id: "craftmanw", timeout: 5)?.value == "摂理")
            let boot = try #require(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value)
            #expect(boot.contains("\\e"))
            #expect(boot.count > 10)
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.value?.contains("\\-") == true)
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(!runtime.isLoaded)
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
        }
    }

    private func iniFixture(language: String) throws -> (URL, ShioriRuntimeLoadContext) {
        let (root, original) = try fixture(crawler: false)
        let master = original.ghostRoot.appendingPathComponent("会話 engine")
        do {
            if language == "crawler" {
                let upstream = Self.products.appendingPathComponent("upstream-crawler")
                try FileManager.default.copyItem(at: upstream.appendingPathComponent("src"), to: master.appendingPathComponent("src"))
                try FileManager.default.copyItem(at: upstream.appendingPathComponent("dnproxy.ini"), to: master.appendingPathComponent("dnproxy.ini"))
            } else {
                let sources = master.appendingPathComponent("src/nested")
                try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
                let ext = language == "csharp" ? "cs" : "vb"
                try FileManager.default.copyItem(at: Self.repository.appendingPathComponent("engines/dnproxy/example/ProbeGhost.\(ext)"),
                                                 to: sources.appendingPathComponent("ProbeGhost.\(ext)"))
                try FileManager.default.copyItem(at: Self.repository.appendingPathComponent("engines/dnproxy/example/dnproxy-\(language).ini"),
                                                 to: master.appendingPathComponent("dnproxy.ini"))
            }
            let arguments = String(data: try JSONEncoder().encode([Self.products.appendingPathComponent("DnProxyHost.dll").path]), encoding: .utf8)!
            try "[SHIOLINK]\nmodule=dnproxy.dll\nexecutable=\(Self.dotnet)\narguments=\(arguments)\ncharmode=UTF-8\n"
                .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
            return (root, .init(ghostURL: root, ghostRoot: original.ghostRoot, moduleName: "会話 engine/dnproxy.dll"))
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func inputSnapshot(master: URL) throws -> [String: Data] {
        let iterator = try #require(FileManager.default.enumerator(at: master.appendingPathComponent("src"), includingPropertiesForKeys: [.isRegularFileKey]))
        var result = ["dnproxy.ini": try Data(contentsOf: master.appendingPathComponent("dnproxy.ini"))]
        for case let file as URL in iterator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[file.path] = try Data(contentsOf: file)
            }
        }
        return result
    }

    @Test(.enabled(if: available, "Build the optional Roslyn D.N.Proxy host"))
    func unchangedCrawlerIniCompilesSourcesAndPreservesReadOnlyInputs() throws {
        let (root, context) = try iniFixture(language: "crawler")
        defer { try? FileManager.default.removeItem(at: root) }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        let before = try inputSnapshot(master: master)
        for file in before.keys {
            try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file == "dnproxy.ini" ? master.appendingPathComponent(file).path : file)
        }
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        for _ in 0..<2 {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "version", timeout: 5)?.value == "DNProxy/2.0.0.0")
            #expect(runtime.request(method: "GET", id: "craftmanw", timeout: 5)?.value == "摂理")
            let boot = try #require(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value)
            #expect(boot.contains("\\e"))
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.value?.contains("\\-") == true)
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
        }
        #expect(try inputSnapshot(master: master) == before)
        #expect(!FileManager.default.fileExists(atPath: master.appendingPathComponent("user.dll").path))
        #expect(!FileManager.default.fileExists(atPath: master.appendingPathComponent("profile").path))
    }

    @Test(.enabled(if: available, "Build the optional real C#/VB Roslyn host"), arguments: ["csharp", "vb"])
    func iniSourceCompilersTalkAndPersist(language: String) throws {
        let (root, context) = try iniFixture(language: language)
        defer { try? FileManager.default.removeItem(at: root) }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        let before = try inputSnapshot(master: master)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        let adapter = try #require(runtime as? ShiolinkAdapter)
        defer { runtime.unload() }
        for count in [1, 2] {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "桜鈴 🌸 \(count)")
            #expect(runtime.request(method: "GET", id: "OnEcho", refs: ["日本語 🌸"], timeout: 5)?.value == "日本語 🌸")
            #expect(runtime.request(method: "GET", id: "OnClose", timeout: 5)?.value == "終了します。")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            let pid = try #require(adapter.lastProcessIdentifier)
            runtime.unload()
            #expect(kill(pid, 0) == -1)
            #expect(errno == ESRCH)
            let filename = language == "csharp" ? "dnproxy-save.json" : "vb-save.txt"
            let save = try String(contentsOf: master.appendingPathComponent(filename), encoding: .utf8)
            #expect(save == "\(count)")
            let log = try String(contentsOf: master.appendingPathComponent("log.txt"), encoding: .utf8)
            #expect(log.contains("unload: 桜鈴"))
        }
        #expect(try inputSnapshot(master: master) == before)
    }

    @Test(.enabled(if: available, "Build the optional real Roslyn host"), arguments: ["syntax", "unsupported"])
    func invalidIniOrSourceFailsAndReapsChild(mode: String) throws {
        let (root, context) = try iniFixture(language: "csharp")
        defer { try? FileManager.default.removeItem(at: root) }
        let master = context.ghostRoot.appendingPathComponent("会話 engine")
        if mode == "syntax" {
            try "invalid C# source !!!".write(to: master.appendingPathComponent("src/nested/ProbeGhost.cs"), atomically: true, encoding: .utf8)
        } else {
            let file = master.appendingPathComponent("dnproxy.ini")
            try (String(contentsOf: file, encoding: .utf8) + "\nGenerateExecutable: 1\n").write(to: file, atomically: true, encoding: .utf8)
        }
        let before = try inputSnapshot(master: master)
        let adapter = ShiolinkAdapter()
        defer { adapter.unload() }
        #expect(!adapter.load(context: context))
        #expect(!adapter.isLoaded)
        let pid = try #require(adapter.lastProcessIdentifier)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
        #expect(try inputSnapshot(master: master) == before)
    }

}
