import SwiftUI
import AppKit

// SSP の右クリックメニューを模倣したサンプル UI。
// メニュー構成例は docs/RightClickMenuMockup.md を参照。

/// 右クリックメニュー UI の SwiftUI 実装
@available(macOS 11.0, *)
struct RightClickMenu: View {
    /// メニュー項目一覧を返す
    var body: some View {
        // 実際のメニュー構成はドキュメントのモックアップを元に仮実装
        Group {
            Button("ゴースト情報") {}
            Menu("ゴースト切替") {
                Button("ゴースト1") {}
                Button("ゴースト2") {}
            }
            Menu("シェル切替") {
                Button("シェル1") {}
                Button("シェル2") {}
            }
            Menu("バルーン切替") {
                Button("バルーン1") {}
            }
            Divider()
            Button("新しいNARを読み込む...") {
                selectAndLoadNAR()
            }
            Divider()
            Button("設定") {}
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
