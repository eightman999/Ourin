import Foundation
import Testing
@testable import Ourin

struct SaoriProtocolTests {
    @Test
    func parseRequestBasic() throws {
        let raw = """
        EXECUTE SAORI/1.0\r
        Charset: UTF-8\r
        Argument0: hello\r
        \r
        body
        """
        let parsed = try SaoriProtocol.parseRequest(raw)
        #expect(parsed.method == "EXECUTE")
        #expect(parsed.version == "SAORI/1.0")
        #expect(parsed.headers["Charset"] == "UTF-8")
        #expect(parsed.headers["Argument0"] == "hello")
        #expect(parsed.body == "body")
    }

    @Test
    func buildAndParseResponseRoundtrip() throws {
        let res = SaoriResponse(
            version: "SAORI/1.0",
            statusCode: 200,
            statusMessage: "OK",
            headers: ["Charset": "UTF-8", "Result": "1"],
            body: "Value: done"
        )
        let wire = SaoriProtocol.buildResponse(res)
        let reparsed = try SaoriProtocol.parseResponse(wire)
        #expect(reparsed.statusCode == 200)
        #expect(reparsed.headers["Result"] == "1")
        #expect(reparsed.body == "Value: done")
    }

    @Test
    func charsetEncodeDecodeShiftJis() throws {
        let input = "こんにちは"
        let data = try SaoriProtocol.encode(input, charset: "Shift_JIS")
        let decoded = try SaoriProtocol.decode(data, charset: "windows-31j")
        #expect(decoded == input)
    }
}
