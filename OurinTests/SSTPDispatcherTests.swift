import Foundation
import AppKit
import Testing
@testable import Ourin

private final class SSTPTranslationRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var translateRequestCount = 0
    private let suffix: String

    init(suffix: String = "-translated") {
        self.suffix = suffix
    }

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        guard id == "OnTranslate" else {
            return .init(ok: true, status: 204)
        }
        translateRequestCount += 1
        return .init(ok: true, status: 200, value: (refs.first ?? "") + suffix)
    }

    func unload() { isLoaded = false }
}

private final class SSTPEventCapturingRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var requests: [(method: String, id: String, refs: [String])] = []

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        requests.append((method, id, refs))
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

private struct SSTPMultiGhostTestState {
    let application: NSApplication
    let previousDelegate: NSApplicationDelegate?
    let appDelegate: AppDelegate
    let previousPrimary: GhostManager?
    let previousAdditional: [GhostManager]
    let primaryToken: UUID
    let secondaryToken: UUID
}

final class FakeSstpRoutingRegistry: SstpRoutingRegistry, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMatchHandler: @Sendable (String?, String?) -> Bool = { _, _ in false }
    private var storedGhostNames: [String] = []

    var matchHandler: @Sendable (String?, String?) -> Bool {
        get { lock.withLock { storedMatchHandler } }
        set { lock.withLock { storedMatchHandler = newValue } }
    }

    var ghostNames: [String] {
        get { lock.withLock { storedGhostNames } }
        set { lock.withLock { storedGhostNames = newValue } }
    }

    func matches(id: String?, receiverGhostName: String?) -> Bool {
        let handler = lock.withLock { storedMatchHandler }
        return handler(id, receiverGhostName)
    }

    func hasGhosts() -> Bool {
        lock.withLock { !storedGhostNames.isEmpty }
    }

    func contains(ghostName: String) -> Bool {
        lock.withLock {
            storedGhostNames.contains { $0.caseInsensitiveCompare(ghostName) == .orderedSame }
        }
    }

    func allGhostNames() -> [String] {
        lock.withLock { storedGhostNames.sorted() }
    }
}

struct FakeSstpBreakPolicy: SstpBreakPolicy {
    let busy: Bool
    let shouldSucceed: Bool
    func isBusy() -> Bool { busy }
    func waitWhileBusy() -> Bool { shouldSucceed }
}

@Suite(.serialized)
struct SSTPDispatcherTests {
    /// 各テストインスタンス固有の独立した SHIORI ブリッジ。
    /// 従来の `BridgeToSHIORI`（`.shared`）の global 静的状態へ一切触れず、
    /// 他スイート（`ExternalServerTests` 等の `.serialized` スイート）と並列実行しても競合しない。
    /// Swift Testing はテスト毎に新しいインスタンスを生成するため、各テストは fresh な bridge を持つ。
    let bridge = ShioriBridgeContext()

    init() {
        GhostRegistry.shared.clear()
        SSTPOwnershipRegistry.shared.removeAll()
        SstpSessionStore.shared.reset()
        ShioriStatusStore.shared.reset(to: "online")
        unsetenv("OURIN_SSTP_LOCAL_ONLY")
    }

    @Test
    func ownedIDMatchesOnlyTheIntendedGhost() async throws {
        SSTPOwnershipRegistry.shared.replaceEntries([
            .init(targetKeys: ["Ghost A", "ghost-a"], ids: ["unique-a", "fmo-a"]),
            .init(targetKeys: ["Ghost B", "ghost-b"], ids: ["unique-b", "fmo-b"])
        ])

        // ReceiverGhostName省略時はプライマリ（先頭）だけを照合する。
        #expect(SSTPOwnershipRegistry.shared.matches(id: "unique-a", receiverGhostName: nil))
        #expect(!SSTPOwnershipRegistry.shared.matches(id: "unique-b", receiverGhostName: nil))
        #expect(SSTPOwnershipRegistry.shared.matches(id: "fmo-b", receiverGhostName: "Ghost B"))
        #expect(!SSTPOwnershipRegistry.shared.matches(id: "unique-a", receiverGhostName: "ghost-b"))
        #expect(!SSTPOwnershipRegistry.shared.matches(id: "unknown", receiverGhostName: "Ghost A"))
    }

    @Test
    func validOwnedIDPromotesExternalRequestToLocalSecurity() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.matchHandler = { id, _ in id == "owned-a" }
        var receivedSecurityLevels: [String] = []
        bridge.liveGhostResolver = { _, _, _, headers in
            receivedSecurityLevels.append(headers["SecurityLevel"] ?? "")
            return .init(status: 204, headers: [:], value: nil)
        }

        let invalid = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "OnOwnedTest",
                "ID": "unknown",
                "SecurityLevel": "external",
                "Option": "nodescript"
            ]
        )
        _ = SSTPDispatcher.dispatch(request: invalid, bridge: bridge, routingRegistry: fake)

        let valid = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "OnOwnedTest",
                "ID": "owned-a",
                "SecurityLevel": "external",
                "Option": "nodescript"
            ]
        )
        _ = SSTPDispatcher.dispatch(request: valid, bridge: bridge, routingRegistry: fake)

        #expect(receivedSecurityLevels == ["external", "local"])
    }

    @Test
    func externalOriginCannotUseOwnedIDToEscalateSecurity() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.matchHandler = { id, _ in id == "owned-a" }
        var receivedSecurityLevels: [String] = []
        bridge.liveGhostResolver = { _, _, _, headers in
            receivedSecurityLevels.append(headers["SecurityLevel"] ?? "")
            return .init(status: 204, headers: [:], value: nil)
        }
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Event": "OnOwnedTest", "ID": "owned-a", "Option": "nodescript"]
        )

        _ = SSTPDispatcher.dispatchExternal(request: req, origin: nil, bridge: bridge, routingRegistry: fake)
        _ = SSTPDispatcher.dispatchExternal(request: req, origin: "https://example.com", bridge: bridge, routingRegistry: fake)

        #expect(receivedSecurityLevels == ["local", "external"])
    }

    @Test
    func sparseReferencesReachShioriWithoutCollapsingIndexes() async throws {
        var receivedReferences: [String] = []
        var receivedHeaders: [String: String] = [:]
        bridge.liveGhostResolver = { _, _, references, headers in
            receivedReferences = references
            receivedHeaders = headers
            return .init(status: 204, headers: [:], value: nil)
        }
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "OnSparseReferenceTest",
                "Reference2": "two",
                "Reference7": "",
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, bridge: bridge)

        #expect(receivedReferences.isEmpty)
        #expect(receivedHeaders["Reference2"] == "two")
        #expect(receivedHeaders["Reference7"] == "")
        #expect(receivedHeaders["Reference0"] == nil)
    }

    @Test
    func communicateSurfaceHeaderReachesShiori() async throws {
        var receivedHeaders: [String: String] = [:]
        bridge.liveGhostResolver = { _, _, _, headers in
            receivedHeaders = headers
            return .init(status: 204, headers: [:], value: nil)
        }
        let req = SSTPRequest(
            method: "COMMUNICATE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "OtherGhost",
                "Sentence": "hello",
                "Surface": "12",
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, bridge: bridge)

        #expect(receivedHeaders["Surface"] == "12")
    }

    @Test
    func notifyPreservesMethodAndStructuredShioriHeaders() async throws {
        var receivedMethod = ""
        bridge.liveGhostResolver = { method, _, _, _ in
            receivedMethod = method
            return .init(
                status: 200,
                headers: ["ValueNotify": "\\h\\s0Notify", "Reference3": "three"],
                value: nil
            )
        }
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Event": "OnNotifyHeadersTest", "Option": "nodescript"]
        )

        let response = SSTPDispatcher.dispatch(request: req, bridge: bridge)

        #expect(receivedMethod == "NOTIFY")
        #expect(response.contains("SSTP/1.4 200 OK"))
        #expect(response.contains("ValueNotify: \\h\\s0Notify"))
        #expect(response.contains("Reference3: three"))
    }

    @Test @MainActor
    func sstpResponseUsesTheSameSingleTranslationAsPlayback() throws {
        let runtime = SSTPTranslationRuntime()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sstp-translation"))
        manager.ghostConfig = GhostConfiguration(name: "Translation Ghost", shiori: "fixture.bundle")
        manager.shioriRuntime = runtime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            manager.shioriRuntime = nil
        }
        bridge.liveGhostResolver = { _, _, _, _ in
            .init(status: 200, headers: [:], value: "\\h\\s0source")
        }
        let request = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Event": "OnTranslationTest", "SecurityLevel": "local"]
        )

        let response = SSTPDispatcher.dispatch(request: request, bridge: bridge)

        #expect(response.contains("Script: \\h\\s0source-translated"))
        #expect(runtime.translateRequestCount == 1)
    }

    @Test @MainActor
    func sstpResponseUsesPrimaryGhostTranslationRegardlessOfRegistrationOrder() throws {
        let primaryRuntime = SSTPTranslationRuntime(suffix: "-primary")
        let secondaryRuntime = SSTPTranslationRuntime(suffix: "-secondary")
        let primary = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sstp-primary"))
        primary.ghostConfig = GhostConfiguration(name: "Primary Ghost", shiori: "fixture.bundle")
        primary.shioriRuntime = primaryRuntime
        let secondary = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sstp-secondary"))
        secondary.ghostConfig = GhostConfiguration(name: "Secondary Ghost", shiori: "fixture.bundle")
        secondary.shioriRuntime = secondaryRuntime

        let state: SSTPMultiGhostTestState = {
            let application = NSApplication.shared
            let previousDelegate = application.delegate
            let appDelegate = (previousDelegate as? AppDelegate) ?? AppDelegate()
            application.delegate = appDelegate
            let previousPrimary = appDelegate.ghostManager
            let previousAdditional = appDelegate.additionalGhosts
            appDelegate.ghostManager = primary
            appDelegate.additionalGhosts = [secondary]
            // 登録順を逆にし、応答順がsessions辞書の順序へ依存しないことを確認する。
            let secondaryToken = EventBridge.shared.register(runtime: secondaryRuntime, ghostManager: secondary)
            let primaryToken = EventBridge.shared.register(runtime: primaryRuntime, ghostManager: primary)
            return SSTPMultiGhostTestState(
                application: application,
                previousDelegate: previousDelegate,
                appDelegate: appDelegate,
                previousPrimary: previousPrimary,
                previousAdditional: previousAdditional,
                primaryToken: primaryToken,
                secondaryToken: secondaryToken
            )
        }()
        defer {
            EventBridge.shared.unregister(state.primaryToken)
            EventBridge.shared.unregister(state.secondaryToken)
            state.appDelegate.ghostManager = state.previousPrimary
            state.appDelegate.additionalGhosts = state.previousAdditional
            state.application.delegate = state.previousDelegate
            primary.shioriRuntime = nil
            secondary.shioriRuntime = nil
        }
        bridge.liveGhostResolver = { _, _, _, _ in
            .init(status: 200, headers: [:], value: "\\h\\s0source")
        }

        let response = SSTPDispatcher.dispatch(request: SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Event": "OnMultiGhostTranslationTest", "SecurityLevel": "local"]
        ), bridge: bridge)

        #expect(response.contains("Script: \\h\\s0source-primary"))
        #expect(!response.contains("source-secondary"))
        #expect(primaryRuntime.translateRequestCount == 1)
        #expect(secondaryRuntime.translateRequestCount == 1)
    }

    @Test
    func requestOptionsSupportMixedSeparators() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Option": "notify nodescript;notranslate,nobreak"]
        )
        #expect(req.options.contains(.notify))
        #expect(req.options.contains(.nodescript))
        #expect(req.options.contains(.notranslate))
        #expect(req.options.contains(.nobreak))
    }

    @Test
    func lowercaseHeadersAreHandledCaseInsensitively() async throws {
        let key = "lower-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0Lowercase")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "event": "Resource",
                "reference0": key,
                "charset": "UTF-8",
                "option": "nodescript"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        // 小文字ヘッダでも event/option が解釈される。nodescript はバルーン再生のみ
        // 抑止し、応答の Script ヘッダは維持される（UKADOC spec_sstp）
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0Lowercase"))
    }

    @Test
    func sendWithoutEventEchoesScriptHeaderWithoutShiori() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Script": "\\h\\s0DirectScript\\e"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        // Event 無し SEND は SHIORI を介さず Script ヘッダを直接扱う（503 にならない）
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0DirectScript\\e"))
    }

    @Test
    func sendResourceMapsToScript() async throws {
        let key = "test-key-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0FromResource")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Charset": "UTF-8"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromResource"))
    }

    @Test
    func notifyReturnsNoContent() async throws {
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Event": "OnNotifyTest", "Charset": "UTF-8"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 204 No Content"))
        #expect(!resp.contains("Script:"))
    }

    @Test
    func executeWithoutCommandReturnsBadRequest() async throws {
        let req = SSTPRequest(method: "EXECUTE", version: "SSTP/1.4", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 400 Bad Request"))
    }

    @Test
    func shioriWireResponseMapsStatusAndData() async throws {
        let key = "wire-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: "SHIORI/3.0 204 No Content\r\nData: sample-data\r\n\r\n"
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "X-SSTP-PassThru": "abc"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 204 No Content"))
        #expect(resp.contains("Data: sample-data"))
        #expect(resp.contains("X-SSTP-PassThru: abc"))
    }

    @Test
    func extendedShioriHeadersMapToSstpAndStatusProperty() async throws {
        let key = "headers-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0FromHeaders\r
            Status: choosing\r
            BaseID: OnChoiceSelect\r
            Marker: marker-1\r
            ErrorLevel: warning\r
            ErrorDescription: sample\r
            BalloonOffset: 12,34\r
            Reference0: ref-zero\r
            Reference1: ref-one\r
            Age: 3\r
            MarkerSend: marker-send\r
            X-SSTP-PassThru-Reply: token-reply\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Status": "talking",
                "X-SSTP-PassThru-Client": "token-client"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromHeaders"))
        #expect(resp.contains("Status: choosing"))
        #expect(resp.contains("BaseID: OnChoiceSelect"))
        #expect(resp.contains("Marker: marker-1"))
        #expect(resp.contains("ErrorLevel: warning"))
        #expect(resp.contains("ErrorDescription: sample"))
        #expect(resp.contains("BalloonOffset: 12,34"))
        #expect(resp.contains("Reference0: ref-zero"))
        #expect(resp.contains("Reference1: ref-one"))
        #expect(resp.contains("Age: 3"))
        #expect(resp.contains("MarkerSend: marker-send"))
        #expect(resp.contains("X-SSTP-PassThru-Client: token-client"))
        #expect(resp.contains("X-SSTP-PassThru-Reply: token-reply"))
    }

    @Test
    func notifyValueNotifyReturnsScript() async throws {
        let key = "notify-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            ValueNotify: \\h\\s0NotifyScript\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0NotifyScript"))
        #expect(resp.contains("ValueNotify: \\h\\s0NotifyScript"))
    }

    @Test
    func sendWithNotifyOptionBehavesAsNotify() async throws {
        let key = "opt-notify-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            ValueNotify: \\h\\s0NotifyViaOption\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "notify"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0NotifyViaOption"))
    }

    @Test
    func nodescriptAndNobreakOptionsAreHandled() async throws {
        let key = "opt-nodescript-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0BalloonSuppressed")
        let nodescriptReq = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )
        let nodescriptResp = SSTPDispatcher.dispatch(request: nodescriptReq, bridge: bridge)
        // nodescript はバルーン再生のみ抑止（応答 Script は維持: UKADOC spec_sstp）
        #expect(nodescriptResp.contains("SSTP/1.4 200 OK"))
        #expect(nodescriptResp.contains("Script: \\h\\s0BalloonSuppressed"))

        // nobreak は「現在実行中のスクリプトを中断せず、終わるまで待つ」オプション（UKADOC spec_sstp）。
        // busy でなければキューイング待機は発生せず、通常経路（200 OK）で処理される。
        let nobreakReq = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nobreak"
            ]
        )
        let nobreakResp = SSTPDispatcher.dispatch(request: nobreakReq, bridge: bridge)
        #expect(nobreakResp.contains("SSTP/1.4 200 OK"))
        #expect(nobreakResp.contains("Script: \\h\\s0BalloonSuppressed"))
    }

    @Test
    func duplicateOptionHeadersAreMerged() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: [
                ("Sender", "UnitTest"),
                ("Option", "nodescript"),
                ("Option", "nobreak")
            ]
        )
        #expect(req.options.contains(.nodescript))
        #expect(req.options.contains(.nobreak))
    }

    @Test
    func ifGhostOverridesScriptForMatchedReceiver() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Emily"]
        let key = "ifghost-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0Base")
        // UKADOC: IfGhost は直後の Script ヘッダと出現順で対応付けられる
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: [
                ("Sender", "UnitTest"),
                ("Event", "Resource"),
                ("Reference0", key),
                ("ReceiverGhostName", "Emily"),
                ("IfGhost", "Emily"),
                ("Script", "\\h\\s0FromIfGhost"),
                ("IfGhost", "Someone"),
                ("Script", "\\h\\s0ForSomeoneElse")
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("Script: \\h\\s0FromIfGhost"))
        #expect(!resp.contains("ForSomeoneElse"))
    }

    @Test
    func ifGhostUnmatchedUsesDefaultScriptBeforeFirstIfGhost() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Mary"]
        // Event 無し SEND: IfGhost 不一致時は最初の IfGhost より前の Script がデフォルト
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: [
                ("Sender", "UnitTest"),
                ("ReceiverGhostName", "Mary"),
                ("Script", "\\h\\s0DefaultScript"),
                ("IfGhost", "Emily"),
                ("Script", "\\h\\s0EmilyOnly")
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0DefaultScript"))
    }

    @Test
    func ifGhostDefaultGhostAliasActsAsDefaultScript() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Mary"]
        // 「さくら」「エミリ」「えみりぃ」はデフォルトゴースト扱いで、
        // その Script はデフォルトスクリプトとしても機能する（UKADOC spec_sstp）
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: [
                ("Sender", "UnitTest"),
                ("ReceiverGhostName", "Mary"),
                ("IfGhost", "エミリ"),
                ("Script", "\\h\\s0AliasDefault")
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0AliasDefault"))
    }

    @Test
    func ifGhostSakuraKeroPairDoesNotMatchWithoutKeroName() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Emily"]
        // UKADOC: 「\0側名,\1側名」書式は両方の名前が一致しなければ選択しない。
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: [
                ("Sender", "UnitTest"),
                ("ReceiverGhostName", "Emily"),
                ("IfGhost", "Emily,Teddy"),
                ("Script", "\\h\\s0PairMatched")
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(!resp.contains("PairMatched"))
    }

    @Test @MainActor
    func ifGhostSakuraKeroPairRequiresBothCharacterNames() throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Emily"]
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sstp-ifghost-pair"))
        manager.ghostConfig = GhostConfiguration(
            name: "Emily4",
            sakuraName: "Emily",
            keroName: "Teddy"
        )
        let token = EventBridge.shared.register(runtime: nil, ghostManager: manager)
        defer { EventBridge.shared.unregister(token) }

        let baseHeaders = [
            ("Sender", "UnitTest"),
            ("ReceiverGhostName", "Emily"),
            ("Script", "\\h\\s0DefaultScript")
        ]
        let mismatch = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: baseHeaders + [
                ("IfGhost", "Emily,NotTeddy"),
                ("Script", "\\h\\s0PairMustNotMatch")
            ]
        )
        let mismatchResponse = SSTPDispatcher.dispatch(request: mismatch, bridge: bridge, routingRegistry: fake)
        #expect(mismatchResponse.contains("Script: \\h\\s0DefaultScript"))
        #expect(!mismatchResponse.contains("PairMustNotMatch"))

        let match = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: baseHeaders + [
                ("IfGhost", "Emily,Teddy"),
                ("Script", "\\h\\s0PairMatches")
            ]
        )
        let matchResponse = SSTPDispatcher.dispatch(request: match, bridge: bridge, routingRegistry: fake)
        #expect(matchResponse.contains("Script: \\h\\s0PairMatches"))
        #expect(!matchResponse.contains("DefaultScript"))
    }

    @Test
    func receiverGhostNameRejectsUnknownRegisteredGhost() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Emily"]
        let key = "receiver-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0Base")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "ReceiverGhostName": "UnknownGhost"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 404 Not Found"))
    }

    @Test
    func securityOriginSetsExternalSecurityLevelForShiori() async throws {
        GhostRegistry.shared.clear()
        defer { GhostRegistry.shared.clear() }
        let key = "origin-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0OriginAware\r
            \r
            """
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "SecurityOrigin": "https://example.com"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0OriginAware"))
    }

    @Test
    func entryIsStoredAndReturned() async throws {
        let key = "entry-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0Entry")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Entry": "temporary=\\h\\s0Temp"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("Entry:"))
        #expect(resp.contains("temporary=\\h\\s0Temp"))
    }

    @Test
    func executeSetCookieAndGetCookie() async throws {
        let setReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Command": "SetCookie",
                "Reference0": "session",
                "Reference1": "abc123"
            ]
        )
        let setResp = SSTPDispatcher.dispatch(request: setReq, bridge: bridge)
        #expect(setResp.contains("SSTP/1.4 200 OK"))

        let getReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Command": "GetCookie",
                "Reference0": "session"
            ]
        )
        let getResp = SSTPDispatcher.dispatch(request: getReq, bridge: bridge)
        #expect(getResp.contains("SSTP/1.4 200 OK"))
        #expect(getResp.contains("Reference0: abc123"))
        #expect(getResp.contains("Data: abc123"))
    }

    @Test
    func executeGetVersionAndGetShortVersion() async throws {
        let getVersionReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetVersion"]
        )
        let getVersionResp = SSTPDispatcher.dispatch(request: getVersionReq, bridge: bridge)
        #expect(getVersionResp.contains("SSTP/1.4 200 OK"))
        #expect(getVersionResp.contains("Reference0:"))

        let getShortReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetShortVersion"]
        )
        let getShortResp = SSTPDispatcher.dispatch(request: getShortReq, bridge: bridge)
        #expect(getShortResp.contains("SSTP/1.4 200 OK"))
        #expect(getShortResp.contains("Reference0:"))
    }

    @Test
    func executeGetFmoReturnsDetailedLocalPayload() async throws {
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetFMO",
                "SecurityLevel": "local"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        // FMO now uses SSP-style record format, not the old key=value; format
        #expect(!resp.contains("baseware.name="))
    }

    @Test
    func executeGetFmoRefusesExternalAccess() async throws {
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetFMO",
                "SecurityLevel": "external"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 420 Refuse"))
    }

    @Test
    func executeSetAndGetProperty() async throws {
        let setReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "SetProperty",
                "Reference0": "currentghost.mousecursor.text",
                "Reference1": "arrow"
            ]
        )
        let setResp = SSTPDispatcher.dispatch(request: setReq, bridge: bridge)
        #expect(setResp.contains("SSTP/1.4 200 OK"))

        let getReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetProperty",
                "Reference0": "currentghost.mousecursor.text"
            ]
        )
        let getResp = SSTPDispatcher.dispatch(request: getReq, bridge: bridge)
        #expect(getResp.contains("SSTP/1.4 200 OK"))
        #expect(getResp.contains("Reference0: arrow"))
    }

    @Test
    func communicateRoutesToShioriWithSenderAsReference0() async throws {
        let key = "comm-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0FromCommunicate")
        // UKADOC OnCommunicate: Reference0=送信元ゴースト名(Sender), Reference1=発言内容(Sentence),
        // Reference2+ = SSTP の ReferenceN。テスト用 Resource イベントは references.first を
        // キーに引くため、Sender に key を入れることで Reference0 へのシフトを検証する。
        let req = SSTPRequest(
            method: "COMMUNICATE",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Sender": key,
                "Sentence": "おはよう"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromCommunicate"))
    }

    @Test
    func giveRoutesToShiori() async throws {
        let key = "give-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0FromGive")
        let req = SSTPRequest(
            method: "GIVE",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromGive"))
    }

    @Test
    func installRoutesToShiori() async throws {
        let key = "install-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0FromInstall")
        let req = SSTPRequest(
            method: "INSTALL",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromInstall"))
    }

    @Test
    func unsupportedMethodReturns501() async throws {
        let req = SSTPRequest(method: "PUSH", version: "SSTP/1.4", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 501 Not Implemented"))
    }

    @Test
    func unsupportedVersionReturns505() async throws {
        let req = SSTPRequest(method: "SEND", version: "SSTP/2.0", headers: [
                "Sender": "UnitTest"])
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/2.0 505 HTTP Version Not Supported"))
    }

    @Test
    func oversizedPayloadReturns413() async throws {
        let body = Data(repeating: 0x41, count: 1024 * 1024 + 1)
        let req = SSTPRequest(method: "SEND", version: "SSTP/1.4", headers: [
                "Sender": "UnitTest"], body: body)
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 413 Payload Too Large"))
    }

    @Test
    func nobreakReturns409WhenPolicyTimesOut() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Option": "nobreak"]
        )
        let fakePolicy = FakeSstpBreakPolicy(busy: true, shouldSucceed: false)
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, breakPolicy: fakePolicy)
        #expect(resp.contains("SSTP/1.4 409 Conflict"))
    }

    @Test @MainActor
    func nobreakBreakEventsPreserveScriptScopeAndPositionReferences() {
        EventBridge.shared.stop()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sstp-break-event-test"))
        let runtime = SSTPEventCapturingRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
            _ = manager.shutdown()
        }

        let script = #"\0hello\e"#
        let request = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Script": script,
                "Scope": "1",
                "BreakPosition": "0",
                "Option": "nobreak"
            ]
        )
        let response = SSTPDispatcher.dispatch(
            request: request,
            bridge: bridge,
            breakPolicy: FakeSstpBreakPolicy(busy: true, shouldSucceed: false)
        )

        #expect(response.contains("SSTP/1.4 409 Conflict"))
        let events = runtime.requests.filter { $0.id == EventID.OnSSTPBreak.rawValue }
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.method == "NOTIFY" })
        #expect(events.map(\.refs) == [[script, "1", "0"], [script, "1", "0"]])
    }

    @Test
    func nobreakProceedsWhenPolicySucceeds() async throws {
        let key = "opt-nobreak-policy-\(UUID().uuidString)"
        bridge.setResource(key, value: "\\h\\s0QueuedAfterBusy")
        let fakePolicy = FakeSstpBreakPolicy(busy: true, shouldSucceed: true)
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nobreak"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, breakPolicy: fakePolicy)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0QueuedAfterBusy"))
    }

    @Test
    func nobreakDoesNotWaitWhenPolicyIsNotBusy() async throws {
        let fakePolicy = FakeSstpBreakPolicy(busy: false, shouldSucceed: false)
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Option": "nobreak"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, breakPolicy: fakePolicy)
        #expect(resp.contains("SSTP/1.4 200 OK"))
    }

    @Test
    func notifyNobreakUsesInjectedPolicy() async throws {
        let fakePolicy = FakeSstpBreakPolicy(busy: true, shouldSucceed: false)
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Option": "nobreak"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, breakPolicy: fakePolicy)
        #expect(resp.contains("SSTP/1.4 409 Conflict"))
    }

    @Test
    func liveBreakPolicyReturnsImmediatelyWhenNotBusy() async throws {
        ShioriStatusStore.shared.update(status: "talking")
        let policy = LiveSstpBreakPolicy(timeout: 0.1, pollInterval: 0.01)
        #expect(!policy.isBusy())
        #expect(policy.waitWhileBusy())
    }

    @Test
    func liveBreakPolicyTimesOutWhenStaysBusy() async throws {
        ShioriStatusStore.shared.update(status: "busy")
        defer { ShioriStatusStore.shared.update(status: "talking") }
        let policy = LiveSstpBreakPolicy(timeout: 0.05, pollInterval: 0.01)
        #expect(policy.isBusy())
        #expect(!policy.waitWhileBusy())
    }

    @Test @MainActor
    func liveBreakPolicyTreatsPlayingGhostAsBusyAndIdleAsFree() throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-live-ghost-busy"))
        manager.shioriRuntime = nil
        ShioriStatusStore.shared.update(status: "talking")
        let token = EventBridge.shared.register(runtime: nil, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            manager.isPlaying = false
        }
        let policy = LiveSstpBreakPolicy(timeout: 0.05, pollInterval: 0.01)

        manager.isPlaying = true
        #expect(policy.isBusy())

        manager.isPlaying = false
        #expect(!policy.isBusy())
    }

    @Test @MainActor
    func nobreakWaitsForPlayingGhostAndThenProceeds() async throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-nobreak-playing-ghost"))
        manager.shioriRuntime = nil
        ShioriStatusStore.shared.update(status: "talking")
        let token = EventBridge.shared.register(runtime: nil, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            manager.isPlaying = false
        }
        manager.isPlaying = true

        // Event 無し SEND は SHIORI ブリッジ（テスト時スレッドローカルな Resource マップ）を
        // 介さず、Script ヘッダを直接バルーン再生する。バックグラウンド実行でも確実に解決でき、
        // 待機成功後の応答検証に使える。
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Script": "\\h\\s0ResumedAfterPlayback",
                "Option": "nobreak"
            ]
        )

        // waitWhileBusy は同期ポーリングのため、バックグラウンドでディスパッチして
        // メインスレッド上で再生完了（isPlaying = false）をシミュレートできるようにする。
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let resp = SSTPDispatcher.dispatch(
                    request: req,
                    bridge: bridge,
                    breakPolicy: LiveSstpBreakPolicy(timeout: 3.0, pollInterval: 0.01)
                )
                DispatchQueue.main.async { continuation.resume(returning: resp) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                manager.isPlaying = false
            }
        }

        #expect(response.contains("SSTP/1.4 200 OK"))
        #expect(response.contains("Script: \\h\\s0ResumedAfterPlayback"))
    }

    @Test @MainActor
    func nobreakWithPlayingGhostTimesOutAndReturns409() throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-nobreak-timeout-ghost"))
        manager.shioriRuntime = nil
        ShioriStatusStore.shared.update(status: "talking")
        let token = EventBridge.shared.register(runtime: nil, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            manager.isPlaying = false
        }
        manager.isPlaying = true

        let request = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Option": "nobreak"]
        )
        let response = SSTPDispatcher.dispatch(
            request: request,
            bridge: bridge,
            breakPolicy: LiveSstpBreakPolicy(timeout: 0.05, pollInterval: 0.01)
        )
        #expect(response.contains("SSTP/1.4 409 Conflict"))
    }

    @Test
    func receiverGhostNameReturns512WhenNoRegistryEntries() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = []
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","ReceiverGhostName": "Emily"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 512 Invisible"))
    }

    @Test
    func sendReturns503WhenShioriUnavailable() async throws {
        // bridge は fresh（何も登録されていない）ため、Resource 解決に失敗し 503 になる。
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","Event": "Resource", "Reference0": "missing-resource-key"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 503 Service Unavailable"))
    }

    @Test
    func externalSecurityCanBeRefusedByPolicy420() async throws {
        setenv("OURIN_SSTP_LOCAL_ONLY", "1", 1)
        defer { unsetenv("OURIN_SSTP_LOCAL_ONLY") }
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest","SecurityLevel": "external"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge)
        #expect(resp.contains("SSTP/1.4 420 Refuse"))
    }

    @Test
    func executeGetNamesReturnsAllGhostNamesFromRegistry() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Emily", "Sakura"]
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetNames"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Reference0: Emily,Sakura"))
    }

    @Test
    func executeGetNameListCommaSeparated() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Sakura", "Emily", "Mary"]
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetNameList"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Reference0: Emily,Mary,Sakura"))
    }

    @Test
    func executeGetGhostNameListReturnsAllGhostNames() async throws {
        let fake = FakeSstpRoutingRegistry()
        fake.ghostNames = ["Ghost1", "Ghost2"]
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetGhostNameList"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Reference0: Ghost1,Ghost2"))
    }

    /// マルチゴースト SSTP ルーティングの照合キー生成（`AppDelegate.receiverTargetKey`）。
    /// SSTP 応答ヘッダ副作用（Surface/Balloon/Icon 等）の宛先解決に使われる。
    @Test
    func receiverGhostNameTargetKeyResolution() async throws {
        // 未指定・空白のみ → nil（プライマリゴーストへフォールバック）
        #expect(AppDelegate.receiverTargetKey(headers: [:]) == nil)
        #expect(AppDelegate.receiverTargetKey(headers: ["ReceiverGhostName": "   "]) == nil)
        // 名前一致（小文字化して照合）
        #expect(AppDelegate.receiverTargetKey(headers: ["ReceiverGhostName": "Emily/Phase4.5"]) == "emily/phase4.5")
        // フォルダ名照合にも同じキーを使う（大小文字の揺れ吸収）
        #expect(AppDelegate.receiverTargetKey(headers: ["ReceiverGhostName": "EMILY4"]) == "emily4")
        // percent エンコードされた日本語名のデコード
        #expect(AppDelegate.receiverTargetKey(headers: ["ReceiverGhostName": "%E3%81%95%E3%81%8F%E3%82%89"]) == "さくら")
        // 前後空白はトリムされる
        #expect(AppDelegate.receiverTargetKey(headers: ["ReceiverGhostName": " emily4 "]) == "emily4")
    }

    // MARK: - Cookie ディスク永続化 (#120)

    @Test
    func cookiePersistsAndRestoresAcrossStoreInstances() throws {
        let store = SstpSessionStore.shared
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sstp-cookie-test-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("sstp_cookie.txt")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 元の状態を退避して復元する
        let savedURL = store.cookieFileURL
        defer {
            store.cookieFileURL = savedURL
            store.reset()
            try? FileManager.default.removeItem(at: tempDir)
        }

        store.reset()
        store.cookieFileURL = fileURL
        store.setCookie(sender: "GhostA", name: "counter", value: "42")
        store.setCookie(sender: "GhostA", name: "topic", value: "海,空") // カンマ入り
        store.setCookie(sender: "GhostB", name: "bgm", value: "on")
        store.saveToDisk()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // 別インスタンス相当として復元を検証
        store.reset()
        store.loadFromDisk()
        #expect(store.getCookie(sender: "GhostA", name: "counter") == "42")
        #expect(store.getCookie(sender: "GhostA", name: "topic") == "海,空")
        #expect(store.getCookie(sender: "GhostB", name: "bgm") == "on")
        #expect(store.getCookie(sender: "GhostC", name: "counter") == nil)
    }

    @Test
    func emptyCookiesDoNotLeaveResidualFile() throws {
        let store = SstpSessionStore.shared
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sstp-cookie-empty-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("sstp_cookie.txt")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let savedURL = store.cookieFileURL
        defer {
            store.cookieFileURL = savedURL
            store.reset()
            try? FileManager.default.removeItem(at: tempDir)
        }

        store.reset()
        store.cookieFileURL = fileURL
        store.setCookie(sender: "GhostA", name: "k", value: "v")
        store.saveToDisk()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        store.reset()
        store.saveToDisk()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test
    func fineRejectsMissingSubcommand() async throws {
        let fake = FakeSstpRoutingRegistry()
        let req = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: ["Sender": "UnitTest"]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 400"))
    }

    @Test
    func fineRejectsUnknownSubcommand() async throws {
        let fake = FakeSstpRoutingRegistry()
        let req = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Reference0": "NoSuchSubcommand"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        // SSP はサブコマンド不一致で 0x1f5 = 501。
        #expect(resp.contains("SSTP/1.4 501"))
    }

    @Test
    func fineMessageSendReturns420WhenNoGhostResolves() async throws {
        let fake = FakeSstpRoutingRegistry()
        let req = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Reference0": "MessageSend",
                "Reference1": "MissingGhost",
                "Reference4": "\\h\\s0Hello"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        // 対象ゴースト不在で SSP は 0x1a4 = 420 Refuse。
        #expect(resp.contains("SSTP/1.4 420"))
    }

    @Test
    func fineMessageSendRejectsMissingReference4() async throws {
        let fake = FakeSstpRoutingRegistry()
        let req = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Reference0": "MessageSend",
                "Reference1": "Emily"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 400"))
    }

    @Test @MainActor
    func fineMessageSendResolvesGhostByNameAndReturns200() throws {
        let fake = FakeSstpRoutingRegistry()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sstp-fine-message"))
        manager.ghostConfig = GhostConfiguration(
            name: "FineTarget",
            sakuraName: "FineSakura",
            keroName: "FineKero"
        )
        let token = EventBridge.shared.register(runtime: nil, ghostManager: manager)
        defer { EventBridge.shared.unregister(token) }

        let req = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Reference0": "MessageSend",
                "Reference1": "FineTarget",
                "Reference4": "\\h\\s0Hello"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
    }

    @Test @MainActor
    func fineMessageSendFallsBackToSakuraNameResolution() throws {
        let fake = FakeSstpRoutingRegistry()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sstp-fine-sakura"))
        manager.ghostConfig = GhostConfiguration(
            name: "FineTarget2",
            sakuraName: "FineSakura2",
            keroName: "FineKero2"
        )
        let token = EventBridge.shared.register(runtime: nil, ghostManager: manager)
        defer { EventBridge.shared.unregister(token) }

        // Reference1 が無い場合、SSP は Reference2（さくら名）で解決する。
        let req = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Reference0": "MessageSend",
                "Reference2": "FineSakura2",
                "Reference3": "FineKero2",
                "Reference4": "\\h\\s0Hello"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200 OK"))
    }

    @Test @MainActor
    func fineSetScriptReturns200() throws {
        let fake = FakeSstpRoutingRegistry()
        let req = SSTPRequest(
            method: "FINE",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Reference0": "SetScript",
                "Reference1": "\\h\\s0Initial"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req, bridge: bridge, routingRegistry: fake)
        #expect(resp.contains("SSTP/1.4 200"))
    }
}
