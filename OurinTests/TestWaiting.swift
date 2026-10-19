import Foundation

/// 条件待ちの上限。全体実行では多数の `@MainActor` テストがメインアクターを順番に使うため、
/// 再生タイマーや `DispatchQueue.main.async` の実行が単体実行より大きく遅れる。
/// 待ちは条件成立で即座に抜けるので、上限を長くしても正常時の所要時間は変わらない。
let testWaitTimeoutNanoseconds: UInt64 = 20_000_000_000

/// メインアクター上の状態が `condition` を満たすまで、メインアクターを解放しながら待つ。
/// 上限に達した場合は何もせず戻り、直後の `#expect` に失敗を報告させる。
@MainActor
func waitUntil(
    timeoutNanoseconds: UInt64 = testWaitTimeoutNanoseconds,
    _ condition: () -> Bool
) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start >= timeoutNanoseconds {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

/// 任意スレッドから更新される値を、呼び出し元のスレッドを塞がずに待つ。
func waitUntilNonisolated(
    timeoutNanoseconds: UInt64 = testWaitTimeoutNanoseconds,
    _ condition: () -> Bool
) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start >= timeoutNanoseconds {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

/// これまでにメインキューへ積まれた処理が一巡するまで待つ。
/// 「後続イベントが送出されないこと」を確認する前に、遅延配送の可能性を消すために使う。
@MainActor
func flushMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}
