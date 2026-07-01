// SerikoTooltipController.swift
// currentghost.seriko.tooltip.scope(ID).textlist(<当たり判定>).text プロパティに基づき、
// 当たり判定領域に一定時間マウスが静止した際（OnMouseHover相当）のツールチップ表示を行う。
import AppKit

final class SerikoTooltipController {
    static let shared = SerikoTooltipController()

    private lazy var window: NSWindow = makeWindow()
    private lazy var label: NSTextField = makeLabel()

    private init() {}

    var isVisible: Bool { window.isVisible }

    /// scope/region に対応するツールチップテキストを screenPoint 付近に表示する。
    /// プロパティ未定義（空文字）の場合は非表示にする。
    func show(scope: Int, region: String, at screenPoint: NSPoint) {
        guard !region.isEmpty else { hide(); return }
        let key = "currentghost.seriko.tooltip.scope(\(scope)).textlist(\(region)).text"
        guard let text = PropertyManager.shared.get(key), !text.isEmpty else {
            hide()
            return
        }

        let padding: CGFloat = 6
        let maxWidth: CGFloat = 260
        let font = label.font ?? NSFont.systemFont(ofSize: 12)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        let width = ceil(bounding.width) + padding * 2
        let height = ceil(bounding.height) + padding * 2

        label.stringValue = text
        label.frame = NSRect(x: padding, y: padding, width: ceil(bounding.width), height: ceil(bounding.height))
        window.setContentSize(NSSize(width: width, height: height))
        // カーソルの少し右上に表示する（画面下端/右端をはみ出さないよう軽くクランプ）。
        var origin = NSPoint(x: screenPoint.x + 12, y: screenPoint.y + 12)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(screenPoint) }) ?? NSScreen.main {
            origin.x = min(origin.x, screen.frame.maxX - width)
            origin.y = min(origin.y, screen.frame.maxY - height)
        }
        window.setFrameOrigin(origin)
        if !window.isVisible {
            window.orderFront(nil)
        }
    }

    func hide() {
        guard window.isVisible else { return }
        window.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .popUpMenu
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(calibratedWhite: 1.0, alpha: 0.95).cgColor
        container.layer?.cornerRadius = 4
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(calibratedWhite: 0.6, alpha: 1.0).cgColor
        w.contentView = container
        return w
    }

    private func makeLabel() -> NSTextField {
        let lbl = NSTextField(labelWithString: "")
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.textColor = .black
        lbl.backgroundColor = .clear
        lbl.isBezeled = false
        lbl.isEditable = false
        lbl.lineBreakMode = .byWordWrapping
        lbl.maximumNumberOfLines = 0
        window.contentView?.addSubview(lbl)
        return lbl
    }
}
