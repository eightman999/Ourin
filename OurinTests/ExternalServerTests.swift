import Testing
@testable import Ourin

struct ExternalServerTests {
    @Test
    func parser() throws {
        let raw = "NOTIFY SSTP/1.1\r\nSender: Test\r\nEvent: Foo\r\nCharset: UTF-8\r\n\r\n"
        let msg = SstpParser.parse(raw)
        #expect(msg?.method == "NOTIFY")
        #expect(msg?.headers["Event"] == "Foo")
    }

    @Test
    func routerNotify() throws {
        let raw = "NOTIFY SSTP/1.1\r\nSender: Test\r\nEvent: Bar\r\nCharset: UTF-8\r\n\r\n"
        let router = SstpRouter()
        let resp = router.handle(raw: raw)
        #expect(resp.contains("204"))
    }

    @Test
    func routerSend() throws {
        let raw = "SEND SSTP/1.1\r\nSender: Test\r\nEvent: Baz\r\nCharset: UTF-8\r\n\r\n"
        let router = SstpRouter()
        let resp = router.handle(raw: raw)
        #expect(resp.contains("200"))
    }
}
