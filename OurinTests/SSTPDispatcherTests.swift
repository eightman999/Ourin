import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct SSTPDispatcherTests {
    init() {
        BridgeToSHIORI.reset()
        GhostRegistry.shared.clear()
        SstpSessionStore.shared.reset()
        ShioriStatusStore.shared.reset(to: "online")
        unsetenv("OURIN_SSTP_LOCAL_ONLY")
    }

    @Test
    func requestOptionsSupportMixedSeparators() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["Option": "notify nodescript;notranslate,nobreak"]
        )
        #expect(req.options.contains(.notify))
        #expect(req.options.contains(.nodescript))
        #expect(req.options.contains(.notranslate))
        #expect(req.options.contains(.nobreak))
    }

    @Test
    func lowercaseHeadersAreHandledCaseInsensitively() async throws {
        let key = "lower-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Lowercase")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "event": "Resource",
                "reference0": key,
                "charset": "UTF-8",
                "option": "nodescript"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
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
        let resp = SSTPDispatcher.dispatch(request: req)
        // Event 無し SEND は SHIORI を介さず Script ヘッダを直接扱う（503 にならない）
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0DirectScript\\e"))
    }

    @Test
    func sendResourceMapsToScript() async throws {
        let key = "test-key-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromResource")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Charset": "UTF-8"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromResource"))
    }

    @Test
    func notifyReturnsNoContent() async throws {
        let req = SSTPRequest(
            method: "NOTIFY",
            version: "SSTP/1.4",
            headers: ["Event": "OnNotifyTest", "Charset": "UTF-8"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 204 No Content"))
        #expect(!resp.contains("Script:"))
    }

    @Test
    func executeWithoutCommandReturnsBadRequest() async throws {
        let req = SSTPRequest(method: "EXECUTE", version: "SSTP/1.4", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 400 Bad Request"))
    }

    @Test
    func shioriWireResponseMapsStatusAndData() async throws {
        let key = "wire-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
            key,
            value: "SHIORI/3.0 204 No Content\r\nData: sample-data\r\n\r\n"
        )
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "X-SSTP-PassThru": "abc"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 204 No Content"))
        #expect(resp.contains("Data: sample-data"))
        #expect(resp.contains("X-SSTP-PassThru: abc"))
    }

    @Test
    func extendedShioriHeadersMapToSstpAndStatusProperty() async throws {
        let key = "headers-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
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
                "Event": "Resource",
                "Reference0": key,
                "Status": "talking",
                "X-SSTP-PassThru-Client": "token-client"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromHeaders"))
        #expect(resp.contains("Status: choosing"))
        #expect(resp.contains("BaseID: OnChoiceSelect"))
        #expect(resp.contains("Marker: marker-1"))
        #expect(resp.contains("ErrorLevel: warning"))
        #expect(resp.contains("ErrorDescription: sample"))
        #expect(resp.contains("BalloonOffset: 12,34"))
        #expect(resp.contains("Reference0: ref-zero"))
        #expect(resp.contains("Age: 3"))
        #expect(resp.contains("MarkerSend: marker-send"))
        #expect(resp.contains("X-SSTP-PassThru-Client: token-client"))
        #expect(resp.contains("X-SSTP-PassThru-Reply: token-reply"))
    }

    @Test
    func notifyValueNotifyReturnsScript() async throws {
        let key = "notify-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
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
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0NotifyScript"))
        #expect(resp.contains("ValueNotify: \\h\\s0NotifyScript"))
    }

    @Test
    func sendWithNotifyOptionBehavesAsNotify() async throws {
        let key = "opt-notify-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
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
                "Event": "Resource",
                "Reference0": key,
                "Option": "notify"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0NotifyViaOption"))
    }

    @Test
    func nodescriptAndNobreakOptionsAreHandled() async throws {
        let key = "opt-nodescript-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0BalloonSuppressed")
        let nodescriptReq = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )
        let nodescriptResp = SSTPDispatcher.dispatch(request: nodescriptReq)
        // nodescript はバルーン再生のみ抑止（応答 Script は維持: UKADOC spec_sstp）
        #expect(nodescriptResp.contains("SSTP/1.4 200 OK"))
        #expect(nodescriptResp.contains("Script: \\h\\s0BalloonSuppressed"))

        // nobreak は「現在実行中のスクリプトを中断せず、終わるまで待つ」オプション（UKADOC spec_sstp）。
        // busy でなければキューイング待機は発生せず、通常経路（200 OK）で処理される。
        let nobreakReq = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Option": "nobreak"
            ]
        )
        let nobreakResp = SSTPDispatcher.dispatch(request: nobreakReq)
        #expect(nobreakResp.contains("SSTP/1.4 200 OK"))
        #expect(nobreakResp.contains("Script: \\h\\s0BalloonSuppressed"))
    }

    @Test
    func duplicateOptionHeadersAreMerged() async throws {
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: [
                ("Option", "nodescript"),
                ("Option", "nobreak")
            ]
        )
        #expect(req.options.contains(.nodescript))
        #expect(req.options.contains(.nobreak))
    }

    @Test
    func ifGhostOverridesScriptForMatchedReceiver() async throws {
        GhostRegistry.shared.clear()
        GhostRegistry.shared.register(name: "Emily", path: "/tmp/emily")
        defer { GhostRegistry.shared.clear() }
        let key = "ifghost-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Base")
        // UKADOC: IfGhost は直後の Script ヘッダと出現順で対応付けられる
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headerEntries: [
                ("Event", "Resource"),
                ("Reference0", key),
                ("ReceiverGhostName", "Emily"),
                ("IfGhost", "Emily"),
                ("Script", "\\h\\s0FromIfGhost"),
                ("IfGhost", "Someone"),
                ("Script", "\\h\\s0ForSomeoneElse")
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("Script: \\h\\s0FromIfGhost"))
        #expect(!resp.contains("ForSomeoneElse"))
    }

    @Test
    func ifGhostUnmatchedUsesDefaultScriptBeforeFirstIfGhost() async throws {
        GhostRegistry.shared.clear()
        GhostRegistry.shared.register(name: "Mary", path: "/tmp/mary")
        defer { GhostRegistry.shared.clear() }
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
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0DefaultScript"))
    }

    @Test
    func ifGhostDefaultGhostAliasActsAsDefaultScript() async throws {
        GhostRegistry.shared.clear()
        GhostRegistry.shared.register(name: "Mary", path: "/tmp/mary")
        defer { GhostRegistry.shared.clear() }
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
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0AliasDefault"))
    }

    @Test
    func ifGhostSakuraKeroPairMatchesBySakuraName() async throws {
        GhostRegistry.shared.clear()
        GhostRegistry.shared.register(name: "Emily", path: "/tmp/emily")
        defer { GhostRegistry.shared.clear() }
        // 「\0側名,\1側名」書式は \0 側名で照合する
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
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0PairMatched"))
    }

    @Test
    func receiverGhostNameRejectsUnknownRegisteredGhost() async throws {
        GhostRegistry.shared.clear()
        GhostRegistry.shared.register(name: "Emily", path: "/tmp/emily")
        defer { GhostRegistry.shared.clear() }
        let key = "receiver-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Base")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "ReceiverGhostName": "UnknownGhost"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 404 Not Found"))
    }

    @Test
    func securityOriginSetsExternalSecurityLevelForShiori() async throws {
        GhostRegistry.shared.clear()
        defer { GhostRegistry.shared.clear() }
        let key = "origin-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(
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
                "Event": "Resource",
                "Reference0": key,
                "SecurityOrigin": "https://example.com"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0OriginAware"))
    }

    @Test
    func entryIsStoredAndReturned() async throws {
        let key = "entry-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0Entry")
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Entry": "temporary=\\h\\s0Temp"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
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
        let setResp = SSTPDispatcher.dispatch(request: setReq)
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
        let getResp = SSTPDispatcher.dispatch(request: getReq)
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
        let getVersionResp = SSTPDispatcher.dispatch(request: getVersionReq)
        #expect(getVersionResp.contains("SSTP/1.4 200 OK"))
        #expect(getVersionResp.contains("Reference0:"))

        let getShortReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: ["Command": "GetShortVersion"]
        )
        let getShortResp = SSTPDispatcher.dispatch(request: getShortReq)
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
        let resp = SSTPDispatcher.dispatch(request: req)
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
        let resp = SSTPDispatcher.dispatch(request: req)
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
        let setResp = SSTPDispatcher.dispatch(request: setReq)
        #expect(setResp.contains("SSTP/1.4 200 OK"))

        let getReq = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetProperty",
                "Reference0": "currentghost.mousecursor.text"
            ]
        )
        let getResp = SSTPDispatcher.dispatch(request: getReq)
        #expect(getResp.contains("SSTP/1.4 200 OK"))
        #expect(getResp.contains("Reference0: arrow"))
    }

    @Test
    func communicateRoutesToShioriWithSenderAsReference0() async throws {
        let key = "comm-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromCommunicate")
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
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromCommunicate"))
    }

    @Test
    func giveRoutesToShiori() async throws {
        let key = "give-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromGive")
        let req = SSTPRequest(
            method: "GIVE",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromGive"))
    }

    @Test
    func installRoutesToShiori() async throws {
        let key = "install-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0FromInstall")
        let req = SSTPRequest(
            method: "INSTALL",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0FromInstall"))
    }

    @Test
    func unsupportedMethodReturns501() async throws {
        let req = SSTPRequest(method: "PUSH", version: "SSTP/1.4", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 501 Not Implemented"))
    }

    @Test
    func unsupportedVersionReturns505() async throws {
        let req = SSTPRequest(method: "SEND", version: "SSTP/2.0", headers: [:])
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/2.0 505 HTTP Version Not Supported"))
    }

    @Test
    func oversizedPayloadReturns413() async throws {
        let body = Data(repeating: 0x41, count: 1024 * 1024 + 1)
        let req = SSTPRequest(method: "SEND", version: "SSTP/1.4", headers: [:], body: body)
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 413 Payload Too Large"))
    }

    @Test
    func nobreakReturns409WhenShioriStatusStaysBusyUntilTimeout() async throws {
        // busy が待機タイムアウトまで解消しない場合は、キューイングを諦めて 409 を返す。
        let originalTimeout = SSTPBreakQueue.defaultTimeout
        SSTPBreakQueue.defaultTimeout = 0.1
        defer {
            SSTPBreakQueue.defaultTimeout = originalTimeout
            ShioriStatusStore.shared.update(status: "talking")
        }
        ShioriStatusStore.shared.update(status: "busy")
        // ShioriStatusStore.shared はプロセス共有のため、並列実行中の他テストが
        // status を上書きすると busy が解消されて 200 になってしまう。
        // 待機ウィンドウの間 busy を再アサートし続けて競合に耐える。
        let keepBusy = Task {
            while !Task.isCancelled {
                ShioriStatusStore.shared.update(status: "busy")
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
        defer { keepBusy.cancel() }
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["Option": "nobreak"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 409 Conflict"))
    }

    @Test
    func nobreakQueuesAndProceedsOnceBusyClears() async throws {
        // UKADOC spec_sstp: nobreak は実行中のスクリプトを中断せず、終わるまで待ってから実行する。
        // busy が待機中に解消されれば、通常のディスパッチ経路（200 OK）まで進む。
        let key = "opt-nobreak-queue-\(UUID().uuidString)"
        BridgeToSHIORI.setResource(key, value: "\\h\\s0QueuedAfterBusy")
        let originalTimeout = SSTPBreakQueue.defaultTimeout
        SSTPBreakQueue.defaultTimeout = 2.0
        defer {
            SSTPBreakQueue.defaultTimeout = originalTimeout
            ShioriStatusStore.shared.update(status: "talking")
        }
        ShioriStatusStore.shared.update(status: "busy")

        let clearBusyAfterDelay = DispatchWorkItem {
            ShioriStatusStore.shared.update(status: "talking")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: clearBusyAfterDelay)

        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Event": "Resource",
                "Reference0": key,
                "Option": "nobreak"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0QueuedAfterBusy"))
    }

    @Test
    func receiverGhostNameReturns512WhenNoRegistryEntries() async throws {
        GhostRegistry.shared.clear()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["ReceiverGhostName": "Emily"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 512 Invisible"))
    }

    @Test
    func sendReturns503WhenShioriUnavailable() async throws {
        BridgeToSHIORI.reset()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["Event": "Resource", "Reference0": "missing-resource-key"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 503 Service Unavailable"))
    }

    @Test
    func externalSecurityCanBeRefusedByPolicy420() async throws {
        setenv("OURIN_SSTP_LOCAL_ONLY", "1", 1)
        defer { unsetenv("OURIN_SSTP_LOCAL_ONLY") }
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: ["SecurityLevel": "external"]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 420 Refuse"))
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
}
