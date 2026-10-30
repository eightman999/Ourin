import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct ShioriEnginePluginTests {
    private static let realEngineIDs = ["kawari", "aktk", "dktrtk", "krht", "dnproxy", "kanahebi", "rosalind",
                                        "miyojs", "aosora", "sana", "sanajk", "phiori", "emo-rs", "emo-rs-lua54",
                                        "yaya", "aya", "nashi"]
    private static var realPluginsAvailable: Bool {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return realEngineIDs.allSatisfy {
            FileManager.default.fileExists(atPath: repository.appendingPathComponent("build/engine-plugins/packages/\($0).plugin/Contents/Resources/engine.json").path)
        }
    }

    @Test func pluginBundleKeepsItsStructureAndRejectsForeignOrEscapingBundles() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = try package(in: root)
        let bundle = root.appendingPathComponent("probe.plugin")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: raw, to: contents.appendingPathComponent("Resources"))
        let info: [String: Any] = ["CFBundleIdentifier": "com.furinlab.ourin.shiori.probe",
                                   "CFBundleName": "Probe", "CFBundlePackageType": "BNDL",
                                   "OurinShioriEnginePackageVersion": 1]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        #expect(Bundle(url: bundle) != nil)
        let destination = root.appendingPathComponent("installed")
        let installed = try ShioriEnginePlugins.install(from: bundle, into: destination)
        #expect(installed.packageURL.lastPathComponent == "probe.plugin")
        #expect(installed.directory.lastPathComponent == "Resources")
        #expect(ShioriEnginePlugins.installed(in: destination).map { $0.id } == ["probe"])
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.install(from: raw, into: destination) }
        #expect(try Data(contentsOf: contents.appendingPathComponent("Info.plist")) == plist)
        var foreign = info; foreign.removeValue(forKey: "OurinShioriEnginePackageVersion")
        try PropertyListSerialization.data(fromPropertyList: foreign, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.read(from: bundle) }
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.removeItem(at: contents.appendingPathComponent("Resources"))
        try FileManager.default.createSymbolicLink(at: contents.appendingPathComponent("Resources"), withDestinationURL: raw)
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.read(from: bundle) }
    }
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Engine-Plugin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func package(in root: URL, id: String = "probe", aliases: [String] = ["probe.dll"],
                         kind: String = "shiolink", markers: [String] = []) throws -> URL {
        let source = root.appendingPathComponent("source-\(id)")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let executable = source.appendingPathComponent("host")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var manifest: [String: Any] = ["schema": 1, "id": id, "name": "試験 \(id)", "kind": kind,
                                      "moduleNames": aliases, "markers": markers]
        manifest[kind == "native" ? "module" : "executable"] = "host"
        try JSONSerialization.data(withJSONObject: manifest).write(to: source.appendingPathComponent("engine.json"))
        return source
    }

    @Test func importPreservesSourceAndRefusesDuplicateOrExternalReferences() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try package(in: root)
        let original = try Data(contentsOf: source.appendingPathComponent("engine.json"))
        let destination = root.appendingPathComponent("installed")
        let engine = try ShioriEnginePlugins.install(from: source, into: destination)
        #expect(engine.id == "probe")
        #expect(ShioriEnginePlugins.installed(in: destination).count == 1)
        #expect(try Data(contentsOf: source.appendingPathComponent("engine.json")) == original)
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.install(from: source, into: destination) }
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.containedURL("../host", in: source) }
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.containedURL("/bin/sh", in: source) }
        let second = try package(in: root, id: "external")
        try FileManager.default.createSymbolicLink(at: second.appendingPathComponent("outside"), withDestinationURL: root)
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.install(from: second, into: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("external").path))
        let symlink = root.appendingPathComponent("linked-package")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        #expect(throws: (any Error).self) { try ShioriEnginePlugins.install(from: symlink, into: root.appendingPathComponent("other")) }
    }

    @Test func genericNamesNeedMarkersAmbiguityRefusesAndSamplesNeverReplaceGhosts() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let plugins = root.appendingPathComponent("plugins"), master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        let first = try package(in: root, id: "first", aliases: ["SHIOLINK.dll"], markers: ["miyo.yaml"])
        try ShioriEnginePlugins.install(from: first, into: plugins)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "SHIOLINK.dll")
        #expect(ShioriEnginePlugins.matching(context: context, root: plugins) == nil)
        let genericDylib = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "libSHIOLINK.so")
        #expect(ShioriEnginePlugins.matching(context: genericDylib, root: plugins) == nil)
        try Data().write(to: master.appendingPathComponent("miyo.yaml"))
        #expect(ShioriEnginePlugins.matching(context: context, root: plugins)?.id == "first",
                "installed=\(ShioriEnginePlugins.installed(in: plugins).map { $0.id }), marker=\(String(describing: UkagakaModuleABI.resolveCaseInsensitive("miyo.yaml", in: master)))")
        let second = try package(in: root, id: "second", aliases: ["SHIOLINK.dll"], markers: ["miyo.yaml"])
        try ShioriEnginePlugins.install(from: second, into: plugins)
        #expect(ShioriEnginePlugins.matching(context: context, root: plugins) == nil)
        try ShioriEnginePlugins.assign(engineID: "first", to: root, root: plugins)
        #expect(ShioriEnginePlugins.matching(context: context, root: plugins)?.id == "first")
        try ShioriEnginePlugins.assign(engineID: nil, to: root, root: plugins)
        #expect(ShioriEnginePlugins.matching(context: context, root: plugins) == nil)
        let sample = try package(in: root, id: "sample", aliases: ["compiled.dll"], kind: "development-sample")
        try ShioriEnginePlugins.install(from: sample, into: plugins)
        let compiled = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "compiled.dll")
        #expect(ShioriEnginePlugins.matching(context: compiled, root: plugins) == nil)
    }

    @Test func ghostLocalModuleHasPriorityAndWindowsSubdirectoryIsResolved() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let plugins = root.appendingPathComponent("plugins"), master = root.appendingPathComponent("ghost/master")
        let subdirectory = master.appendingPathComponent("Engine")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try ShioriEnginePlugins.install(from: package(in: root), into: plugins)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "engine\\PROBE.dll")
        #expect(ShioriEnginePlugins.matching(context: context, root: plugins)?.id == "probe")
        #expect(ShioriEnginePlugins.dictionaryDirectory(for: context)?.path.lowercased() == subdirectory.path.lowercased())
        try Data().write(to: subdirectory.appendingPathComponent("libPROBE.dylib"))
        #expect(ShioriEnginePlugins.matching(context: context, root: plugins) == nil)
    }

    @Test func installedNativeEngineTakesPriorityOverTheBuiltInYayaVM() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = root
        defer { OurinPaths.testBaseOverride = previous }
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "yaya.dll")
        #expect(ShioriRuntimeFactory.makeRuntime(context: context)?.kind == .yaya)
        try ShioriEnginePlugins.install(from: package(in: root, id: "latest-yaya", aliases: ["yaya.dll"], kind: "native"))
        #expect(ShioriRuntimeFactory.makeRuntime(context: context)?.kind == .native)
        // The user can also select a native engine for a descriptor with another DLL name.
        let renamed = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "custom.dll")
        try ShioriEnginePlugins.assign(engineID: "latest-yaya", to: root)
        #expect(ShioriRuntimeFactory.makeRuntime(context: renamed)?.kind == .native)
        try ShioriEnginePlugins.assign(engineID: nil, to: root)
        #expect(ShioriRuntimeFactory.makeRuntime(context: context)?.kind == .native)
    }

    @Test func ambiguousOrUnavailableYayaPluginCannotSilentlyBecomeTheBuiltInVM() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = root
        defer { OurinPaths.testBaseOverride = previous }
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "yaya.dll")
        let first = try ShioriEnginePlugins.install(from: package(in: root, id: "first-yaya", aliases: ["yaya.dll"], kind: "native"))
        try ShioriEnginePlugins.install(from: package(in: root, id: "second-yaya", aliases: ["yaya.dll"], kind: "native"))
        #expect(ShioriRuntimeFactory.makeRuntime(context: context) == nil)
        try ShioriEnginePlugins.assign(engineID: first.id, to: root)
        #expect(ShioriRuntimeFactory.makeRuntime(context: context)?.kind == .native)
        try FileManager.default.moveItem(at: first.packageURL, to: root.appendingPathComponent("removed-first"))
        #expect(ShioriRuntimeFactory.makeRuntime(context: context) == nil)
        // A ghost's own macOS module remains authoritative even with a stale shared selection.
        try Data().write(to: master.appendingPathComponent("libyaya.dylib"))
        #expect(ShioriRuntimeFactory.makeRuntime(context: context)?.kind == .native)
    }

    @Test func invalidExplicitTransportCannotFallBackToYayaOrAnInstalledNativeEngine() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = root
        defer { OurinPaths.testBaseOverride = previous }
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try ShioriEnginePlugins.install(from: package(in: root, id: "latest-yaya", aliases: ["yaya.dll"], kind: "native"))
        try Data("[SHIOLINK]\nexecutable=/missing-ourin-test-host\nmodule=yaya.dll\n".utf8)
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"))
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "yaya.dll")
        #expect(ShioriRuntimeFactory.makeRuntime(context: context) == nil)
    }

    @Test(.enabled(if: realPluginsAvailable, "Generate optional real engine plugins with engines/package-plugins.py"),
          arguments: realEngineIDs)
    func installedRealEngineUsesProductionFactoryWithoutGhostConfiguration(id: String) throws {
        let source = repository.appendingPathComponent("build/engine-plugins/packages/\(id).plugin")
        try #require(FileManager.default.fileExists(atPath: source.appendingPathComponent("Contents/Resources/engine.json").path),
                     "Generate actual engine plugins with engines/package-plugins.py before this integration test")
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = root
        defer { OurinPaths.testBaseOverride = previous }
        let pluginRoot = try ShioriEnginePlugins.installationRoot()
        let installed = try ShioriEnginePlugins.install(from: source, into: pluginRoot)
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        let fixturePath: String
        switch id {
        case "miyojs": fixturePath = "engines/miyojs/fixtures"
        case "sana", "sanajk": fixturePath = "engines/miyojs/fixtures/\(id)"
        case "phiori": fixturePath = "build/engines/phiori/upstream-sample"
        case "nashi": fixturePath = "engines/nashi"
        case "emo-rs", "emo-rs-lua54": fixturePath = "build/engines/\(id)/upstream-script"
        default: fixturePath = "engines/\(id)/example"
        }
        let fixture = repository.appendingPathComponent(fixturePath)
        let inputs = id == "nashi" ? [fixture.appendingPathComponent("fixture.json")]
            : try FileManager.default.contentsOfDirectory(at: fixture, includingPropertiesForKeys: nil)
        for child in inputs {
            try FileManager.default.copyItem(at: child,
                to: master.appendingPathComponent(id == "nashi" ? "ghost.json" : child.lastPathComponent))
        }
        if id == "dnproxy" {
            let sources = master.appendingPathComponent("src")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: master.appendingPathComponent("ProbeGhost.cs"),
                                             to: sources.appendingPathComponent("ProbeGhost.cs"))
            try FileManager.default.copyItem(at: master.appendingPathComponent("dnproxy-csharp.ini"),
                                             to: master.appendingPathComponent("dnproxy.ini"))
        }
        if id == "rosalind" {
            let script = master.appendingPathComponent("Ghost.csx")
            let products = installed.directory.appendingPathComponent("osx-arm64").path
            let text = try String(contentsOf: script, encoding: .utf8)
            try text.replacingOccurrences(of: "@ROSALIND_PRODUCTS@", with: products)
                .write(to: script, atomically: true, encoding: .utf8)
        }
        if id == "phiori" {
            try FileManager.default.copyItem(at: repository.appendingPathComponent("engines/miyojs/fixtures/phiori/probe.py"),
                                             to: master.appendingPathComponent("probe.py"))
        }
        let snapshots = try FileManager.default.contentsOfDirectory(at: master, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { ($0, try Data(contentsOf: $0)) }
        let module = installed.descriptor.moduleNames.first ?? "emo.dll"
        if id == "emo-rs" { try ShioriEnginePlugins.assign(engineID: id, to: root, root: pluginRoot) }
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: module)
        #expect(ShioriEnginePlugins.matching(context: context)?.id == id)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        for _ in 0..<2 {
            try #require(runtime.load(context: context), "Real plugin \(id) must load")
            if id == "phiori" {
                #expect(runtime.request(method: "NOTIFY", id: "ownerghostname", refs: ["probe"], timeout: 5) != nil)
            }
            let boot = try #require(runtime.request(method: "GET", id: id == "phiori" ? "OnOurinCounter" : "OnBoot",
                                                    refs: id == "phiori" ? ["桜鈴 🌸"] : [], timeout: 10))
            #expect(boot.status == 200)
            #expect(boot.value?.isEmpty == false)
            #expect(runtime.request(method: "NOTIFY", id: "OnNotify", timeout: 5) != nil)
            runtime.unload()
            #expect(!runtime.isLoaded)
        }
        for (path, data) in snapshots { #expect(try Data(contentsOf: path) == data) }
        #expect(!FileManager.default.fileExists(atPath: master.appendingPathComponent("SHIOLINK.ourin.ini").path))
    }

    @Test(.enabled(if: realPluginsAvailable, "Generate real engine plugins first"))
    func ayaUsesPluginCharsetForJapaneseReferencesWithoutChangingTheGhost() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = root
        defer { OurinPaths.testBaseOverride = previous }
        try ShioriEnginePlugins.install(from: repository.appendingPathComponent("build/engine-plugins/packages/aya.plugin"))
        let master = root.appendingPathComponent("ghost/master")
        let directory = master.appendingPathComponent("Engine")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repository.appendingPathComponent("engines/aya/example"), to: directory)
        let original = try Data(contentsOf: directory.appendingPathComponent("aya5.txt"))
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "engine\\AYA5.DLL")
        #expect(context.communication.encoding == nil)
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        #expect(runtime.kind == .native)
        defer { runtime.unload() }
        try #require(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "version", timeout: 5)?.value == "Tc607-2")
        let text = "表ソ・半角ｶﾅ・①髙"
        #expect(runtime.request(method: "GET", id: "OnEcho", refs: [text], timeout: 5)?.value == text)
        runtime.unload()
        #expect(try Data(contentsOf: directory.appendingPathComponent("aya5.txt")) == original)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("SHIOLINK.ourin.ini").path))
    }

    @Test func subprocessEnvironmentKeepsRuntimeOverridesWithoutInjectingTheTestHost() {
        let environment = ShiolinkConfiguration.childEnvironment(overrides: ["DOTNET_MULTILEVEL_LOOKUP": "0"],
            parent: ["PATH": "/usr/bin:/bin", "XCTestBundlePath": "/test/bundle", "DYLD_INSERT_LIBRARIES": "/test/inject.dylib"])
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(environment["XCTestBundlePath"] == nil)
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(environment["DOTNET_MULTILEVEL_LOOKUP"] == "0")
    }

    @Test(.enabled(if: realPluginsAvailable, "Generate real engine ZIP packages first"))
    func zipImportRunsKawariAndPreservesTheArchive() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("kawari.plugin.zip")
        let compressor = Process()
        compressor.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        compressor.arguments = ["-c", "-k", "--keepParent",
            repository.appendingPathComponent("build/engine-plugins/packages/kawari.plugin").path, archive.path]
        try compressor.run(); compressor.waitUntilExit()
        try #require(compressor.terminationStatus == 0)
        let before = try Data(contentsOf: archive)
        let previous = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = root
        defer { OurinPaths.testBaseOverride = previous }
        try ShioriEnginePlugins.install(from: archive)
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: repository.appendingPathComponent("engines/kawari/example/kawarirc.kis"),
                                         to: master.appendingPathComponent("kawarirc.kis"))
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "shiori.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        defer { runtime.unload() }
        try #require(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == #"\0桜鈴・華和梨起動\e"#)
        #expect(try Data(contentsOf: archive) == before)
    }
}
