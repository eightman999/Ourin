import SwiftUI

@available(macOS 11.0, *)
struct DevToolsCommands: Commands {
    var body: some Commands {
        CommandMenu("DevTools") {
            Button("DevToolsを表示") {
                if #available(macOS 13.0, *) {
                    openWindow(id: "DevTools")
                } else {
                    (NSApp.delegate as? AppDelegate)?.showDevTools()
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }

    @available(macOS 13.0, *)
    @Environment(\.openWindow) private var openWindow
}
