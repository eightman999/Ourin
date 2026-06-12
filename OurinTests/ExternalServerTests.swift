import Foundation
import Testing
@testable import Ourin

/// 外部 SSTP サーバ経路（生テキスト → SSTPParser → SSTPDispatcher）のテスト。
/// P2-10 の一本化により SstpRouter / SstpMessage は廃止された。
struct ExternalServerTests {
    private func makeServer(securityLocalOnly: Bool = true) -> OurinExternalServer {
        let server = OurinExternalServer()
        server.updateConfig(.init(
            securityLocalOnly: securityLocalOnly,
            maxPayloadSize: 1024 * 1024,
            timeout: 30,
            enableTCP: false,
            enableHTTP: false,
            enableXPC: false,
            enableDistributedIPC: false
        ))
        return server
    }

    @Test
    func parserKeepsRequestLineAndHeaders() throws {
        let raw = "NOTIFY SSTP/1.1\r\nSender: Test\r\nEvent: Foo\r\nCharset: UTF-8\r\n\r\n"
        let req = SSTPParser.parseRequest(text: raw)
        #expect(req.method == "NOTIFY")
        #expect(req.version == "SSTP/1.1")
        #expect(req.headerValue("Event") == "Foo")
    }

    @Test
    func parserPreservesDuplicateHeadersInOrder() throws {
        let raw = """
        SEND SSTP/1.4\r
        Sender: Test\r
        Script: \\h\\s0Default\\e\r
        IfGhost: Emily\r
        Script: \\h\\s0ForEmily\\e\r
        Charset: UTF-8\r
        \r
        """
        let req = SSTPParser.parseRequest(text: raw)
        let bindings = req.scriptBindings
        #expect(bindings.count == 2)
        #expect(bindings[0].ifGhost == nil)
        #expect(bindings[0].script == "\\h\\s0Default\\e")
        #expect(bindings[1].ifGhost == "Emily")
        #expect(bindings[1].script == "\\h\\s0ForEmily\\e")
    }

    @Test
    func responseStatusLineHasSinglePrefix() throws {
        let raw = "NOTIFY SSTP/1.1\r\nSender: Test\r\nEvent: Bar\r\nCharset: UTF-8\r\n\r\n"
        let resp = makeServer().handleRaw(raw)
        #expect(!resp.contains("SSTP/SSTP"))
        #expect(resp.hasPrefix("SSTP/1.1 "))
    }

    @Test
    func httpRequestLineParsesApiPath() throws {
        let parsed = SstpHttpServer.parseRequestLine("POST /api/sstp/v1 HTTP/1.1")
        #expect(parsed?.method == "POST")
        #expect(parsed?.path == "/api/sstp/v1")
    }

    @Test
    func httpOriginAllowsOnlyLocalOrNull() throws {
        #expect(SstpHttpServer.isAcceptedOrigin("http://localhost:3000") == true)
        #expect(SstpHttpServer.isAcceptedOrigin("null") == true)
        #expect(SstpHttpServer.isAcceptedOrigin("https://example.com") == false)
    }

    @Test
    func serverNotifyReturnsNoContent() throws {
        let raw = "NOTIFY SSTP/1.1\r\nSender: Test\r\nEvent: Bar\r\nCharset: UTF-8\r\n\r\n"
        let resp = makeServer().handleRaw(raw)
        #expect(resp.contains("204"))
    }

    @Test
    func serverSendWithEventRoutesToShiori() throws {
        let key = "send-server-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromServer")
        let raw = """
        SEND SSTP/1.1\r
        Sender: Test\r
        Event: Resource\r
        Reference0: \(key)\r
        Charset: UTF-8\r
        \r
        """
        let resp = makeServer().handleRaw(raw)
        #expect(resp.contains("200"))
        #expect(resp.contains("Script: \\h\\s0FromServer"))
    }

    @Test
    func serverSendScriptWithoutEventEchoesScript() throws {
        let raw = "SEND SSTP/1.4\r\nSender: Test\r\nScript: \\h\\s0Hello\\e\r\nCharset: UTF-8\r\n\r\n"
        let resp = makeServer().handleRaw(raw)
        #expect(resp.contains("200"))
        #expect(resp.contains("Script: \\h\\s0Hello\\e"))
    }

    @Test
    func serverNodescriptStillDispatchesEvent() throws {
        let key = "nodescript-server-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Dispatched")
        let raw = """
        SEND SSTP/1.1\r
        Sender: Test\r
        Event: Resource\r
        Reference0: \(key)\r
        Option: nodescript\r
        Charset: UTF-8\r
        \r
        """
        let resp = makeServer().handleRaw(raw)
        // nodescript はバルーン再生のみ抑止し、イベント処理（SHIORI送出）と応答は行う
        #expect(resp.contains("200"))
        #expect(resp.contains("Script: \\h\\s0Dispatched"))
    }

    @Test
    func serverExecuteWithoutCommand() throws {
        let raw = "EXECUTE SSTP/1.1\r\nSender: Test\r\nCharset: UTF-8\r\n\r\n"
        let resp = makeServer().handleRaw(raw)
        #expect(resp.contains("400"))
    }

    @Test
    func serverInstallRoutesToBridge() throws {
        let key = "install-server-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Installed")
        let raw = """
        INSTALL SSTP/1.1\r
        Sender: Test\r
        Event: Resource\r
        Reference0: \(key)\r
        Charset: UTF-8\r
        \r
        """
        let resp = makeServer().handleRaw(raw)
        #expect(resp.contains("200"))
        #expect(resp.contains("Script: \\h\\s0Installed"))
    }

    @Test
    func serverRefusesExternalSecurityLevelByDefault() throws {
        let raw = """
        SEND SSTP/1.1\r
        Sender: Test\r
        Event: OnTest\r
        SecurityLevel: external\r
        Charset: UTF-8\r
        \r
        """
        let resp = makeServer().handleRaw(raw)
        #expect(resp.contains("420"))
    }

    @Test
    func serverCanAllowExternalSecurityLevelWhenConfigured() throws {
        let key = "external-server-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0ExternalAllowed")
        let raw = """
        SEND SSTP/1.1\r
        Sender: Test\r
        Event: Resource\r
        Reference0: \(key)\r
        SecurityLevel: external\r
        Charset: UTF-8\r
        \r
        """
        let resp = makeServer(securityLocalOnly: false).handleRaw(raw)
        #expect(resp.contains("200"))
        #expect(resp.contains("Script: \\h\\s0ExternalAllowed"))
    }

    @Test
    func serverParseFailureReturns400() throws {
        let resp = makeServer().handleRaw("garbage")
        #expect(resp.contains("400"))
    }

    @Test
    func serverIfGhostUnmatchedFallsBackToDefaultScript() throws {
        // IfGhost 不一致時は最初の IfGhost より前の Script（デフォルトスクリプト）が使われる
        let raw = """
        SEND SSTP/1.4\r
        Sender: Test\r
        Script: \\h\\s0DefaultScript\\e\r
        IfGhost: no-such-ghost-\(UUID().uuidString)\r
        Script: \\h\\s0NeverMatched\\e\r
        Charset: UTF-8\r
        \r
        """
        let resp = makeServer().handleRaw(raw)
        #expect(resp.contains("200"))
        #expect(resp.contains("Script: \\h\\s0DefaultScript\\e"))
    }
}
