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
#if compiler(>=5.7)
        if #available(macOS 13.0, *) {
            DevToolsWindowOpener.shared?.open()
        } else {
            (NSApp.delegate as? AppDelegate)?.showDevTools()
        }
#else
        (NSApp.delegate as? AppDelegate)?.showDevTools()
#endif
    }
}

// MARK: - macOS13以降用のWindowOpenerを別スコープで定義
#if compiler(>=5.7)
@available(macOS 13.0, *)
private struct DevToolsWindowOpener: View {
    @Environment(\.openWindow) private var openWindow

    static var shared: Self? = {
        // Dummy View を生成して Environment を使わせる
        let opener = Self()
        return opener
    }()

    func open() {
        openWindow(id: "DevTools")
    }

    var body: some View {
        EmptyView()
    }
}
#endif
