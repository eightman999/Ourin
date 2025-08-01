// InputMonitor.swift
// キーボード・マウス入力を監視して SHIORI イベントへ変換する
import AppKit

final class InputMonitor {
    static let shared = InputMonitor()
    private init() {}

    private var local: Any?
    private var global: Any?
    private var handler: ((ShioriEvent)->Void)?

    /// 監視を開始し、イベント発生時にハンドラへ通知する
    func start(handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] ev in
            // マウスダウン・アップイベントの場合、UI要素上でのクリックか判定する
            if ev.type == .leftMouseDown || ev.type == .rightMouseDown || ev.type == .otherMouseDown ||
               ev.type == .leftMouseUp || ev.type == .rightMouseUp || ev.type == .otherMouseUp {
                if let window = ev.window {
                    // hitTestでクリック位置にUI要素があるかチェック
                    let hitView = window.contentView?.hitTest(ev.locationInWindow)
                    NSLog("[InputMonitor] Click at (%f, %f), hitView: %@", ev.locationInWindow.x, ev.locationInWindow.y, hitView?.description ?? "nil")
                    if hitView != nil {
                        // UI要素上のクリックなので、SHIORIイベントは送らずに通常のイベント処理に任せる
                        NSLog("[InputMonitor] UI element clicked, passing to SwiftUI")
                        return ev
                    }
                    NSLog("[InputMonitor] Background clicked, dispatching to SHIORI")
                }
            }

            // 背景クリック、またはマウスダウン以外のイベントは通常通りディスパッチする
            self?.dispatch(ev)
            return ev
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self] ev in
            self?.dispatch(ev)
        }
    }

    /// 監視を停止する
    func stop() {
        if let l = local { NSEvent.removeMonitor(l); local = nil }
        if let g = global { NSEvent.removeMonitor(g); global = nil }
    }

    /// NSEvent を SHIORI イベントへ変換してハンドラに渡す
    private func dispatch(_ ev: NSEvent) {
        let mod = ev.modifierFlags
        let modifiers = [
            mod.contains(.command) ? "Command" : nil,
            mod.contains(.option) ? "Option" : nil,
            mod.contains(.shift) ? "Shift" : nil,
            mod.contains(.control) ? "Control" : nil,
            mod.contains(.capsLock) ? "CapsLock" : nil,
            mod.contains(.function) ? "Function" : nil
        ].compactMap{$0}.joined(separator: "|")

        let loc = ev.locationInWindow
        let screenLoc: NSPoint
        if let w = ev.window {
            let p = w.convertToScreen(NSRect(origin: loc, size: .zero)).origin
            screenLoc = p
        } else {
            // グローバルモニタでは既にスクリーン座標が得られる
            screenLoc = ev.locationInWindow
        }

        // NSEvent の種類に応じてイベント ID を決定
        let id: EventID
        switch ev.type {
        case .keyDown: id = .OnKeyDown
        case .keyUp: id = .OnKeyUp
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: id = .OnMouseDown
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: id = .OnMouseUp
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: id = .OnMouseMove
        case .scrollWheel: id = .OnMouseWheel
        default: return
        }

        // SHIORI へ渡すパラメータを構築
        var params: [String:String] = [
            "screenX": String(Int(screenLoc.x)),
            "screenY": String(Int(screenLoc.y)),
            "modifiers": modifiers
        ]
        if ev.type == .keyDown || ev.type == .keyUp {
            params["keyCode"] = String(ev.keyCode)
            params["characters"] = ev.characters ?? ""
        }
        if ev.type == .scrollWheel {
            params["deltaX"] = String(Int(ev.scrollingDeltaX))
            params["deltaY"] = String(Int(ev.scrollingDeltaY))
        }
        // 構築したイベントをハンドラに通知
        handler?(ShioriEvent(id: id, params: params))
    }
}
