import AppKit
import CoreGraphics

/// NSWindow から CGWindowID 列を生成するユーティリティ
enum WindowIDMapper {
    /// 複数ウィンドウの ID を取得する。Windows の HWND 列と同じくバイト値 1 区切り（ukadoc plugin-event: OnGhostBoot）。
    static func ids(for windows: [NSWindow]) -> String {
        ListDelimiter.join(windows.map { id(for: $0) })
    }

    /// 単一ウィンドウの CGWindowID を取得（存在しない場合は "0"）
    private static func id(for window: NSWindow) -> String {
        let wid = CGWindowID(window.windowNumber)
        if let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as NSArray?,
           info.count > 0 {
            return String(wid)
        }
        return "0"
    }
}
