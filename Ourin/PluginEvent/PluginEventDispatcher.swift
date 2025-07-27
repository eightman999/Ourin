import Foundation
import AppKit

/// PLUGIN イベントをプラグインへ配送するディスパッチャ
final class PluginEventDispatcher {
    /// 登録済みプラグイン一覧
    private let registry: PluginRegistry
    /// OnSecondChange 用タイマー
    private var timer: DispatchSourceTimer?

    /// 初期化時にプラグインメタ情報を参照してタイマーを開始する
    init(registry: PluginRegistry) {
        self.registry = registry
        setupTimer()
        sendVersion()
    }

    // MARK: - Timer
    /// `secondchangeinterval` に従い DispatchSourceTimer を生成
    private func setupTimer() {
        let interval = registry.metas.values.compactMap { $0.secondChangeInterval }.min() ?? 0
        guard interval > 0 else { return }
        let t = DispatchSource.makeTimerSource()
        t.schedule(deadline: .now() + .seconds(interval), repeating: .seconds(interval))
        t.setEventHandler { [weak self] in
            self?.onSecondChange()
        }
        t.resume()
        timer = t
    }

    /// ディスパッチャを停止
    func stop() { timer?.cancel() }

    // MARK: - Event helpers
    /// フレームを構築し全プラグインへ送信する
    private func sendFrame(id: String, refs: [String], notify: Bool = false) {
        let frame = PluginFrame(id: id, references: refs, notify: notify)
        let req = frame.build()
        for plugin in registry.plugins {
            _ = plugin.send(req)
        }
    }

    /// version イベントを全プラグインへ送信し応答を受け取る
    private func sendVersion() {
        for plugin in registry.plugins {
            let req = PluginFrame(id: "version").build()
            _ = plugin.send(req)
        }
    }

    /// 秒周期イベント
    func onSecondChange() { sendFrame(id: "OnSecondChange", refs: []) }

    /// ゴースト起動時イベント
    func onGhostBoot(windows: [NSWindow], ghostName: String, shellName: String, ghostID: String, path: String) {
        let ref0 = WindowIDMapper.ids(for: windows)
        let pathPosix = PathNormalizer.posix(path)
        sendFrame(id: "OnGhostBoot", refs: [ref0, ghostName, shellName, ghostID, pathPosix])
    }

    /// メニュー実行時イベント
    func onMenuExec(windows: [NSWindow], ghostName: String, shellName: String, ghostID: String, path: String) {
        let ref0 = WindowIDMapper.ids(for: windows)
        let pathPosix = PathNormalizer.posix(path)
        sendFrame(id: "OnMenuExec", refs: [ref0, ghostName, shellName, ghostID, pathPosix])
    }

    /// インストール完了イベント
    func onInstallComplete(type: String, name: String, path: String) {
        let pathPosix = PathNormalizer.posix(path)
        sendFrame(id: "OnInstallComplete", refs: [type, name, pathPosix])
    }

    /// ゴースト終了通知（NOTIFY）
    func onGhostExit(windows: [NSWindow], ghostName: String, shellName: String, ghostID: String, path: String) {
        let ref0 = WindowIDMapper.ids(for: windows)
        let pathPosix = PathNormalizer.posix(path)
        sendFrame(id: "OnGhostExit", refs: [ref0, ghostName, shellName, ghostID, pathPosix], notify: true)
    }

    /// ゴースト情報更新通知（NOTIFY）
    func onGhostInfoUpdate(windows: [NSWindow], ghostName: String, shellName: String, ghostID: String, path: String) {
        let ref0 = WindowIDMapper.ids(for: windows)
        let pathPosix = PathNormalizer.posix(path)
        sendFrame(id: "OnGhostInfoUpdate", refs: [ref0, ghostName, shellName, ghostID, pathPosix], notify: true)
    }

    /// その他ゴーストのトークイベント
    func onOtherGhostTalk(ghostName: String, baseName: String, reasons: String, eventID: String, script: String, refs: [String]) {
        var arr = [ghostName, baseName, reasons, eventID, script]
        arr.append(contentsOf: refs)
        sendFrame(id: "OnOtherGhostTalk", refs: arr)
    }

    /// 選択/アンカー選択等の横流しイベント
    func onArbitraryEvent(id: String, refs: [String], notify: Bool = false) {
        sendFrame(id: id, refs: refs, notify: notify)
    }
}
