import SwiftUI
import AppKit

// SSP の右クリックメニューを模倣した UI。
// メニュー構成例は docs/RightClickMenuMockup.md を参照。

/// 右クリックメニュー UI の SwiftUI 実装（メニューバーエクストラ用）
@available(macOS 11.0, *)
struct RightClickMenu: View {
    private var ghostManager: GhostManager? {
        (NSApp.delegate as? AppDelegate)?.ghostManager
    }

    var body: some View {
        Group {
            // ゴースト切り替え
            ghostSubmenu

            // シェル切り替え
            shellSubmenu

            // バルーン切り替え
            balloonSubmenu

            // 着せ替え
            dressupSubmenu

            Divider()

            // 情報
            Button("情報(I)") {
                ghostManager?.handleMenuAction("menu_ghost_info")
            }

            // 話しかける
            Button("話しかける(T)") {
                ghostManager?.handleMenuAction("menu_communicate")
            }

            Divider()

            // 再読み込み
            Button("再読み込み(R)") {
                ghostManager?.handleMenuAction("menu_reload")
            }

            Button("NARを読み込む...") {
                selectAndLoadNAR()
            }

            Divider()

            Button("設定(O)") {
                ghostManager?.handleMenuAction("menu_settings")
            }

            Button("DevTools") {
                (NSApp.delegate as? AppDelegate)?.showDevTools()
            }

            Divider()

            Button("終了(Q)") { NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: - Ghost Submenu

    @ViewBuilder
    private var ghostSubmenu: some View {
        let ghosts = NarRegistry.shared.installedItems(ofType: "ghost").map(\.name).sorted()
        if !ghosts.isEmpty {
            Menu("ゴースト(G)") {
                ForEach(ghosts, id: \.self) { ghost in
                    let isCurrent = ghost == ghostManager?.ghostConfig?.name
                    Button {
                        ghostManager?.handleMenuAction("switch_ghost:\(percentEncode(ghost))")
                    } label: {
                        Text("\(isCurrent ? "● " : "")\(ghost)")
                    }
                }
            }
        }
    }

    // MARK: - Shell Submenu

    @ViewBuilder
    private var shellSubmenu: some View {
        if let manager = ghostManager {
            let shellRoot = manager.ghostURL.appendingPathComponent("shell", isDirectory: true)
            let shells = shellNames(in: shellRoot)
            if shells.count > 1 {
                Menu("シェル(S)") {
                    ForEach(shells, id: \.self) { shell in
                        let isCurrent = shell == manager.activeShellName
                        Button {
                            manager.handleMenuAction("switch_shell:\(percentEncode(shell))")
                        } label: {
                            Text("\(isCurrent ? "● " : "")\(shell)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Balloon Submenu

    @ViewBuilder
    private var balloonSubmenu: some View {
        let balloons = NarRegistry.shared.installedItems(ofType: "balloon").map(\.name).sorted()
        if !balloons.isEmpty {
            Menu("バルーン(B)") {
                ForEach(balloons, id: \.self) { balloon in
                    Button {
                        ghostManager?.handleMenuAction("switch_balloon:\(percentEncode(balloon))")
                    } label: {
                        Text(balloon)
                    }
                }
            }
        }
    }

    // MARK: - Dressup Submenu

    @ViewBuilder
    private var dressupSubmenu: some View {
        if let manager = ghostManager {
            let scope = manager.currentScope
            let entries = manager.dressupMenuEntries(for: scope)
            if !entries.isEmpty {
                Menu("着せ替え(D)") {
                    ForEach(entries, id: \.bindGroupID) { entry in
                        let enabled = manager.isDressupBindGroupEnabled(scope: scope, bindGroupID: entry.bindGroupID)
                        Button {
                            manager.toggleDressupBindGroup(scope: scope, bindGroupID: entry.bindGroupID)
                        } label: {
                            if let image = manager.dressupThumbnailImage(for: entry) {
                                Label {
                                    Text("\(enabled ? "✓ " : "")\(entry.category) / \(entry.part)")
                                } icon: {
                                    Image(nsImage: image)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                            } else {
                                Text("\(enabled ? "✓ " : "")\(entry.category) / \(entry.part)")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func selectAndLoadNAR() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "nar")].compactMap { $0 }
        panel.title = "NARファイルを選択"
        panel.message = "読み込むNARファイルを選択してください"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                NSApp.delegate?.application?(NSApp, openFiles: [url.path])
            }
        }
    }

    private func shellNames(in root: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()
    }

    private func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
