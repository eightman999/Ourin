import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Balloon Management and Positioning

extension GhostManager {
    // MARK: - Balloon helpers
    func getBalloonVM(for scope: Int) -> BalloonViewModel {
        if let vm = balloonViewModels[scope] { return vm }
        let vm = BalloonViewModel()
        balloonViewModels[scope] = vm

        let view = BalloonView(
            viewModel: vm,
            onClick: { [weak self] in self?.onBalloonClicked(fromScope: scope) },
            config: balloonConfig,
            imageLoader: balloonImageLoader
        )
        let hc = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hc)
        win.isOpaque = false
        win.backgroundColor = NSColor.clear
        win.styleMask = [NSWindow.StyleMask.borderless]
        win.hasShadow = false
        // Balloon windows: highest level, above everything (ghost + other apps)
        // Use popUpMenu (101) to ensure balloons are always on top
        win.level = NSWindow.Level.popUpMenu
        win.hidesOnDeactivate = false
        win.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, NSWindow.CollectionBehavior.fullScreenAuxiliary]

        // Enable dragging the balloon window by its content
        win.isMovableByWindowBackground = true
        win.isMovable = true

        // Start with a reasonable initial size; it will resize based on content
        win.setFrame(.init(x: 450, y: 300, width: 250, height: 100), display: true)
        win.identifier = NSUserInterfaceItemIdentifier("GhostBalloonWindow_\(scope)")
        win.orderOut(nil)
        balloonWindows[scope] = win

        // Observe balloon window movement to save position
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balloonWindowDidChangeFrame(_:)),
            name: NSWindow.didMoveNotification,
            object: win
        )

        // show/hide per text and resize window to fit content
        // Use debouncing to prevent flickering from rapid text updates
        balloonTextCancellables[scope] = vm.$text
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self, weak win, weak hc] text in
                guard let self = self, let win = win, let hc = hc else { return }
                if text.isEmpty {
                    if win.isVisible {
                        win.orderOut(nil)
                    }
                } else {
                    let wasVisible = win.isVisible

                    // Resize window to fit content
                    let fittingSize = hc.view.fittingSize
                    let newSize = CGSize(width: max(250, min(fittingSize.width, 400)),
                                       height: max(50, min(fittingSize.height, 600)))

                    // Only update if size changed significantly (avoid micro-adjustments)
                    let currentSize = win.frame.size
                    if abs(currentSize.width - newSize.width) > 5 || abs(currentSize.height - newSize.height) > 5 {
                        var frame = win.frame
                        frame.size = newSize
                        win.setFrame(frame, display: false, animate: false)
                        self.positionBalloonWindow()
                    }

                    // Only call orderFront if not already visible
                    if !wasVisible {
                        win.orderFront(nil)
                    }
                }
            }
        positionBalloonWindow()
        return vm
    }

    func appendText(_ s: String) {
        // Always use current scope only - no parallel display for character dialogue
        // if syncEnabled {
        //     let targets = syncScopes.isEmpty ? [0,1] : Array(syncScopes)
        //     for sc in targets { getBalloonVM(for: sc).text += s }
        // } else {
            getBalloonVM(for: currentScope).text += s
        // }
    }

    func onBalloonClicked(fromScope: Int) {
        guard let _ = pendingClick else { return }
        // Click handling logic is managed by script tokens; placeholder for future use.
    }
    // MARK: - Balloon Positioning

    @objc func characterWindowDidChangeFrame(_ notification: Notification) {
        positionBalloonWindow()

        // Save window positions when moved
        if let window = notification.object as? NSWindow,
           let identifier = window.identifier?.rawValue,
           identifier.hasPrefix("GhostCharacterWindow_") {
            let scopeStr = identifier.replacingOccurrences(of: "GhostCharacterWindow_", with: "")
            if let scope = Int(scopeStr) {
                let frame = window.frame
                resourceManager.setCharDefaultLeft(scope: scope, value: Int(frame.origin.x))
                resourceManager.setCharDefaultTop(scope: scope, value: Int(frame.origin.y))
                Log.debug("[GhostManager] Saved scope \(scope) position: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
            }
        }
    }

    @objc func balloonWindowDidChangeFrame(_ notification: Notification) {
        // Save balloon window positions when moved by user
        if let window = notification.object as? NSWindow,
           let identifier = window.identifier?.rawValue,
           identifier.hasPrefix("GhostBalloonWindow_") {
            let scopeStr = identifier.replacingOccurrences(of: "GhostBalloonWindow_", with: "")
            if let scope = Int(scopeStr) {
                let frame = window.frame
                resourceManager.setBalloonLeft(scope: scope, value: Int(frame.origin.x))
                resourceManager.setBalloonTop(scope: scope, value: Int(frame.origin.y))
                Log.debug("[GhostManager] Saved balloon \(scope) position: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
            }
        }
    }

    func positionBalloonWindow() {
        let margin: CGFloat = 8
        let verticalOffset: CGFloat = 80 // Move balloon higher above character head

        // Position each balloon next to its corresponding character window
        for (scope, balloonWin) in balloonWindows {
            guard let charWin = characterWindows[scope] else { continue }
            let cFrame = charWin.frame

            var f = balloonWin.frame

            // Priority 1: User saved position (highest priority)
            if let savedX = resourceManager.getBalloonLeft(scope: scope),
               let savedY = resourceManager.getBalloonTop(scope: scope) {
                f.origin.x = CGFloat(savedX)
                f.origin.y = CGFloat(savedY)
                Log.debug("[GhostManager] Using saved balloon position for scope \(scope): (\(savedX), \(savedY))")
            }
            // Priority 2: YAYA script position (from SakuraScript \![set,balloondistance,...])
            // This is handled by SakuraScriptEngine commands
            // Priority 3: Default position relative to character (lowest priority)
            else {
                // Position balloon to the right of character for all scopes
                // This provides consistent positioning regardless of scope
                f.origin.x = cFrame.maxX + margin
                f.origin.y = cFrame.maxY - f.height + verticalOffset
            }

            // Keep balloon within screen bounds
            if let screen = charWin.screen?.visibleFrame {
                if f.maxX > screen.maxX { f.origin.x = screen.maxX - f.width - margin }
                if f.minX < screen.minX { f.origin.x = screen.minX + margin }
                if f.maxY > screen.maxY { f.origin.y = screen.maxY - f.height - margin }
                if f.minY < screen.minY { f.origin.y = screen.minY + margin }
            }
            balloonWin.setFrameOrigin(f.origin)
        }
    }

    // MARK: - Balloon Image Display
    
    /// Handle balloon image display - \_b[filepath,x,y,...] or \_b[filepath,inline,...]
    func handleBalloonImage(args: [String]) {
        guard !args.isEmpty else {
            Log.info("[GhostManager] Invalid balloon image command: no filepath")
            return
        }
        
        let filepath = args[0]
        
        // Check for inline mode
        if args.count >= 2 && args[1].lowercased() == "inline" {
            Log.debug("[GhostManager] Balloon inline image: \(filepath)")
            // TODO: Load and display inline image in balloon
            // Parse additional options (opaque, --option=value, etc.)
            let options = Array(args.dropFirst(2))
            for option in options {
                if option.lowercased() == "opaque" {
                    Log.debug("[GhostManager]   - Opaque mode")
                } else if option.hasPrefix("--") {
                    Log.debug("[GhostManager]   - Option: \(option)")
                }
            }
        } else if args.count >= 3 {
            // Positioned mode: filepath,x,y[,options...]
            if let x = Int(args[1]), let y = Int(args[2]) {
                Log.debug("[GhostManager] Balloon positioned image: \(filepath) at (\(x), \(y))")
                // TODO: Load and display image at specified position
                let options = Array(args.dropFirst(3))
                for option in options {
                    if option.lowercased() == "opaque" {
                        Log.debug("[GhostManager]   - Opaque mode")
                    } else if option.hasPrefix("--") {
                        Log.debug("[GhostManager]   - Option: \(option)")
                    }
                }
            }
        }
    }
    
}
