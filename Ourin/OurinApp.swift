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
    /// The currently running ghost's manager.
    var ghostManager: GhostManager?
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

        // ninix仕様に準拠した起動判定: shm_open("/ninix", O_RDWR, 0) で判定
        if FmoManager.isAnotherInstanceRunning(sharedName: "/ninix") {
            NSLog("Another baseware instance is already running. Terminating.")
            NSApplication.shared.terminate(nil)
            return
        }

        // 起動時に FMO を初期化。
        // ninixとの互換性のため "/ninix" という共有メモリ名を使用
        do {
            fmo = try FmoManager(mutexName: "/ninix_mutex", sharedName: "/ninix")
        } catch FmoError.alreadyRunning {
            // 判定をすり抜けた場合のフォールバック
            NSLog("Application already running (FMO). Retrying after short delay...")
            usleep(300_000)
            do {
                fmo = try FmoManager(mutexName: "/ninix_mutex", sharedName: "/ninix")
            } catch {
                NSLog("Application already running (FMO) after retry. Terminating.")
                NSApplication.shared.terminate(nil)
            }
        } catch {
            // 権限エラーなどの場合でも、他インスタンスが起動していなければ続行を試みる
            NSLog("FMO init failed: \(error)")
            NSLog("Continuing without FMO (single instance enforcement disabled)")
        }

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

        // プラグインを探索してロード
        let registry = PluginRegistry()
        registry.discoverAndLoad()
        pluginRegistry = registry
        // プラグイン読み込み後にディスパッチャを開始
        pluginDispatcher = PluginEventDispatcher(registry: registry)

        // HEADLINE モジュールも探索してロード
        let hRegistry = HeadlineRegistry()
        hRegistry.discoverAndLoad()
        headlineRegistry = hRegistry

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

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: .ourinWebHomeURLReceived, object: nil)
        // 終了時に共有メモリとセマフォを開放
        fmo?.cleanup()
        pluginRegistry?.unloadAll()
        headlineRegistry?.unloadAll()
        eventBridge?.stop()
        externalServer?.stop()
        // PLUGIN ディスパッチャ停止
        pluginDispatcher?.stop()
        // ゴーストをシャットダウン
        ghostManager?.shutdown()
        // 念のため残留プロセスを掃除
        ProcessKiller.killOtherOurinAndYaya()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let info = response.notification.request.content.userInfo
        guard (info["ourinTrayBalloon"] as? String) == "1" else { return }
        EventBridge.shared.notify(.OnTrayBalloonClick, params: [
            "Reference0": response.notification.request.identifier,
            "Reference1": (info["title"] as? String) ?? "",
            "Reference2": (info["message"] as? String) ?? ""
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
        if let url = Bundle.main.url(forResource: "emily4", withExtension: "nar") {
            NSLog("[installDefaultGhost] Found emily4.nar at: \(url.path)")
            installNar(at: url)
        } else {
            NSLog("[installDefaultGhost] Bundled emily4.nar not found")
            // If emily4.nar is not bundled, try to run emily4 if it's already installed
            if let ghost = NarRegistry.shared.installedItems(ofType: "ghost").first(where: { $0.name == "emily4" }) {
                NSLog("[installDefaultGhost] emily4 already installed, running it")
                runGhost(at: ghost.path)
            }
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

    private func runGhost(at root: URL) {
        NSLog("[runGhost] Starting ghost from: \(root.path)")
        // If a ghost is already running, shut it down first.
        if let existingManager = self.ghostManager {
            NSLog("[runGhost] Shutting down existing ghost")
            existingManager.shutdown()
            self.ghostManager = nil
        }

        // Create and start the new ghost manager.
        NSLog("[runGhost] Creating GhostManager for: \(root.path)")
        let newManager = GhostManager(ghostURL: root)
        self.ghostManager = newManager
        NSLog("[runGhost] Starting GhostManager")
        newManager.start()
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
