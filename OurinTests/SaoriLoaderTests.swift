import Foundation
import Testing
@testable import Ourin

struct SaoriLoaderTests {
    @Test
    func loadsAndRequestsUsingStandardPosixSaoriABI() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let moduleURL = repositoryRoot.appendingPathComponent("satori_core/build/external_saori.dylib")
        try #require(FileManager.default.fileExists(atPath: moduleURL.path))

        let loader = try SaoriLoader(url: moduleURL)
        defer { loader.unload() }

        let version = try loader.send(
            "GET Version SAORI/1.0\r\nCharset: UTF-8\r\n\r\n"
        )
        let versionResponse = try SaoriProtocol.parseResponse(version)
        #expect(versionResponse.statusCode == 200)

        let response = try loader.send(
            "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\nArgument0: ping\r\n\r\n"
        )
        let parsed = try SaoriProtocol.parseResponse(response)
        #expect(parsed.statusCode == 200)
        #expect(parsed.headers["Result"] == "external-saori-ok")
        #expect(parsed.headers["Value0"] == "fixture-value")
    }
}
