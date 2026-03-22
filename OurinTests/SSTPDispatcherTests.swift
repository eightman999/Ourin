import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct SSTPDispatcherTests {
    init() {
        BridgeToSHIORI.reset()
        GhostRegistry.shared.clear()
        SstpSessionStore.shared.reset()
        ShioriStatusStore.shared.reset(to: "online")
        unsetenv("OURIN_SSTP_LOCAL_ONLY")
    }

    @Test
    func requestOptionsSupportMixedSeparators() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["Option": "notify nodescript;notranslate,nobreak"]
        )
        #expect(req.options.contains(.notify))
        #expect(req.options.contains(.nodescript))
        #expect(req.options.contains(.notranslate))
        #expect(req.options.contains(.nobreak))
    }

    @Test
    func lowercaseHeadersAreHandledCaseInsensitively() async throws {
        let key = "lower-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Lowercase")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "event": "Resource",
                "reference0": key,
                "charset": "UTF-8",
                "option": "nodescript"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(!resp.contains("Script:"))
    }

    @Test
    func sendResourceMapsToScript() async throws {
        let key = "test-key-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromResource")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Charset": "UTF-8"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromResource"))
    }

    @Test
    func notifyReturnsNoContent() async throws {
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: ["Event": "OnNotifyTest", "Charset": "UTF-8"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 204 No Content"))
        #expect(!resp.contains("Script:"))
    }

    @Test
    func executeWithoutCommandReturnsBadRequest() async throws {
        let req = SSTPRequest(method: "EXECUTE", version: "SSTP/1.4", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 400 Bad Request"))
    }

    @Test
    func shioriWireResponseMapsStatusAndData() async throws {
        let key = "wire-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
            key,
            value: "SHIORI/3.0 204 No Content\r\nData: sample-data\r\n\r\n"
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "X-SSTP-PassThru": "abc"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 204 No Content"))
        #expect(resp.contains("Data: sample-data"))
        #expect(resp.contains("X-SSTP-PassThru: abc"))
    }

    @Test
    func extendedShioriHeadersMapToSstpAndStatusProperty() async throws {
        let key = "headers-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0FromHeaders\r
            Status: choosing\r
            BaseID: OnChoiceSelect\r
            Marker: marker-1\r
            ErrorLevel: warning\r
            ErrorDescription: sample\r
            BalloonOffset: 12,34\r
            Reference0: ref-zero\r
            Age: 3\r
            MarkerSend: marker-send\r
            X-SSTP-PassThru-Reply: token-reply\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Status": "talking",
                "X-SSTP-PassThru-Client": "token-client"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromHeaders"))
        #expect(resp.contains("Status: choosing"))
        #expect(resp.contains("BaseID: OnChoiceSelect"))
        #expect(resp.contains("Marker: marker-1"))
        #expect(resp.contains("ErrorLevel: warning"))
        #expect(resp.contains("ErrorDescription: sample"))
        #expect(resp.contains("BalloonOffset: 12,34"))
        #expect(resp.contains("Reference0: ref-zero"))
        #expect(resp.contains("Age: 3"))
        #expect(resp.contains("MarkerSend: marker-send"))
        #expect(resp.contains("X-SSTP-PassThru-Client: token-client"))
        #expect(resp.contains("X-SSTP-PassThru-Reply: token-reply"))
    }

    @Test
    func notifyValueNotifyReturnsScript() async throws {
        let key = "notify-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            ValueNotify: \\h\\s0NotifyScript\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0NotifyScript"))
        #expect(resp.contains("ValueNotify: \\h\\s0NotifyScript"))
    }

    @Test
    func sendWithNotifyOptionBehavesAsNotify() async throws {
        let key = "opt-notify-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            ValueNotify: \\h\\s0NotifyViaOption\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Option": "notify"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0NotifyViaOption"))
    }

    @Test
    func nodescriptAndNobreakOptionsAreHandled() async throws {
        let key = "opt-nodescript-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0ShouldNotAppear")
        let nodescriptReq = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )
        let nodescriptResp = SSTPDispatcher.dispatch(request: nodescriptReq)
        #expect(nodescriptResp.contains("SSTP/1.4 200 OK"))
        #expect(!nodescriptResp.contains("Script:"))

        let nobreakReq = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Option": "nobreak"
            ]
        )
        let nobreakResp = SSTPDispatcher.dispatch(request: nobreakReq)
        #expect(nobreakResp.contains("SSTP/1.4 210 Break"))
    }

    @Test
    func ifGhostOverridesScriptForMatchedReceiver() async throws {
        GhostRegistry.shared.clear()
        GhostRegistry.shared.register(name: "Emily", path: "/tmp/emily")
        defer { GhostRegistry.shared.clear() }
        let key = "ifghost-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Base")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "ReceiverGhostName": "Emily",
                "IfGhost": "Emily=\\h\\s0FromIfGhost|\\uFromIfGhost"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("Script: \\h\\s0FromIfGhost"))
    }

    @Test
    func receiverGhostNameRejectsUnknownRegisteredGhost() async throws {
        GhostRegistry.shared.clear()
        GhostRegistry.shared.register(name: "Emily", path: "/tmp/emily")
        defer { GhostRegistry.shared.clear() }
        let key = "receiver-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Base")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "ReceiverGhostName": "UnknownGhost"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 404 Not Found"))
    }

    @Test
    func securityOriginSetsExternalSecurityLevelForShiori() async throws {
        GhostRegistry.shared.clear()
        defer { GhostRegistry.shared.clear() }
        let key = "origin-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0OriginAware\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "SecurityOrigin": "https://example.com"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0OriginAware"))
    }

    @Test
    func entryIsStoredAndReturned() async throws {
        let key = "entry-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Entry")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Entry": "temporary=\\h\\s0Temp"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("Entry:"))
        #expect(resp.contains("temporary=\\h\\s0Temp"))
    }

    @Test
    func executeSetCookieAndGetCookie() async throws {
        let setReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Command": "SetCookie",
                "Reference0": "session",
                "Reference1": "abc123"
            ]
        )
        let setResp = SSTPDispatcher.dispatch(request: setReq)
        #expect(setResp.contains("SSTP/1.4 200 OK"))

        let getReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Command": "GetCookie",
                "Reference0": "session"
            ]
        )
        let getResp = SSTPDispatcher.dispatch(request: getReq)
        #expect(getResp.contains("SSTP/1.4 200 OK"))
        #expect(getResp.contains("Reference0: abc123"))
        #expect(getResp.contains("Data: abc123"))
    }

    @Test
    func executeGetVersionAndGetShortVersion() async throws {
        let getVersionReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetVersion"]
        )
        let getVersionResp = SSTPDispatcher.dispatch(request: getVersionReq)
        #expect(getVersionResp.contains("SSTP/1.4 200 OK"))
        #expect(getVersionResp.contains("Reference0:"))

        let getShortReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetShortVersion"]
        )
        let getShortResp = SSTPDispatcher.dispatch(request: getShortReq)
        #expect(getShortResp.contains("SSTP/1.4 200 OK"))
        #expect(getShortResp.contains("Reference0:"))
    }

    @Test
    func executeGetFmoReturnsDetailedLocalPayload() async throws {
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetFMO",
                "SecurityLevel": "local"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("baseware.name="))
        #expect(resp.contains("baseware.pid="))
        #expect(resp.contains("baseware.path="))
    }

    @Test
    func executeGetFmoRefusesExternalAccess() async throws {
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetFMO",
                "SecurityLevel": "external"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 420 Refuse"))
    }

    @Test
    func executeSetAndGetProperty() async throws {
        let setReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "SetProperty",
                "Reference0": "currentghost.mousecursor.text",
                "Reference1": "arrow"
            ]
        )
        let setResp = SSTPDispatcher.dispatch(request: setReq)
        #expect(setResp.contains("SSTP/1.4 200 OK"))

        let getReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetProperty",
                "Reference0": "currentghost.mousecursor.text"
            ]
        )
        let getResp = SSTPDispatcher.dispatch(request: getReq)
        #expect(getResp.contains("SSTP/1.4 200 OK"))
        #expect(getResp.contains("Reference0: arrow"))
    }

    @Test
    func communicateRoutesToShiori() async throws {
        let key = "comm-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromCommunicate")
        let req = SSTPRequest(
            method: "COMMUNICATE",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromCommunicate"))
    }

    @Test
    func giveRoutesToShiori() async throws {
        let key = "give-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromGive")
        let req = SSTPRequest(
            method: "GIVE",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromGive"))
    }

    @Test
    func installRoutesToShiori() async throws {
        let key = "install-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromInstall")
        let req = SSTPRequest(
            method: "INSTALL",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromInstall"))
    }

    @Test
    func unsupportedMethodReturns501() async throws {
        let req = SSTPRequest(method: "PUSH", version: "SSTP/1.4", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 501 Not Implemented"))
    }

    @Test
    func unsupportedVersionReturns505() async throws {
        let req = SSTPRequest(method: "SEND", version: "SSTP/2.0", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/2.0 505 HTTP Version Not Supported"))
    }

    @Test
    func oversizedPayloadReturns413() async throws {
        let body = Data(repeating: 0x41, count: 1024 * 1024 + 1)
        let req = SSTPRequest(method: "SEND", version: "SSTP/1.4", headers: [:], body: body)
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 413 Payload Too Large"))
    }

    @Test
    func nobreakReturns409WhenShioriStatusBusy() async throws {
        ShioriStatusStore.shared.update(status: "busy")
        defer { ShioriStatusStore.shared.update(status: "talking") }
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["Option": "nobreak"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 409 Conflict"))
    }

    @Test
    func receiverGhostNameReturns512WhenNoRegistryEntries() async throws {
        GhostRegistry.shared.clear()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["ReceiverGhostName": "Emily"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 512 Invisible"))
    }

    @Test
    func sendReturns503WhenShioriUnavailable() async throws {
        BridgeToSHIORI.reset()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["Event": "Resource", "Reference0": "missing-resource-key"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 503 Service Unavailable"))
    }

    @Test
    func externalSecurityCanBeRefusedByPolicy420() async throws {
        setenv("OURIN_SSTP_LOCAL_ONLY", "1", 1)
        defer { unsetenv("OURIN_SSTP_LOCAL_ONLY") }
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["SecurityLevel": "external"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 420 Refuse"))
    }
}
