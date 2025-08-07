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
    private var yayaAdapter: YayaAdapter?
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

    private func installNar(at url: URL) {
        do {
            let target = try narInstaller.install(fromNar: url)
            NSApp.presentAlert(style: .informational,
                               title: "Installed",
                               text: "Installed: \(url.lastPathComponent)")
            runGhost(at: target)
        } catch {
            NSApp.presentAlert(style: .critical,
                               title: "Install failed",
                               text: String(describing: error))
        }
    }

    private func runGhost(at root: URL) {
        let ghostRoot = root.appendingPathComponent("ghost/master", isDirectory: true)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: ghostRoot, includingPropertiesForKeys: nil) else { return }
        let dics = contents.filter { $0.pathExtension.lowercased() == "dic" }.map { $0.lastPathComponent }
        guard let adapter = YayaAdapter() else { return }
        yayaAdapter = adapter
        guard adapter.load(ghostRoot: ghostRoot, dics: dics) else { return }
        if let res = adapter.request(method: "GET", id: "OnBoot"), res.ok {
            if let script = res.value {
                NSApp.presentAlert(style: .informational, title: "OnBoot", text: script)
            }
        }
        adapter.unload()
        yayaAdapter = nil
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
    static let testScenarioStarted = Notification.Name("testScenarioStarted")
    static let testScenarioStopped = Notification.Name("testScenarioStopped")
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
