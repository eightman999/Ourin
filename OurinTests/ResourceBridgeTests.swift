import Testing
@testable import Ourin

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
}
