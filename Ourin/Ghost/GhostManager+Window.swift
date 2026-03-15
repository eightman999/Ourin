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
    }

    private var stickyIgnoreScopes: Set<Int> {
        get { WindowCommandStorage.stickyIgnoreScopes[ObjectIdentifier(self)] ?? [] }
        set { WindowCommandStorage.stickyIgnoreScopes[ObjectIdentifier(self)] = newValue }
    }

    private var asyncMoveWorkItems: [Int: DispatchWorkItem] {
        get { WindowCommandStorage.asyncMoveWorkItems[ObjectIdentifier(self)] ?? [:] }
        set { WindowCommandStorage.asyncMoveWorkItems[ObjectIdentifier(self)] = newValue }
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
    }

    // Note: This extension uses the following properties declared in the main GhostManager class:
    // - stickyWindowRelationships


    // MARK: - Window Setup

    func setupWindows() {
        Log.debug("[GhostManager] Setting up windows")
        // Create Character Windows for scope 0 (master), 1 (partner), and potentially 2-3 (additional characters)
        // Always create at least scope 0 and 1; additional scopes can be created dynamically
        for scope in 0..<4 {
            setupCharacterWindow(for: scope)
        }
    }

    func setupCharacterWindow(for scope: Int) {
        let dragDropHandler: (ShioriEvent) -> Void = { event in
            // Forward drag-drop events to EventBridge for broadcasting
            EventBridge.shared.notify(event.id, params: event.params)
        }

        let vm = CharacterViewModel()
        characterViewModels[scope] = vm

        let characterView = CharacterView(viewModel: vm, onDragDropEvent: dragDropHandler)
        let hostingController = NSHostingController(rootView: characterView)

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

        // Enable dragging the window by its content
        window.isMovableByWindowBackground = true
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
                let baseY = screenFrame.minY + 5

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

        // Show the window only for initial scopes (0 and 1)
        // Other scopes (2, 3, etc.) will be shown when first referenced in a script via \pN
        if scope <= 1 {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Window is created but not shown yet
            // It will be shown when scope is switched to via script
            Log.debug("[GhostManager] Scope \(scope) window created but not shown (will show on first use)")
        }

        // Keep window visible and prevent auto-hiding
        window.isReleasedWhenClosed = false

        characterWindows[scope] = window

        // Track window movement/resize
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidChangeFrame(_:)), name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidChangeFrame(_:)), name: NSWindow.didResizeNotification, object: window)
    }

    // MARK: - Window Position and Display Control
    
    /// Move window to back (behind other windows)
    func moveWindowToBack(scope: Int) {
        Log.debug("[GhostManager] Moving scope \(scope) window to back")
        DispatchQueue.main.async {
            if let window = self.characterWindows[scope] {
                window.orderBack(nil)
                window.level = .normal
                Log.info("[GhostManager] Moved scope \(scope) to background")
            }
        }
    }
    
    /// Move window to front (above other windows)
    func moveWindowToFront(scope: Int) {
        Log.debug("[GhostManager] Moving scope \(scope) window to front")
        DispatchQueue.main.async {
            if let window = self.characterWindows[scope] {
                window.orderFront(nil)
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
                Log.info("[GhostManager] Moved scope \(scope) to foreground")
            }
        }
    }
    
    /// Synchronous window move
    func moveWindow(scope: Int, x: Int, y: Int, time: Int, method: String, ignoreStickyWindow: Bool = false) {
        Log.debug("[GhostManager] Moving scope \(scope) to (\(x), \(y)) over \(time)ms with method '\(method)'")
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

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.moveWindow(scope: scope, x: x, y: y, time: time, method: method, ignoreStickyWindow: ignoreStickyWindow)
            var pending = self.asyncMoveWorkItems
            pending.removeValue(forKey: scope)
            self.asyncMoveWorkItems = pending
        }
        var pending = asyncMoveWorkItems
        pending[scope] = workItem
        asyncMoveWorkItems = pending

        DispatchQueue.main.async(execute: workItem)
    }

    func cancelMoveWindowAsync(scope: Int?) {
        var pending = asyncMoveWorkItems
        if let scope {
            pending[scope]?.cancel()
            pending.removeValue(forKey: scope)
            Log.debug("[GhostManager] Canceled async move for scope \(scope)")
        } else {
            for (_, workItem) in pending {
                workItem.cancel()
            }
            pending.removeAll()
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
        }
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
            for arg in args {
                if arg == "--option=ignore-sticky-window" {
                    spec.ignoreStickyWindow = true
                    continue
                }
                guard arg.hasPrefix("--") else { continue }
                let parts = arg.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let key = parts[0].lowercased()
                let value = parts[1]
                switch key {
                case "x":
                    spec.x = Int(value)
                case "y":
                    spec.y = Int(value)
                case "time":
                    spec.time = Int(value) ?? 0
                case "base":
                    spec.base = value
                case "base-offset":
                    spec.baseOffset = value
                case "move-offset":
                    spec.moveOffset = value
                case "method":
                    spec.method = value
                case "scope", "scopeid":
                    spec.scopeID = Int(value)
                case "option":
                    if value.lowercased() == "ignore-sticky-window" {
                        spec.ignoreStickyWindow = true
                    }
                default:
                    break
                }
            }
            return spec
        }

        guard args.count >= 2, let x = Int(args[0]), let y = Int(args[1]) else { return nil }
        spec.x = x
        spec.y = y
        spec.time = args.count >= 3 ? (Int(args[2]) ?? 0) : 0
        spec.method = args.count >= 4 ? args[3] : ""
        spec.scopeID = args.count >= 5 ? Int(args[4]) : nil
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
            let targetX = Int(baseAnchorPoint.x + CGFloat(spec.x ?? 0) - moveAnchorPoint.x)
            let targetY = Int(baseAnchorPoint.y + CGFloat(spec.y ?? 0) - moveAnchorPoint.y)
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
            // Order windows from back to front based on scopes array
            for (index, scope) in scopes.enumerated() {
                if let window = self.characterWindows[scope] {
                    if index == scopes.count - 1 {
                        // Last window (topmost)
                        window.orderFront(nil)
                    } else {
                        // Order behind the next window
                        if let nextWindow = self.characterWindows[scopes[index + 1]] {
                            window.order(.below, relativeTo: nextWindow.windowNumber)
                        }
                    }
                }
            }
            Log.info("[GhostManager] Z-order set successfully")
        }
    }
    
    /// Reset Z-order to default
    func resetWindowZOrder() {
        Log.debug("[GhostManager] Resetting Z-order to default")
        DispatchQueue.main.async {
            // Restore default floating window level for all
            for (scope, window) in self.characterWindows {
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
                window.orderFront(nil)
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
        
        // Move all follower windows relative to master
        for followerScope in followers {
            if let followerWindow = characterWindows[followerScope] {
                let offset: CGFloat = CGFloat((followerScope - masterScope) * 100) // Simple offset logic
                let newFrame = NSRect(
                    x: masterFrame.origin.x + offset,
                    y: masterFrame.origin.y,
                    width: followerWindow.frame.width,
                    height: followerWindow.frame.height
                )
                followerWindow.setFrame(newFrame, display: true)
            }
        }
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
            
            Log.info("[GhostManager] All sticky window relationships removed")
        }
    }
    
    /// Reset all window positions to default
    func executeResetWindowPos() {
        Log.debug("[GhostManager] Executing window position reset")
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
            if stateLC == "stayontop" {
                window.level = .floating
                Log.info("[GhostManager] Window set to stay on top")
            } else if stateLC == "!stayontop" {
                window.level = .normal
                Log.info("[GhostManager] Window stay on top disabled")
            } else if stateLC == "minimize" {
                window.miniaturize(nil)
                Log.info("[GhostManager] Window minimized")
            }
        }
    }
    
}
