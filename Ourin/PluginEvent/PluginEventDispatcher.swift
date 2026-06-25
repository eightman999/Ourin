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
    /// XPC プロセス分離が有効な場合のクライアント（nil ならインプロセス実行）
    private let xpcClient: PluginXpcClient?

    /// プラグインが Script を返したときにホスト側で実行させるためのコールバック。
    /// 構築側（AppDelegate 等）が `sakuraEngine.run(script:)` 等へ配線する。
    /// TODO: host wires onScript (see OurinApp.swift / GhostManager+System.swift:175-179)
    var onScript: ((String, Set<String>) -> Void)?
    /// プラグインが Event を返したときにホスト側へ再ディスパッチさせるためのコールバック。
    /// 構築側が `EventBridge.notify(_:params:)` 等へ配線する。
    /// TODO: host wires onEmitEvent (see GhostManager+System.swift:180-186)
    var onEmitEvent: ((String, [String: String], Set<String>) -> Bool)?

    /// プラグインへワイヤテキストを送信する。XPC 分離が有効なら別プロセスのワーカーへ、
    /// それ以外は従来通りインプロセス（CFBundle ロード）で実行する。
    private func transportSend(_ req: String, to plugin: Plugin) -> String {
        if let xpc = xpcClient {
            if let resp = xpc.send(req, bundlePath: plugin.bundle.bundleURL.path) {
                return resp
            }
            logger.warning("plugin XPC send failed; bundle=\(plugin.bundle.bundleURL.lastPathComponent)")
            return ""
        }
        return plugin.send(req)
    }

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
        // プロセス分離モードが有効なら XPC クライアントを用意する（既定はインプロセス）
        if let serviceName = PluginIsolation.resolvedXpcServiceName() {
            self.xpcClient = PluginXpcClient(serviceName: serviceName)
            logger.info("plugin isolation=xpc service=\(serviceName)")
        } else {
            self.xpcClient = nil
        }
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
    private func sendFrame(id: String, refs: [String], notify: Bool = false, securityLevel: PluginSecurityLevel = .local) {
        for plugin in registry.plugins {
            guard let q = queues[plugin] else { continue }
            // version 交渉で得た文字コードを Charset ヘッダへ反映する
            let req = PluginFrame(id: id, references: refs, charset: charset(for: plugin), notify: notify, securityLevel: securityLevel).build()
            q.async { [weak self, logger, id, req, plugin, notify] in
                let start = Date()
                let resp = self?.transportSend(req, to: plugin) ?? ""
                let elapsed = Date().timeIntervalSince(start)
                logger.debug("ID \(id) to \(plugin.bundle.bundleURL.lastPathComponent) (\(elapsed)s)")
                if elapsed > 3 {
                    logger.warning("timeout: \(id) >3s")
                }
                // NOTIFY フレームは応答を破棄する。GET フレームは Script/Event を実行する。
                if !notify {
                    self?.handleResponse(resp, from: plugin)
                }
            }
        }
    }

    /// プラグインからの応答を解釈し、Script/Event をホスト側へ引き渡す。
    /// `OurinPluginEventBridge.transportAction` / `shouldHandleTarget` と同じ判定を再利用するため、
    /// GhostManager+System.swift:173-187 と同一のルーティング規則が適用される。
    private func handleResponse(_ resp: String, from plugin: Plugin) {
        guard !resp.isEmpty,
              let parsed = try? PluginProtocolParser.parseResponse(resp),
              parsed.statusCode == 200 else { return }
        guard let action = OurinPluginEventBridge.transportAction(from: parsed, notifyOnly: false) else { return }
        guard OurinPluginEventBridge.shouldHandleTarget(action.target) else {
            logger.debug("ignored target: \(action.target ?? "nil") from \(plugin.bundle.bundleURL.lastPathComponent)")
            return
        }
        OurinPluginEventBridge.deliver(
            action,
            runScript: { action in
                guard let script = action.script else { return }
                onScript?(script, action.scriptOptions)
            },
            emitEvent: { action in
                guard let eventName = action.eventName else { return false }
                return onEmitEvent?(eventName, action.references, action.eventOptions) ?? false
            }
        )
    }

    /// version イベントを全プラグインへ送信し応答を受け取る
    private func sendVersion() {
        for plugin in registry.plugins {
            let req = PluginFrame(id: "version").build()
            queues[plugin]?.async { [weak self, logger, req, plugin] in
                let resp = self?.transportSend(req, to: plugin) ?? ""
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
        let list = registry.allMetas.map { "\($0.name),\($0.id)" }
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
    func notifyCalendarSkinPathList(paths: [String]) { notifyPathList(id: "calendarskinpathlist", paths: paths) }
    func notifyCalendarPluginPathList(paths: [String]) { notifyPathList(id: "calendarpluginpathlist", paths: paths) }

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
    /// SSTP 経由など外部由来で中継する場合は `securityLevel: .external` を指定する。
    func onArbitraryEvent(id: String, refs: [String], notify: Bool = false, securityLevel: PluginSecurityLevel = .local) {
        sendFrame(id: id, refs: refs, notify: notify, securityLevel: securityLevel)
    }
}
