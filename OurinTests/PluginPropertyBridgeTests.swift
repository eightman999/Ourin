import Testing
@testable import Ourin

struct PluginPropertyBridgeTests {
    @Test
    func extGetDelegatesToPluginBridge() {
        let plugin = PropertyPlugin(name: "Bridge", path: "/plugin/bridge.plugin", id: "bridge-id")
        let provider = PluginPropertyProvider(
            plugins: [plugin],
            extGet: { target, key in
                target.id == "bridge-id" && key == "somekey" ? "plugin-value" : nil
            }
        )

        #expect(provider.get(key: "index(0).ext.somekey") == "plugin-value")
        #expect(provider.get(key: "(bridge-id).ext.missing") == nil)
    }

    @Test
    func extSetDelegatesToPluginBridge() {
        let plugin = PropertyPlugin(name: "Bridge", path: "/plugin/bridge.plugin", id: "bridge-id")
        var calls: [(String, String)] = []
        let provider = PluginPropertyProvider(
            plugins: [plugin],
            extSet: { _, key, value in
                calls.append((key, value))
                return key == "somekey" && value == "x"
            }
        )

        #expect(provider.set(key: "index(0).ext.somekey", value: "x"))
        #expect(calls.count == 1)
        #expect(calls.first?.0 == "somekey")
        #expect(calls.first?.1 == "x")
        #expect(provider.set(key: "index(0).name", value: "no") == false)
    }
}
