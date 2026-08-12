import Foundation
import Testing
@testable import Ourin

private final class CapturingUtilityRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var requests: [(method: String, id: String, refs: [String])] = []
    var responses: [String: String] = [:]

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        requests.append((method, id, refs))
        if let value = responses[id] {
            return .init(ok: true, status: 200, value: value)
        }
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

@Suite(.serialized)
struct GhostUtilityCommandTests {
    @Test
    func displayTextRemovesControlTagsAndKeepsNewlines() {
        let engine = SakuraScriptEngine()
        let script = #"\0Hello\n[half]World\![sound,cdplay,7]\e"#

        #expect(engine.displayText(from: script) == "Hello\nWorld")
    }

    @Test @MainActor
    func backlogKeepsVisibleTextAndCapsHistory() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-backlog-test"))

        manager.recordBacklog(from: #"\0Control-only\![sound,cdplay,7]\e"#)
        #expect(manager.backlogEntries.count == 1)
        #expect(manager.backlogEntries[0].text == "Control-only")

        for index in 1...200 {
            manager.recordBacklog(from: "\\0Entry \(index)\\e")
        }

        #expect(manager.backlogEntries.count == 200)
        #expect(manager.backlogEntries.first?.text == "Entry 1")
        #expect(manager.backlogEntries.last?.text == "Entry 200")
    }

    @Test @MainActor
    func cdplayReportsUnsupportedMediaThroughOnSoundError() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-cdplay-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.runScript(#"\![sound,cdplay,7]"#)

        let error = runtime.requests.first { $0.id == "OnSoundError" }
        #expect(error?.method == "NOTIFY")
        #expect(error?.refs == ["cdplay", "-2", "audio-cd-track-7", "audio_cd_unsupported"])
    }

    @Test @MainActor
    func raiseUsesGetAndNotifyUsesNotify() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-raise-command-test"))
        let runtime = CapturingUtilityRuntime()
        runtime.responses["OnBoot"] = #"\0standard raise response\e"#
        runtime.responses["OnRaiseTest"] = #"\0custom raise response\e"#
        manager.shioriRuntime = runtime
        let otherManager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-raise-command-other-test"))
        let otherRuntime = CapturingUtilityRuntime()
        otherManager.shioriRuntime = otherRuntime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        let otherToken = EventBridge.shared.register(runtime: otherRuntime, ghostManager: otherManager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.unregister(otherToken)
            EventBridge.shared.stop()
        }

        manager.runScript(#"\![raise,OnBoot,standard]\![raise,OnRaiseTest,custom]\![notify,OnNotifyTest,notify]"#)

        let standardRaise = runtime.requests.first { $0.id == "OnBoot" }
        let customRaise = runtime.requests.first { $0.id == "OnRaiseTest" }
        let notify = runtime.requests.first { $0.id == "OnNotifyTest" }
        #expect(standardRaise?.method == "GET")
        #expect(standardRaise?.refs == ["standard"])
        #expect(customRaise?.method == "GET")
        #expect(customRaise?.refs == ["custom"])
        #expect(notify?.method == "NOTIFY")
        #expect(notify?.refs == ["notify"])
        #expect(otherRuntime.requests.isEmpty)
    }

    @Test @MainActor
    func resetWindowPositionRaisesEventBeforeDefaultReset() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-reset-window-event-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.runScript(#"\![execute,resetwindowpos]"#)

        let resetEvent = runtime.requests.first { $0.id == EventID.OnResetWindowPos.rawValue }
        #expect(resetEvent?.method == "GET")
        #expect(resetEvent?.refs.isEmpty == true)
    }

    @Test @MainActor
    func balloonTimeoutNotifiesDisplayedScriptAndZeroRemainingTime() async throws {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-balloon-timeout-event-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        let balloon = manager.getBalloonVM(for: manager.currentScope)
        balloon.balloonTimeout = 0.01
        manager.appendText("timed out")

        for _ in 0..<20 where runtime.requests.first(where: { $0.id == EventID.OnBalloonTimeout.rawValue }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let timeout = runtime.requests.first { $0.id == EventID.OnBalloonTimeout.rawValue }
        #expect(timeout?.method == "NOTIFY")
        #expect(timeout?.refs == ["timed out", "0"])

        let close = runtime.requests.first { $0.id == EventID.OnBalloonClose.rawValue }
        #expect(close?.method == "NOTIFY")
        #expect(close?.refs == ["timed out"])
        #expect(balloon.text.isEmpty)
    }
}
