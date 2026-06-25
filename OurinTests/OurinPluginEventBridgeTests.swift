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
            scriptOption: "nobreak,notranslate",
            eventOption: "notify",
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
        #expect(action?.scriptOptions == Set(["nobreak", "notranslate"]))
        #expect(action?.eventName == "OnPluginBridge")
        #expect(action?.sendsEventAsNotify == true)
        #expect(action?.references["Reference0"] == "alpha")
        #expect(action?.references["Reference1"] == "beta")
        #expect(OurinPluginEventBridge.shouldHandleTarget("baseware") == true)
        #expect(OurinPluginEventBridge.shouldHandleTarget("__SYSTEM_ALL_GHOST__") == true)
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

    @Test
    func normalizesLowercaseReferenceHeaders() async throws {
        let response = PluginResponse(
            statusCode: 200,
            statusMessage: "OK",
            script: "\\0Fallback\\e",
            otherHeaders: [
                "event": "OnLowercase",
                "reference10": "ten",
                "reference2": "two"
            ]
        )

        let action = OurinPluginEventBridge.transportAction(from: response, notifyOnly: false)
        #expect(action?.eventName == "OnLowercase")
        #expect(action?.references["Reference2"] == "two")
        #expect(action?.references["Reference10"] == "ten")
    }

    @Test
    func parserAcceptsCaseInsensitiveResponseHeaders() async throws {
        let wire = """
        PLUGIN/2.0 200 OK\r
        charset: UTF-8\r
        script: \\0Hello\\e\r
        scriptoption: nobreak\r
        event: OnParsed\r
        eventoption: notify\r
        target: __SYSTEM_ALL_GHOST__\r
        reference0: alpha\r
        \r
        """

        let response = try PluginProtocolParser.parseResponse(wire)
        let action = OurinPluginEventBridge.transportAction(from: response, notifyOnly: false)

        #expect(response.version == "PLUGIN/2.0")
        #expect(response.eventOption == "notify")
        #expect(response.target == "__SYSTEM_ALL_GHOST__")
        #expect(action?.scriptOptions == Set(["nobreak"]))
        #expect(action?.sendsEventAsNotify == true)
        #expect(action?.references["Reference0"] == "alpha")
    }

    @Test
    func eventResponseRunsFallbackOnlyWhenGhostDoesNotAnswer() async throws {
        let action = PluginTransportAction(
            target: nil,
            script: "\\0Default\\e",
            scriptOptions: [],
            eventName: "OnPluginEvent",
            eventOptions: [],
            references: [:]
        )

        var ranScript = false
        let handled = OurinPluginEventBridge.deliver(
            action,
            runScript: { _ in ranScript = true },
            emitEvent: { _ in false }
        )

        #expect(handled == true)
        #expect(ranScript == true)
    }

    @Test
    func eventResponseSkipsFallbackWhenGhostAnswers() async throws {
        let action = PluginTransportAction(
            target: nil,
            script: "\\0Default\\e",
            scriptOptions: [],
            eventName: "OnPluginEvent",
            eventOptions: [],
            references: [:]
        )

        var ranScript = false
        let handled = OurinPluginEventBridge.deliver(
            action,
            runScript: { _ in ranScript = true },
            emitEvent: { _ in true }
        )

        #expect(handled == true)
        #expect(ranScript == false)
    }

    @Test
    func notifyEventDoesNotRunDefaultScript() async throws {
        let action = PluginTransportAction(
            target: nil,
            script: "\\0Default\\e",
            scriptOptions: [],
            eventName: "OnPluginEvent",
            eventOptions: ["notify"],
            references: [:]
        )

        var ranScript = false
        let handled = OurinPluginEventBridge.deliver(
            action,
            runScript: { _ in ranScript = true },
            emitEvent: { _ in true }
        )

        #expect(handled == true)
        #expect(ranScript == false)
    }
}
