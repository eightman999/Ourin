// InputMonitor.swift
import AppKit

final class InputMonitor {
    static let shared = InputMonitor()
    private init() {}

    private var local: Any?
    private var global: Any?
    private var handler: ((ShioriEvent)->Void)?

    func start(handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] ev in
            self?.dispatch(ev)
            return ev
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self] ev in
            self?.dispatch(ev)
        }
    }

    func stop() {
        if let l = local { NSEvent.removeMonitor(l); local = nil }
        if let g = global { NSEvent.removeMonitor(g); global = nil }
    }

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
            screenLoc = ev.locationInWindow // already in screen coords for global monitor
        }

        let id: String
        switch ev.type {
        case .keyDown: id = "OnKeyDown"
        case .keyUp: id = "OnKeyUp"
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: id = "OnMouseDown"
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: id = "OnMouseUp"
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: id = "OnMouseMove"
        case .scrollWheel: id = "OnMouseWheel"
        default: return
        }

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
        handler?(ShioriEvent(id: id, params: params))
    }
}
