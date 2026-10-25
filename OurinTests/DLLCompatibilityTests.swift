import Foundation
import Testing
@testable import Ourin

/// 伺か DLL 共通 ABI（load(h,len) / request(h,&len)）と、Windows 向け `.dll` 名からの
/// macOS ネイティブモジュール解決の互換を検証する。
@Suite(.serialized)
@MainActor
struct DLLCompatibilityTests {
    // MARK: - 名前解決

    @Test
    func nativeCandidatesKeepRelativeDirectoryAndSkipDLL() {
        let candidates = UkagakaModuleABI.nativeModuleCandidates(forDLLName: "saori\\Foo.dll")
        #expect(candidates.first == "saori/Foo.dylib")
        #expect(candidates.contains("saori/libFoo.dylib"))
        #expect(candidates.contains("saori/Foo.plugin"))
        #expect(!candidates.contains { $0.hasSuffix(".dll") })
    }

    @Test
    func loadDirectoryArgumentHasTrailingSeparator() {
        let url = URL(fileURLWithPath: "/tmp/ourin/plugin/foo", isDirectory: true)
        #expect(UkagakaModuleABI.directoryArgument(for: url) == "/tmp/ourin/plugin/foo/")
    }

    @Test
    func saoriResolverPrefersNativePortOverWindowsDLLAndIgnoresCase() throws {
        let root = DLLFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let saoriDir = root.appendingPathComponent("Saori", isDirectory: true)
        try FileManager.default.createDirectory(at: saoriDir, withIntermediateDirectories: true)
        try DLLFixture.writeFakeWindowsDLL(to: saoriDir.appendingPathComponent("foo.dll"))
        let port = saoriDir.appendingPathComponent("libfoo.dylib")
        FileManager.default.createFile(atPath: port.path, contents: Data("x".utf8))

        let registry = SaoriRegistry(searchPaths: [root])
        let found = registry.resolveModuleURL(named: "saori\\FOO.dll")

        #expect(found?.standardizedFileURL.path.lowercased() == port.standardizedFileURL.path.lowercased())
    }

    @Test
    func saoriResolverDoesNotReturnWindowsOnlyDLL() throws {
        let root = DLLFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try DLLFixture.writeFakeWindowsDLL(to: root.appendingPathComponent("only_windows.dll"))

        let registry = SaoriRegistry(searchPaths: [root])
        #expect(registry.resolveModuleURL(named: "only_windows.dll") == nil)
    }

    @Test
    func prioritizedSaoriSearchPathWinsOverDefaults() throws {
        let shared = DLLFixture.temporaryDirectory()
        let ghost = DLLFixture.temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: shared)
            try? FileManager.default.removeItem(at: ghost)
        }
        for dir in [shared, ghost] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: dir.appendingPathComponent("bar.dylib").path, contents: Data("x".utf8))
        }
        let registry = SaoriRegistry(searchPaths: [shared])
        registry.addSearchPath(ghost, prioritized: true)

        #expect(registry.resolveModuleURL(named: "bar.dll")?.deletingLastPathComponent().standardizedFileURL
            == ghost.standardizedFileURL)
    }

    // MARK: - SAORI 実モジュール

    @Test
    func saoriVersionHandshakeIsSentOnceAndLoadGetsTrailingSlash() throws {
        let root = DLLFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let moduleURL = root.appendingPathComponent("counter.dylib")
        try DLLFixture.compile(.saori, to: moduleURL)

        let manager = SaoriManager(registry: SaoriRegistry(searchPaths: [root]))
        defer { manager.unloadAll() }

        _ = try manager.execute(moduleName: "counter.dll", arguments: ["a"])
        let second = try manager.execute(moduleName: "counter.dll", arguments: ["b"])

        #expect(second.headerValue("Result") == "1")
        #expect(second.headerValue("Value0") == root.standardizedFileURL.path + "/"
            || second.headerValue("Value0") == root.path + "/")
    }

    // MARK: - PLUGIN

    @Test
    func pluginDirectoryWithoutInstallTxtLoadsDylibPortUsingUkagakaABI() throws {
        let base = DLLFixture.temporaryDirectory()
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }
        let pluginDir = try OurinPaths.subdirectory("plugin").appendingPathComponent("echo_plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try """
        charset,UTF-8
        name,Echo Port
        id,dll-compat-echo
        filename,Echo.dll
        """.write(to: pluginDir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try DLLFixture.writeFakeWindowsDLL(to: pluginDir.appendingPathComponent("Echo.dll"))
        try DLLFixture.compile(.ukagaka, to: pluginDir.appendingPathComponent("Echo.dylib"))

        let registry = PluginRegistry()
        registry.discoverAndLoad()
        defer { registry.unloadAll() }

        let plugin = try #require(registry.plugins.first)
        #expect(plugin.url.lastPathComponent == "Echo.dylib")
        #expect(plugin.convention == .ukagaka)
        #expect(registry.metas[plugin]?.id == "dll-compat-echo")
        #expect(registry.legacyMetas.isEmpty)

        let response = try plugin.get(id: "OnLoadPath")
        #expect(response.statusCode == 200)
        #expect(response.value?.hasSuffix("/echo_plugin/") == true)
    }

    @Test
    func bundleWithoutIdentifierCanDeclareUkagakaABI() throws {
        let root = DLLFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("NoID.plugin", isDirectory: true)
        try DLLFixture.makeBundle(at: bundleURL, executableName: "NoID", variant: .ukagaka, extraPlist: [
            UkagakaModuleABI.conventionInfoKey: "ukagaka"
        ])

        let plugin = try Plugin(url: bundleURL)
        #expect(plugin.convention == .ukagaka)
        #expect(plugin.load(directoryURL: root))
        let response = try plugin.get(id: "OnLoadPath")
        #expect(response.value == root.path + "/")
    }

    // MARK: - HEADLINE

    @Test
    func headlineDirectoryLayoutLoadsDylibPort() throws {
        let base = DLLFixture.temporaryDirectory()
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }
        let dir = try OurinPaths.subdirectory("headline").appendingPathComponent("news", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        charset,UTF-8
        name,News Port
        dllname,News.dll
        url,https://example.invalid/
        """.write(to: dir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try DLLFixture.compile(.ukagaka, to: dir.appendingPathComponent("libNews.dylib"))

        let registry = HeadlineRegistry()
        registry.discoverAndLoad()
        defer { registry.unloadAll() }

        let module = try #require(registry.modules.first { $0.url.deletingLastPathComponent().lastPathComponent == "news" })
        #expect(registry.metas[module]?.name == "News Port")
        #expect(module.send("GET Headline HEADLINE/2.0M\r\nCharset: UTF-8\r\n\r\n").contains("ukagaka"))
    }
}

private enum DLLFixture {
    enum Variant: String {
        case ukagaka = "MODULE_UKAGAKA"
        case saori = "MODULE_SAORI"
    }

    static var sourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/dll_compat/module.c")
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinDLLCompat-\(UUID().uuidString)", isDirectory: true)
    }

    static func writeFakeWindowsDLL(to url: URL) throws {
        try Data([0x4D, 0x5A, 0x90, 0x00]).write(to: url)
    }

    static func makeBundle(at bundleURL: URL, executableName: String, variant: Variant, extraPlist: [String: String]) throws {
        let macOS = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        var plist: [String: String] = [
            "CFBundleExecutable": executableName,
            "CFBundlePackageType": "BNDL"
        ]
        plist.merge(extraPlist) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        try compile(variant, to: macOS.appendingPathComponent(executableName), bundle: true)
    }

    static func compile(_ variant: Variant, to outputURL: URL, bundle: Bool = false) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = [
            "-DDLL_COMPAT_FIXTURE_BUILD=1",
            "-D\(variant.rawValue)=1",
            "-std=c11",
            "-fvisibility=default",
            bundle ? "-bundle" : "-dynamiclib",
            sourceURL.path,
            "-o",
            outputURL.path
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "DLLCompatibilityTests", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "clang failed: \(stderr)"])
        }
    }
}
