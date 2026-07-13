import SwiftUI
import AppKit
import ApplicationServices
import UserNotifications

// Plugin host
import Foundation
// FMO 機能を組み込み、起動時に初期化する

struct OurinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // Settings window - hidden by default, can be opened from menu
        WindowGroup("Settings", id: "Settings") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Ourin") {
                    appDelegate.showAboutWindow()
                }
            }
        }

        WindowGroup("DevTools", id: "DevTools") {
            DevToolsView()
        }
        
        // The right-click menu has moved to the menu bar.
        if #available(macOS 13.0, *) {
            MenuBarExtra("Ourin") {
                RightClickMenu()
            }
            .commands {
                ModernDevToolsCommands()
            }
        }
    }

    private func openSettingsWindow() {
        // If a Settings window already exists, just focus it (identify by custom identifier or localized title)
        let settingsID = NSUserInterfaceItemIdentifier("SettingsWindow")
        for window in NSApplication.shared.windows {
            if window.identifier == settingsID || window.title == NSLocalizedString("Settings", comment: "Settings window title") {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                return
            }
        }

        // Create an in-app Settings window (instead of opening System Settings)
        let controller = NSHostingController(rootView: ContentView())
        let win = NSWindow(contentViewController: controller)
        win.identifier = settingsID
        win.title = NSLocalizedString("Settings", comment: "Settings window title")
        win.setContentSize(NSSize(width: 900, height: 600))
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func openAboutWindow() {
        for window in NSApplication.shared.windows {
            if window.title == NSLocalizedString("About Ourin", comment: "About window title") {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        // Create the About window by opening the scene
        NSApp.sendAction(Selector(("showAboutWindow:")), to: nil, from: nil)
        // Fallback: explicitly open via scene id
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var fmo: FmoManager?
    var pluginRegistry: PluginRegistry?
    var headlineRegistry: HeadlineRegistry?
    var eventBridge: EventBridge?
    /// 外部 SHIORI イベントサーバ
    var externalServer: OurinExternalServer?
    /// PLUGIN Event 配送用ディスパッチャ
    var pluginDispatcher: PluginEventDispatcher?
    /// NAR インストーラ
    private let narInstaller = NarInstaller()
    /// The currently running ghost's manager (primary). 既存の単一ゴースト経路の互換のため維持。
    var ghostManager: GhostManager?
    /// 同時起動している追加ゴースト（プライマリ以外）。複数ゴースト同時実行用。
    var additionalGhosts: [GhostManager] = []
    let shioriRuntimeCache = ShioriRuntimeCache(capacity: 2)
    /// 起動中の全ゴースト（プライマリ＋追加）。FMO 集約・一括終了に使う。
    var allGhostManagers: [GhostManager] {
        ([ghostManager].compactMap { $0 }) + additionalGhosts
    }

    /// SHIORI 要求（SSTP/Web/Resource ブリッジ）の宛先ゴーストを解決する。
    /// ヘッダに ReceiverGhostName 指定があれば該当ゴースト、無ければプライマリゴーストの
    /// YayaAdapter を返す。宛先が見つからなければ nil。
    /// `ghostManager` / `additionalGhosts` はメインスレッドで更新されるため、参照解決は
    /// 常にメインスレッドで行う（バックグラウンドの SSTP キューからの並行読みによる data race を防ぐ）。
    func yayaAdapterForShioriRequest(headers: [String: String]) -> YayaAdapter? {
        if Thread.isMainThread {
            return resolveYayaAdapter(headers: headers)
        }
        return DispatchQueue.main.sync { self.resolveYayaAdapter(headers: headers) }
    }

    /// SHIORI要求の宛先ランタイムを解決する。YAYA・里々・ネイティブSHIORIを同じ境界で扱う。
    func shioriRuntimeForShioriRequest(headers: [String: String]) -> GhostShioriRuntime? {
        if Thread.isMainThread {
            return resolveGhostManager(headers: headers)?.shioriRuntime
        }
        return DispatchQueue.main.sync { self.resolveGhostManager(headers: headers)?.shioriRuntime }
    }

    /// SSTP 応答ヘッダ副作用（Surface/Balloon/Icon 等）の宛先 GhostManager を解決する。
    /// 照合規則は `yayaAdapterForShioriRequest` と同一（ReceiverGhostName → プライマリへフォールバック）。
    func ghostManagerForShioriRequest(headers: [String: String]) -> GhostManager? {
        if Thread.isMainThread {
            return resolveGhostManager(headers: headers)
        }
        return DispatchQueue.main.sync { self.resolveGhostManager(headers: headers) }
    }

    private func resolveYayaAdapter(headers: [String: String]) -> YayaAdapter? {
        resolveGhostManager(headers: headers)?.yayaAdapter
    }

    /// ReceiverGhostName ヘッダから照合キーを作る純関数部（テスト用に static 公開）。
    /// SSTPDispatcher のレジストリ照合に合わせて percent デコード＋小文字化する。
    /// 未指定・空白のみの場合は nil（＝プライマリゴーストへフォールバック）。
    static func receiverTargetKey(headers: [String: String]) -> String? {
        guard let receiver = headers["ReceiverGhostName"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !receiver.isEmpty else { return nil }
        return (receiver.removingPercentEncoding ?? receiver).lowercased()
    }

    private func resolveGhostManager(headers: [String: String]) -> GhostManager? {
        if let target = Self.receiverTargetKey(headers: headers) {
            if let gm = allGhostManagers.first(where: {
                ($0.ghostConfig?.name.lowercased() == target) ||
                ($0.ghostURL.lastPathComponent.lowercased() == target)
            }) {
                return gm
            }
        }
        return ghostManager
    }
    /// DevTools window for legacy macOS
    private var devToolsWindow: NSWindow?
    /// About window
    private var aboutWindow: NSWindow?
    private var isRunningUnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningUnderTests {
            NSLog("[AppDelegate] Detected XCTest environment; skipping full app bootstrap")
            return
        }

        // Ensure single instance and clean helper state by killing others first
        ProcessKiller.killOtherOurinAndYaya()

        // 共有メモリの存在で他のベースウェアが起動しているか判定
        if FmoManager.isAnotherInstanceRunning() {
            if ProcessKiller.hasOtherOurinInstance() {
                NSLog("Another baseware instance is already running. Terminating.")
                NSApplication.shared.terminate(nil)
                return
            }
            NSLog("FMO exists but no other Ourin process was found. Reclaiming stale FMO resources.")
            FmoManager.reclaimStaleResources()
        }

        // FMO を初期化（クラッシュ後の残留セマフォ/共有メモリは自動的に上書き再作成される）
        do {
            fmo = try FmoManager()
        } catch {
            NSLog("FMO init failed: \(error)")
            NSLog("Continuing without FMO (single instance enforcement disabled)")
        }

        // READFMO（YAYA builtin）から現在の FMO スナップショットを同期的に取得できるようにする。
        // yaya_core からの host_op:"fmo" 問い合わせに対し、起動中ゴーストのレコードから
        // SSP 互換 `id.key\x01value\r\n` 文字列を構築して返す。
        YayaAdapter.fmoSnapshotProvider = { [weak self] () -> String in
            guard let self else { return "" }
            return FmoManager.buildSnapshot(records: self.collectFmoRecords())
        }

        // 旧データ（Application Support / 旧サンドボックスコンテナ）を ~/Documents/Ourin へ一度だけ移行する。
        // plugin/headline 探索や startup ghost より前に行い、各 Registry が移行後の公開フォルダを参照できるようにする。
        OurinPaths.migrateLegacyDataIfNeeded()

        // Hide the default Settings window on startup
        DispatchQueue.main.async {
            let settingsTitle = NSLocalizedString("Settings", comment: "Settings window title")
            for window in NSApplication.shared.windows {
                if window.title == settingsTitle || window.contentViewController?.view.className.contains("ContentView") == true {
                    window.close()
                }
            }
        }

        // Register handler for x-ukagaka-link scheme early
        WebHandler.shared.register()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWebHomeURL(_:)),
            name: .ourinWebHomeURLReceived,
            object: nil
        )
        UNUserNotificationCenter.current().delegate = self

        // FMO 更新通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFmoRefresh(_:)),
            name: .fmoNeedsRefresh,
            object: nil
        )

        // プラグインを探索してロード
        let registry = PluginRegistry()
        registry.discoverAndLoad()
        pluginRegistry = registry
        // プラグイン読み込み後にディスパッチャを開始
        pluginDispatcher = PluginEventDispatcher(registry: registry)
        // プラグインが返した Script:/Event: をホスト（アクティブゴースト）へ配線する
        pluginDispatcher?.onScript = { [weak self] script, options in
            DispatchQueue.main.async {
                self?.ghostManager?.runPluginScript(script, options: options.union(["plugin-script"]))
            }
        }
        pluginDispatcher?.onEmitEvent = { event, refs, options in
            let notifyOnly = options.contains("notify")
            if Thread.isMainThread {
                return EventBridge.shared.dispatchPluginResponseEvent(event, params: refs, notifyOnly: notifyOnly, scriptOptions: options)
            }
            return DispatchQueue.main.sync {
                EventBridge.shared.dispatchPluginResponseEvent(event, params: refs, notifyOnly: notifyOnly, scriptOptions: options)
            }
        }
        // HEADLINE モジュールも探索してロード
        let hRegistry = HeadlineRegistry()
        hRegistry.discoverAndLoad()
        headlineRegistry = hRegistry
        notifyPluginCatalogs()

        // SSTP / Web / Resource からの SHIORI 要求を、稼働中のゴースト（YAYA）へ橋渡しする。
        // ネイティブ SHIORI バンドルが無い通常構成では BridgeToSHIORI のホストが nil のため、
        // このリゾルバが実ゴーストへ要求を送り、ReferenceN/Value/Status を保持した応答を返す。
        // クロージャは SSTP サーバのバックグラウンドキューから呼ばれ、宛先は呼び出し時に解決する。
        BridgeToSHIORI.liveGhostResolver = { [weak self] method, event, references, headers in
            guard let self else { return nil }
            // 宛先ランタイムはメインスレッドで解決する（ghostManager / additionalGhosts はメインで更新される）。
            guard let runtime = self.shioriRuntimeForShioriRequest(headers: headers) else { return nil }
            // IPC 自体は呼び出し元キュー（SSTP バックグラウンド等）で同期実行する。
            // 直列リスナーキューを長時間塞がないよう短めのタイムアウトにする。
            let res: ShioriRuntimeResponse?
            if event == "Resource", let key = references.first {
                // Resource 疑似イベント（ResourceBridge 由来）は SHIORI Resource GET（ID=リソース名）へ正規化する。
                res = runtime.request(method: "GET", id: key, headers: headers, refs: [], timeout: 2.0)
            } else {
                res = runtime.request(method: method, id: event, headers: headers, refs: references, timeout: 2.0)
            }
            guard let res, res.ok else { return nil }
            return BridgeToSHIORI.BridgeShioriResponse(status: res.status, headers: res.headers ?? [:], value: res.value)
        }

        // 外部 SSTP サーバを起動
        let ext = OurinExternalServer()
        let securitySettings = ExternalServerSecuritySettings.load()
        ext.updateConfig(securitySettings.asServerConfig())
        ext.start()
        externalServer = ext

        // ユーザーが選択したゴースト、またはデフォルトのゴーストを起動
        let startupGhostKey = "OurinStartupGhost"
        if let ghostName = UserDefaults.standard.string(forKey: startupGhostKey), !ghostName.isEmpty {
            self.runNamedGhost(name: ghostName)
        } else {
            self.installDefaultGhost()
        }
        
        // オーナードローメニューアクションの通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOwnerDrawMenuAction(_:)),
            name: NSNotification.Name("OwnerDrawMenuAction"),
            object: nil
        )
    }
    
    @objc private func handleOwnerDrawMenuAction(_ notification: Notification) {
        guard let action = notification.userInfo?["action"] as? String else { return }
        ghostManager?.handleMenuAction(action)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't terminate when Settings window is closed - ghost windows should remain visible
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // OnClose を GET で送り、応答スクリプト（お別れトーク、末尾 \-）を再生してから終了する（UKADOC）
        if isRunningUnderTests { return .terminateNow }
        guard let gm = ghostManager, !gm.isShuttingDown else {
            return .terminateNow
        }
        if gm.beginCloseSequence(reason: "user", replyToTermination: true) {
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: .ourinWebHomeURLReceived, object: nil)
        NotificationCenter.default.removeObserver(self, name: .fmoNeedsRefresh, object: nil)
        // 終了時に共有メモリとセマフォを開放
        fmo?.cleanup()
        pluginRegistry?.unloadAll()
        headlineRegistry?.unloadAll()
        eventBridge?.stop()
        externalServer?.stop()
        // PLUGIN ディスパッチャ停止
        pluginDispatcher?.stop()
        // ゴーストをシャットダウン（追加ゴースト→プライマリ）
        terminateAllAdditionalGhosts()
        ghostManager?.shutdown()
        shioriRuntimeCache.removeAll()
        // 念のため残留プロセスを掃除
        ProcessKiller.killOtherOurinAndYaya()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let info = response.notification.request.content.userInfo
        guard (info["ourinTrayBalloon"] as? String) == "1" else { return }
        EventBridge.shared.notify(.OnTrayBalloonClick, refs: [
            "identifier": response.notification.request.identifier,
            "title": (info["title"] as? String) ?? "",
            "message": (info["message"] as? String) ?? ""
        ])
    }

    func application(_ app: NSApplication, openFiles filenames: [String]) {
        for path in filenames {
            if URL(fileURLWithPath: path).pathExtension.lowercased() == "nar" {
                installNar(at: URL(fileURLWithPath: path))
            }
        }
        app.reply(toOpenOrPrint: NSApplication.DelegateReply.success)
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls where ["nar", "zip"].contains(url.pathExtension.lowercased()) {
            installNar(at: url)
        }
    }

    @objc private func handleFmoRefresh(_ notification: Notification) {
        refreshFmo()
    }

    @objc private func handleWebHomeURL(_ notification: Notification) {
        guard let urlString = notification.userInfo?["url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            NSLog("[WebHandler] Ignored invalid homeurl notification")
            return
        }

        ResourceManager().homeurl = urlString
        ghostManager?.resourceManager.homeurl = urlString
        ghostManager?.ghostConfig?.homeurl = urlString
        ghostManager?.checkGhostUpdate(options: ["web-homeurl"])
        NSLog("[WebHandler] Applied homeurl from web link: \(urlString)")
    }

    /// Install bundled emily4.nar and run it if present
    func installDefaultGhost() {
        // 既に emily4 が導入済み（移行で取り込まれた場合を含む）なら再インストールせず起動する。
        // これをしないと、移行で配置済みの ghost/emily4 へバンドル nar を重ねて書き込もうとし、衝突する。
        if let ghost = NarRegistry.shared.installedItems(ofType: "ghost").first(where: { $0.name == "emily4" }) {
            NSLog("[installDefaultGhost] emily4 already installed at \(ghost.path.path); running it")
            runGhost(at: ghost.path)
            return
        }

        if let url = Bundle.main.url(forResource: "emily4", withExtension: "nar") {
            NSLog("[installDefaultGhost] Found emily4.nar at: \(url.path)")
            installNar(at: url)
        } else {
            NSLog("[installDefaultGhost] Bundled emily4.nar not found and emily4 not installed")
        }
    }

    func runNamedGhost(name: String) {
        guard let ghost = NarRegistry.shared.installedItems(ofType: "ghost").first(where: { $0.name == name }) else {
            NSLog("Could not find ghost named \(name)")
            DispatchQueue.main.async {
                let title = NSLocalizedString("Ghost not found", comment: "Alert title when ghost is missing")
                let format = NSLocalizedString("The ghost '%@' could not be found. It may have been moved or deleted.", comment: "Alert body when ghost is missing")
                let text = String(format: format, name)
                NSApp.presentAlert(style: .critical, title: title, text: text)
            }
            return
        }
        runGhost(at: ghost.path)
    }

    private func installNar(at url: URL) {
        NSLog("[installNar] Installing NAR from: \(url.path)")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let target = try self.narInstaller.install(fromNar: url)
                NSLog("[installNar] Installed to: \(target.path)")
                DispatchQueue.main.async {
                    self.notifyInstallComplete(at: target)
                    self.notifyPluginCatalogs()
                    let title = NSLocalizedString("Installed", comment: "Alert title when installation succeeded")
                    let fmt = NSLocalizedString("Installed: %@", comment: "Alert body for installed file")
                    let text = String(format: fmt, url.lastPathComponent)
                    NSApp.presentAlert(style: .informational, title: title, text: text)
                    NSLog("[installNar] Running ghost at: \(target.path)")
                    self.runGhost(at: target)
                }
            } catch NarInstaller.Error.directoryConflict(let ghostName) {
                NSLog("[installNar] Ghost \(ghostName) already installed, running it instead")
                // Find the already-installed ghost and run it
                DispatchQueue.main.async {
                    if let ghost = NarRegistry.shared.installedItems(ofType: "ghost").first(where: { $0.name == ghostName }) {
                        NSLog("[installNar] Found already-installed ghost at: \(ghost.path.path)")
                        self.runGhost(at: ghost.path)
                    } else {
                        NSLog("[installNar] Could not find already-installed ghost: \(ghostName)")
                        let title = NSLocalizedString("Ghost conflict", comment: "Alert title for ghost conflict")
                        let fmt = NSLocalizedString("Ghost '%@' is already installed but could not be loaded.", comment: "Alert body for ghost conflict")
                        let text = String(format: fmt, ghostName)
                        NSApp.presentAlert(style: .warning, title: title, text: text)
                    }
                }
            } catch {
                NSLog("[installNar] Install failed: \(error)")
                DispatchQueue.main.async {
                    let title = NSLocalizedString("Install failed", comment: "Alert title for install failure")
                    NSApp.presentAlert(style: .critical, title: title, text: String(describing: error))
                }
            }
        }
    }

    private func notifyPluginCatalogs() {
        guard let dispatcher = pluginDispatcher else { return }
        dispatcher.notifyInstalledPlugin()
        dispatcher.notifyPluginPathList(paths: pluginRegistry?.allMetas.map { $0.packagePath ?? $0.executablePath } ?? [])
        dispatcher.notifyCalendarSkinPathList(paths: CalendarRegistry.shared.installedSkins().map { $0.path.path })
        dispatcher.notifyCalendarPluginPathList(paths: CalendarRegistry.shared.installedPlugins().map { $0.path.path })

        let ghosts = NarRegistry.shared.installedItems(ofType: "ghost")
        var ghostNames: [String] = []
        var sakuraNames: [String] = []
        var keroNames: [String] = []
        for ghost in ghosts {
            ghostNames.append(ghost.name)
            let root = ghost.path.appendingPathComponent("ghost/master", isDirectory: true)
            if let config = GhostConfiguration.load(from: root) {
                sakuraNames.append(config.sakuraName)
                keroNames.append(config.keroName ?? "")
            } else {
                sakuraNames.append("")
                keroNames.append("")
            }
        }
        dispatcher.notifyInstalledGhostName(names0: ghostNames, names1: sakuraNames, names2: keroNames)
        dispatcher.notifyGhostPathList(paths: ghosts.map { $0.path.path })

        let balloons = NarRegistry.shared.installedItems(ofType: "balloon")
        dispatcher.notifyInstalledBalloonName(names: balloons.map { $0.name })
        dispatcher.notifyBalloonPathList(paths: balloons.map { $0.path.path })

        let headlinePaths = headlineRegistry?.modules.map { $0.bundle.bundleURL.path } ?? []
        dispatcher.notifyHeadlinePathList(paths: headlinePaths)
    }

    private func notifyInstallComplete(at target: URL) {
        let type = target.deletingLastPathComponent().lastPathComponent
        let name = target.lastPathComponent
        pluginDispatcher?.onInstallComplete(type: type, name: name, path: target.path)
    }

    /// 起動中の全ゴースト（プライマリ＋追加）から FmoGhostRecord を収集する。
    /// 複数ゴースト同時実行時は各ゴーストが 1 レコードを占める（FMO ID は出力側で連番付与）。
    func collectFmoRecords() -> [FmoGhostRecord] {
        allGhostManagers.compactMap { gm in
            guard let config = gm.ghostConfig else { return nil }
            var record = FmoGhostRecord()
            record.name = config.sakuraName
            record.keroname = config.keroName ?? ""
            record.path = gm.ghostURL.path
            record.shell = gm.activeShellName
            record.balloon = gm.balloonConfig?.name ?? ""
            record.sakuraSurface = gm.characterViewModels[0]?.currentSurfaceID ?? 0
            record.keroSurface = gm.characterViewModels[1]?.currentSurfaceID ?? 10

            // 標準 SSP/UKADOC FMO フィールド
            record.fullname = config.name
            record.ghostname = config.name
            record.ghostpath = gm.ghostURL.path
            record.moduleState = "running"

            // ウィンドウ識別子: 実ウィンドウ番号（NSWindow.windowNumber, 安定・一意・非ゼロ）を優先。
            // ウィンドウが未生成・未表示で番号が取れない場合はゴーストパス由来の安定ハッシュで代替する。
            // ハッシュは各スコープにスコープ番号を加味し、ゴースト間・スコープ間で衝突しないようにする。
            func stableID(forScope scope: Int) -> Int {
                if let n = gm.characterWindows[scope]?.windowNumber, n != 0 {
                    return n
                }
                // 安定ハッシュ（負値や 0 を避けるため絶対値+1）
                var hasher = Hasher()
                hasher.combine(gm.ghostURL.standardizedFileURL.path)
                hasher.combine(scope)
                let h = hasher.finalize()
                return abs(h % 0x7FFF_FFFF) + 1
            }

            record.hwnd = stableID(forScope: 0)
            record.kerohwnd = stableID(forScope: 1)

            // hwndlist: このゴーストの全キャラクターウィンドウ識別子をスコープ順で並べる。
            // 実ウィンドウが存在するスコープのみ列挙し、無ければ sakura/kero の安定 ID を使う。
            if !gm.characterWindows.isEmpty {
                record.hwndList = gm.characterWindows
                    .sorted(by: { $0.key < $1.key })
                    .map { String(stableID(forScope: $0.key)) }
                    .joined(separator: ",")
            } else {
                record.hwndList = "\(record.hwnd),\(record.kerohwnd)"
            }

            return record
        }
    }

    /// FMO 共有メモリを現在のゴースト状態で更新する
    func refreshFmo() {
        guard let fmo else { return }
        let records = collectFmoRecords()
        fmo.writeSnapshot(records: records)
    }

    func runGhost(at root: URL) {
        NSLog("[runGhost] Starting ghost from: \(root.path)")
        // If a ghost is already running, shut it down first.
        if let existingManager = self.ghostManager {
            NSLog("[runGhost] Shutting down existing ghost")
            if let cached = existingManager.shutdown(preserveRuntimeForCache: true) {
                shioriRuntimeCache.store(runtime: cached.runtime, context: cached.context)
            }
            self.ghostManager = nil
        }

        // Create and start the new ghost manager.
        NSLog("[runGhost] Creating GhostManager for: \(root.path)")
        let newManager = GhostManager(ghostURL: root)
        self.ghostManager = newManager
        NSLog("[runGhost] Starting GhostManager")
        newManager.start()
    }

    // MARK: - Multiple concurrent ghosts

    /// 追加ゴーストを同時起動する（プライマリは置き換えない）。
    /// EventBridge は各ゴーストを個別セッションとして登録し、NOTIFY を全ゴーストへ配信する。
    /// SSTP は ReceiverGhostName で対象を絞り込める。
    /// - Returns: 起動した GhostManager（既に同一パスが起動中なら既存を返す）
    @discardableResult
    func launchAdditionalGhost(at root: URL) -> GhostManager {
        if let existing = allGhostManagers.first(where: { $0.ghostURL.standardizedFileURL == root.standardizedFileURL }) {
            NSLog("[launchAdditionalGhost] already running: \(root.lastPathComponent)")
            return existing
        }
        NSLog("[launchAdditionalGhost] launching: \(root.path)")
        let manager = GhostManager(ghostURL: root)
        additionalGhosts.append(manager)
        manager.start()
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
        return manager
    }

    /// インストール済みゴースト名から追加ゴーストを起動する。
    @discardableResult
    func launchAdditionalGhost(named name: String) -> GhostManager? {
        guard let item = NarRegistry.shared.installedItems(ofType: "ghost")
            .first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            NSLog("[launchAdditionalGhost] not found: \(name)")
            return nil
        }
        return launchAdditionalGhost(at: item.path)
    }

    /// 追加ゴーストを終了する（プライマリは対象外）。
    func terminateAdditionalGhost(_ manager: GhostManager) {
        guard let idx = additionalGhosts.firstIndex(where: { $0 === manager }) else { return }
        additionalGhosts.remove(at: idx)
        manager.shutdown()
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
    }

    /// すべての追加ゴーストを終了する。
    func terminateAllAdditionalGhosts() {
        let managers = additionalGhosts
        additionalGhosts.removeAll()
        for m in managers { m.shutdown() }
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
    }

    /// Show DevTools window on macOS < 13
    func showDevTools() {
        if devToolsWindow == nil {
            let controller = NSHostingController(rootView: DevToolsView())
            let win = NSWindow(contentViewController: controller)
            win.setContentSize(NSSize(width: 700, height: 500))
            win.title = NSLocalizedString("DevTools", comment: "DevTools window title")
            devToolsWindow = win
        }
        devToolsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Show About window
    func showAboutWindow() {
        if aboutWindow == nil {
            let controller = NSHostingController(rootView: AboutView())
            let win = NSWindow(contentViewController: controller)
            win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            win.isReleasedWhenClosed = false
            win.center()
            win.setContentSize(NSSize(width: 520, height: 280))
            win.title = NSLocalizedString("About Ourin", comment: "About window title")
            aboutWindow = win
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let devToolsReload = Notification.Name("devToolsReload")
    static let fmoNeedsRefresh = Notification.Name("fmoNeedsRefresh")
}

private extension NSApplication {
    func presentAlert(style: NSAlert.Style, title: String, text: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
