import Foundation
import Testing
@testable import Ourin

/// テスト用の SstpDispatcherHost 実装。
/// AppDelegate / GhostManager 無しに、emit された効果（生成・順序・値）と GetFMO 用レコードを検証する。
/// dispatch → host.apply は同期的に呼ばれるため、記録はシングルスレッドで行われる。
final class SpySstpDispatcherHost: SstpDispatcherHost, @unchecked Sendable {
    private(set) var effects: [SstpUIEffect] = []
    /// GetFMO で返すレコード。テスト側で差し替える。
    var fmoRecords: [FmoGhostRecord] = []

    func apply(_ effect: SstpUIEffect) {
        effects.append(effect)
    }

    func collectFmoRecords() -> [FmoGhostRecord] {
        fmoRecords
    }

    func collectCollisionList(params: [String]) -> String {
        _ = params
        return "head,body"
    }
}

/// 共有シングルトンを扱う既存の直列化スイートへ所属させる。
/// 別スイートにすると `.serialized` 同士でもスイート間は並列実行され、
/// BridgeToSHIORI などの状態を互いに reset する競合が発生するため。
extension SSTPDispatcherTests {

    // MARK: - SHIORI 応答ヘッダ由来の効果

    @Test
    func surfaceHeaderEmitsUpdateSurfaceEffect() async throws {
        let key = "surface-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0SurfaceEffect\r
            Surface: 5\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(spy.effects.contains { $0.kind == .updateSurface(id: 5) })
    }

    @Test
    func invalidSurfaceEmitsNoSurfaceEffect() async throws {
        let key = "surface-bad-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0NoSurface\r
            Surface: not-a-number\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        // 不正な Surface（数値変換不可）は効果を emit しない
        #expect(!spy.effects.contains { effect in
            if case .updateSurface = effect.kind { return true }
            return false
        })
    }

    @Test
    func balloonHeaderEmitsSwitchBalloonEffect() async throws {
        let key = "balloon-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0BalloonEffect\r
            Balloon: custom-balloon\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(spy.effects.contains { $0.kind == .switchBalloon(name: "custom-balloon") })
    }

    @Test
    func balloonOffsetHeaderEmitsBalloonOffsetEffect() async throws {
        let key = "offset-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0OffsetEffect\r
            BalloonOffset: 12,34\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(spy.effects.contains { $0.kind == .balloonOffset(x: "12", y: "34", isRelative: false) })
    }

    @Test
    func malformedBalloonOffsetEmitsNoOffsetEffect() async throws {
        let key = "offset-bad-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0NoOffset\r
            BalloonOffset: 12\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        // "x" だけ（y 無し）は効果を emit しない
        #expect(!spy.effects.contains { effect in
            if case .balloonOffset = effect.kind { return true }
            return false
        })
    }

    @Test
    func iconHeaderEmitsSetTaskTrayIconEffect() async throws {
        let key = "icon-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0IconEffect\r
            Icon: mark.png,tooltip-text\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(spy.effects.contains { $0.kind == .setTaskTrayIcon(filename: "mark.png", text: "tooltip-text") })
    }

    @Test
    func effectsCarryReceiverGhostNameHeader() async throws {
        // ReceiverGhostName で宛先ゴーストを指定する場合、効果の requestHeaders へ保持される
        GhostRegistry.shared.register(name: "Emily", path: "/tmp/emily")
        let key = "receiver-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0ReceiverEffect\r
            Surface: 7\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "ReceiverGhostName": "Emily",
                "Option": "nodescript"
            ]
        )

        _ = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        let surfaceEffect = spy.effects.first { effect in
            if case .updateSurface = effect.kind { return true }
            return false
        }
        #expect(surfaceEffect != nil)
        // 宛先解決用ヘッダが効果に保持されている
        #expect(surfaceEffect?.requestHeaders["ReceiverGhostName"] == "Emily")
    }

    @Test
    func nodescriptPreservesScriptHeaderInResponse() async throws {
        // nodescript はバルーン再生のみ抑止し、応答の Script ヘッダは維持される（既存挙動の回帰）
        let key = "nodescript-effect-\(UUID().uuidString)"
        bridge.setResource(
            key,
            value: """
            SHIORI/3.0 200 OK\r
            Value: \\h\\s0NodescriptKept\r
            Surface: 3\r
            \r
            """
        )
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "SEND",
            version: "SSTP/1.4",
            headers: [
                "Sender": "UnitTest",
                "Event": "Resource",
                "Reference0": key,
                "Option": "nodescript"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(resp.contains("Script: \\h\\s0NodescriptKept"))
        // 効果自体は nodescript に関わらず emit される
        #expect(spy.effects.contains { $0.kind == .updateSurface(id: 3) })
    }

    // MARK: - 拡張 EXECUTE の UI 効果

    @Test
    func executeDumpSurfaceEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "dumpsurface",
                "Reference0": "0",
                "Reference1": "10"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(spy.effects.contains { $0.kind == .dumpSurface(params: ["0", "10"]) })
    }

    @Test
    func executeMoveAsyncEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "moveasync",
                "Reference0": "0",
                "Reference1": "120",
                "Reference2": "160",
                "Reference3": "250",
                "Reference4": "ease",
                "Reference5": "1"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(spy.effects.contains {
            $0.kind == .moveWindowAsync(scope: 0, x: 120, y: 160, time: 250, method: "ease", ignoreSticky: true)
        })
    }

    @Test
    func executeMoveAsyncInvalidArgsReturn400AndEmitNoEffect() async throws {
        let spy = SpySstpDispatcherHost()
        // time（Reference3）が非数値 → badRequest
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "moveasync",
                "Reference0": "0",
                "Reference1": "120",
                "Reference2": "160",
                "Reference3": "not-a-number",
                "Reference4": "ease"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 400 Bad Request"))
        #expect(!spy.effects.contains { effect in
            if case .moveWindowAsync = effect.kind { return true }
            return false
        })
    }

    @Test
    func executeSetTrayIconEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "settrayicon",
                "Reference0": "icon.png",
                "Reference1": "hover text"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(spy.effects.contains { $0.kind == .setTaskTrayIcon(filename: "icon.png", text: "hover text") })
    }

    @Test
    func executeSetTaskTrayIconAliasEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "settasktrayicon",
                "Reference0": "alias.png"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(spy.effects.contains { $0.kind == .setTaskTrayIcon(filename: "alias.png", text: "") })
    }

    @Test
    func executeSetTrayBalloonEmitsEffect() async throws {
        let spy = SpySstpDispatcherHost()
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "settrayballoon",
                "Reference0": "title=Hello",
                "Reference1": "message=World"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(spy.effects.contains { $0.kind == .setTrayBalloon(options: ["title=Hello", "message=World"]) })
    }

    // MARK: - GetFMO の host 委譲

    @Test
    func getFmoUsesHostProvidedRecords() async throws {
        let spy = SpySstpDispatcherHost()
        spy.fmoRecords = [
            FmoGhostRecord(name: "EffectGhost", keroname: "", path: "/tmp/effect")
        ]
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "GetFMO",
                "SecurityLevel": "local"
            ]
        )

        let resp = SSTPDispatcher.dispatch(request: req, host: spy, bridge: bridge)

        #expect(resp.contains("SSTP/1.4 200 OK"))
        // host.collectFmoRecords() の内容が Snapshot に現れる（AppDelegate 非依存の検証）
        #expect(resp.contains("EffectGhost"))
    }
}
