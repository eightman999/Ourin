import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct CalendarRegistryTests {
    @Test
    func discoversCalendarSkinsAndPlugins() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinCalendar-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let skin = base.appendingPathComponent("calendar/skin/default", isDirectory: true)
        let plugin = base.appendingPathComponent("calendar/plugin/sample", isDirectory: true)
        try FileManager.default.createDirectory(at: skin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: true)
        try """
        charset,Shift_JIS
        name,Default
        background.filename,bg
        """.write(to: skin.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try """
        default,evt0
        book,evt1
        """.write(to: skin.appendingPathComponent("icon.txt"), atomically: true, encoding: .utf8)
        try """
        name,Sample Calendar
        dllname,SCHEDULE.dll
        post,support
        id,calendar-id
        """.write(to: plugin.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)

        let registry = CalendarRegistry()
        let skins = registry.installedSkins()
        let plugins = registry.installedPlugins()

        #expect(skins.count == 1)
        #expect(skins[0].name == "Default")
        #expect(skins[0].iconMap["book"] == "evt1")
        #expect(plugins.count == 1)
        #expect(plugins[0].name == "Sample Calendar")
        #expect(plugins[0].filename == "SCHEDULE.dll")
        #expect(plugins[0].post == "support")

        let skinProvider = CalendarSkinPropertyProvider(skins: skins)
        let pluginProvider = CalendarPluginPropertyProvider(plugins: plugins)
        #expect(skinProvider.get(key: "count") == "1")
        #expect(standardized(skinProvider.get(key: "index(0).background.filename")) == standardized(skin.appendingPathComponent("bg.png").path))
        #expect(standardized(skinProvider.get(key: "index(0).icon(book).filename")) == standardized(skin.appendingPathComponent("evt1.png").path))
        #expect(standardized(pluginProvider.get(key: "index(0).path")) == standardized(plugin.appendingPathComponent("SCHEDULE.dll").path))
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
