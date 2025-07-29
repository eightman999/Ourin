import SwiftUI
import AppKit
import ApplicationServices

// Plugin host
import Foundation
// FMO 機能を組み込み、起動時に初期化する

@main
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
        MenuBarExtra("Ourin") {
            RightClickMenu()
        }
        Commands {
            DevToolsCommands()
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
        app.reply(toOpenOrPrint: .success)
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "nar" {
            installNar(at: url)
        }
    }

    private func installNar(at url: URL) {
        do {
            try narInstaller.install(fromNar: url)
            NSApp.presentAlert(style: .informational,
                               title: "Installed",
                               text: "Installed: \(url.lastPathComponent)")
        } catch {
            NSApp.presentAlert(style: .critical,
                               title: "Install failed",
                               text: String(describing: error))
        }
    }
}

extension NSApplication {
    enum Reply { case success, failure }
    func reply(toOpenOrPrint reply: Reply) {
        switch reply {
        case .success: self.reply(toOpenOrPrint: .success)
        case .failure: self.reply(toOpenOrPrint: .failure)
        }
    }
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
