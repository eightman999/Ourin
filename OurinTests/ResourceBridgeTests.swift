import Testing
@testable import Ourin
import Foundation

@Suite(.serialized)
struct ResourceBridgeTests {
    @Test
    func cacheBehavior() async throws {
        BridgeToSHIORI.reset()
        BridgeToSHIORI.setResource("test.key", value: "value1")
        let bridge = ResourceBridge.shared
        bridge.invalidateAll()
        let v1 = bridge.get("test.key")
        let v2 = bridge.get("test.key")
        #expect(v1 == "value1")
        // same result when cached
        #expect(v1 == v2)
        BridgeToSHIORI.reset()
    }

    @Test
    func menuParsing() async throws {
        BridgeToSHIORI.reset()
        BridgeToSHIORI.setResource("menu.test.caption", value: "T&est")
        BridgeToSHIORI.setResource("menu.test.visible", value: "0")
        let bridge = ResourceBridge.shared
        bridge.invalidateAll()
        let item = bridge.menuItem(for: "menu.test.caption")
        #expect(item?.title == "Test")
        #expect(item?.shortcut == "e")
        #expect(item?.visible == false)
        BridgeToSHIORI.reset()
    }

    @Test
    func colorAndRecommend() async throws {
        BridgeToSHIORI.reset()
        BridgeToSHIORI.setResource("menu.test.color.r", value: "255")
        BridgeToSHIORI.setResource("menu.test.color.g", value: "128")
        BridgeToSHIORI.setResource("menu.test.color.b", value: "0")
        BridgeToSHIORI.setResource("sakura.recommendsites", value: "Foo\u{01}https://example.com\u{01}banner.png\u{01}talk\u{02}")
        let bridge = ResourceBridge.shared
        bridge.invalidateAll()
        if let color = bridge.colorValue(for: "menu.test.color") {
            #expect(Int(color.redComponent * 255) == 255)
            #expect(Int(color.greenComponent * 255) == 128)
            #expect(Int(color.blueComponent * 255) == 0)
        } else {
            Issue.record("color nil")
        }
        if let list = bridge.recommendSites(for: "sakura.recommendsites", base: nil) {
            #expect(list.count == 1)
            #expect(list[0].title == "Foo")
            #expect(list[0].url == "https://example.com")
            #expect(list[0].talk == "talk")
        } else {
            Issue.record("list nil")
        }
        BridgeToSHIORI.reset()
    }

    @Test
    func refreshesAfterNilFetch() async throws {
        BridgeToSHIORI.reset()
        BridgeToSHIORI.setResource("dynamic.key", value: "")
        let bridge = ResourceBridge.shared
        bridge.invalidateAll()
        let initial = bridge.get("dynamic.key")
        #expect(initial == nil)
        BridgeToSHIORI.setResource("dynamic.key", value: "updated")
        let refreshed = bridge.get("dynamic.key")
        #expect(refreshed == "updated")
        BridgeToSHIORI.reset()
    }

    @Test
    func supportsNewResourceKeys() async throws {
        BridgeToSHIORI.reset()
        defer { BridgeToSHIORI.reset() }
        BridgeToSHIORI.setResource("getaistate", value: "1,2,3")
        BridgeToSHIORI.setResource("getaistateex", value: "1,2\u{01}3,4")
        BridgeToSHIORI.setResource("tooltip", value: "On_tooltip")
        BridgeToSHIORI.setResource("balloon_tooltip", value: "On_balloon_tooltip")
        BridgeToSHIORI.setResource("legacyinterface", value: "1")
        BridgeToSHIORI.setResource("other_homeurl_override", value: "https://example.com/update")
        BridgeToSHIORI.setResource("sakura.portalsites", value: "Portal\u{01}https://portal.example\u{01}\u{01}\u{02}")
        BridgeToSHIORI.setResource("sakura.recommendsites", value: "Rec\u{01}https://rec.example\u{01}\u{01}talk\u{02}")

        let bridge = ResourceBridge.shared
        bridge.invalidateAll()

        #expect(bridge.aiState() == "1,2,3")
        #expect(bridge.aiStateEx() == ["1,2", "3,4"])
        #expect(bridge.tooltipEventName() == "On_tooltip")
        #expect(bridge.balloonTooltipEventName() == "On_balloon_tooltip")
        #expect(bridge.legacyInterfaceEnabled() == true)
        #expect(bridge.otherHomeURLOverride() == "https://example.com/update")
        #expect(bridge.portalSites(base: nil)?.first?.title == "Portal")
        #expect(bridge.recommendSites(forCharacter: "sakura", base: nil)?.first?.title == "Rec")
    }

    @Test
    func exposesComprehensiveMenuKeySets() async throws {
        BridgeToSHIORI.reset()
        defer { BridgeToSHIORI.reset() }
        BridgeToSHIORI.setResource("inforootbutton.caption", value: "Info")
        BridgeToSHIORI.setResource("inforootbutton.visible", value: "1")
        BridgeToSHIORI.setResource("char2.recommendsites.caption", value: "Char2")
        BridgeToSHIORI.setResource("char2.recommendsites.visible", value: "0")
        BridgeToSHIORI.setResource("menu.frame.color.r", value: "10")
        BridgeToSHIORI.setResource("menu.frame.color.g", value: "20")
        BridgeToSHIORI.setResource("menu.frame.color.b", value: "30")

        let bridge = ResourceBridge.shared
        bridge.invalidateAll()

        let captions = bridge.ownerDrawMenuCaptionKeys()
        let visibilities = bridge.ownerDrawMenuVisibilityKeys()
        #expect(captions.contains("inforootbutton.caption"))
        #expect(captions.contains("char2.recommendsites.caption"))
        #expect(visibilities.contains("quitbutton.visible"))
        #expect(visibilities.contains("char2.recommendsites.visible"))
        #expect(ResourceBridge.ownerDrawMenuButtonBaseKeys.count >= 80)

        let captionMap = bridge.ownerDrawMenuCaptions()
        #expect(captionMap["inforootbutton.caption"]?.title == "Info")
        #expect(captionMap["char2.recommendsites.caption"]?.visible == false)

        let colorMap = bridge.ownerDrawMenuColorMap()
        #expect(colorMap["menu.frame.color"] != nil)
    }

    @Test
    func menuItemsUseDiscoveredGhostShellBalloonLists() async throws {
        BridgeToSHIORI.reset()
        let unique = UUID().uuidString
        let ghostName = "ghost-\(unique)"
        let balloonName = "balloon-\(unique)"
        let base = try OurinPaths.baseDirectory()
        let ghostDir = base.appendingPathComponent("ghost", isDirectory: true).appendingPathComponent(ghostName, isDirectory: true)
        let shellRoot = ghostDir.appendingPathComponent("shell", isDirectory: true)
        let shellA = shellRoot.appendingPathComponent("master", isDirectory: true)
        let shellB = shellRoot.appendingPathComponent("winter", isDirectory: true)
        let balloonDir = base.appendingPathComponent("balloon", isDirectory: true).appendingPathComponent(balloonName, isDirectory: true)

        try FileManager.default.createDirectory(at: shellA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shellB, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: balloonDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: ghostDir)
            try? FileManager.default.removeItem(at: balloonDir)
            BridgeToSHIORI.reset()
        }

        BridgeToSHIORI.setResource("ghostrootbutton.caption", value: "Ghost")
        BridgeToSHIORI.setResource("shellrootbutton.caption", value: "Shell")
        BridgeToSHIORI.setResource("balloonrootbutton.caption", value: "Balloon")

        let bridge = ResourceBridge.shared
        bridge.invalidateAll()

        let items = bridge.menuItems()

        let ghostSubmenu = items.first { $0.caption == "Ghost" }
        let shellSubmenu = items.first { $0.caption == "Shell" }
        let balloonSubmenu = items.first { $0.caption == "Balloon" }
        #expect(ghostSubmenu != nil)
        #expect(shellSubmenu != nil)
        #expect(balloonSubmenu != nil)

        if case .submenu(let ghostItems, _) = ghostSubmenu?.type {
            #expect(ghostItems.contains(where: { $0.caption == ghostName }))
        } else {
            Issue.record("Ghost submenu should exist")
        }

        if case .submenu(let shellItems, _) = shellSubmenu?.type {
            #expect(shellItems.contains(where: { $0.caption == "master" }))
            #expect(shellItems.contains(where: { $0.caption == "winter" }))
        } else {
            Issue.record("Shell submenu should exist")
        }

        if case .submenu(let balloonItems, _) = balloonSubmenu?.type {
            #expect(balloonItems.contains(where: { $0.caption == balloonName }))
        } else {
            Issue.record("Balloon submenu should exist")
        }
    }
}
