// OurinNarInstallerSample/AppDelegate.swift
import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let installer = NarInstaller()

    func applicationDidFinishLaunching(_ notification: Notification) {}

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
            try installer.install(fromNar: url)
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
