import SwiftUI

struct DevToolsCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("DevTools") {
            Button("DevToolsを表示") {
                openWindow(id: "DevTools")
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }
}
