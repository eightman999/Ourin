import Foundation
import Testing
@testable import Ourin

/// `EventBridge.shared` はプロセス全体で 1 つのセッション表を持ち、`notify` / `dispatch` は
/// 登録済みの全セッションへ配送する。Swift Testing は別スイートを並列に実行するため、
/// あるスイートが登録したテスト用ランタイムへ別スイートのイベント（OnSSTPBlacklisting、
/// OnVideoPlayFailure 等）が届いたり、`runningGhostNames()` に他スイートのゴーストが
/// 混ざったりする。
///
/// この trait を付けたスイート同士は、スイート単位で排他実行される。セッションを登録して
/// 受信内容を検証するスイートと、`EventBridge.shared` へ配送を起こすスイートに付ける。
struct EventBridgeIsolationTrait: SuiteTrait, TestScoping {
    /// スイート全体で 1 回だけロックを取る（テスト単位にすると、同じスイート内の
    /// 前後テストの間に他スイートが割り込める）。
    var isRecursive: Bool { false }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await EventBridgeTestLock.shared.acquire()
        do {
            try await function()
        } catch {
            await EventBridgeTestLock.shared.release()
            throw error
        }
        await EventBridgeTestLock.shared.release()
    }
}

extension Trait where Self == EventBridgeIsolationTrait {
    /// `EventBridge.shared` のセッション表を他スイートと共有しないように排他実行する。
    static var eventBridgeIsolated: Self { Self() }
}

/// FIFO の非同期ロック。待機中はスレッドを塞がない（メインアクターのテストを止めない）。
actor EventBridgeTestLock {
    static let shared = EventBridgeTestLock()

    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !locked {
            locked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            locked = false
        } else {
            // ロックを保持したまま次の待機者へ引き渡す。
            waiters.removeFirst().resume()
        }
    }
}
