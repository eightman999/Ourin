import Foundation

/// 旧内部APIの互換ファサード。新規コードは `SstpBreakPolicy` を注入する。
/// タイムアウトは呼び出し単位で指定し、グローバル可変状態を持たない。
@available(*, deprecated, message: "SstpBreakPolicyを注入してください")
enum SSTPBreakQueue {
    @discardableResult
    static func waitWhileBusy(timeout: TimeInterval) -> Bool {
        LiveSstpBreakPolicy(timeout: timeout, pollInterval: 0.02).waitWhileBusy()
    }
}
