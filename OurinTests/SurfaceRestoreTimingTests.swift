import Foundation
import Testing
@testable import Ourin

private final class SurfaceRestoreRuntime: GhostShioriRuntime {
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

    var restoreRequests: [(method: String, id: String, refs: [String])] {
        requests.filter { $0.id == "OnSurfaceRestore" }
    }
}

/// UKADOC（OnSurfaceRestore）: トーク後一定時間経過後に一度発生。SSP では喋りタイムアウト + 15 秒後
/// （バルーンが閉じてから 15 秒後）。喋りタイムアウトが 0 のときだけ OnSurfaceRestore まで表示を続ける。
/// 15 秒は `surfaceRestoreDelay` で短くして確かめる。
@Suite(.serialized, .eventBridgeIsolated)
struct SurfaceRestoreTimingTests {
    @MainActor
    private func makeManager(
        _ name: String,
        delay: TimeInterval
    ) -> (manager: GhostManager, runtime: SurfaceRestoreRuntime, token: UUID) {
        EventBridge.shared.stop()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/\(name)"))
        let runtime = SurfaceRestoreRuntime()
        manager.shioriRuntime = runtime
        manager.surfaceRestoreDelay = delay
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        return (manager, runtime, token)
    }

    @MainActor
    private func tearDown(_ manager: GhostManager, _ token: UUID) {
        EventBridge.shared.unregister(token)
        EventBridge.shared.stop()
        _ = manager.shutdown()
    }

    @Test @MainActor
    func surfaceRestoreIsNotSentWhileWaitingForChoice() async throws {
        // Taromati2 の初回起動の名前確認: 選択肢を出したまま OnSurfaceRestore が来て、
        // その応答でバルーンが置き換わり選べなくなっていた。
        let (manager, runtime, token) = makeManager("ourin-surface-restore-choice-test", delay: 0.2)
        defer { tearDown(manager, token) }
        runtime.responses["OnChoiceSelect"] = #"\0\![set,balloontimeout,200]了解\e"#

        manager.runScript(#"\0\s[5]\![set,balloontimeout,0]これでいい？\n\q[はい,yes]\q[いいえ,no]\e"#)
        let vm = manager.getBalloonVM(for: 0)
        try await waitUntil { !manager.isPlaying && vm.text.contains("いいえ") }
        #expect(manager.inlineChoiceIndices.count == 2)

        // 遅延の数倍待っても、選択肢を待つ間は送らない。
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(runtime.restoreRequests.isEmpty)
        #expect(manager.surfaceRestoreTimer == nil)
        #expect(vm.text.contains("これでいい？"))

        // 選んだ後のトークが閉じてから一度だけ送る。
        let yes = try #require(vm.anchors.first { $0.choiceIndex == 0 })
        manager.onBalloonAnchorClicked(yes, fromScope: 0)
        try await waitUntil { !runtime.restoreRequests.isEmpty }
        #expect(runtime.requests.contains { $0.id == "OnChoiceSelect" })
        #expect(runtime.restoreRequests.count == 1)
        #expect(vm.text.isEmpty)
    }

    @Test @MainActor
    func surfaceRestoreIsSentOnceAfterBalloonCloses() async throws {
        let (manager, runtime, token) = makeManager("ourin-surface-restore-close-test", delay: 1.0)
        defer { tearDown(manager, token) }

        manager.runScript(#"\0\s[5]\![set,balloontimeout,1000]こんにちは\e"#)
        let vm = manager.getBalloonVM(for: 0)
        try await waitUntil { !manager.isPlaying && vm.text.contains("こんにちは") }
        // トークは終わったが、喋りタイムアウトで閉じるまでは数え始めない。
        #expect(manager.surfaceRestorePending)
        #expect(manager.surfaceRestoreTimer == nil)

        try await waitUntil { vm.text.isEmpty }
        let closedAt = Date()
        #expect(runtime.requests.contains { $0.id == "OnBalloonTimeout" })
        #expect(runtime.restoreRequests.isEmpty)
        #expect(manager.surfaceRestoreTimer != nil)

        try await waitUntil { !runtime.restoreRequests.isEmpty }
        #expect(Date().timeIntervalSince(closedAt) >= 0.5)
        // 一度だけ。自分のゴーストへ GET で送る。
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(runtime.restoreRequests.count == 1)
        #expect(runtime.restoreRequests.first?.method == "GET")
        #expect(!manager.surfaceRestorePending)
    }

    @Test @MainActor
    func newTalkCancelsPendingSurfaceRestore() async throws {
        let (manager, runtime, token) = makeManager("ourin-surface-restore-cancel-test", delay: 1.0)
        defer { tearDown(manager, token) }

        manager.runScript(#"\0\![set,balloontimeout,100]一つ目\e"#)
        try await waitUntil { manager.surfaceRestoreTimer != nil }
        #expect(manager.getBalloonVM(for: 0).text.isEmpty)
        #expect(runtime.restoreRequests.isEmpty)

        // バルーンが閉じた後、送る前に次のトークが始まれば取り消す（既定の喋りタイムアウトで表示を続ける）。
        manager.runScript(#"\0二つ目のトーク\e"#)
        try await waitUntil { manager.getBalloonVM(for: 0).text.contains("二") }
        #expect(manager.surfaceRestoreTimer == nil)

        try await Task.sleep(nanoseconds: 1_500_000_000)
        #expect(runtime.restoreRequests.isEmpty)
        #expect(manager.surfaceRestorePending)
    }

    @Test @MainActor
    func zeroBalloonTimeoutKeepsBalloonUntilSurfaceRestore() async throws {
        let (manager, runtime, token) = makeManager("ourin-surface-restore-zero-timeout-test", delay: 1.0)
        defer { tearDown(manager, token) }

        manager.runScript(#"\0\![set,balloontimeout,0]ずっと表示\e"#)
        let vm = manager.getBalloonVM(for: 0)
        try await waitUntil { !manager.isPlaying && vm.text.contains("ずっと表示") }
        // 喋りタイムアウト 0: トークの終わりから数え、送るまでバルーンを表示し続ける。
        #expect(manager.surfaceRestoreTimer != nil)
        #expect(vm.text.contains("ずっと表示"))

        try await waitUntil { !runtime.restoreRequests.isEmpty }
        #expect(runtime.restoreRequests.count == 1)
        #expect(vm.text.isEmpty)
    }

    @Test @MainActor
    func surfaceOnlyScriptDoesNotTriggerSurfaceRestore() async throws {
        // Taromati2 の OnSurfaceRestore の応答と同じ形。トークを出さないので、復帰を繰り返さない。
        let (manager, runtime, token) = makeManager("ourin-surface-restore-surface-only-test", delay: 0.2)
        defer { tearDown(manager, token) }

        manager.runScript(#"\w9\w9\w9\0\s[0]\1\s[10]"#)
        try await waitUntil { !manager.isPlaying }
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(runtime.restoreRequests.isEmpty)
        #expect(!manager.surfaceRestorePending)
        #expect(manager.surfaceRestoreTimer == nil)
    }

    @Test @MainActor
    func passiveModeSuppressesSurfaceRestore() async throws {
        // UKADOC（PassiveMode）: OnSurfaceRestore が来ない。
        let (manager, runtime, token) = makeManager("ourin-surface-restore-passive-test", delay: 0.2)
        defer { tearDown(manager, token) }
        manager.passiveModeActive = true

        manager.runScript(#"\0\![set,balloontimeout,0]パッシブ\e"#)
        let vm = manager.getBalloonVM(for: 0)
        try await waitUntil { !manager.isPlaying && vm.text.contains("パッシブ") }
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(runtime.restoreRequests.isEmpty)
        #expect(vm.text.contains("パッシブ"))
    }
}
