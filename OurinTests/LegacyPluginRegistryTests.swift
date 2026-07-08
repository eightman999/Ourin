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
        try """
        menu.title,共有値
        """.write(to: pluginDir.appendingPathComponent("message.japanese.txt"), atomically: true, encoding: .utf8)
        try """
        menu.title,Shared Value
        """.write(to: pluginDir.appendingPathComponent("message.english.txt"), atomically: true, encoding: .utf8)

        let registry = PluginRegistry()
        registry.discoverAndLoad()

        #expect(registry.plugins.isEmpty)
        #expect(registry.legacyMetas.count == 1)
        let meta = try #require(registry.legacyMetas.first?.meta)
        #expect(meta.name == "Shared Value")
        #expect(meta.filename == "shared_value.dll")
        #expect(meta.charset == "UTF-8")
        #expect(standardized(meta.path) == standardized(pluginDir.appendingPathComponent("shared_value.dll").path))
        #expect(meta.secondChangeInterval == 10)
        #expect(meta.otherGhostTalk == false)
        #expect(meta.craftman == "SSP BUGTRAQ")
        #expect(meta.craftmanURL == "http://example.com/plugin/")
        #expect(meta.isNative == false)
        #expect(meta.message(for: "menu.title", language: "ja") == "共有値")
        #expect(meta.message(for: "menu.title", language: "en") == "Shared Value")
        #expect(meta.menuDefinitions == [
            PluginMenuDefinition(itemID: "plugin-id", messageKey: "menu.plugin-id")
        ])

        let entry = try #require(registry.compatibilityEntries.first)
        #expect(entry.name == "Shared Value")
        #expect(entry.executionState == .metadataOnly)
        #expect(entry.canDispatchRequests == false)
        #expect(entry.native == false)
        #expect(entry.path == entry.compatibilityPath)
        #expect(standardized(entry.compatibilityPath) == standardized(pluginDir.appendingPathComponent("shared_value.dll").path))
        #expect(standardized(entry.executablePath) == standardized(entry.compatibilityPath))
        #expect(entry.localizedMessageLanguages == ["english", "japanese"])

        let provider = PluginPropertyProvider(plugins: registry.allMetas.map {
            PropertyPlugin(
                name: $0.name,
                path: $0.path,
                id: $0.id,
                charset: $0.charset ?? "UTF-8",
                craftmanw: $0.craftman ?? "",
                craftmanurl: $0.craftmanURL ?? "",
                filename: $0.filename,
                native: $0.isNative,
                localizedMessages: $0.localizedMessages
            )
        })
        #expect(provider.get(key: "count") == "1")
        #expect(standardized(provider.get(key: "index(0).path")) == standardized(pluginDir.appendingPathComponent("shared_value.dll").path))
        #expect(provider.get(key: "index(0).charset") == "UTF-8")
        #expect(provider.get(key: "index(0).message.menu.title") == "共有値" || provider.get(key: "index(0).message.menu.title") == "Shared Value")
        #expect(provider.get(key: "index(0).native") == "0")
        #expect(provider.get(key: "index(0).executionstate") == "metadataOnly")
        #expect(provider.get(key: "index(0).candispatchrequests") == "0")
        #expect(standardized(provider.get(key: "(\(entry.executablePath)).path")) == standardized(entry.compatibilityPath))

        let menuJA = try #require(registry.pluginMenuEntries(language: "ja").first)
        #expect(menuJA.pluginID == "plugin-id")
        #expect(menuJA.itemID == "plugin-id")
        #expect(menuJA.title == "共有値")
        #expect(menuJA.canDispatchRequests == false)
        #expect(registry.pluginMenuEntry(forActionIdentifier: menuJA.actionIdentifier, language: "ja") == menuJA)

        let menuEN = try #require(registry.pluginMenuEntries(language: "en").first)
        #expect(menuEN.title == "Shared Value")
    }

    @Test
    func pluginMenuEntriesUseCommandMessagesAndBuildOnMenuExecReferences() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinPluginMenu-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let pluginDir = base.appendingPathComponent("plugin/menu_fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try """
        Charset,UTF-8
        name,Menu Fixture
        filename,menu_fixture.dll
        id,menu-fixture
        menu,open_settings
        """.write(to: pluginDir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try """
        menu.title,メニューfixture
        menu.open_settings,設定を開く
        """.write(to: pluginDir.appendingPathComponent("message.japanese.txt"), atomically: true, encoding: .utf8)
        try """
        menu.title,Menu Fixture
        menu.open_settings,Open Settings
        """.write(to: pluginDir.appendingPathComponent("message.english.txt"), atomically: true, encoding: .utf8)

        let registry = PluginRegistry()
        registry.discoverAndLoad()

        let entryJA = try #require(registry.pluginMenuEntries(language: "ja").first)
        #expect(entryJA.pluginID == "menu-fixture")
        #expect(entryJA.itemID == "open_settings")
        #expect(entryJA.title == "設定を開く")
        #expect(entryJA.canDispatchRequests == false)

        let entryEN = try #require(registry.pluginMenuEntries(language: "en").first)
        #expect(entryEN.title == "Open Settings")

        let refs = PluginEventDispatcher.menuExecReferences(
            menuItemID: entryJA.itemID,
            windows: [],
            ghostName: "さくら",
            shellName: "default.shell",
            ghostID: "ghost-id",
            path: "/Users/t/Ghosts/Sakura"
        )
        #expect(refs == ["", "さくら", "default.shell", "ghost-id", "/Users/t/Ghosts/Sakura", "open_settings"])

        let wire = PluginFrame(id: "OnMenuExec", references: refs).build()
        #expect(wire.hasPrefix("GET PLUGIN/2.0M"))
        #expect(wire.contains("Reference0: \r\n"))
        #expect(wire.contains("Reference4: /Users/t/Ghosts/Sakura"))
        #expect(wire.contains("Reference5: open_settings"))
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

        let entry = try #require(registry.compatibilityEntries.first)
        #expect(entry.executionState == .metadataOnly)
        #expect(entry.canDispatchRequests == false)
        #expect(entry.path == meta.path)
        #expect(entry.executablePath == meta.executablePath)
        #expect(entry.packagePath == nil)
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
            packagePath: "/plugin/test_mac",
            executionState: "metadataOnly",
            canDispatchRequests: false
        )
        let provider = PluginPropertyProvider(plugins: [plugin])
        #expect(provider.get(key: "index(0).path") == "/plugin/test/test.dll")
        #expect(provider.get(key: "index(0).executablepath") == "/plugin/test/test.plugin")
        #expect(provider.get(key: "index(0).packagepath") == "/plugin/test_mac")
        #expect(provider.get(key: "index(0).executionstate") == "metadataOnly")
        #expect(provider.get(key: "index(0).candispatchrequests") == "0")
        #expect(provider.get(key: "(/plugin/test/test.plugin).id") == "prop-test")
        #expect(provider.get(key: "(/plugin/test_mac).id") == "prop-test")
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
