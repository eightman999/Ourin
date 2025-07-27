import AppKit
import CoreGraphics

/// NSWindow から CGWindowID 列を生成するユーティリティ
enum WindowIDMapper {
    /// 複数ウィンドウの ID をカンマ区切りで取得
    static func ids(for windows: [NSWindow]) -> String {
        let ids = windows.map { String(CGWindowID($0.windowNumber)) }
        return ids.joined(separator: ",")
    }
}
