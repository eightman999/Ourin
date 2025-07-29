import SwiftUI

@available(macOS 11.0, *)
struct DevToolsCommands: Commands {
    var body: some Commands {
        CommandMenu("DevTools") {
            Button("DevToolsを表示") { openDevTools() }
                .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }

    private func openDevTools() {
        if #available(macOS 13.0, *) {
            openWindow(id: "DevTools")
        } else {
            (NSApp.delegate as? AppDelegate)?.showDevTools()
        }
    }

    // `openWindow` is available from macOS 13.0. Keeping the property
    // unconditionally defined lets the compiler resolve the symbol when
    // building with a modern SDK while older macOS versions simply ignore it
    // at runtime via the availability check in `openDevTools()`.
    @available(macOS 13.0, *)
    @Environment(\.openWindow) private var openWindow
}
