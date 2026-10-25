import Foundation
import AppKit
import Testing
@testable import Ourin

private final class FineWireRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var scripts: [String] = []

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }
    func request(method: String, id: String, headers: [String: String], refs: [String], timeout: TimeInterval) -> ShioriRuntimeResponse? {
        if id == "OnTranslate" { scripts.append(refs.first ?? "") }
        return .init(ok: true, status: 204)
    }
    func unload() { isLoaded = false }
}

/// SSP 2.8.35f デコンパイル互換: P1/P2 修正の回帰テスト。
/// - #106 Sender/User-Agent 両方無し SEND/NOTIFY → 400
/// - #107 SHIORI 非標準ステータス → 204 丸め
/// - #108 X-Force-Activate-Me → forceActivate 効果
/// - #110 X-SSTP-Return- フォールバック
/// - #112 SecurityOrigin: null
/// - #113 EXECUTE Command[args] 形式とネイティブコマンド
@Suite(.serialized, .eventBridgeIsolated)
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

    // MARK: - #109 FINE（ProcNotifyFINE @0x68adf0 互換）

    // 正本: リクエスト行は `FINE <subcommand> [SSTP/x.y]`。
    // MessageSend は Reference0=宛先（さくら名）, Reference1=けろ名, Reference3=内容。

    @Test
    func fineRequestLineSubcommandIsAccepted() async throws {
        // `FINE MessageSend SSTP/1.4` 形式。内容はあるが稼働ゴーストが無いので
        // SSP どおり 420 Refuse（旧実装はサブコマンドが version スロットに入り 505）。
        let req = SSTPRequest(
            method: "FINE",
            version: "MessageSend",
            headers: [
                "Reference0": "Emily",
                "Reference3": "\\h\\s0Fine\\e",
                "Charset": "UTF-8"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 420 Refuse"))
    }

    @MainActor
    @Test(arguments: ["SetScript", "SetScriptPartial"])
    func fineWireSetScriptUsesReference0AsInitialText(_ command: String) async throws {
        try await withFineGhosts([.init(name: "Input Ghost")]) { managers, _ in
            let initial = "\\0入力の初期値\\e"
            let request = SSTPParser.parseRequest(text:
                "FINE \(command) SSTP/1.4\r\nCharset: UTF-8\r\nReference0: \(initial)\r\n\r\n")
            let response = SSTPDispatcher.dispatch(request: request, bridge: bridge)
            #expect(response.hasPrefix("SSTP/1.4 200 OK"))
            await flushFineDelivery()
            let dialog = try #require(managers[0].activeInputDialogs.first { $0.id == "OnFine\(command)" })
            let field = try #require(dialog.alert.accessoryView as? NSTextField)
            #expect(field.stringValue == initial)
            #expect(field.stringValue != command)
        }
    }

    @Test
    func fineUnknownSubcommandReturns501() async throws {
        let req = SSTPRequest(
            method: "FINE",
            version: "UnknownSub",
            headers: ["Charset": "UTF-8"]
        )
        #expect(SSTPDispatcher.dispatch(request: req, bridge: bridge).contains("SSTP/1.4 501"))

        // サブコマンド空も一致なしとして 501（旧実装は 400）。
        let empty = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: ["Charset": "UTF-8"]
        )
        #expect(SSTPDispatcher.dispatch(request: empty, bridge: bridge).contains("SSTP/1.4 501"))
    }

    @MainActor
    @Test(arguments: ["MessageSend", "SetScript", "SetScriptPartial"])
    func fineLegacyReference0SubcommandIsRejectedWithoutDelivery(_ command: String) async throws {
        await withFineGhosts([.init(name: command)]) { managers, runtimes in
            let request = SSTPParser.parseRequest(text:
                "FINE SSTP/1.4\r\nCharset: UTF-8\r\nReference0: \(command)\r\nReference3: \\0unexpected\\e\r\n\r\n")
            let response = SSTPDispatcher.dispatch(request: request, bridge: bridge)
            #expect(response.hasPrefix("SSTP/1.4 501"))
            await flushFineDelivery()
            #expect(runtimes[0].scripts.isEmpty)
            #expect(managers[0].activeInputDialogs.isEmpty)
        }
    }

    @MainActor
    @Test
    func fineWireMessageSendUsesReference3AndOnlySakuraMatch() async throws {
        await withFineGhosts([
            .init(name: "First Ghost", sakuraName: "First Sakura", keroName: "First Kero"),
            .init(name: "Second Ghost", sakuraName: "Second Sakura", keroName: "Second Kero")
        ]) { _, runtimes in
            let content = "\\0Reference3の本文\\e"
            let request = SSTPParser.parseRequest(text:
                "FINE MessageSend SSTP/1.4\r\nCharset: UTF-8\r\nReference0: first sakura\r\nReference1: Second Kero\r\nReference2: wrong-ref2\r\nReference3: \(content)\r\nReference4: wrong-ref4\r\n\r\n")
            #expect(SSTPDispatcher.dispatch(request: request, bridge: bridge).hasPrefix("SSTP/1.4 200 OK"))
            await flushFineDelivery()
            #expect(runtimes[0].scripts == [content])
            #expect(runtimes[1].scripts.isEmpty)
        }
    }

    @MainActor
    @Test(arguments: ["", "Missing Sakura"])
    func fineWireMessageSendFallsBackToUniqueKero(_ sakura: String) async throws {
        await withFineGhosts([
            .init(name: "First", keroName: "First Kero"),
            .init(name: "Second", keroName: "Second Kero")
        ]) { _, runtimes in
            let content = "\\0Kero only\\e"
            let request = SSTPParser.parseRequest(text:
                "FINE MessageSend SSTP/1.4\r\nReference0: \(sakura)\r\nReference1: second kero\r\nReference3: \(content)\r\n\r\n")
            #expect(SSTPDispatcher.dispatch(request: request, bridge: bridge).hasPrefix("SSTP/1.4 200 OK"))
            await flushFineDelivery()
            #expect(runtimes[0].scripts.isEmpty)
            #expect(runtimes[1].scripts == [content])
        }
    }

    @MainActor
    @Test(arguments: ["missing", "unspecified", "ambiguous-sakura", "ambiguous-kero"])
    func fineWireMessageSendRefusesUnresolvedOrAmbiguousTargets(_ scenario: String) async throws {
        await withFineGhosts([
            .init(name: "First", sakuraName: "Shared Sakura", keroName: "Shared Kero"),
            .init(name: "Second", sakuraName: "Shared Sakura", keroName: "Shared Kero")
        ]) { _, runtimes in
            let references: String
            switch scenario {
            case "missing": references = "Reference0: Unknown\r\nReference1: Unknown Kero\r\n"
            case "ambiguous-sakura": references = "Reference0: Shared Sakura\r\n"
            case "ambiguous-kero": references = "Reference1: Shared Kero\r\n"
            default: references = ""
            }
            let request = SSTPParser.parseRequest(text:
                "FINE MessageSend SSTP/1.4\r\n\(references)Reference3: \\0must not broadcast\\e\r\n\r\n")
            #expect(SSTPDispatcher.dispatch(request: request, bridge: bridge).hasPrefix("SSTP/1.4 420 Refuse"))
            await flushFineDelivery()
            #expect(runtimes.allSatisfy { $0.scripts.isEmpty })
        }
    }

    @MainActor
    private func flushFineDelivery() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    private func withFineGhosts(
        _ configurations: [GhostConfiguration],
        body: ([GhostManager], [FineWireRuntime]) async throws -> Void
    ) async rethrows {
        let application = NSApplication.shared
        let previousDelegate = application.delegate
        let appDelegate = (previousDelegate as? AppDelegate) ?? AppDelegate()
        let previousPrimary = appDelegate.ghostManager
        let previousAdditional = appDelegate.additionalGhosts
        application.delegate = appDelegate
        let runtimes = configurations.map { _ in FineWireRuntime() }
        let managers = configurations.enumerated().map { index, configuration in
            let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-fine-\(UUID().uuidString)"))
            manager.ghostConfig = configuration
            manager.shioriRuntime = runtimes[index]
            return manager
        }
        appDelegate.ghostManager = managers.first
        appDelegate.additionalGhosts = Array(managers.dropFirst())
        let tokens = managers.enumerated().map {
            EventBridge.shared.register(runtime: runtimes[$0.offset], ghostManager: $0.element)
        }
        defer {
            tokens.forEach { EventBridge.shared.unregister($0) }
            for manager in managers {
                Array(manager.activeInputDialogs).forEach { manager.closeInputDialog(id: $0.id) }
                manager.cancelPlaybackForBalloonBreak()
                manager.shioriRuntime = nil
            }
            appDelegate.ghostManager = previousPrimary
            appDelegate.additionalGhosts = previousAdditional
            application.delegate = previousDelegate
        }
        try await body(managers, runtimes)
    }

    @Test
    func fineMessageSendWithoutContentReturns400() async throws {
        let req = SSTPRequest(
            method: "FINE",
            version: "MessageSend",
            headers: ["Reference0": "Emily", "Charset": "UTF-8"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 400 Bad Request"))
    }
}
