import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Window Setup and Position Control

extension GhostManager {
    private struct WindowCommandStorage {
        static var stickyIgnoreScopes: [ObjectIdentifier: Set<Int>] = [:]
        static var asyncMoveWorkItems: [ObjectIdentifier: [Int: DispatchWorkItem]] = [:]
        static var asyncMoveAnimationTimers: [ObjectIdentifier: [Int: Timer]] = [:]
        static var lastOwnerDrawMenuPoint: NSPoint?
        static var lastOwnerDrawMenuTime: TimeInterval?
    }

    private var stickyIgnoreScopes: Set<Int> {
        get { WindowCommandStorage.stickyIgnoreScopes[ObjectIdentifier(self)] ?? [] }
        set { WindowCommandStorage.stickyIgnoreScopes[ObjectIdentifier(self)] = newValue }
    }

    private var asyncMoveWorkItems: [Int: DispatchWorkItem] {
        get { WindowCommandStorage.asyncMoveWorkItems[ObjectIdentifier(self)] ?? [:] }
        set { WindowCommandStorage.asyncMoveWorkItems[ObjectIdentifier(self)] = newValue }
    }

    private var asyncMoveAnimationTimers: [Int: Timer] {
        get { WindowCommandStorage.asyncMoveAnimationTimers[ObjectIdentifier(self)] ?? [:] }
        set { WindowCommandStorage.asyncMoveAnimationTimers[ObjectIdentifier(self)] = newValue }
    }

    private struct MoveCommandSpec {
        var x: Int?
        var y: Int?
        var time: Int = 0
        var method: String = ""
        var scopeID: Int?
        var base: String?
        var baseOffset: String?
        var moveOffset: String?
        var ignoreStickyWindow: Bool = false
        var wait: Bool = false
    }

    private struct ResizeCommandSpec {
        var width: Int?
        var height: Int?
        var time: Int = 0
        var scopeID: Int?
    }

    // Note: This extension uses the following properties declared in the main GhostManager class:
    // - stickyWindowRelationships
    // - stickyWindowOffsets
    // - windowZOrderScopes


    // MARK: - Window Setup

    func setupWindows() {
        Log.debug("[GhostManager] Setting up windows")
        // よく使う scope 0(本体)/1(相方) のみ先行生成する。
        // 追加キャラ（\p[N] / scope>=2）は参照時に ensureCharacterWindow で遅延生成し、
        // 多数キャラ・複数ゴーストでも起動コストとメモリを抑える（大量表示対応）。
        for scope in 0..<2 {
            setupCharacterWindow(for: scope)
        }
    }

    /// 指定スコープのキャラウィンドウが未生成なら生成して返す（遅延生成・大量キャラ対応）。
    /// NSWindow を扱うため必ずメインスレッドで呼ぶこと。冪等。
    @discardableResult
    func ensureCharacterWindow(for scope: Int) -> NSWindow? {
        if let existing = characterWindows[scope] { return existing }
        guard scope >= 0 else { return nil }
        Log.debug("[GhostManager] Lazily creating character window for scope \(scope)")
        setupCharacterWindow(for: scope)
        return characterWindows[scope]
    }

    func setupCharacterWindow(for scope: Int) {
        let dragDropHandler: (ShioriEvent) -> Void = { [weak self] event in
            guard let self else {
                EventBridge.shared.dispatch(event)
                return
            }

            // URLドロップは対象キャラクターのゴーストだけへ問い合わせ、
            // 応答が無い場合に限って標準のダウンロード生命周期へ進む。
            if event.id == .OnURLDrop {
                self.handleURLDropEvent(event)
                return
            }

            EventBridge.shared.dispatch(event)
        }

        let vm = CharacterViewModel()
        vm.alignment = desktopAlignment(for: scope)
        characterViewModels[scope] = vm

        let characterView = CharacterView(viewModel: vm, scopeID: scope, onDragDropEvent: dragDropHandler)
        let hostingController = NSViewController()
        hostingController.view = CharacterHitTestingHostingView(rootView: characterView, viewModel: vm)

        let window = NSWindow(contentViewController: hostingController)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask = [.borderless]
        window.ignoresMouseEvents = false
        // Ghost windows: above normal windows but below balloons
        // Use .statusBar (25) so ghosts are above normal apps but below popUpMenu (balloons)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // CharacterHitTestingHostingView limits window dragging to visible surface pixels.
        window.isMovableByWindowBackground = false
        window.isMovable = true

        // Position character windows
        let characterWidth: CGFloat = 300
        let characterHeight: CGFloat = 400

        // Try to restore saved position first
        var didRestore = false
        if let savedX = resourceManager.getCharDefaultLeft(scope: scope),
           let savedY = resourceManager.getCharDefaultTop(scope: scope) {
            window.setFrame(.init(x: CGFloat(savedX), y: CGFloat(savedY), width: characterWidth, height: characterHeight), display: true)
            Log.debug("[GhostManager] Scope \(scope) window restored to saved position (\(savedX), \(savedY))")
            didRestore = true
        }

        // Otherwise use default positions
        if !didRestore {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let margin: CGFloat = 10 // Small margin between characters
                // visibleFrame.minY は下側 Dock を除いた可視領域の下端、すなわち Dock の上端。
                // ウィンドウの origin.y は下辺なので、ここに合わせると起動時に Dock の直上へ置ける。
                let baseY = screenFrame.minY

                // Calculate positions: all characters line up from right side
                // Scope 0 (sakura/master) is rightmost
                // Scope 1+ (kero/partners) are to the left of scope 0
                let baseX = screenFrame.maxX - characterWidth - 20
                let x = baseX - (CGFloat(scope) * (characterWidth + margin))

                window.setFrame(.init(x: x, y: baseY, width: characterWidth, height: characterHeight), display: true)
                Log.debug("[GhostManager] Scope \(scope) window at default position (\(x), \(baseY))")
            } else {
                // Fallback positioning
                let x: CGFloat = 200 + (CGFloat(scope) * 320)
                window.setFrame(.init(x: x, y: 200, width: characterWidth, height: characterHeight), display: true)
            }
        }

        window.identifier = NSUserInterfaceItemIdentifier("GhostCharacterWindow_\(scope)")

        // サーフェス画像がロードされるまで、全スコープの窓を表示しない。
        // 起動時に scope 1 を先に表示すると、ベース画像がまだ無い窓へ SERIKO の
        // オーバーレイだけが描画され、目元などの顔パーツが単体で浮いて見える。
        // updateSurface が実画像を設定した時だけ orderFront する。
        window.orderOut(nil)
        Log.debug("[GhostManager] Scope \(scope) window created hidden until a surface is loaded")

        // Keep window visible and prevent auto-hiding
        window.isReleasedWhenClosed = false

        characterWindows[scope] = window
        enforceDesktopAlignment(for: scope)
        if let snapshot = DisplayObserver.snapshot(for: window) {
            displayHandoverStates[scope] = snapshot
        }

        // Reapply a previously requested z-order when a lazily-created scope appears.
        if let scopes = windowZOrderScopes {
            applyWindowZOrder(scopes: scopes)
        }

        // Track window movement/resize
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidChangeFrame(_:)), name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidChangeFrame(_:)), name: NSWindow.didResizeNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidMiniaturize(_:)), name: NSWindow.didMiniaturizeNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidDeminiaturize(_:)), name: NSWindow.didDeminiaturizeNotification, object: window)

        // Additional scopes can be created lazily after the SHIORI runtime is
        // already registered.  Their initial monitor state must still be
        // observable as OnDisplayHandover(init).
        if eventToken != nil {
            emitInitialDisplayHandover(for: scope)
        }
    }

    /// Emit the startup form of OnDisplayHandover once for each character
    /// window.  The event is targeted to this ghost because Reference1 is the
    /// scope number within the ghost, not a global window identifier.
    func emitInitialDisplayHandoverEvents() {
        for scope in characterWindows.keys.sorted() {
            emitInitialDisplayHandover(for: scope)
        }
    }

    private func emitInitialDisplayHandover(for scope: Int) {
        guard eventToken != nil,
              !sentInitialDisplayHandoverScopes.contains(scope),
              let window = characterWindows[scope],
              let snapshot = DisplayObserver.snapshot(for: window) else {
            return
        }
        displayHandoverStates[scope] = snapshot
        let sent = EventBridge.shared.notify(
            .OnDisplayHandover,
            refs: [
                "state": "init",
                "scopeID": String(scope),
                "previousDisplay": "",
                "currentDisplay": snapshot.wireValue
            ],
            to: self,
            ignoreResponseScript: true
        )
        if sent {
            sentInitialDisplayHandoverScopes.insert(scope)
        }
    }

    /// Detect a real monitor transition for a character window.  Resize and
    /// desktop-coordinate changes on the same monitor do not count as a
    /// handover; the display ID is the authoritative transition key.
    func updateDisplayHandover(for window: NSWindow, scope: Int) {
        guard let current = DisplayObserver.snapshot(for: window) else { return }
        let previous = displayHandoverStates[scope]
        displayHandoverStates[scope] = current
        guard let previous,
              previous.displayID != current.displayID,
              eventToken != nil else {
            return
        }
        _ = EventBridge.shared.request(
            .OnDisplayHandover,
            refs: [
                "state": "update",
                "scopeID": String(scope),
                "previousDisplay": previous.wireValue,
                "currentDisplay": current.wireValue
            ],
            to: self
        )
    }

    // MARK: - Right-Click Menu

    func setupRightClickMenu() {
        InputMonitor.shared.rightClickMenuHandler = { [weak self] screenPoint in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.showOwnerDrawMenu(at: screenPoint)
            }
        }
    }

    func showOwnerDrawMenu(at screenPoint: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastTime = WindowCommandStorage.lastOwnerDrawMenuTime,
           let lastPoint = WindowCommandStorage.lastOwnerDrawMenuPoint,
           now - lastTime < 0.35,
           hypot(screenPoint.x - lastPoint.x, screenPoint.y - lastPoint.y) < 24 {
            return
        }
        WindowCommandStorage.lastOwnerDrawMenuTime = now
        WindowCommandStorage.lastOwnerDrawMenuPoint = screenPoint

        let bridge = ResourceBridge.shared
        let shellBase = ghostURL.appendingPathComponent("shell/\(activeShellName)", isDirectory: true)
        let config = bridge.ownerDrawMenuConfig(base: shellBase)
        var items = bridge.menuItems()

        if items.isEmpty {
            items = defaultMenuItems()
        }
        appendPluginMenu(to: &items)

        OwnerDrawMenuCoordinator.shared.showMenu(at: screenPoint, config: config, items: items) { [weak self] action in
            self?.handleMenuAction(action)
        }
    }

    private func appendPluginMenu(to items: inout [OwnerDrawMenuItem]) {
        guard let registry = AppDelegate.resolve()?.pluginRegistry else { return }
        let entries = registry.pluginMenuEntries()
        guard !entries.isEmpty else { return }

        let pluginItems = entries.map { entry in
            var item = OwnerDrawMenuItem(type: .button(action: entry.actionIdentifier), caption: entry.title)
            item.enabled = entry.canDispatchRequests
            return item
        }
        items.append(OwnerDrawMenuItem(type: .submenu(items: pluginItems, action: nil), caption: "プラグイン(P)"))
    }

    private func defaultMenuItems() -> [OwnerDrawMenuItem] {
        var items: [OwnerDrawMenuItem] = []

        let ghosts = NarRegistry.shared.installedItems(ofType: "ghost").map(\.name).sorted()
        if !ghosts.isEmpty {
            let ghostItems = ghosts.map { name in
                let safe = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? name
                return OwnerDrawMenuItem(type: .button(action: "switch_ghost:\(safe)"), caption: name)
            }
            items.append(OwnerDrawMenuItem(type: .submenu(items: ghostItems, action: nil), caption: "ゴースト(G)"))
        }

        let shellRoot = ghostURL.appendingPathComponent("shell", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: shellRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let shells = entries.filter(\.hasDirectoryPath).map(\.lastPathComponent).sorted()
            if shells.count > 1 {
                let shellItems = shells.map { name in
                    let safe = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? name
                    return OwnerDrawMenuItem(type: .button(action: "switch_shell:\(safe)"), caption: name)
                }
                items.append(OwnerDrawMenuItem(type: .submenu(items: shellItems, action: nil), caption: "シェル(S)"))
            }
        }

        let balloons = NarRegistry.shared.installedItems(ofType: "balloon").map(\.name).sorted()
        if !balloons.isEmpty {
            let balloonItems = balloons.map { name in
                let safe = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? name
                return OwnerDrawMenuItem(type: .button(action: "switch_balloon:\(safe)"), caption: name)
            }
            items.append(OwnerDrawMenuItem(type: .submenu(items: balloonItems, action: nil), caption: "バルーン(B)"))
        }

        let scope = currentScope
        let dressupEntries = dressupMenuEntries(for: scope)
        if !dressupEntries.isEmpty {
            let dressupItems = dressupEntries.map { entry in
                let enabled = isDressupBindGroupEnabled(scope: scope, bindGroupID: entry.bindGroupID)
                let prefix = enabled ? "✓ " : ""
                return OwnerDrawMenuItem(type: .button(action: "dressup_bindgroup:\(scope):\(entry.bindGroupID)"), caption: "\(prefix)\(entry.category) / \(entry.part)")
            }
            items.append(OwnerDrawMenuItem(type: .submenu(items: dressupItems, action: nil), caption: "着せ替え(D)"))
        }

        items.append(OwnerDrawMenuItem(type: .separator, caption: ""))
        items.append(OwnerDrawMenuItem(type: .button(action: "menu_ghost_info"), caption: "情報(I)"))
        items.append(OwnerDrawMenuItem(type: .button(action: "menu_communicate"), caption: "話しかける(T)"))
        items.append(OwnerDrawMenuItem(type: .separator, caption: ""))
        items.append(OwnerDrawMenuItem(type: .button(action: "menu_reload"), caption: "再読み込み(R)"))
        items.append(OwnerDrawMenuItem(type: .button(action: "menu_settings"), caption: "設定(O)"))
        items.append(OwnerDrawMenuItem(type: .separator, caption: ""))
        items.append(OwnerDrawMenuItem(type: .button(action: "menu_quit"), caption: "終了(Q)"))

        return items
    }

    // MARK: - Window Position and Display Control

    /// Move window to back (behind other windows)
    func moveWindowToBack(scope: Int) {
        Log.debug("[GhostManager] Moving scope \(scope) window to back")
        DispatchQueue.main.async {
            if let window = self.characterWindows[scope] {
                guard self.characterWindowHasLoadedSurface(window) else {
                    window.orderOut(nil)
                    return
                }
                window.orderBack(nil)
                window.level = .normal
                Log.info("[GhostManager] Moved scope \(scope) to background")
            }
        }
    }

    @objc func characterWindowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        let scope = characterWindows.first(where: { $0.value === window })?.key
        let reason = scope.flatMap { pendingWindowStateReasons.removeValue(forKey: $0) } ?? "system"
        EventBridge.shared.notify(.OnWindowStateMinimize, refs: ["reason": reason, "windowID": id])
    }

    @objc func characterWindowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        let scope = characterWindows.first(where: { $0.value === window })?.key
        let reason = scope.flatMap { pendingWindowStateReasons.removeValue(forKey: $0) } ?? "system"
        EventBridge.shared.notify(.OnWindowStateRestore, refs: ["reason": reason, "windowID": id])
    }
    
    /// Move window to front (above other windows)
    func moveWindowToFront(scope: Int) {
        Log.debug("[GhostManager] Moving scope \(scope) window to front")
        DispatchQueue.main.async {
            if let window = self.characterWindows[scope] {
                guard self.orderCharacterWindowIfLoaded(window) else { return }
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
                Log.info("[GhostManager] Moved scope \(scope) to foreground")
            }
        }
    }
    
    /// \4 - 相方キャラクターから離れる方向へ水平移動する（UKADOC）
    func moveAwayFromPartner(scope: Int) {
        DispatchQueue.main.async {
            guard let window = self.characterWindows[scope],
                  let partner = self.partnerWindow(for: scope) else { return }
            let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            let step: CGFloat = 120
            var frame = window.frame
            // 相方より左に居るなら更に左へ、右に居るなら更に右へ
            if frame.midX <= partner.frame.midX {
                frame.origin.x = max(screen.minX, frame.origin.x - step)
            } else {
                frame.origin.x = min(screen.maxX - frame.width, frame.origin.x + step)
            }
            window.setFrame(frame, display: true, animate: true)
            Log.info("[GhostManager] \\4 moved scope \(scope) away from partner")
        }
    }

    /// \5 - 相方キャラクターと接触する距離まで水平移動する（UKADOC）
    func moveTowardPartner(scope: Int) {
        DispatchQueue.main.async {
            guard let window = self.characterWindows[scope],
                  let partner = self.partnerWindow(for: scope) else { return }
            var frame = window.frame
            // 相方の左右どちら側に居るかを保ち、辺が接する位置へ移動する
            if frame.midX <= partner.frame.midX {
                frame.origin.x = partner.frame.minX - frame.width
            } else {
                frame.origin.x = partner.frame.maxX
            }
            window.setFrame(frame, display: true, animate: true)
            Log.info("[GhostManager] \\5 moved scope \(scope) adjacent to partner")
        }
    }

    /// 相方キャラクターのウィンドウ（scope 0 ↔ 1、その他のスコープは scope 0 を相方とみなす）
    private func partnerWindow(for scope: Int) -> NSWindow? {
        let partnerScope = (scope == 0) ? 1 : 0
        return characterWindows[partnerScope]
    }

    /// Synchronous window move
    func moveWindow(scope: Int, x: Int, y: Int, time: Int, method: String, ignoreStickyWindow: Bool = false) {
        Log.debug("[GhostManager] Moving scope \(scope) to (\(x), \(y)) over \(time)ms with method '\(method)'")
        cancelMoveWindowAsync(scope: scope)
        DispatchQueue.main.async {
            guard let window = self.characterWindows[scope] else {
                Log.info("[GhostManager] No window found for scope \(scope)")
                return
            }

            let targetFrame = NSRect(x: CGFloat(x), y: CGFloat(y), width: window.frame.width, height: window.frame.height)
            if ignoreStickyWindow {
                var ignored = self.stickyIgnoreScopes
                ignored.insert(scope)
                self.stickyIgnoreScopes = ignored
            }

            if time > 0 {
                // Animated move
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = TimeInterval(time) / 1000.0
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                }, completionHandler: {
                    if ignoreStickyWindow {
                        var ignored = self.stickyIgnoreScopes
                        ignored.remove(scope)
                        self.stickyIgnoreScopes = ignored
                    }
                    Log.debug("[GhostManager] Window move animation completed for scope \(scope)")
                })
            } else {
                // Instant move
                window.setFrame(targetFrame, display: true)
                if ignoreStickyWindow {
                    var ignored = self.stickyIgnoreScopes
                    ignored.remove(scope)
                    self.stickyIgnoreScopes = ignored
                }
            }

            // Save new position
            self.resourceManager.setCharDefaultLeft(scope: scope, value: x)
            self.resourceManager.setCharDefaultTop(scope: scope, value: y)
        }
    }
    
    /// Asynchronous window move (non-blocking)
    func moveWindowAsync(scope: Int, x: Int, y: Int, time: Int, method: String, ignoreStickyWindow: Bool = false) {
        Log.debug("[GhostManager] Moving scope \(scope) asynchronously to (\(x), \(y))")
        cancelMoveWindowAsync(scope: scope)

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard workItem?.isCancelled == false else { return }
            guard let window = self.characterWindows[scope] else {
                Log.info("[GhostManager] No window found for async move scope \(scope)")
                return
            }

            let targetFrame = NSRect(
                x: CGFloat(x),
                y: CGFloat(y),
                width: window.frame.width,
                height: window.frame.height
            )

            // Keep the legacy immediate path identical to synchronous move.
            // For timed moves we use an explicit frame timer so cancellation can
            // stop an already-running move at its current position.
            if time <= 0 {
                self.moveWindow(
                    scope: scope,
                    x: x,
                    y: y,
                    time: 0,
                    method: method,
                    ignoreStickyWindow: ignoreStickyWindow
                )
            } else {
                self.startAsyncMoveAnimation(
                    scope: scope,
                    from: window.frame,
                    to: targetFrame,
                    time: time,
                    method: method,
                    ignoreStickyWindow: ignoreStickyWindow
                )
                self.resourceManager.setCharDefaultLeft(scope: scope, value: x)
                self.resourceManager.setCharDefaultTop(scope: scope, value: y)
            }
            var pending = self.asyncMoveWorkItems
            pending.removeValue(forKey: scope)
            self.asyncMoveWorkItems = pending
        }
        var pending = asyncMoveWorkItems
        pending[scope] = workItem
        asyncMoveWorkItems = pending

        guard let workItem else { return }
        DispatchQueue.main.async(execute: workItem)
    }

    private func startAsyncMoveAnimation(
        scope: Int,
        from startFrame: NSRect,
        to targetFrame: NSRect,
        time: Int,
        method: String,
        ignoreStickyWindow: Bool
    ) {
        guard characterWindows[scope] != nil else { return }

        if ignoreStickyWindow {
            var ignored = stickyIgnoreScopes
            ignored.insert(scope)
            stickyIgnoreScopes = ignored
        }

        let duration = max(0.001, TimeInterval(time) / 1000.0)
        let startDate = Date()
        let timerKey = scope
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let window = self.characterWindows[scope] else {
                timer.invalidate()
                return
            }

            let progress = min(1.0, max(0.0, Date().timeIntervalSince(startDate) / duration))
            let easedProgress = Self.moveAnimationProgress(progress, method: method)
            var frame = startFrame
            frame.origin.x = startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * easedProgress
            frame.origin.y = startFrame.origin.y + (targetFrame.origin.y - startFrame.origin.y) * easedProgress
            window.setFrame(frame, display: true)

            guard progress >= 1.0 else { return }
            timer.invalidate()
            var timers = self.asyncMoveAnimationTimers
            timers.removeValue(forKey: timerKey)
            self.asyncMoveAnimationTimers = timers
            if ignoreStickyWindow {
                var ignored = self.stickyIgnoreScopes
                ignored.remove(scope)
                self.stickyIgnoreScopes = ignored
            }
            Log.debug("[GhostManager] Async window move animation completed for scope \(scope)")
        }

        var timers = asyncMoveAnimationTimers
        timers[timerKey] = timer
        asyncMoveAnimationTimers = timers
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func moveAnimationProgress(_ progress: Double, method: String) -> Double {
        let clamped = min(1.0, max(0.0, progress))
        switch method.lowercased() {
        case "linear":
            return clamped
        case "easein", "ease-in":
            return clamped * clamped
        case "easeout", "ease-out":
            return 1.0 - (1.0 - clamped) * (1.0 - clamped)
        default:
            // Match NSAnimationContext's ease-in/ease-out feel used by the
            // synchronous move path.
            return clamped * clamped * (3.0 - 2.0 * clamped)
        }
    }

    func cancelMoveWindowAsync(scope: Int?) {
        var pending = asyncMoveWorkItems
        if let scope {
            pending[scope]?.cancel()
            pending.removeValue(forKey: scope)
            let wasAnimating = asyncMoveAnimationTimers[scope] != nil
            asyncMoveAnimationTimers[scope]?.invalidate()
            if wasAnimating, let window = characterWindows[scope] {
                resourceManager.setCharDefaultLeft(scope: scope, value: Int(window.frame.origin.x))
                resourceManager.setCharDefaultTop(scope: scope, value: Int(window.frame.origin.y))
            }
            var timers = asyncMoveAnimationTimers
            timers.removeValue(forKey: scope)
            asyncMoveAnimationTimers = timers
            var ignored = stickyIgnoreScopes
            ignored.remove(scope)
            stickyIgnoreScopes = ignored
            Log.debug("[GhostManager] Canceled async move for scope \(scope)")
        } else {
            for (_, workItem) in pending {
                workItem.cancel()
            }
            pending.removeAll()
            for (scope, timer) in asyncMoveAnimationTimers {
                timer.invalidate()
                if let window = characterWindows[scope] {
                    resourceManager.setCharDefaultLeft(scope: scope, value: Int(window.frame.origin.x))
                    resourceManager.setCharDefaultTop(scope: scope, value: Int(window.frame.origin.y))
                }
            }
            var timers = asyncMoveAnimationTimers
            timers.removeAll()
            asyncMoveAnimationTimers = timers
            var ignored = stickyIgnoreScopes
            ignored.removeAll()
            stickyIgnoreScopes = ignored
            Log.debug("[GhostManager] Canceled all async move commands")
        }
        asyncMoveWorkItems = pending
    }

    func executeMoveCommand(args: [String], async: Bool) {
        guard let spec = parseMoveCommand(args: args) else { return }
        let scopeID = spec.scopeID ?? currentScope
        guard let (x, y) = resolveMoveTarget(scope: scopeID, spec: spec) else { return }

        if async {
            moveWindowAsync(scope: scopeID, x: x, y: y, time: spec.time, method: spec.method, ignoreStickyWindow: spec.ignoreStickyWindow)
        } else {
            moveWindow(scope: scopeID, x: x, y: y, time: spec.time, method: spec.method, ignoreStickyWindow: spec.ignoreStickyWindow)
            if spec.wait && spec.time > 0 {
                playbackQueue.append(.wait(TimeInterval(spec.time) / 1000.0))
            }
        }
    }

    func resizeWindow(scope: Int, width: Int?, height: Int?, time: Int) {
        DispatchQueue.main.async {
            guard let window = self.characterWindows[scope] else {
                Log.info("[GhostManager] No window found for resize scope \(scope)")
                return
            }
            let newWidth = max(1, width ?? Int(window.frame.width))
            let newHeight = max(1, height ?? Int(window.frame.height))
            let targetFrame = NSRect(
                x: window.frame.origin.x,
                y: window.frame.origin.y,
                width: CGFloat(newWidth),
                height: CGFloat(newHeight)
            )
            if time > 0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = TimeInterval(time) / 1000.0
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                }
            } else {
                window.setFrame(targetFrame, display: true)
            }
            Log.debug("[GhostManager] Resized scope \(scope) to \(newWidth)x\(newHeight)")
        }
    }

    func executeResizeCommand(args: [String]) {
        guard let spec = parseResizeCommand(args: args) else { return }
        let scopeID = spec.scopeID ?? currentScope
        resizeWindow(scope: scopeID, width: spec.width, height: spec.height, time: spec.time)
    }

    private func parseMoveCommand(args: [String]) -> MoveCommandSpec? {
        var spec = MoveCommandSpec()
        guard !args.isEmpty else { return nil }

        if args.first?.lowercased() == "cancel" {
            spec.method = "cancel"
            if args.count >= 2 {
                spec.scopeID = Int(args[1])
            }
            return spec
        }

        if args.contains(where: { $0.hasPrefix("--") }) {
            let parsed = parseLongOptions(args)
            for (key, value) in parsed.named {
                switch key.lowercased() {
                case "x": spec.x = Int(value)
                case "y": spec.y = Int(value)
                case "time": spec.time = Int(value) ?? 0
                case "base": spec.base = value
                case "base-offset": spec.baseOffset = value
                case "move-offset": spec.moveOffset = value
                case "method": spec.method = value
                case "scope", "scopeid": spec.scopeID = Int(value)
                case "option":
                    if value.lowercased() == "ignore-sticky-window" { spec.ignoreStickyWindow = true }
                case "wait":
                    // A truthy wait value or presence of wait flag implies waiting
                    spec.wait = parseWaitFlag(parsed.named, fallback: parsed.positional.first)
                default: break
                }
            }
            if !spec.wait {
                spec.wait = parseWaitFlag(parsed.named, fallback: parsed.positional.first)
            }
            return spec
        }

        guard args.count >= 2,
              let xAxis = parseLegacyMoveAxis(args[0]),
              let yAxis = parseLegacyMoveAxis(args[1]) else { return nil }
        // Legacy SSP syntax allows "fix" for either axis to retain its
        // current coordinate. Keep nil here so resolveMoveTarget can use the
        // current frame instead of rejecting the whole command.
        spec.x = xAxis.value
        spec.y = yAxis.value
        spec.time = args.count >= 3 ? (Int(args[2]) ?? 0) : 0
        spec.method = args.count >= 4 ? args[3] : ""
        spec.scopeID = args.count >= 5 ? Int(args[4]) : nil
        // Allow a bare wait token in positional form
        if args.map({ $0.lowercased() }).contains(where: { $0 == "wait" || $0 == "--wait" || $0 == "true" }) {
            spec.wait = true
        }
        return spec
    }

    private func parseResizeCommand(args: [String]) -> ResizeCommandSpec? {
        var spec = ResizeCommandSpec()
        guard !args.isEmpty else { return nil }

        if args.contains(where: { $0.hasPrefix("--") }) {
            for arg in args where arg.hasPrefix("--") {
                let parts = arg.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let key = parts[0].lowercased()
                let value = parts[1]
                switch key {
                case "width", "w":
                    spec.width = Int(value)
                case "height", "h":
                    spec.height = Int(value)
                case "time":
                    spec.time = Int(value) ?? 0
                case "scope", "scopeid":
                    spec.scopeID = Int(value)
                default:
                    break
                }
            }
            return spec.width != nil || spec.height != nil ? spec : nil
        }

        guard let width = Int(args[0]) else { return nil }
        spec.width = width
        if args.count >= 2 {
            spec.height = Int(args[1])
        }
        if args.count >= 3 {
            spec.time = Int(args[2]) ?? 0
        }
        if args.count >= 4 {
            spec.scopeID = Int(args[3])
        }
        return spec
    }

    private func resolveMoveTarget(scope: Int, spec: MoveCommandSpec) -> (Int, Int)? {
        guard let window = characterWindows[scope] else { return nil }
        let currentFrame = window.frame

        if spec.method == "cancel" {
            cancelMoveWindowAsync(scope: spec.scopeID ?? scope)
            return nil
        }

        let baseRect = resolveMoveBaseRect(scope: scope, spec: spec) ?? currentFrame
        let baseAnchorPoint = resolveAnchorPoint(token: spec.baseOffset, rect: baseRect) ?? CGPoint(x: baseRect.origin.x, y: baseRect.origin.y)
        let moveAnchorPoint = resolveAnchorPoint(token: spec.moveOffset, rect: currentFrame) ?? CGPoint(x: 0, y: 0)

        if spec.base != nil {
            let targetX = spec.x.map {
                Int(baseAnchorPoint.x + CGFloat($0) - moveAnchorPoint.x)
            } ?? Int(currentFrame.origin.x)
            let targetY = spec.y.map {
                Int(baseAnchorPoint.y + CGFloat($0) - moveAnchorPoint.y)
            } ?? Int(currentFrame.origin.y)
            return (targetX, targetY)
        }

        return (spec.x ?? Int(currentFrame.origin.x), spec.y ?? Int(currentFrame.origin.y))
    }

    private func resolveMoveBaseRect(scope: Int, spec: MoveCommandSpec) -> CGRect? {
        guard let base = spec.base?.lowercased() else { return nil }
        switch base {
        case "screen":
            return NSScreen.main?.visibleFrame
        case "window", "current":
            return characterWindows[scope]?.frame
        default:
            if let value = Int(base) {
                return characterWindows[value]?.frame
            }
            if base.hasPrefix("scope"), let value = Int(base.replacingOccurrences(of: "scope", with: "")) {
                return characterWindows[value]?.frame
            }
            return nil
        }
    }

    private func resolveAnchorPoint(token: String?, rect: CGRect) -> CGPoint? {
        guard let token = token?.lowercased() else { return nil }
        let parts = token.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let horizontal = parts[0]
        let vertical = parts[1]

        let x: CGFloat
        switch horizontal {
        case "left": x = rect.minX
        case "center", "middle": x = rect.midX
        case "right": x = rect.maxX
        default: return nil
        }

        let y: CGFloat
        switch vertical {
        case "top": y = rect.maxY
        case "center", "middle": y = rect.midY
        case "bottom": y = rect.minY
        default: return nil
        }

        return CGPoint(x: x, y: y)
    }

    private func parseLongOptions(_ args: [String]) -> (named: [String: String], positional: [String]) {
        var named: [String: String] = [:]
        var positional: [String] = []
        for arg in args {
            guard arg.hasPrefix("--") else {
                positional.append(arg)
                continue
            }
            let body = String(arg.dropFirst(2))
            let parts = body.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                named[parts[0].lowercased()] = parts[1]
            } else {
                named[parts[0].lowercased()] = "true"
            }
        }
        return (named, positional)
    }

    private func parseWaitFlag(_ named: [String: String], fallback: String?) -> Bool {
        if let wait = named["wait"]?.lowercased() {
            return wait == "1" || wait == "true" || wait == "yes"
        }
        guard let fallback = fallback?.lowercased() else { return false }
        return fallback == "wait" || fallback == "--wait" || fallback == "true"
    }

    private func parseLegacyMoveAxis(_ token: String) -> (value: Int?, fixed: Bool)? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized.lowercased() == "fix" {
            return (nil, true)
        }
        guard let value = Int(normalized) else { return nil }
        return (value, false)
    }

    func executeSetScalingCommand(args: [String], enqueueWaitAtFront: Bool = false) {
        guard args.count >= 3 else { return }
        let params = Array(args.dropFirst(2))
        let parsed = parseLongOptions(params)

        let xPercent: Double?
        let yPercent: Double?
        let timeMs: Double
        let wait: Bool

        if !parsed.named.isEmpty {
            xPercent = Double(parsed.named["x"] ?? parsed.named["scaling"] ?? parsed.positional.first ?? "")
            yPercent = Double(parsed.named["y"] ?? parsed.positional.dropFirst().first ?? "")
            timeMs = Double(parsed.named["time"] ?? parsed.positional.dropFirst(2).first ?? "0") ?? 0
            wait = parseWaitFlag(parsed.named, fallback: parsed.positional.dropFirst(3).first)
        } else {
            xPercent = Double(params[0])
            yPercent = params.count >= 2 ? Double(params[1]) : nil
            timeMs = params.count >= 3 ? (Double(params[2]) ?? 0) : 0
            wait = params.count >= 4 ? parseWaitFlag([:], fallback: params[3]) : false
        }

        guard let xPercent else { return }
        let targetScaleX = xPercent / 100.0
        let targetScaleY = (yPercent ?? xPercent) / 100.0
        let scope = currentScope
        let animationKey = "scaling:\(scope)"

        if Thread.isMainThread {
            animateUserScaling(
                scope: scope,
                targetX: targetScaleX,
                targetY: targetScaleY,
                duration: timeMs / 1000.0
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.animateUserScaling(
                    scope: scope,
                    targetX: targetScaleX,
                    targetY: targetScaleY,
                    duration: timeMs / 1000.0
                )
            }
        }

        if wait && timeMs > 0 {
            let waitUnit: GhostManager.PlaybackUnit = .waitForVisualEffect(animationKey)
            if enqueueWaitAtFront {
                playbackQueue.insert(waitUnit, at: 0)
            } else {
                playbackQueue.append(waitUnit)
            }
        }
    }

    func executeSetAlphaCommand(args: [String], enqueueWaitAtFront: Bool = false) {
        guard args.count >= 3 else { return }
        let params = Array(args.dropFirst(2))
        let parsed = parseLongOptions(params)

        let alphaPercent: Double?
        let timeMs: Double
        let wait: Bool

        if !parsed.named.isEmpty {
            alphaPercent = Double(parsed.named["value"] ?? parsed.named["alpha"] ?? parsed.positional.first ?? "")
            timeMs = Double(parsed.named["time"] ?? parsed.positional.dropFirst().first ?? "0") ?? 0
            wait = parseWaitFlag(parsed.named, fallback: parsed.positional.dropFirst(2).first)
        } else {
            alphaPercent = Double(params[0])
            timeMs = params.count >= 2 ? (Double(params[1]) ?? 0) : 0
            wait = params.count >= 3 ? parseWaitFlag([:], fallback: params[2]) : false
        }

        guard let alphaPercent else { return }
        let scope = currentScope

        // UKADOC: negative values leave the current alpha unchanged and only
        // request a redraw.  Do not clamp them to zero (which would make the
        // character disappear).
        if alphaPercent < 0 {
            let redraw = { [weak self] in
                guard let self, let viewModel = self.characterViewModels[scope] else { return }
                viewModel.objectWillChange.send()
                Log.debug("[GhostManager] Redrew scope (scope) without changing alpha")
            }
            if Thread.isMainThread {
                redraw()
            } else {
                DispatchQueue.main.async(execute: redraw)
            }
            return
        }

        let targetAlpha = min(max(alphaPercent / 100.0, 0.0), 1.0)
        let animationKey = "alpha:\(scope)"

        if Thread.isMainThread {
            animateCharacterAlpha(
                scope: scope,
                target: targetAlpha,
                duration: timeMs / 1000.0
            )
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.animateCharacterAlpha(
                    scope: scope,
                    target: targetAlpha,
                    duration: timeMs / 1000.0
                )
            }
        }

        if wait && timeMs > 0 {
            let waitUnit: GhostManager.PlaybackUnit = .waitForVisualEffect(animationKey)
            if enqueueWaitAtFront {
                playbackQueue.insert(waitUnit, at: 0)
            } else {
                playbackQueue.append(waitUnit)
            }
        }
    }

    /// `set,scaling` の変化時間を SwiftUI の View 更新へ実際に反映する。
    /// `NSAnimationContext` は `@Published` の Double 代入を補間しないため、
    /// メイン RunLoop 上で値そのものを更新する。イベントは最終値に到達した時だけ発火する。
    private func animateUserScaling(scope: Int, targetX: Double, targetY: Double, duration: TimeInterval) {
        let key = "scaling:\(scope)"
        cancelVisualEffectAnimation(key: key)
        guard let viewModel = characterViewModels[scope] else { return }
        guard duration > 0 else {
            setUserScaling(scope: scope, x: targetX, y: targetY)
            return
        }

        let startX = viewModel.userScaleX
        let startY = viewModel.userScaleY
        let startBalloonX = balloonViewModels[scope]?.scaleX
        let startBalloonY = balloonViewModels[scope]?.scaleY
        let startDate = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, self.characterViewModels[scope] != nil else {
                timer.invalidate()
                return
            }
            let progress = min(1.0, max(0.0, Date().timeIntervalSince(startDate) / duration))
            let eased = Self.easeInOut(progress)
            let x = startX + (targetX - startX) * eased
            let y = startY + (targetY - startY) * eased
            let finished = progress >= 1.0
            self.setUserScaling(
                scope: scope,
                x: finished ? targetX : x,
                y: finished ? targetY : y,
                emitEvent: finished,
                eventBeforeXPercent: finished ? startX * 100.0 : nil,
                eventBeforeYPercent: finished ? startY * 100.0 : nil,
                eventBeforeBalloonX: finished ? startBalloonX : nil,
                eventBeforeBalloonY: finished ? startBalloonY : nil
            )
            if finished {
                timer.invalidate()
                self.visualEffectAnimationTimers.removeValue(forKey: key)
            }
        }
        visualEffectAnimationTimers[key] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// `set,alpha` の時間変化を実値へ反映する。透明度はSHIORIイベントを持たないため、
    /// タイマー各フレームで ViewModel を更新し、最後のフレームで目標値を厳密に設定する。
    private func animateCharacterAlpha(scope: Int, target: Double, duration: TimeInterval) {
        let key = "alpha:\(scope)"
        cancelVisualEffectAnimation(key: key)
        guard let viewModel = characterViewModels[scope] else { return }
        guard duration > 0 else {
            viewModel.alpha = target
            return
        }

        let start = viewModel.alpha
        let startDate = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let viewModel = self.characterViewModels[scope] else {
                timer.invalidate()
                return
            }
            let progress = min(1.0, max(0.0, Date().timeIntervalSince(startDate) / duration))
            let eased = Self.easeInOut(progress)
            viewModel.alpha = progress >= 1.0 ? target : start + (target - start) * eased
            if progress >= 1.0 {
                timer.invalidate()
                self.visualEffectAnimationTimers.removeValue(forKey: key)
            }
        }
        visualEffectAnimationTimers[key] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelVisualEffectAnimation(key: String) {
        visualEffectAnimationTimers[key]?.invalidate()
        visualEffectAnimationTimers.removeValue(forKey: key)
    }

    private static func easeInOut(_ progress: Double) -> Double {
        let clamped = min(1.0, max(0.0, progress))
        return clamped * clamped * (3.0 - 2.0 * clamped)
    }

    private func parseScopeTokenList(_ tokens: [String]) -> [Int] {
        var result: [Int] = []
        for token in tokens {
            let lowered = token.lowercased()
            if lowered == "current" {
                result.append(currentScope)
                continue
            }
            if lowered == "all" {
                result.append(contentsOf: characterWindows.keys.sorted())
                continue
            }
            let split = token.split { [",", ";", "|", "/"].contains($0) }.map(String.init)
            for part in split {
                if let id = Int(part.trimmingCharacters(in: .whitespaces)) {
                    result.append(id)
                }
            }
        }
        var deduped: [Int] = []
        for id in result where !deduped.contains(id) {
            deduped.append(id)
        }
        return deduped
    }

    func executeSetZOrderCommand(args: [String]) {
        guard args.count >= 3 else { return }
        let tokens = Array(args.dropFirst(2))
        let parsed = parseLongOptions(tokens)
        let targetTokens = parsed.named["order"]?.split(separator: ",").map(String.init) ?? tokens
        let scopes = parseScopeTokenList(targetTokens)
        guard !scopes.isEmpty else { return }
        setWindowZOrder(scopes: scopes)
    }

    func executeSetStickyWindowCommand(args: [String]) {
        guard args.count >= 3 else { return }
        let tokens = Array(args.dropFirst(2))
        let parsed = parseLongOptions(tokens)
        var groups: [[Int]] = []

        if let groupSpec = parsed.named["group"] {
            let rawGroups = groupSpec.split(separator: "|").map(String.init)
            for raw in rawGroups {
                let ids = parseScopeTokenList([raw])
                if ids.count >= 2 { groups.append(ids) }
            }
        } else {
            let ids = parseScopeTokenList(tokens)
            if ids.count >= 2 { groups.append(ids) }
        }

        guard !groups.isEmpty else { return }
        resetStickyWindow()
        for group in groups {
            let master = group[0]
            let followers = Array(group.dropFirst())
            setStickyWindow(masterScope: master, followerScopes: followers)
        }
    }
    
    /// Set window position for specific scope
    func setWindowPosition(x: Int, y: Int, scopeID: Int) {
        Log.debug("[GhostManager] Setting window position for scope \(scopeID) to (\(x), \(y))")
        DispatchQueue.main.async {
            guard let window = self.characterWindows[scopeID] else {
                Log.info("[GhostManager] No window found for scope \(scopeID)")
                return
            }
            
            let newFrame = NSRect(x: CGFloat(x), y: CGFloat(y), width: window.frame.width, height: window.frame.height)
            window.setFrame(newFrame, display: true)
            
            // Lock window position (prevent user dragging)
            window.isMovable = false
            
            // Save position
            self.resourceManager.setCharDefaultLeft(scope: scopeID, value: x)
            self.resourceManager.setCharDefaultTop(scope: scopeID, value: y)
            
            Log.info("[GhostManager] Scope \(scopeID) position locked to (\(x), \(y))")
        }
    }
    
    /// Reset window position to default (allow user movement)
    func resetWindowPosition() {
        Log.debug("[GhostManager] Resetting window positions")
        DispatchQueue.main.async {
            for (scope, window) in self.characterWindows {
                // Unlock window movement
                window.isMovable = true
                
                // Restore default position if available
                let savedX = self.resourceManager.getCharDefaultLeft(scope: scope)
                let savedY = self.resourceManager.getCharDefaultTop(scope: scope)

                if let x = savedX, let y = savedY, x != 0 || y != 0 {
                    let newFrame = NSRect(x: CGFloat(x), y: CGFloat(y),
                                        width: window.frame.width, height: window.frame.height)
                    window.setFrame(newFrame, display: true)
                }
                
                Log.info("[GhostManager] Scope \(scope) position unlocked")
            }
        }
    }
    
    /// Set Z-order (window layering)
    func setWindowZOrder(scopes: [Int]) {
        Log.debug("[GhostManager] Setting Z-order: \(scopes)")
        DispatchQueue.main.async {
            self.windowZOrderScopes = scopes
            self.applyWindowZOrder(scopes: scopes)
            Log.info("[GhostManager] Z-order set successfully")
        }
    }

    private func applyWindowZOrder(scopes: [Int]) {
        // Order windows from back to front based on scopes array.
        for (index, scope) in scopes.enumerated() {
            guard let window = characterWindows[scope] else { continue }
            guard characterWindowHasLoadedSurface(window) else {
                window.orderOut(nil)
                continue
            }
            if index == scopes.count - 1 {
                _ = orderCharacterWindowIfLoaded(window)
            } else if let nextWindow = characterWindows[scopes[index + 1]] {
                if characterWindowHasLoadedSurface(nextWindow) {
                    window.order(.below, relativeTo: nextWindow.windowNumber)
                } else {
                    _ = orderCharacterWindowIfLoaded(window)
                }
            }
        }
    }
    
    /// Reset Z-order to default
    func resetWindowZOrder() {
        Log.debug("[GhostManager] Resetting Z-order to default")
        DispatchQueue.main.async {
            self.windowZOrderScopes = nil
            // Restore default floating window level for all
            for (scope, window) in self.characterWindows {
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
                _ = self.orderCharacterWindowIfLoaded(window)
                Log.info("[GhostManager] Scope \(scope) Z-order reset")
            }
        }
    }
    
    /// Set sticky window (window follows another window)
    func setStickyWindow(masterScope: Int, followerScopes: [Int]) {
        Log.debug("[GhostManager] Setting sticky windows: \(followerScopes) follow scope \(masterScope)")
        DispatchQueue.main.async {
            // Store relationships
            self.stickyWindowRelationships[masterScope] = Set(followerScopes)
            self.captureStickyWindowOffsets(masterScope: masterScope)
            
            // Add observer for master window movement
            if let masterWindow = self.characterWindows[masterScope] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.stickyMasterWindowMoved(_:)),
                    name: NSWindow.didMoveNotification,
                    object: masterWindow
                )
                Log.info("[GhostManager] Sticky window relationships established")
            }
        }
    }
    
    @objc func stickyMasterWindowMoved(_ notification: Notification) {
        guard let masterWindow = notification.object as? NSWindow,
              let masterScope = characterWindows.first(where: { $0.value == masterWindow })?.key,
              let followers = stickyWindowRelationships[masterScope] else {
            return
        }

        if stickyIgnoreScopes.contains(masterScope) {
            return
        }
        
        let masterFrame = masterWindow.frame
        
        // Move all follower windows using the relative positions captured when the
        // sticky relationship was established. A missing offset means that the
        // follower did not have a window yet; do not invent a position for it.
        for followerScope in followers {
            guard let followerWindow = characterWindows[followerScope],
                  let offset = stickyWindowOffsets[masterScope]?[followerScope] else { continue }
            let origin = Self.stickyFollowerOrigin(masterOrigin: masterFrame.origin, offset: offset)
            var newFrame = followerWindow.frame
            newFrame.origin = origin
            followerWindow.setFrame(newFrame, display: true)
        }
    }

    private func captureStickyWindowOffsets(masterScope: Int) {
        guard let masterWindow = characterWindows[masterScope] else {
            stickyWindowOffsets[masterScope] = [:]
            return
        }

        let masterOrigin = masterWindow.frame.origin
        stickyWindowOffsets[masterScope] = Dictionary(
            uniqueKeysWithValues: (stickyWindowRelationships[masterScope] ?? []).compactMap { followerScope in
                guard let followerWindow = characterWindows[followerScope] else { return nil }
                return (followerScope, Self.stickyOffset(masterOrigin: masterOrigin, followerOrigin: followerWindow.frame.origin))
            }
        )
    }

    static func stickyOffset(masterOrigin: CGPoint, followerOrigin: CGPoint) -> CGPoint {
        CGPoint(x: followerOrigin.x - masterOrigin.x, y: followerOrigin.y - masterOrigin.y)
    }

    static func stickyFollowerOrigin(masterOrigin: CGPoint, offset: CGPoint) -> CGPoint {
        CGPoint(x: masterOrigin.x + offset.x, y: masterOrigin.y + offset.y)
    }
    
    /// Reset sticky window relationships
    func resetStickyWindow() {
        Log.debug("[GhostManager] Resetting sticky window relationships")
        DispatchQueue.main.async {
            // Remove all observers
            for window in self.characterWindows.values {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didMoveNotification,
                    object: window
                )
            }
            
            // Clear relationships
            self.stickyWindowRelationships.removeAll()
            self.stickyWindowOffsets.removeAll()
            
            Log.info("[GhostManager] All sticky window relationships removed")
        }
    }
    
    /// Reset all window positions to default
    func executeResetWindowPos() {
        Log.debug("[GhostManager] Executing window position reset")

        // SSP互換: 位置初期化メニュー相当の操作では先にイベントをGETで発火し、
        // 応答スクリプトが返らない場合だけ標準の位置リセットを実行する。
        // EventBridge.request は未登録ゴースト／204応答を false として返すため、
        // イベント処理が利用できない場合も従来どおり既定処理へフォールバックする。
        guard !EventBridge.shared.request(.OnResetWindowPos) else { return }

        DispatchQueue.main.async {
            // Reset each window to its default/saved position
            for (scope, window) in self.characterWindows {
                // Get saved position or use default
                let savedX = self.resourceManager.getCharDefaultLeft(scope: scope)
                let savedY = self.resourceManager.getCharDefaultTop(scope: scope)

                if let x = savedX, let y = savedY, x != 0 || y != 0 {
                    let newFrame = NSRect(
                        x: CGFloat(x),
                        y: CGFloat(y),
                        width: window.frame.width,
                        height: window.frame.height
                    )
                    window.setFrame(newFrame, display: true)
                } else {
                    // Use default positions (scope-based)
                    self.positionWindowAtDefault(scope: scope, window: window)
                }
                
                // Unlock window
                window.isMovable = true
            }
            
            Log.info("[GhostManager] All window positions reset")
        }
    }
    
    /// Position window at default location based on scope
    func positionWindowAtDefault(scope: Int, window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowWidth = window.frame.width
        let windowHeight = window.frame.height
        
        // Default positions based on scope
        let x: CGFloat
        let y: CGFloat
        
        switch scope {
        case 0: // Master at right-center
            x = screenFrame.maxX - windowWidth - 100
            y = screenFrame.midY - windowHeight / 2
        case 1: // Partner at left-center
            x = screenFrame.minX + 100
            y = screenFrame.midY - windowHeight / 2
        default: // Others spaced out
            x = screenFrame.midX - windowWidth / 2 + CGFloat(scope * 50)
            y = screenFrame.midY - windowHeight / 2
        }
        
        let newFrame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        window.setFrame(newFrame, display: true)
    }
    
    // MARK: - Display Settings Commands
    
    /// Set window state (stayontop, minimize, etc.)
    func setWindowState(state: String) {
        Log.debug("[GhostManager] Setting window state: \(state)")
        DispatchQueue.main.async {
            guard let window = self.characterWindows[self.currentScope] else { return }
            
            let stateLC = state.lowercased()
            if stateLC == "stayontop" || stateLC == "topmost" {
                window.level = .floating
                Log.info("[GhostManager] Window set to stay on top")
            } else if stateLC == "!stayontop" || stateLC == "normal" {
                window.level = .normal
                Log.info("[GhostManager] Window stay on top disabled")
            } else if stateLC == "minimize" {
                if !window.isMiniaturized {
                    if let scope = self.characterWindows.first(where: { $0.value === window })?.key {
                        self.pendingWindowStateReasons[scope] = "script"
                    }
                    window.miniaturize(nil)
                }
                Log.info("[GhostManager] Window minimized")
            } else if stateLC == "maximize" {
                guard self.orderCharacterWindowIfLoaded(window, makeKey: true) else { return }
                if !window.isZoomed {
                    window.zoom(nil)
                }
                Log.info("[GhostManager] Window maximized")
            } else if stateLC == "restore" {
                guard self.orderCharacterWindowIfLoaded(window) else { return }
                if window.isMiniaturized {
                    if let scope = self.characterWindows.first(where: { $0.value === window })?.key {
                        self.pendingWindowStateReasons[scope] = "script"
                    }
                    window.deminiaturize(nil)
                }
                if window.isZoomed {
                    window.zoom(nil)
                }
                Log.info("[GhostManager] Window restored")
            } else if stateLC == "hide" {
                window.orderOut(nil)
                Log.info("[GhostManager] Window hidden")
            } else if stateLC == "show" {
                guard self.orderCharacterWindowIfLoaded(window) else { return }
                Log.info("[GhostManager] Window shown")
            } else if stateLC == "focus" || stateLC == "activate" {
                guard self.orderCharacterWindowIfLoaded(window, makeKey: true) else { return }
                NSApp.activate(ignoringOtherApps: true)
                Log.info("[GhostManager] Window focused")
            }
        }
    }

    func setCurrentWindowHidden(_ hidden: Bool) {
        DispatchQueue.main.async {
            guard let window = self.characterWindows[self.currentScope] else { return }
            if hidden {
                window.orderOut(nil)
            } else {
                _ = self.orderCharacterWindowIfLoaded(window)
            }
        }
    }

    func focusCurrentWindow() {
        DispatchQueue.main.async {
            guard let window = self.characterWindows[self.currentScope] else { return }
            guard self.orderCharacterWindowIfLoaded(window, makeKey: true) else { return }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func maximizeCurrentWindow() {
        DispatchQueue.main.async {
            guard let window = self.characterWindows[self.currentScope] else { return }
            guard self.orderCharacterWindowIfLoaded(window, makeKey: true) else { return }
            if !window.isZoomed {
                window.zoom(nil)
            }
        }
    }

    /// 画像未ロードのキャラクター窓は、z-order や表示コマンドからも表示しない。
    ///
    /// 起動直後や `\p[N]` で先に作られた窓に SERIKO オーバーレイだけが入ると、
    /// 目元などの画像片が単独で浮いて見える。サーフェス画像の設定は
    /// `GhostManager+Surface.updateSurface` だけが表示を許可するため、その他の
    /// order-front 経路もここで同じ条件に揃える。
    @discardableResult
    private func orderCharacterWindowIfLoaded(
        _ window: NSWindow,
        makeKey: Bool = false
    ) -> Bool {
        guard characterWindowHasLoadedSurface(window) else {
            window.orderOut(nil)
            return false
        }

        if makeKey {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        return true
    }

    private func characterWindowHasLoadedSurface(_ window: NSWindow) -> Bool {
        guard let scope = characterWindows.first(where: { $0.value === window })?.key else {
            return false
        }
        return characterViewModels[scope]?.image != nil
    }

    // MARK: - 見切れ / 重なり 判定 (UKADOC OnSecondChange Reference1 / Reference2)

    /// 見切れ（screen cutoff）状態のスコープ ID リストを返す。
    /// キャラクターウィンドウが所属スクリーンの可視フレーム外にはみ出している場合に見切れと判定する。
    /// - Returns: 該当スコープ ID を数値順にカンマ区切りした文字列（none → 空文字列）
    func mikireScopes() -> String {
        let scopes = collectVisibleCharacterFrames()
        var hit: [Int] = []
        for (scope, frame, screenFrame) in scopes {
            // 可視フレームに完全に含まれていなければ見切れ
            if !screenFrame.contains(frame) {
                hit.append(scope)
            }
        }
        return hit.sorted().map(String.init).joined(separator: ",")
    }

    /// 重なり（overlap with another character window）状態のスコープ ID リストを返す。
    /// 同一ゴーストの他キャラウィンドウと矩形が交差している場合に重なりと判定する。
    /// - Returns: 該当スコープ ID を数値順にカンマ区切りした文字列（none → 空文字列）
    func kasanariScopes() -> String {
        let scopes = collectVisibleCharacterFrames()
        var hit: Set<Int> = []
        for i in 0..<scopes.count {
            let (a, fa, _) = scopes[i]
            for j in (i+1)..<scopes.count {
                let (b, fb, _) = scopes[j]
                if fa.intersects(fb) {
                    hit.insert(a)
                    hit.insert(b)
                }
            }
        }
        return hit.sorted().map(String.init).joined(separator: ",")
    }

    /// 表示中のキャラウィンドウについて (scope, ウィンドウ矩形, 所属スクリーンの可視矩形) を集める。
    /// 非表示／ミニ化中／所属スクリーン不明のウィンドウは除外する。
    private func collectVisibleCharacterFrames() -> [(scope: Int, frame: CGRect, screenVisible: CGRect)] {
        var result: [(scope: Int, frame: CGRect, screenVisible: CGRect)] = []
        for (scope, window) in characterWindows {
            guard window.isVisible, !window.isMiniaturized else { continue }
            let frame = window.frame
            guard frame.width > 0, frame.height > 0 else { continue }
            let screenVisible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            guard screenVisible.width > 0, screenVisible.height > 0 else { continue }
            result.append((scope, frame, screenVisible))
        }
        return result
    }

    // MARK: - OnOffscreen / OnOverlap（UKADOC: 状態遷移時に逐次通知、Reference0=現在 / Reference1=直前）

    /// OnOtherOffscreen / OnOtherOverlap 用に自ゴーストのキャラ矩形スナップショットを公開する。
    func characterFrameList() -> [(scope: Int, frame: CGRect, screenVisible: CGRect)] {
        collectVisibleCharacterFrames()
    }

    /// OnOffscreen Reference0: 見切れ中スコープ ID を \x01 区切りで昇順に並べる（該当なし → 空文字列）。
    static func offscreenRef0(frames: [(scope: Int, frame: CGRect, screenVisible: CGRect)]) -> String {
        frames.filter { !$0.screenVisible.contains($0.frame) }
            .map { $0.scope }
            .sorted()
            .map(String.init)
            .joined(separator: "\u{01}")
    }

    /// OnOverlap Reference0: 重なっているスコープ ID ペア（"小-大"）を \x01 区切りで並べる（該当なし → 空文字列）。
    static func overlapRef0(frames: [(scope: Int, frame: CGRect, screenVisible: CGRect)]) -> String {
        var pairs: [(Int, Int)] = []
        for i in 0..<frames.count {
            for j in (i + 1)..<frames.count {
                if frames[i].frame.intersects(frames[j].frame) {
                    let a = min(frames[i].scope, frames[j].scope)
                    let b = max(frames[i].scope, frames[j].scope)
                    pairs.append((a, b))
                }
            }
        }
        return pairs.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map { "\($0.0)-\($0.1)" }
            .joined(separator: "\u{01}")
    }

    /// 見切れ／重なり状態の遷移を検出し、発火すべきイベントを返す（毎秒 tick から呼ばれる）。
    /// 初回はベースラインのみ確立してイベントを返さない。
    func overlapTransitionEvents() -> [(id: EventID, params: [String: String])] {
        let frames = collectVisibleCharacterFrames()
        let offscreen = Self.offscreenRef0(frames: frames)
        let overlap = Self.overlapRef0(frames: frames)
        var events: [(id: EventID, params: [String: String])] = []

        if let prev = lastOffscreenRef0 {
            if prev != offscreen {
                events.append((.OnOffscreen, ["Reference0": offscreen, "Reference1": prev]))
            }
        }
        lastOffscreenRef0 = offscreen

        if let prev = lastOverlapRef0 {
            if prev != overlap {
                events.append((.OnOverlap, ["Reference0": overlap, "Reference1": prev]))
            }
        }
        lastOverlapRef0 = overlap

        return events
    }
}
