import Foundation
import Testing
@testable import Ourin

struct PluginEncodingTests {
    @Test
    func requestEncodingUsesDeclaredCharset() throws {
        let request = PluginRequest(
            method: .get,
            id: "OnEncoding",
            charset: "Shift_JIS",
            references: ["Reference0": "日本語"]
        )
        let wire = PluginProtocolBuilder.buildRequest(request)
        let data = PluginWireCodec.encodeRequest(wire, charset: request.charset)

        #expect(String(data: data, encoding: .utf8) == nil)
        let decoded = EncodingAdapter.decode(data, charset: "cp932")
        #expect(decoded?.contains("Reference0: 日本語") == true)
    }

    @Test
    func responseDecodingUsesResponseCharsetHeader() throws {
        let response = PluginResponse(
            statusCode: 200,
            statusMessage: "OK",
            charset: "Shift_JIS",
            script: "\\0日本語\\e",
            otherHeaders: [
                "Event": "OnPluginEncoding",
                "Reference0": "成功"
            ]
        )
        let wire = PluginProtocolBuilder.buildResponse(response)
        let data = EncodingAdapter.encode(wire, charset: "Shift_JIS")
        let decoded = try #require(PluginWireCodec.decodeResponse(data, requestCharset: "UTF-8"))
        let parsed = try PluginProtocolParser.parseResponse(decoded)

        #expect(parsed.script == "\\0日本語\\e")
        #expect(parsed.otherHeaders["Reference0"] == "成功")
        #expect(parsed.charset == "Shift_JIS")
    }
}
