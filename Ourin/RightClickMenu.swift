import SwiftUI
import AppKit

// SSP の右クリックメニューを模倣したサンプル UI。
// メニュー構成例は docs/RightClickMenuMockup.md を参照。

/// 右クリックメニュー UI の SwiftUI 実装
@available(macOS 11.0, *)
struct RightClickMenu: View {
    private var ghostManager: GhostManager? {
        (NSApp.delegate as? AppDelegate)?.ghostManager
    }

    /// メニュー項目一覧を返す
    var body: some View {
        Group {
            Button("ゴースト情報") {
                ghostManager?.handleMenuAction("menu_ghost_info")
            }
            if let manager = ghostManager {
                let scope = manager.currentScope
                let entries = manager.dressupMenuEntries(for: scope)
                if !entries.isEmpty {
                    Menu("着せ替え") {
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
            Divider()
            Button("新しいNARを読み込む...") {
                selectAndLoadNAR()
            }
            Divider()
            Button("設定") {
                ghostManager?.handleMenuAction("menu_settings")
            }
            Button("DevTools を開く") {
                (NSApp.delegate as? AppDelegate)?.showDevTools()
            }
            Divider()
            Button("終了") { NSApplication.shared.terminate(nil) }
        }
    }

    /// NAR ファイルを選択して読み込む
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
                // AppDelegate に NAR インストール処理を依頼
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    // Use the existing installNar infrastructure via openFiles
                    NSApp.delegate?.application?(NSApp, openFiles: [url.path])
                }
            }
        }
    }
}
