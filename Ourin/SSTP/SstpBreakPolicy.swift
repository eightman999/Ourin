import Foundation

protocol SstpBreakPolicy: Sendable {
    func isBusy() -> Bool
    func waitWhileBusy() -> Bool
}

struct LiveSstpBreakPolicy: SstpBreakPolicy {
    let timeout: TimeInterval
    let pollInterval: TimeInterval

    static let live = LiveSstpBreakPolicy(timeout: 5.0, pollInterval: 0.02)

    func isBusy() -> Bool {
        ShioriStatusStore.shared.currentStatus.lowercased() == "busy"
    }

    /// 同期ポーリングで待機するため、SSTPのバックグラウンド受信経路からだけ呼ぶ。
    /// メインスレッドから直接呼ぶと、最大`timeout`秒UIを停止させる。
    func waitWhileBusy() -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while isBusy() {
            if Date() >= deadline {
                return false
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return true
    }
}
