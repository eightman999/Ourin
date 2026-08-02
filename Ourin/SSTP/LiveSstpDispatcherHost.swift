import AppKit
import Foundation

/// SstpDispatcherHost の実運用実装。AppDelegate / GhostManager の具体 UI API を扱う。
///
/// ステートレスな値型であり、呼び出し時に NSApp.delegate から実ゴーストを動的に解決する。
/// そのため初期化やAppDelegate側への配線は不要で、不変な `live` 1つを使い回す。
struct LiveSstpDispatcherHost: SstpDispatcherHost {
    /// 既定の実運用インスタンス（不変・ステートレス）。
    static let live = LiveSstpDispatcherHost()

    func apply(_ effect: SstpUIEffect) {
        // 現行挙動（DispatchQueue.main.async で UI スレッドへ委譲）を維持する。
        // effect は Sendable なのでメインスレッドへ安全にキャプチャできる。
        DispatchQueue.main.async {
            LiveSstpDispatcherHost.applyOnMain(effect)
        }
    }

    func collectFmoRecords() -> [FmoGhostRecord] {
        // 従来どおり AppDelegate.collectFmoRecords() を直接呼ぶ（現行のスレッド挙動を維持）。
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return [] }
        return appDelegate.collectFmoRecords()
    }

    /// メインスレッド上で実行される効果適用の本体。
    /// DispatchQueue.main.async 経由で呼ばれることを前提とする（非 @MainActor 関数）。
    private static func applyOnMain(_ effect: SstpUIEffect) {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        guard let gm = appDelegate.ghostManagerForShioriRequest(headers: effect.requestHeaders) else { return }
        switch effect.kind {
        case .updateSurface(let id):
            gm.updateSurface(id: id)
        case .switchBalloon(let name):
            _ = gm.switchBalloon(named: name, scope: gm.currentScope, raiseEvent: true)
        case .balloonOffset(let x, let y, let isRelative):
            gm.handleBalloonOffset(x: x, y: y, isRelative: isRelative)
        case .setTaskTrayIcon(let filename, let text):
            gm.setTaskTrayIcon(filename: filename, text: text)
        case .dumpSurface(let params):
            gm.executeDumpSurface(params: params)
        case .moveWindowAsync(let scope, let x, let y, let time, let method, let ignoreSticky):
            gm.moveWindowAsync(scope: scope, x: x, y: y, time: time, method: method, ignoreStickyWindow: ignoreSticky)
        case .setTrayBalloon(let options):
            gm.setTrayBalloon(options: options)
        }
    }
}
