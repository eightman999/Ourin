import SwiftUI
import AppKit
import ApplicationServices

// Plugin host
import Foundation
// FMO 機能を組み込み、起動時に初期化する

struct OurinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
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
}

class AppDelegate: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 起動時に FMO を初期化。既に起動していれば終了する
        do {
            fmo = try FmoManager()
        } catch FmoError.alreadyRunning {
            NSLog("Application already running")
            NSApplication.shared.terminate(nil)
        } catch {
            NSLog("FMO init failed: \(error)")
        }

        // Register handler for x-ukagaka-link scheme early
        WebHandler.shared.register()

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

        // Start SHIORI event bridge
        let bridge = EventBridge.shared
        bridge.start()
        eventBridge = bridge

        // 外部 SSTP サーバを起動
        let ext = OurinExternalServer()
        ext.start()
        externalServer = ext

        // ユーザーが選択したゴースト、またはデフォルトのゴーストを起動
        let startupGhostKey = "OurinStartupGhost"
        if let ghostName = UserDefaults.standard.string(forKey: startupGhostKey), !ghostName.isEmpty {
            self.runNamedGhost(name: ghostName)
        } else {
            self.installDefaultGhost()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        for url in urls where url.pathExtension.lowercased() == "nar" {
            installNar(at: url)
        }
    }

    /// Install bundled emily4.nar and run it if present
    func installDefaultGhost() {
        if let url = Bundle.main.url(forResource: "emily4", withExtension: "nar") {
            installNar(at: url)
        } else {
            NSLog("Bundled emily4.nar not found")
        }
    }

    func runNamedGhost(name: String) {
        guard let ghost = NarRegistry.shared.installedItems(ofType: "ghost").first(where: { $0.name == name }) else {
            NSLog("Could not find ghost named \(name)")
            DispatchQueue.main.async {
                NSApp.presentAlert(style: .critical,
                                   title: "Ghost not found",
                                   text: "The ghost '\(name)' could not be found. It may have been moved or deleted.")
            }
            return
        }
        runGhost(at: ghost.path)
    }

    private func installNar(at url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let target = try self.narInstaller.install(fromNar: url)
                DispatchQueue.main.async {
                    NSApp.presentAlert(style: .informational,
                                       title: "Installed",
                                       text: "Installed: \(url.lastPathComponent)")
                    self.runGhost(at: target)
                }
            } catch {
                DispatchQueue.main.async {
                    NSApp.presentAlert(style: .critical,
                                       title: "Install failed",
                                       text: String(describing: error))
                }
            }
        }
    }

    private func runGhost(at root: URL) {
        // If a ghost is already running, shut it down first.
        if let existingManager = self.ghostManager {
            existingManager.shutdown()
            self.ghostManager = nil
        }

        // Create and start the new ghost manager.
        let newManager = GhostManager(ghostURL: root)
        self.ghostManager = newManager
        newManager.start()
    }

    /// Show DevTools window on macOS < 13
    func showDevTools() {
        if devToolsWindow == nil {
            let controller = NSHostingController(rootView: DevToolsView())
            let win = NSWindow(contentViewController: controller)
            win.setContentSize(NSSize(width: 700, height: 500))
            win.title = "DevTools"
            devToolsWindow = win
        }
        devToolsWindow?.makeKeyAndOrderFront(nil)
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
