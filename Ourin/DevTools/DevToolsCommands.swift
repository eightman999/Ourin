import SwiftUI

@available(macOS 13.0, *)
struct ModernDevToolsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // View メニューにDevTools項目を追加
        CommandMenu("View") {
            Button("DevTools を表示") {
                openDevTools()
            }
            .keyboardShortcut("d", modifiers: [.command])
        }
        
        // Debug メニューを追加
        CommandMenu("Debug") {
            Button("リロード") {
                reloadDevTools()
            }
            .keyboardShortcut("r", modifiers: [.command])
            
            
            Button("診断情報をエクスポート") {
                exportDiagnostics()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            
            Divider()
            
            Button("プラグインを再読み込み") {
                reloadPlugins()
            }
            
            Button("外部サーバーを再起動") {
                restartExternalServers()
            }
        }
        
        // Help メニューにDevTools関連項目を追加
        CommandMenu("Help") {
            Button("DevTools ヘルプ") {
                openDevToolsHelp()
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
            
            Button("SHIORI 仕様書を開く") {
                openShioriSpecs()
            }
            
            Button("プラグイン開発ガイド") {
                openPluginGuide()
            }
        }
    }

    private func openDevTools() {
        openWindow(id: "DevTools")
    }
    
    private func reloadDevTools() {
        ResourceBridge.shared.invalidateAll()
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.pluginRegistry?.unloadAll()
            appDelegate.pluginRegistry?.discoverAndLoad()
        }
        
        NotificationCenter.default.post(name: .devToolsReload, object: nil)
    }
    
    
    private func exportDiagnostics() {
        let format = NSLocalizedString("診断情報は %@ にエクスポートされました", comment: "Diagnostics export message")
        let text = String(format: format, Date().description)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OurinDiagnostics.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func reloadPlugins() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.pluginRegistry?.unloadAll()
            appDelegate.pluginRegistry?.discoverAndLoad()
        }
    }
    
    private func restartExternalServers() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.externalServer?.stop()
            appDelegate.externalServer?.start()
        }
    }
    
    private func openDevToolsHelp() {
        if let url = URL(string: "https://github.com/eightman999/Ourin/wiki/DevTools") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openShioriSpecs() {
        let docsPath = Bundle.main.bundlePath.appending("/Contents/Resources/docs")
        if let url = URL(string: "file://\(docsPath)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openPluginGuide() {
        if let url = URL(string: "https://github.com/eightman999/Ourin/wiki/Plugin-Development") {
            NSWorkspace.shared.open(url)
        }
    }
}
