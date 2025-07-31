import Testing
@testable import Ourin

struct BuildGETTests {
    @Test
    func buildHeader() async throws {
        let data = buildGET(id: "Ping", refs: ["foo", "bar"])
        let expected = "Charset: UTF-8\r\nID: Ping\r\nReference0: foo\r\nReference1: bar\r\nSender: Ourin\r\n\r\n".data(using: .utf8)!
        #expect(data == expected)
    }
}
