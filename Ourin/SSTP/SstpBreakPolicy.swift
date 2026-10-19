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
        if ShioriStatusStore.shared.currentStatus.lowercased() == "busy" {
            return true
        }
        // 登録済みゴーストがスクリプト再生中の場合も busy 扱いにして、
        // nobreak 要求を再生完了まで待機させる。
        return EventBridge.shared.isAnyGhostPlaying()
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
