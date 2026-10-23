import AppKit
import SwiftUI

@main
struct OurinInstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = InstallerModel()

    var body: some Scene {
        WindowGroup("Ourin インストーラー") {
            InstallerView()
                .environmentObject(model)
                .frame(width: 720, height: 500)
        }
        .commands {
            // ウインドウは 1 枚だけにする。
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM の実行ファイルとして直接起動しても通常のアプリとして前面に出す。
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.styleMask.remove(.resizable)
            window.center()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
