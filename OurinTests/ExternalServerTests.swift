import Foundation
import Testing
@testable import Ourin

struct ExternalServerTests {
    private func withInstalledGhost<T>(_ body: () throws -> T) throws -> T {
        let ghostName = "test-ghost-\(UUID().uuidString)"
        let ghostDir = try OurinPaths.baseDirectory()
            .appendingPathComponent("ghost", isDirectory: true)
            .appendingPathComponent(ghostName, isDirectory: true)
        try FileManager.default.createDirectory(at: ghostDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghostDir) }
        return try body()
    }

    @Test
    func parser() throws {
        let raw = "NOTIFY SSTP/1.1\r\nSender: Test\r\nEvent: Foo\r\nCharset: UTF-8\r\n\r\n"
        let msg = SstpParser.parse(raw)
        #expect(msg?.method == "NOTIFY")
        #expect(msg?.headers["Event"] == "Foo")
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
    func routerNotify() throws {
        try withInstalledGhost {
            let raw = "NOTIFY SSTP/1.1\r\nSender: Test\r\nEvent: Bar\r\nCharset: UTF-8\r\n\r\n"
            let router = SstpRouter()
            let resp = router.handle(raw: raw)
            #expect(resp.contains("204"))
        }
    }

    @Test
    func routerSend() throws {
        try withInstalledGhost {
            let raw = "SEND SSTP/1.1\r\nSender: Test\r\nEvent: Baz\r\nCharset: UTF-8\r\n\r\n"
            let router = SstpRouter()
            let resp = router.handle(raw: raw)
            #expect(resp.contains("200"))
        }
    }

    @Test
    func routerExecuteWithoutCommand() throws {
        try withInstalledGhost {
            let raw = "EXECUTE SSTP/1.1\r\nSender: Test\r\nCharset: UTF-8\r\n\r\n"
            let router = SstpRouter()
            let resp = router.handle(raw: raw)
            #expect(resp.contains("400"))
        }
    }

    @Test
    func routerGiveReturnsNoContent() throws {
        try withInstalledGhost {
            let raw = "GIVE SSTP/1.1\r\nSender: Test\r\nCharset: UTF-8\r\n\r\n"
            let router = SstpRouter()
            let resp = router.handle(raw: raw)
            #expect(resp.contains("204"))
        }
    }

    @Test
    func routerInstallRoutesToBridge() throws {
        try withInstalledGhost {
            let key = "install-router-\(UUID().uuidString)"
            BridgeToSHIORI.setResource(key, value: "\\h\\s0Installed")
            let raw = """
            INSTALL SSTP/1.1\r
            Sender: Test\r
            Event: Resource\r
            Reference0: \(key)\r
            Charset: UTF-8\r
            \r
            """
            let router = SstpRouter()
            let resp = router.handle(raw: raw)
            #expect(resp.contains("200"))
            #expect(resp.contains("Script: \\h\\s0Installed"))
        }
    }

    @Test
    func routerCanAllowExternalSecurityLevelWhenConfigured() throws {
        try withInstalledGhost {
            let key = "external-router-\(UUID().uuidString)"
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
            let router = SstpRouter()
            router.updateConfig(.init(securityLocalOnly: false, maxPayloadSize: 1024 * 1024, timeout: 30))
            let resp = router.handle(raw: raw)
            #expect(resp.contains("200"))
            #expect(resp.contains("Script: \\h\\s0ExternalAllowed"))
        }
    }
}
