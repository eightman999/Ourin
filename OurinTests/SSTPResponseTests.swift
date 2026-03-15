import Testing
@testable import Ourin

struct SSTPResponseTests {
    @Test
    func toWireFormatIncludesScriptDataPassThru() async throws {
        var response = SSTPResponse(
            version: "SSTP/1.4",
            statusCode: 200,
            headers: ["Charset": "UTF-8", "Sender": "Ourin"]
        )
        response.setScript("\\h\\s0hello")
        response.setData("payload")
        response.setPassThru("token")

        let wire = response.toWireFormat()
        #expect(wire.contains("SSTP/1.4 200 OK"))
        #expect(wire.contains("Charset: UTF-8"))
        #expect(wire.contains("Sender: Ourin"))
        #expect(wire.contains("Script: \\h\\s0hello"))
        #expect(wire.contains("Data: payload"))
        #expect(wire.contains("X-SSTP-PassThru: token"))
    }

    @Test
    func noContentResponseStillFormats() async throws {
        let response = SSTPResponse(statusCode: 204, headers: ["Charset": "UTF-8"])
        let wire = response.toWireFormat()
        #expect(wire.contains("SSTP/1.4 204 No Content"))
        #expect(wire.contains("Charset: UTF-8"))
    }

    @Test
    func defaultStatusMessageMappings() async throws {
        #expect(SSTPResponse.defaultStatusMessage(for: 210) == "Break")
        #expect(SSTPResponse.defaultStatusMessage(for: 512) == "Invisible")
        #expect(SSTPResponse.defaultStatusMessage(for: 501) == "Not Implemented")
        #expect(SSTPResponse.defaultStatusMessage(for: 999) == "Status")
    }
}

