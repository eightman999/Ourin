import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct ComponentUpdateTargetTests {
    @Test
    func discoveryNormalizesNestedShellsAndDescriptorAliases() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-component-target-\(UUID().uuidString)", isDirectory: true)
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }
        OurinPaths.testBaseOverride = base

        let shell = base
            .appendingPathComponent("ghost/Emily/shell/Classic", isDirectory: true)
        let balloon = base.appendingPathComponent("balloon/Soft", isDirectory: true)
        let plugin = base.appendingPathComponent("plugin/Weather", isDirectory: true)
        let headline = base.appendingPathComponent("headline/News", isDirectory: true)
        let language = base.appendingPathComponent("language/Japanese", isDirectory: true)
        for directory in [shell, balloon, plugin, headline, language] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try "name,クラシック\nid,classic-id\nhomeurl,https://example.com/classic/\n"
            .data(using: .utf8)!
            .write(to: shell.appendingPathComponent("descript.txt"))
        try "name,Soft Balloon\nhomeurl,https://example.com/balloon/\n"
            .data(using: .utf8)!
            .write(to: balloon.appendingPathComponent("descript.txt"))
        try "name,Weather Plugin\nid,weather-id\nhomeurl,https://example.com/plugin/\n"
            .data(using: .utf8)!
            .write(to: plugin.appendingPathComponent("descript.txt"))
        try "name,News Headline\nhomeurl,https://example.com/headline/\n"
            .data(using: .utf8)!
            .write(to: headline.appendingPathComponent("descript.txt"))
        try "name,日本語\nhomeurl,https://example.com/language/\n"
            .data(using: .utf8)!
            .write(to: language.appendingPathComponent("descript.txt"))

        let targets = ComponentUpdateTargetDiscovery.discover()
        #expect(targets.count == 5)

        let shellTarget = try #require(targets.first { $0.type == "shell" })
        #expect(shellTarget.name == "クラシック")
        #expect(shellTarget.matches(name: "classic-id"))
        #expect(shellTarget.homeURL == "https://example.com/classic/")
        #expect(shellTarget.path.standardizedFileURL == shell.standardizedFileURL)

        let pluginTarget = try #require(targets.first { $0.type == "plugin" })
        #expect(pluginTarget.matches(name: "weather-id"))
        #expect(pluginTarget.homeURL == "https://example.com/plugin/")
    }

    @Test
    func unsupportedTargetTypesAreNotDiscovered() {
        #expect(ComponentUpdateTargetDiscovery.discover(types: ["ghost", "calendar"]).isEmpty)
    }
}
