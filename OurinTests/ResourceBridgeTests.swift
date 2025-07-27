import Testing
@testable import Ourin

struct ResourceBridgeTests {
    @Test
    func cacheBehavior() async throws {
        let bridge = ResourceBridge.shared
        bridge.invalidateAll()
        let v1 = bridge.get("test.key")
        let v2 = bridge.get("test.key")
        // same result when cached
        #expect(v1 == v2)
    }

    @Test
    func menuParsing() async throws {
        let bridge = ResourceBridge.shared
        bridge.invalidateAll()
        // BridgeToSHIORI は固定文字列を返すため caption として扱う
        let item = bridge.menuItem(for: "menu.test.caption")
        #expect(item?.title.contains("Placeholder") == true)
    }
}
