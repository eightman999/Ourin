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
            Button("設定") {}
            Button("終了") { NSApplication.shared.terminate(nil) }
        }
    }
}
