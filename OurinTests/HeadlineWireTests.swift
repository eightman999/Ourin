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

    @Test
    func buildVersionRequest20() async throws {
        let req = HeadlineWireEngine.buildVersionRequest(version: .v2_0)
        #expect(req.contains("GET Version HEADLINE/2.0"))
        #expect(req.contains("Charset: UTF-8"))
        #expect(req.contains("Sender: Ourin"))
        #expect(req.hasSuffix("\r\n\r\n"))
    }

    @Test
    func buildVersionRequest20M() async throws {
        let req = HeadlineWireEngine.buildVersionRequest(version: .v2_0M)
        #expect(req.contains("GET Version HEADLINE/2.0M"))
        #expect(req.contains("Charset: UTF-8"))
        #expect(req.contains("Sender: Ourin"))
    }

    @Test
    func buildHeadlineRequest20() async throws {
        let req = HeadlineWireEngine.buildHeadlineRequest(
            path: "/tmp/test.html",
            version: .v2_0,
            charset: .utf8,
            sender: "SSP"
        )
        #expect(req.contains("GET Headline HEADLINE/2.0"))
        #expect(req.contains("Charset: UTF-8"))
        #expect(req.contains("Sender: SSP"))
        #expect(req.contains("Option: url"))
        #expect(req.contains("Path: /tmp/test.html"))
        #expect(req.hasSuffix("\r\n\r\n"))
    }

    @Test
    func buildHeadlineRequest20M() async throws {
        let req = HeadlineWireEngine.buildHeadlineRequest(
            path: "/tmp/test.html",
            version: .v2_0M
        )
        #expect(req.contains("GET Headline HEADLINE/2.0M"))
        #expect(req.contains("Charset: UTF-8"))
        #expect(req.contains("Sender: Ourin"))
    }

    @Test
    func buildHeadlineRequestShiftJIS() async throws {
        let req = HeadlineWireEngine.buildHeadlineRequest(
            path: "C:\\SSP\\temp\\test.html",
            version: .v2_0,
            charset: .shiftJIS
        )
        #expect(req.contains("Charset: Shift_JIS"))
    }

    @Test
    func parseVersionResponse() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: UTF-8\r
        Value: HeadlineModule 1.1\r
        \r
        """
        let version = HeadlineWireEngine.parseVersion(resp)
        #expect(version == "HeadlineModule 1.1")
    }

    @Test
    func parseVersionResponseNoValue() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: UTF-8\r
        \r
        """
        let version = HeadlineWireEngine.parseVersion(resp)
        #expect(version == nil)
    }

    @Test
    func parseCharsetUTF8() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: UTF-8\r
        \r
        """
        let charset = HeadlineWireEngine.parseCharset(resp)
        #expect(charset == .utf8)
    }

    @Test
    func parseCharsetShiftJIS() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: Shift_JIS\r
        \r
        """
        let charset = HeadlineWireEngine.parseCharset(resp)
        #expect(charset == .shiftJIS)
    }

    @Test
    func parseRequestCharset() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: UTF-8\r
        RequestCharset: Shift_JIS\r
        \r
        """
        let reqCharset = HeadlineWireEngine.parseRequestCharset(resp)
        #expect(reqCharset == .shiftJIS)
    }

    @Test
    func parseRequestCharsetNotPresent() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: UTF-8\r
        \r
        """
        let reqCharset = HeadlineWireEngine.parseRequestCharset(resp)
        #expect(reqCharset == nil)
    }

    @Test
    func parseHeadlinesMultiple() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: UTF-8\r
        Headline: ほげほげ1\u{01}https://example.com/1\r
        Headline: ほげほげ2\u{01}https://example.com/2\r
        Headline: ほげほげ3\u{01}https://example.com/3\r
        \r
        """
        let headlines = HeadlineWireEngine.parseLines(resp)
        #expect(headlines.count == 3)
        #expect(headlines[0].0 == "ほげほげ1")
        #expect(headlines[0].1 == "https://example.com/1")
        #expect(headlines[1].0 == "ほげほげ2")
        #expect(headlines[2].0 == "ほげほげ3")
    }

    @Test
    func parseHeadlinesWithoutURL() async throws {
        let resp = """
        HEADLINE/2.0 200 OK\r
        Charset: UTF-8\r
        Headline: プレーンテキストヘッドライン\r
        \r
        """
        let headlines = HeadlineWireEngine.parseLines(resp)
        #expect(headlines.count == 1)
        #expect(headlines[0].0 == "プレーンテキストヘッドライン")
        #expect(headlines[0].1 == nil)
    }

    @Test
    func legacyBuildRequestBackwardCompatibility() async throws {
        // Ensure the legacy buildRequest method still works and defaults to 2.0M
        let req = HeadlineWireEngine.buildRequest(path: "/tmp/file")
        #expect(req.contains("GET Headline HEADLINE/2.0M"))
        #expect(req.contains("Charset: UTF-8"))
    }
}
