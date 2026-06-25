import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct LegacyPluginRegistryTests {
    @Test
    func discoversLegacyWindowsPluginMetadataWithoutLoadingDLL() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinPlugin-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let pluginDir = base.appendingPathComponent("plugin/shared_value", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try """
        Charset,UTF-8
        name,Shared Value
        craftman,SSP BUGTRAQ
        filename,shared_value.dll
        secondchangeinterval,10
        otherghosttalk,0
        id,plugin-id
        homeurl,http://example.com/plugin/
        """.write(to: pluginDir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)

        let registry = PluginRegistry()
        registry.discoverAndLoad()

        #expect(registry.plugins.isEmpty)
        #expect(registry.legacyMetas.count == 1)
        let meta = try #require(registry.legacyMetas.first?.meta)
        #expect(meta.name == "Shared Value")
        #expect(meta.filename == "shared_value.dll")
        #expect(standardized(meta.path) == standardized(pluginDir.appendingPathComponent("shared_value.dll").path))
        #expect(meta.secondChangeInterval == 10)
        #expect(meta.otherGhostTalk == false)
        #expect(meta.craftman == "SSP BUGTRAQ")
        #expect(meta.craftmanURL == "http://example.com/plugin/")
        #expect(meta.isNative == false)

        let provider = PluginPropertyProvider(plugins: registry.allMetas.map {
            PropertyPlugin(
                name: $0.name,
                path: $0.path,
                id: $0.id,
                craftmanw: $0.craftman ?? "",
                craftmanurl: $0.craftmanURL ?? "",
                filename: $0.filename,
                native: $0.isNative
            )
        })
        #expect(provider.get(key: "count") == "1")
        #expect(standardized(provider.get(key: "index(0).path")) == standardized(pluginDir.appendingPathComponent("shared_value.dll").path))
        #expect(provider.get(key: "index(0).native") == "0")
    }

    @Test
    func deduplicatesLegacyPluginsWithSameID() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinPluginDedup-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let sameID = "DUPLICATE-ID-0001"
        // 2 つの legacy ディレクトリが同一 ID を持つ
        for name in ["plugin_alpha", "plugin_beta"] {
            let dir = base.appendingPathComponent("plugin/\(name)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try """
            Charset,UTF-8
            name,\(name)
            filename,\(name).dll
            id,\(sameID)
            """.write(to: dir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        }

        let registry = PluginRegistry()
        registry.discoverAndLoad()

        // 同一 ID は 1 件だけ登録される
        #expect(registry.legacyMetas.count == 1)
        let ids = registry.allMetas.map { $0.id }
        #expect(ids.filter { $0 == sameID }.count == 1)
    }

    @Test
    func separatesCompatibilityAndExecutablePath() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinPluginPath-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let pluginDir = base.appendingPathComponent("plugin/legacy_one", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try """
        Charset,UTF-8
        name,Legacy One
        filename,legacy.dll
        id,path-test-id
        """.write(to: pluginDir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)

        let registry = PluginRegistry()
        registry.discoverAndLoad()

        let meta = try #require(registry.legacyMetas.first?.meta)
        // compatibilityPath は元 DLL パス（descript.txt filename 由来）
        #expect(standardized(meta.compatibilityPath) == standardized(pluginDir.appendingPathComponent("legacy.dll").path))
        // path は compatibilityPath の alias
        #expect(meta.path == meta.compatibilityPath)
        // legacy の場合は executablePath も互換パスと同一（native bundle が無いため）
        #expect(meta.executablePath == meta.compatibilityPath)
        // legacy ディレクトリには install.txt が無いため packagePath は nil
        #expect(meta.packagePath == nil)
    }

    @Test
    func propertyProviderExposesExecutableAndPackagePath() throws {
        let plugin = PropertyPlugin(
            name: "Test",
            path: "/plugin/test/test.dll",
            id: "prop-test",
            filename: "test.dll",
            native: false,
            executablePath: "/plugin/test/test.plugin",
            packagePath: "/plugin/test_mac"
        )
        let provider = PluginPropertyProvider(plugins: [plugin])
        #expect(provider.get(key: "index(0).path") == "/plugin/test/test.dll")
        #expect(provider.get(key: "index(0).executablepath") == "/plugin/test/test.plugin")
        #expect(provider.get(key: "index(0).packagepath") == "/plugin/test_mac")
    }
}

private func standardized(_ path: String?) -> String? {
    path.map {
        let standardized = URL(fileURLWithPath: $0).standardizedFileURL.path
        if standardized == "/var" { return "/private/var" }
        if standardized.hasPrefix("/var/") { return "/private" + standardized }
        return standardized
    }
}
