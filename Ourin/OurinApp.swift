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
        // The right-click menu has moved to the menu bar.
        MenuBarExtra("Ourin") {
            RightClickMenu()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var fmo: FmoManager?
    var pluginRegistry: PluginRegistry?
    var headlineRegistry: HeadlineRegistry?
    var eventBridge: EventBridge?
    /// PLUGIN Event 配送用ディスパッチャ
    var pluginDispatcher: PluginEventDispatcher?

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 終了時に共有メモリとセマフォを開放
        fmo?.cleanup()
        pluginRegistry?.unloadAll()
        headlineRegistry?.unloadAll()
        eventBridge?.stop()
        // PLUGIN ディスパッチャ停止
        pluginDispatcher?.stop()
    }
}
