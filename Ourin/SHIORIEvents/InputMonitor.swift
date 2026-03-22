// InputMonitor.swift
// キーボード・マウス入力を監視して SHIORI イベントへ変換する
import AppKit

final class InputMonitor {
    static let shared = InputMonitor()
    private init() {}

    private var local: Any?
    private var global: Any?
    private var handler: ((ShioriEvent)->Void)?

    // Track mouse down events to detect clicks
    private var mouseDownLocation: CGPoint?
    private var mouseDownTime: Date?
    private var mouseDownButton: NSEvent.EventType?
    private var lastClickLocation: CGPoint?
    private var lastClickTime: Date?
    private var lastClickButton: String?
    private var clickStreak: Int = 0
    private var gestureStartLocation: CGPoint?
    private var gestureLastLocation: CGPoint?
    private var dragStarted = false
    private var dragButton: String?
    private var isPointerInsideGhostArea = false
    private var hoverTimer: Timer?
    private var hoverParams: [String: String] = [:]

    /// 監視を開始し、イベント発生時にハンドラへ通知する
    func start(handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]) { [weak self] ev in
            guard let self = self else { return ev }
            self.updatePointerRegion(for: ev)

            // マウスダウン・アップイベントの場合、ゴースト/バルーンウィンドウかどうかを判定する
            if ev.type == .leftMouseDown || ev.type == .rightMouseDown || ev.type == .otherMouseDown ||
               ev.type == .leftMouseUp || ev.type == .rightMouseUp || ev.type == .otherMouseUp {
                if let window = ev.window {
                    let windowId = window.identifier?.rawValue ?? ""
                    NSLog("[InputMonitor] Click at (%f, %f) in window: %@", ev.locationInWindow.x, ev.locationInWindow.y, windowId)

                    // ゴーストキャラクターウィンドウまたはバルーンウィンドウの場合、SHIORIに送信する
                    if windowId.hasPrefix("GhostCharacterWindow") || windowId.hasPrefix("GhostBalloonWindow") {
                        NSLog("[InputMonitor] Ghost/Balloon window clicked, dispatching to SHIORI")

                        // Track mouse down for click detection
                        if ev.type == .leftMouseDown || ev.type == .rightMouseDown || ev.type == .otherMouseDown {
                            self.mouseDownLocation = ev.locationInWindow
                            self.mouseDownTime = Date()
                            self.mouseDownButton = ev.type
                            self.dragStarted = false
                            self.dragButton = self.mouseButtonName(for: ev)
                            if ev.type == .rightMouseDown {
                                self.gestureStartLocation = ev.locationInWindow
                                self.gestureLastLocation = ev.locationInWindow
                            }
                        }

                        // Detect click on mouse up
                        if ev.type == .leftMouseUp || ev.type == .rightMouseUp || ev.type == .otherMouseUp {
                            self.dispatchDragEndIfNeeded(ev)
                            if let downLoc = self.mouseDownLocation,
                               let downTime = self.mouseDownTime,
                               let downButton = self.mouseDownButton {
                                let upLoc = ev.locationInWindow
                                let distance = hypot(upLoc.x - downLoc.x, upLoc.y - downLoc.y)
                                let duration = Date().timeIntervalSince(downTime)

                                // Check if it's a click (small movement, short duration, matching button)
                                let isClick = distance < 5.0 && duration < 1.0 &&
                                    ((downButton == .leftMouseDown && ev.type == .leftMouseUp) ||
                                     (downButton == .rightMouseDown && ev.type == .rightMouseUp) ||
                                     (downButton == .otherMouseDown && ev.type == .otherMouseUp))

                                if isClick {
                                    NSLog("[InputMonitor] Click detected, dispatching OnMouseClick")
                                    self.dispatchClick(ev)
                                }

                                // Reset tracking
                                self.mouseDownLocation = nil
                                self.mouseDownTime = nil
                                self.mouseDownButton = nil
                                self.dragButton = nil

                                if ev.type == .rightMouseUp {
                                    self.dispatchGestureIfNeeded(ev)
                                    self.gestureStartLocation = nil
                                    self.gestureLastLocation = nil
                                }
                            }
                        }

                        if ev.type == .rightMouseDragged {
                            self.gestureLastLocation = ev.locationInWindow
                        }
                        if ev.type == .leftMouseDragged || ev.type == .rightMouseDragged || ev.type == .otherMouseDragged {
                            self.dispatchDragStartIfNeeded(ev)
                        }

                        self.dispatch(ev)
                        return ev
                    }

                    // その他のウィンドウの場合、hitTestでクリック位置にUI要素があるかチェック
                    let hitView = window.contentView?.hitTest(ev.locationInWindow)
                    if hitView != nil {
                        // UI要素上のクリックなので、SHIORIイベントは送らずに通常のイベント処理に任せる
                        NSLog("[InputMonitor] UI element clicked, passing to SwiftUI")
                        return ev
                    }
                    NSLog("[InputMonitor] Background clicked, dispatching to SHIORI")
                }
            }

            // 背景クリック、またはマウスダウン以外のイベントは通常通りディスパッチする
            if ev.type == .leftMouseDragged || ev.type == .rightMouseDragged || ev.type == .otherMouseDragged {
                self.dispatchDragStartIfNeeded(ev)
            }
            if ev.type == .leftMouseUp || ev.type == .rightMouseUp || ev.type == .otherMouseUp {
                self.dispatchDragEndIfNeeded(ev)
            }
            self.dispatch(ev)
            return ev
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .scrollWheel]) { [weak self] ev in
            self?.updatePointerRegion(for: ev)
            self?.dispatch(ev)
        }
    }

    /// 監視を停止する
    func stop() {
        if let l = local { NSEvent.removeMonitor(l); local = nil }
        if let g = global { NSEvent.removeMonitor(g); global = nil }
        hoverTimer?.invalidate()
        hoverTimer = nil
        isPointerInsideGhostArea = false
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
        if ev.type == .otherMouseDown || ev.type == .otherMouseUp || ev.type == .otherMouseDragged {
            let button = mouseButtonName(for: ev)
            params["button"] = button
            params["buttonNumber"] = String(ev.buttonNumber)
        }
        // 構築したイベントをハンドラに通知
        handler?(ShioriEvent(id: id, params: params))

        if ev.type == .otherMouseDown {
            handler?(ShioriEvent(id: .OnMouseDownEx, params: params))
        } else if ev.type == .otherMouseUp {
            handler?(ShioriEvent(id: .OnMouseUpEx, params: params))
        }

        if ev.type == .mouseMoved || ev.type == .leftMouseDragged || ev.type == .rightMouseDragged || ev.type == .otherMouseDragged {
            scheduleHover(with: params)
        } else if ev.type == .leftMouseDown || ev.type == .rightMouseDown || ev.type == .otherMouseDown {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    /// Dispatch OnMouseClick event
    private func dispatchClick(_ ev: NSEvent) {
        let params = mouseParams(for: ev, includeButton: true)
        let button = params["button"] ?? "left"
        let isExButton = isExtendedButton(button)

        handler?(ShioriEvent(id: .OnMouseClick, params: params))
        if isExButton {
            handler?(ShioriEvent(id: .OnMouseClickEx, params: params))
        }

        if let previousTime = lastClickTime,
           let previousLoc = lastClickLocation,
           let previousButton = lastClickButton {
            let current = mouseScreenLocation(for: ev)
            let elapsed = Date().timeIntervalSince(previousTime)
            let distance = hypot(current.x - previousLoc.x, current.y - previousLoc.y)
            if elapsed <= 0.35 && distance < 5.0 && previousButton == button {
                clickStreak += 1
            } else {
                clickStreak = 1
            }
        } else {
            clickStreak = 1
        }

        if clickStreak >= 2 {
            if isExButton {
                handler?(ShioriEvent(id: .OnMouseDoubleClickEx, params: params))
            } else {
                handler?(ShioriEvent(id: .OnMouseDoubleClick, params: params))
            }
        }
        if clickStreak >= 3 {
            var multi = params
            multi["count"] = String(clickStreak)
            if isExButton {
                handler?(ShioriEvent(id: .OnMouseMultipleClickEx, params: multi))
            } else {
                handler?(ShioriEvent(id: .OnMouseMultipleClick, params: multi))
            }
        }
        lastClickTime = Date()
        lastClickLocation = mouseScreenLocation(for: ev)
        lastClickButton = button
    }

    private func dispatchGestureIfNeeded(_ ev: NSEvent) {
        guard let start = gestureStartLocation, let end = gestureLastLocation else { return }
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) >= 20 else { return }

        let direction: String
        if abs(dx) > abs(dy) {
            direction = dx >= 0 ? "right" : "left"
        } else {
            direction = dy >= 0 ? "up" : "down"
        }
        handler?(ShioriEvent(id: .OnMouseGesture, params: [
            "Reference0": direction,
            "Reference1": "\(Int(start.x)),\(Int(start.y))",
            "Reference2": "\(Int(end.x)),\(Int(end.y))"
        ]))
    }

    private func updatePointerRegion(for ev: NSEvent) {
        let inside = isGhostOrBalloonWindow(ev.window)
        guard inside != isPointerInsideGhostArea else { return }
        isPointerInsideGhostArea = inside

        if inside {
            let params = mouseParams(for: ev, includeButton: false)
            handler?(ShioriEvent(id: .OnMouseEnter, params: params))
            handler?(ShioriEvent(id: .OnMouseEnterAll, params: params))
            scheduleHover(with: params)
        } else {
            hoverTimer?.invalidate()
            hoverTimer = nil
            let params = mouseParams(for: ev, includeButton: false)
            handler?(ShioriEvent(id: .OnMouseLeave, params: params))
            handler?(ShioriEvent(id: .OnMouseLeaveAll, params: params))
        }
    }

    private func dispatchDragStartIfNeeded(_ ev: NSEvent) {
        guard !dragStarted else { return }
        guard isGhostOrBalloonWindow(ev.window) else { return }
        dragStarted = true
        var params = mouseParams(for: ev, includeButton: true)
        if let dragButton {
            params["button"] = dragButton
        }
        handler?(ShioriEvent(id: .OnMouseDragStart, params: params))
    }

    private func dispatchDragEndIfNeeded(_ ev: NSEvent) {
        guard dragStarted else { return }
        dragStarted = false
        var params = mouseParams(for: ev, includeButton: true)
        if let dragButton {
            params["button"] = dragButton
        }
        handler?(ShioriEvent(id: .OnMouseDragEnd, params: params))
    }

    private func scheduleHover(with params: [String: String]) {
        guard isPointerInsideGhostArea else { return }
        hoverParams = params
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            guard let self, self.isPointerInsideGhostArea else { return }
            self.handler?(ShioriEvent(id: .OnMouseHover, params: self.hoverParams))
        }
    }

    private func mouseScreenLocation(for ev: NSEvent) -> NSPoint {
        let loc = ev.locationInWindow
        if let w = ev.window {
            return w.convertToScreen(NSRect(origin: loc, size: .zero)).origin
        }
        return loc
    }

    private func mouseButtonName(for ev: NSEvent) -> String {
        switch ev.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return "left"
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return "right"
        case .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return buttonNameFromNumber(ev.buttonNumber)
        default:
            return "left"
        }
    }

    private func buttonNameFromNumber(_ number: Int) -> String {
        switch number {
        case 2: return "wheel"
        case 3: return "x1"
        case 4: return "x2"
        default: return "button\(number)"
        }
    }

    private func isExtendedButton(_ button: String) -> Bool {
        button != "left" && button != "right"
    }

    private func mouseParams(for ev: NSEvent, includeButton: Bool) -> [String: String] {
        let mod = ev.modifierFlags
        let modifiers = [
            mod.contains(.command) ? "Command" : nil,
            mod.contains(.option) ? "Option" : nil,
            mod.contains(.shift) ? "Shift" : nil,
            mod.contains(.control) ? "Control" : nil,
            mod.contains(.capsLock) ? "CapsLock" : nil,
            mod.contains(.function) ? "Function" : nil
        ].compactMap { $0 }.joined(separator: "|")

        let screen = mouseScreenLocation(for: ev)
        var params: [String: String] = [
            "screenX": String(Int(screen.x)),
            "screenY": String(Int(screen.y)),
            "modifiers": modifiers
        ]
        // 可能ならコリジョン領域名を付与（キャラクターウィンドウ内のみ）
        if let id = ev.window?.identifier?.rawValue, id.hasPrefix("GhostCharacterWindow_") {
            let parts = id.split(separator: "_")
            if let last = parts.last, let scope = Int(last) {
                let point = ev.locationInWindow
                if let gm = (NSApp.delegate as? AppDelegate)?.ghostManager,
                   let region = gm.collisionRegionName(at: point, scope: scope), !region.isEmpty {
                    params["region"] = region
                }
            }
        }
        if includeButton {
            params["button"] = mouseButtonName(for: ev)
            if ev.type == .otherMouseDown || ev.type == .otherMouseUp || ev.type == .otherMouseDragged {
                params["buttonNumber"] = String(ev.buttonNumber)
            }
        }
        return params
    }

    private func isGhostOrBalloonWindow(_ window: NSWindow?) -> Bool {
        guard let id = window?.identifier?.rawValue else { return false }
        return id.hasPrefix("GhostCharacterWindow") || id.hasPrefix("GhostBalloonWindow")
    }
}
