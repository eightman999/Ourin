import Foundation
import Testing
@testable import Ourin

struct PluginCatalogTests {
    @Test func catalogFiltersWithheldInvalidPathsAndDuplicateIDs() throws {
        let valid: [String: Any] = ["id": "clock", "name": "時計", "file": "clock.zip",
            "limitations": "表示を確認。実GUIは未検証。", "author": "作者", "bytes": 123,
            "sha256": String(repeating: "a", count: 64), "upstream": "https://github.com/owner/clock"]
        var hidden = valid; hidden["id"] = "withheld"
        var traversal = valid; traversal["id"] = "traversal"; traversal["file"] = "../clock.zip"
        var encoded = valid; encoded["id"] = "encoded"; encoded["file"] = "%2e%2e%2fclock.zip"
        var noHash = valid; noHash["id"] = "no-hash"; noHash["sha256"] = "bad"
        let data = try JSONSerialization.data(withJSONObject: [
            "schema": 1, "withheld": ["withheld"],
            "packages": [valid, valid, hidden, traversal, encoded, noHash]])
        let items = try PluginCatalog.decode(data)
        #expect(items.count == 1)
        let item = try #require(items.first)
        #expect(item.matches("時計 作者"))
        #expect(item.matches("未検証"))
        #expect(!item.matches("時計 unknown"))
        #expect(item.downloadURL?.absoluteString == "https://furinlab.com/ourin/downloads/plugins/clock.zip")
        #expect(PluginCatalog.webURL("javascript:alert(1)") == nil)
        #expect(PluginCatalog.webURL("https://user:password@example.com/") == nil)
    }

    @Test func publishedCatalogFieldVariantsDecode() throws {
        // packages.json の先発版（upstream）と追加版（source_url）の形を保存する。
        let data = Data(#"""
        {"schema":1,"packages":[
          {"id":"tmidi-msg","name":"tmidi_msg","file":"tmidi-msg-ourin-20261026.zip",
           "upstream":"https://github.com/JiayuYangX/tmidi_msg/releases/tag/v1.1.0",
           "limitations":"Windows側bridgeが必要。","bytes":69968,
           "sha256":"fd6bf7f8035a438ea2a89dd3549d6d4baccdbb21fd9072709fa5482934f07018"},
          {"id":"inventory","name":"Inventory","file":"inventory-ourin-20261026-extra1.zip",
           "source_url":"https://github.com/ambergon/ukagakaPlugin_Inventory",
           "limitations":"GUI操作は未検証。","bytes":1734524,
           "sha256":"bd60b47d6c39d15091d02cfc83143a82b842804133a7bf24af7cc415299ea434"}
        ]}
        """#.utf8)
        let items = try PluginCatalog.decode(data)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.downloadURL?.host == "furinlab.com" && $0.pageURL != nil })
    }

    @Test func invalidCatalogOrUnknownSchemaIsAnError() {
        #expect(throws: (any Error).self) { try PluginCatalog.decode(Data("{}".utf8)) }
        #expect(throws: (any Error).self) {
            try PluginCatalog.decode(Data(#"{"schema":2,"packages":[]}"#.utf8))
        }
    }

    @Test func installedScanFindsNewPackageWithoutExecutingOrModifyingIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package = root.appendingPathComponent("new-plugin")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = Data("charset,UTF-8\nname,新規時計\nid,clock\ncraftman,作者\nfilename,unknown.dll\n".utf8)
        let file = package.appendingPathComponent("descript.txt")
        try descriptor.write(to: file)
        let items = PluginCatalog.installedItems(registered: [], paths: [root, root])
        #expect(items.count == 1)
        #expect(items.first?.pluginID == "clock")
        #expect(items.first?.name == "新規時計")
        #expect(items.first?.status == "未読込（再起動後に確認）")
        #expect(try Data(contentsOf: file) == descriptor)
        #expect(try FileManager.default.contentsOfDirectory(atPath: package.path) == ["descript.txt"])
    }
}
