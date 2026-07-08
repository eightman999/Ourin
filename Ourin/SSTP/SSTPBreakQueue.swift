import Foundation

/// SSTP `Option: nobreak` 指定時のキューイング待機を担うヘルパー。
///
/// UKADOC SSTP/1.x 仕様: `nobreak` は「現在実行中のスクリプトを中断せず、終わるまで待つ」
/// （ワイヤ上のオプション。実行を打ち切って即時応答するものではない）。
/// `ShioriStatusStore.currentStatus` が `"busy"` である間はリクエストをブロッキング待機させ、
/// busy が解消（Status ヘッダの更新）され次第、呼び出し元（`SSTPDispatcher`）へ制御を返して
/// 通常のディスパッチ経路（SHIORI呼び出し・スクリプト再生）へ進ませる。
///
/// `dispatch(request:)` は SSTPListener / HTTPBridge / DirectSSTPXPC / OurinExternalServer から
/// バックグラウンドスレッド経由でのみ呼ばれるため、ここでの短いポーリング待機はメインスレッドを
/// ブロックしない（メインスレッドから直接呼び出さないこと）。
enum SSTPBreakQueue {
    /// ポーリング間隔。
    private static let pollInterval: TimeInterval = 0.02
    /// 待機の上限（これを超えても busy が解消しない場合は諦めて呼び出し元に false を返す）。
    /// テストからも上書きできるよう internal な var にしている。
    static var defaultTimeout: TimeInterval = 5.0

    /// `ShioriStatusStore` の状態が "busy" でなくなるまで待機する。
    /// - Parameter timeout: 待機上限秒数。省略時は `defaultTimeout`。
    /// - Returns: busy が解消して抜けたら true。タイムアウトした場合は false。
    @discardableResult
    static func waitWhileBusy(timeout: TimeInterval? = nil) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? defaultTimeout)
        while ShioriStatusStore.shared.currentStatus.lowercased() == "busy" {
            if Date() >= deadline {
                return false
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return true
    }
}
