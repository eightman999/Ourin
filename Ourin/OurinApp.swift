import SwiftUI
import AppKit
// FMO 機能を組み込み、起動時に初期化する

@main
struct OurinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var fmo: FmoManager?

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 終了時に共有メモリとセマフォを開放
        fmo?.cleanup()
    }
}
