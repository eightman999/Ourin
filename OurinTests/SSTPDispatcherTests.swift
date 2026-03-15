import Foundation
import Testing
@testable import Ourin

struct SSTPDispatcherTests {
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
}
