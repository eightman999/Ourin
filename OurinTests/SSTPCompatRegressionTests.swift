import Foundation
import Testing
@testable import Ourin

/// SSP 2.8.35f デコンパイル互換: P1/P2 修正の回帰テスト。
/// - #106 Sender/User-Agent 両方無し SEND/NOTIFY → 400
/// - #107 SHIORI 非標準ステータス → 204 丸め
/// - #108 X-Force-Activate-Me → forceActivate 効果
/// - #110 X-SSTP-Return- フォールバック
/// - #112 SecurityOrigin: null
/// - #113 EXECUTE Command[args] 形式とネイティブコマンド
@Suite(.serialized)
struct SSTPCompatRegressionTests {
    let bridge = ShioriBridgeContext()

    init() {
        GhostRegistry.shared.clear()
        SSTPOwnershipRegistry.shared.removeAll()
    }

    // MARK: - #106 Sender / User-Agent

    @Test
    func sendWithoutSenderAndUserAgentReturns400() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["Event": "OnTest", "Charset": "UTF-8"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 400 Bad Request"))
    }

    @Test
    func notifyWithoutSenderAndUserAgentReturns400() async throws {
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: ["Event": "OnTest", "Charset": "UTF-8"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 400 Bad Request"))
    }

    @Test
    func sendWithUserAgentOnlyIsAccepted() async throws {
        // Sender が無くても User-Agent があれば SSP は受理する。
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Script": "\\h\\s0UA\\e",
                "Charset": "UTF-8",
                "User-Agent": "CompatTest/1.0"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
    }

    // MARK: - #107 非標準ステータス 204 丸め

    @Test
    func shioriNonStandardStatusIsRoundedTo204() async throws {
        let key = "compat-500-\(UUID().uuidString)"
        bridge.setResource(key, value: "SHIORI/3.0 500 Internal Server Error\r\n\r\n")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Charset": "UTF-8",
                "Option": "nodescript"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 204 No Content"))
    }

    @Test
    func shioriStandardStatusesPassThrough() async throws {
        // 200 はそのまま 200。
        let key200 = "compat-200-\(UUID().uuidString)"
        bridge.setResource(key200, value: "SHIORI/3.0 200 OK\r\nValue: v\r\n\r\n")
        let req200 = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key200,
                "Charset": "UTF-8",
                "Option": "nodescript"
            ]
        )
        #expect(SSTPDispatcher.dispatch(request: req200, bridge: bridge).contains("SSTP/1.4 200 OK"))
    }

    // MARK: - #108 X-Force-Activate-Me

    @Test
    func forceActivateHeaderEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Script": "\\h\\s0Act\\e",
                "Charset": "UTF-8",
                "X-Force-Activate-Me": "true"
            ]
        )
        _ = SSTPDispatcher.dispatch(
            request: req,
            host: spy,
            bridge: bridge
        )
        guard case .forceActivate = spy.effects.last?.kind else {
            Issue.record("expected forceActivate effect, got \(String(describing: spy.effects.last?.kind))")
            return
        }
    }

    @Test
    func forceActivateHeaderZeroValueDoesNotEmitEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Script": "\\h\\s0Act\\e",
                "Charset": "UTF-8",
                "X-Force-Activate-Me": "0"
            ]
        )
        _ = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)
        #expect(spy.effects.isEmpty)
    }

    // MARK: - #110 X-SSTP-Return- フォールバック

    @Test
    func shioriReturnHeadersFallbackToSstpResponse() async throws {
        let key = "compat-return-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: "SHIORI/3.0 200 OK\r\nValue: v\r\nX-SSTP-Return-Marker: keep\r\n\r\n"
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Charset": "UTF-8",
                "Option": "nodescript"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("X-SSTP-Return-Marker: keep"))
    }

    // MARK: - #113 EXECUTE Command[args] 形式

    @Test
    func executeCallGhostBracketSyntaxEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "CallGhost[Emily,raise-event]"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        guard case .callGhost(let name, let options) = spy.effects.last?.kind else {
            Issue.record("expected callGhost effect, got \(String(describing: spy.effects.last?.kind))")
            return
        }
        #expect(name == "Emily")
        #expect(options == ["raise-event"])
    }

    @Test
    func executeURLExecEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "URLExec", "Reference0": "https://example.com/"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        guard case .openURL(let url) = spy.effects.last?.kind else {
            Issue.record("expected openURL effect")
            return
        }
        #expect(url == "https://example.com/")
    }

    @Test
    func executeGetCollisionReturnsCollisionList() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetCollision"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        // SpySstpDispatcherHost.collectCollisionList は "head,body" を返す。
        #expect(resp.contains("head,body"))
    }

    @Test
    func executeCompressArchiveRequiresLocalSecurity() async throws {
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "CompressArchive",
                "Reference0": "in",
                "Reference1": "out.zip",
                "SecurityLevel": "external"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 420 Refuse"))
    }
}
