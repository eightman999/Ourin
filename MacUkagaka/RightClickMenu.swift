import SwiftUI
import AppKit

struct RightClickMenu: View {
    var body: some View {
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
