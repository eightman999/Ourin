import Testing
@testable import Ourin

struct OurinPluginEventBridgeTests {
    @Test
    func parsesScriptAndEventFromGetResponse() async throws {
        let response = PluginResponse(
            statusCode: 200,
            statusMessage: "OK",
            value: nil,
            script: "\\0Hello\\e",
            scriptOption: nil,
            target: "baseware",
            otherHeaders: [
                "Event": "OnPluginBridge",
                "Reference0": "alpha",
                "Reference1": "beta"
            ]
        )

        let action = OurinPluginEventBridge.transportAction(from: response, notifyOnly: false)
        #expect(action != nil)
        #expect(action?.script == "\\0Hello\\e")
        #expect(action?.eventName == "OnPluginBridge")
        #expect(action?.references["Reference0"] == "alpha")
        #expect(action?.references["Reference1"] == "beta")
        #expect(OurinPluginEventBridge.shouldHandleTarget("baseware") == true)
    }

    @Test
    func ignoresNotifyResponses() async throws {
        let response = PluginResponse(
            statusCode: 204,
            statusMessage: "No Content",
            script: "\\0Ignored\\e",
            otherHeaders: ["Event": "OnIgnored"]
        )

        #expect(OurinPluginEventBridge.transportAction(from: response, notifyOnly: true) == nil)
    }

    @Test
    func rejectsUnknownTarget() async throws {
        #expect(OurinPluginEventBridge.shouldHandleTarget("other-ghost") == false)
        #expect(OurinPluginEventBridge.shouldHandleTarget("ourin") == true)
        #expect(OurinPluginEventBridge.shouldHandleTarget(nil) == true)
    }
}
