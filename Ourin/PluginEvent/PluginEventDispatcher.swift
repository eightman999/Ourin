import Foundation
import AppKit
import OSLog

/// PLUGIN イベントをプラグインへ配送するディスパッチャ
final class PluginEventDispatcher {
    /// 登録済みプラグイン一覧
    private let registry: PluginRegistry
    /// OnSecondChange 用タイマー
    private var timer: DispatchSourceTimer?
    /// プラグインごとの直列キュー
    private var queues: [Plugin: DispatchQueue] = [:]
    /// ロガー
    private let logger = CompatLogger(subsystem: "Ourin", category: "PluginEvent")
    /// version 応答で交渉したプラグインごとの文字コード（複数キュー間で共有するため要ロック）
    private let charsetLock = NSLock()
    private var pluginCharsets: [Plugin: String] = [:]

    /// プラグインに適用する送信文字コードを取得（既定 UTF-8）
    private func charset(for plugin: Plugin) -> String {
        charsetLock.lock(); defer { charsetLock.unlock() }
        return pluginCharsets[plugin] ?? "UTF-8"
    }

    /// version 応答で得た文字コードを保存する
    private func setCharset(_ cs: String, for plugin: Plugin) {
        charsetLock.lock(); defer { charsetLock.unlock() }
        pluginCharsets[plugin] = cs
    }

    /// 初期化時にプラグインメタ情報を参照してタイマーを開始する
    init(registry: PluginRegistry) {
        self.registry = registry
        // 各プラグイン用の直列キューを生成
        for plugin in registry.plugins {
            queues[plugin] = DispatchQueue(label: "plugin.queue." + plugin.bundle.bundleURL.lastPathComponent)
        }
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
        for plugin in registry.plugins {
            guard let q = queues[plugin] else { continue }
            // version 交渉で得た文字コードを Charset ヘッダへ反映する
            let req = PluginFrame(id: id, references: refs, charset: charset(for: plugin), notify: notify).build()
            q.async { [logger, id, req, plugin] in
                let start = Date()
                let _ = plugin.send(req)
                let elapsed = Date().timeIntervalSince(start)
                logger.debug("ID \(id) to \(plugin.bundle.bundleURL.lastPathComponent) (\(elapsed)s)")
                if elapsed > 3 {
                    logger.warning("timeout: \(id) >3s")
                }
            }
        }
    }

    /// version イベントを全プラグインへ送信し応答を受け取る
    private func sendVersion() {
        for plugin in registry.plugins {
            let req = PluginFrame(id: "version").build()
            queues[plugin]?.async { [weak self, logger, req, plugin] in
                let resp = plugin.send(req)
                let name = plugin.bundle.bundleURL.lastPathComponent
                // 応答の Charset ヘッダを以降の通信へ適用する(PLUGIN_EVENT/2.0M §4.1)
                if let parsed = try? PluginProtocolParser.parseResponse(resp) {
                    self?.setCharset(parsed.charset, for: plugin)
                    logger.debug("version <- \(name): \(parsed.value ?? "") charset=\(parsed.charset)")
                } else {
                    logger.debug("version request -> \(name)")
                }
            }
        }
    }

    // MARK: - Catalog events
    /// インストール済みプラグイン一覧を通知
    func notifyInstalledPlugin() {
        let list = registry.metas.values.map { "\($0.name),\($0.id)" }
        sendFrame(id: "installedplugin", refs: [ListDelimiter.join(list)], notify: true)
    }

    /// 任意のパスリストを通知するユーティリティ
    private func notifyPathList(id: String, paths: [String]) {
        let normalized = paths.map { PathNormalizer.posix($0) }
        sendFrame(id: id, refs: normalized, notify: true)
    }

    func notifyPluginPathList(paths: [String]) { notifyPathList(id: "pluginpathlist", paths: paths) }
    func notifyGhostPathList(paths: [String]) { notifyPathList(id: "ghostpathlist", paths: paths) }
    func notifyBalloonPathList(paths: [String]) { notifyPathList(id: "balloonpathlist", paths: paths) }
    func notifyHeadlinePathList(paths: [String]) { notifyPathList(id: "headlinepathlist", paths: paths) }

    func notifyInstalledGhostName(names0: [String], names1: [String], names2: [String]) {
        let r0 = ListDelimiter.join(names0)
        let r1 = ListDelimiter.join(names1)
        let r2 = ListDelimiter.join(names2)
        sendFrame(id: "installedghostname", refs: [r0, r1, r2], notify: true)
    }

    func notifyInstalledBalloonName(names: [String]) {
        let r0 = ListDelimiter.join(names)
        sendFrame(id: "installedballoonname", refs: [r0], notify: true)
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
        // 仕様(PLUGIN_EVENT/2.0M): Reference5 は 0x01 区切りで束ねた単一の Reference
        let arr = [ghostName, baseName, reasons, eventID, script, ListDelimiter.join(refs)]
        sendFrame(id: "OnOtherGhostTalk", refs: arr)
    }

    /// 選択/アンカー選択等の横流しイベント
    func onArbitraryEvent(id: String, refs: [String], notify: Bool = false) {
        sendFrame(id: id, refs: refs, notify: notify)
    }
}
