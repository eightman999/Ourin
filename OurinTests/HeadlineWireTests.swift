import Testing
@testable import Ourin

struct HeadlineWireTests {
    @Test
    func buildAndParse() async throws {
        let req = HeadlineWireEngine.buildRequest(path: "/tmp/file")
        #expect(req.contains("GET Headline"))
        let resp = "Headline: hello\u{01}https://example.com\r\n\r\n"
        let parsed = HeadlineWireEngine.parseLines(resp)
        #expect(parsed.count == 1)
        #expect(parsed.first?.0 == "hello")
        #expect(parsed.first?.1 == "https://example.com")
    }
}
