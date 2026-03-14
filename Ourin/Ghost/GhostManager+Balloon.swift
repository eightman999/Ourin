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
        // Initialize balloon ID from character view model
        if let charVM = characterViewModels[scope] {
            vm.balloonID = charVM.currentBalloonID
        }
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
        if let noclear = pendingClick {
            pendingClick = nil
            if !noclear {
                getBalloonVM(for: fromScope).text = ""
            }
            processNextUnit()
            return
        }

        guard let action = pendingAnchorAction else { return }
        pendingAnchorAction = nil

        let vm = getBalloonVM(for: fromScope)
        vm.anchorActive = false

        switch action {
        case .event(let id, let references):
            var params: [String: String] = [:]
            for (index, ref) in references.enumerated() {
                params["Reference\(index)"] = ref
            }

            if id.hasPrefix("On") {
                EventBridge.shared.notifyCustom(id, params: params)
            } else {
                var exParams = params
                exParams["Reference1"] = id
                EventBridge.shared.notifyCustom("OnAnchorSelectEx", params: exParams)
                EventBridge.shared.notifyCustom("OnAnchorSelect", params: ["Reference0": id])
            }
        case .script(let script):
            sakuraEngine.run(script: script)
        }
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
        
        // Parse options
        var isInline = false
        var x: CGFloat = 0
        var y: CGFloat = 0
        var isOpaque = false
        var useSelfAlpha = false
        var clipping: CGRect? = nil
        var isForeground = false
        
        // Check for inline mode
        if args.count >= 2 && args[1].lowercased() == "inline" {
            isInline = true
            // Parse options after "inline"
            let options = Array(args.dropFirst(2))
            for option in options {
                parseBalloonImageOption(option, &isOpaque, &useSelfAlpha, &clipping, &isForeground)
            }
        } else if args.count >= 3 {
            // Positioned mode: filepath,x,y[,options...]
            if let xPos = Int(args[1]), let yPos = Int(args[2]) {
                x = CGFloat(xPos)
                y = CGFloat(yPos)
                // Parse options after x,y
                let options = Array(args.dropFirst(3))
                for option in options {
                    parseBalloonImageOption(option, &isOpaque, &useSelfAlpha, &clipping, &isForeground)
                }
            } else {
                Log.info("[GhostManager] Invalid balloon image coordinates: \(args[1]), \(args[2])")
                return
            }
        }
        
        // Load image
        let image = loadBalloonImage(filepath: filepath, isOpaque: isOpaque, useSelfAlpha: useSelfAlpha)
        
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            
            let balloonImage = BalloonViewModel.BalloonImage(
                filepath: filepath,
                x: x,
                y: y,
                isInline: isInline,
                isOpaque: isOpaque,
                useSelfAlpha: useSelfAlpha,
                clipping: clipping,
                isForeground: isForeground,
                image: image
            )
            
            if isInline {
                // For inline images, we'll insert them into the text at the current position
                // This is handled by the text rendering system
                Log.debug("[GhostManager] Inline image: \(filepath)")
            }
            
            vm.balloonImages.append(balloonImage)
            Log.debug("[GhostManager] Added balloon image: \(filepath) at (\(x), \(y)), inline: \(isInline)")
        }
    }
    
    /// Parse balloon image option
    private func parseBalloonImageOption(_ option: String, _ isOpaque: inout Bool, _ useSelfAlpha: inout Bool, _ clipping: inout CGRect?, _ isForeground: inout Bool) {
        let opt = option.lowercased()
        if opt == "opaque" {
            isOpaque = true
        } else if opt == "--option=use_self_alpha" {
            useSelfAlpha = true
        } else if opt.hasPrefix("--clipping=") {
            let parts = opt.replacingOccurrences(of: "--clipping=", with: "").split(separator: " ").map(String.init)
            if parts.count >= 4,
               let left = Double(parts[0]), let top = Double(parts[1]),
               let right = Double(parts[2]), let bottom = Double(parts[3]) {
                clipping = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            }
        } else if opt == "--option=fixed" {
            // Fixed mode - doesn't scroll with text (not implemented yet)
        } else if opt == "--option=background" {
            isForeground = false
        } else if opt == "--option=foreground" {
            isForeground = true
        }
    }
    
    /// Load balloon image from ghost directory
    private func loadBalloonImage(filepath: String, isOpaque: Bool, useSelfAlpha: Bool) -> NSImage? {
        // Build full path relative to ghost directory
        let imagePath: URL
        if filepath.hasPrefix("/") || filepath.contains(":/") {
            // Absolute path or URL
            imagePath = URL(string: filepath)!
        } else {
            // Relative path - prepend ghost path
            let masterPath = ghostURL.appendingPathComponent("ghost/master").path
            imagePath = URL(fileURLWithPath: masterPath).appendingPathComponent(filepath)
        }
        
        guard let image = NSImage(contentsOf: imagePath) else {
            Log.info("[GhostManager] Failed to load balloon image: \(filepath)")
            return nil
        }
        
        // Apply transparency if not opaque
        if !isOpaque {
            // For PNG with alpha channel, use self alpha if specified
            if useSelfAlpha {
                // The image already has alpha, so just use it as-is
            } else {
                // Default behavior: use top-left pixel as transparent color
                if let rep = image.representations.first as? NSBitmapImageRep,
                   rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
                    let _ = rep.colorAt(x: 0, y: 0)
                    // Create image with transparency (simplified)
                    // Full implementation would require pixel-by-pixel processing
                }
            }
        }
        
        return image
    }

    /// Handle cursor position move - \_l[x,y]
    func handleCursorMove(x: String, y: String) {
        let baseX = getBalloonVM(for: currentScope).cursorX
        let baseY = getBalloonVM(for: currentScope).cursorY
        let newX = parseCursorCoordinate(value: x, base: baseX)
        let newY = parseCursorCoordinate(value: y, base: baseY)
        
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.cursorX = newX
            vm.cursorY = newY
            Log.debug("[GhostManager] Cursor moved to: (\(newX), \(newY))")
        }
    }

    /// Parse cursor coordinate value
    private func parseCursorCoordinate(value: String, base: CGFloat) -> CGFloat {
        let config = balloonConfig
        
        if value == "" || value == "@" {
            // Keep current value
            return base
        }
        
        // Check for relative (@) prefix
        var isRelative = false
        var cleanValue = value
        if value.hasPrefix("@") {
            isRelative = true
            cleanValue = String(value.dropFirst())
        }
        
        // Parse value
        if let numValue = Double(cleanValue) {
            // Numeric value in pixels
            if isRelative {
                return base + numValue
            }
            return numValue
        } else if cleanValue.hasSuffix("em") {
            // Font height units
            let emValue = Double(cleanValue.dropLast(2)) ?? 0
            let fontSize = CGFloat(config?.fontHeight ?? 12)
            let result = emValue * fontSize
            return isRelative ? base + result : result
        } else if cleanValue.hasSuffix("lh") {
            // Line height units
            let lhValue = Double(cleanValue.dropLast(2)) ?? 0
            let fontSize = CGFloat(config?.fontHeight ?? 12)
            // Assume line height = font height * 1.2 (typical)
            let lineHeight = fontSize * 1.2
            let result = lhValue * lineHeight
            return isRelative ? base + result : result
        } else if cleanValue.hasSuffix("%") {
            // Percentage of font height
            let pctValue = Double(cleanValue.dropLast()) ?? 0
            let fontSize = CGFloat(config?.fontHeight ?? 12)
            let result = (pctValue / 100.0) * fontSize
            return isRelative ? base + result : result
        }
        
        // Default: parse as pixel value
        return base
    }

    /// Handle balloon offset - \![set,balloonoffset,x,y]
    func handleBalloonOffset(x: String, y: String, isRelative: Bool = false) {
        let baseX = getBalloonVM(for: currentScope).balloonOffsetX
        let baseY = getBalloonVM(for: currentScope).balloonOffsetY
        
        let newX = parseBalloonCoordinate(value: x, base: baseX, isRelative: isRelative)
        let newY = parseBalloonCoordinate(value: y, base: baseY, isRelative: isRelative)
        
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.balloonOffsetX = newX
            vm.balloonOffsetY = newY
            vm.useCustomOffset = true
            Log.debug("[GhostManager] Balloon offset set to: (\(newX), \(newY))")
            self.positionBalloonWindow()
        }
    }

    /// Parse balloon offset coordinate value
    private func parseBalloonCoordinate(value: String, base: CGFloat, isRelative: Bool) -> CGFloat {
        if value == "" || value == "@" {
            return base
        }
        
        var isValueRelative = false
        var cleanValue = value
        if value.hasPrefix("@") {
            isValueRelative = true
            cleanValue = String(value.dropFirst())
        }
        
        if let numValue = Double(cleanValue) {
            if isValueRelative || isRelative {
                return base + numValue
            }
            return numValue
        }
        
        return base
    }

    /// Handle balloon alignment - \![set,balloonalign,direction]
    func handleBalloonAlignment(direction: String) {
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            
            switch direction {
            case "left":
                vm.balloonAlignment = .left
            case "center":
                vm.balloonAlignment = .center
            case "top":
                vm.balloonAlignment = .top
            case "right":
                vm.balloonAlignment = .right
            case "bottom":
                vm.balloonAlignment = .bottom
            case "none":
                vm.balloonAlignment = .none
            default:
                Log.info("[GhostManager] Unknown balloon alignment: \(direction)")
            }
            
            Log.debug("[GhostManager] Balloon alignment set to: \(direction)")
            self.positionBalloonWindow()
        }
    }

    /// Parse font height value
    func parseFontHeight(_ value: String, baseFontSize: CGFloat) -> CGFloat {
        if value == "default" {
            return baseFontSize
        }
        
        if value.hasPrefix("+") {
            // Relative increase
            let deltaStr = String(value.dropFirst())
            if let delta = Double(deltaStr) {
                return baseFontSize + delta
            }
            return baseFontSize
        } else if value.hasPrefix("-") {
            // Relative decrease
            let deltaStr = String(value.dropFirst())
            if let delta = Double(deltaStr) {
                return baseFontSize - delta
            }
            return baseFontSize
        } else if value.hasSuffix("%") {
            // Percentage of default
            let pctStr = String(value.dropLast())
            if let pct = Double(pctStr) {
                return baseFontSize * (pct / 100.0)
            }
            return baseFontSize
        } else if let numValue = Double(value) {
            // Absolute pixel value
            return numValue
        }
        
        return baseFontSize
    }

    /// Parse color value
    func parseColor(from value: String, defaultValue: NSColor) -> NSColor {
        if value == "default" || value == "" {
            return defaultValue
        }
        
        // Check for hex color #RRGGBB or #RRGGBBAA
        if value.hasPrefix("#") {
            let hexValue = String(value.dropFirst())
            if hexValue.count == 6 {
                // #RRGGBB format
                let rStr = String(hexValue.prefix(2))
                let gStr = String(hexValue.dropFirst(2).prefix(2))
                let bStr = String(hexValue.dropFirst(4).prefix(2))
                if let r = UInt8(rStr, radix: 16),
                   let g = UInt8(gStr, radix: 16),
                   let b = UInt8(bStr, radix: 16) {
                    return NSColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
                }
            } else if hexValue.count == 8 {
                // #RRGGBBAA format
                let rStr = String(hexValue.prefix(2))
                let gStr = String(hexValue.dropFirst(2).prefix(2))
                let bStr = String(hexValue.dropFirst(4).prefix(2))
                let aStr = String(hexValue.dropFirst(6).prefix(2))
                if let r = UInt8(rStr, radix: 16),
                   let g = UInt8(gStr, radix: 16),
                   let b = UInt8(bStr, radix: 16),
                   let a = UInt8(aStr, radix: 16) {
                    return NSColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: CGFloat(a)/255.0)
                }
            }
            return defaultValue
        } else if value.hasPrefix("rgb(") || value.hasPrefix("r,g,b") || value.hasPrefix("r g b") {
            // RGB format: r,g,b or r g b
            let parts = value.components(separatedBy: CharacterSet(charactersIn: "rgb, ").inverted).joined(separator: ",").components(separatedBy: .whitespaces)
            if parts.count >= 3,
               let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) {
                return NSColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
            }
            return defaultValue
        } else if value == "none" {
            return .clear
        } else {
            // Named colors
            let colorLower = value.lowercased()
            switch colorLower {
            case "red": return .red
            case "green": return .green
            case "blue": return .blue
            case "yellow": return .yellow
            case "cyan": return .cyan
            case "magenta": return .magenta
            case "black": return .black
            case "white": return .white
            case "gray": return .gray
            case "darkgray": return .darkGray
            default: return defaultValue
            }
        }
    }

    /// Parse tri-state value (0/1/true/false/default/disable)
    func parseTriState(_ value: String, currentValue: String) -> Bool {
        let v = value.lowercased()
        if v == "1" || v == "true" {
            return true
        } else if v == "0" || v == "false" {
            return false
        }
        // default/disable - return current value
        return currentValue == "1"
    }

    /// Reset font to default values
    func resetFontDefaults(vm: BalloonViewModel) {
        let config = balloonConfig
        vm.fontName = ""
        vm.fontSize = CGFloat(config?.fontHeight ?? 12)
        vm.fontWeight = .regular
        vm.fontItalic = false
        vm.fontUnderline = false
        vm.fontStrike = false
        vm.fontColor = config?.fontColor ?? .textColor
        vm.shadowColor = .clear
        vm.shadowStyle = .none
    }

    /// Set font to disabled style
    func setFontDisabled(vm: BalloonViewModel) {
        // Use system disabled font styling
        vm.fontName = ""
        vm.fontSize = 12
        vm.fontWeight = .regular
        vm.fontItalic = false
        vm.fontUnderline = false
        vm.fontStrike = true
        vm.fontColor = .gray
        vm.shadowColor = .clear
        vm.shadowStyle = .none
    }

    /// Clear text - \c[char,line,...]
    func handleTextClear(args: [String]) {
        guard let vm = balloonViewModels[currentScope] else { return }
        
        var charsToClear = 0
        var linesToClear = 0
        
        if args.isEmpty {
            // Clear all text
            vm.text = ""
            Log.debug("[GhostManager] Cleared all text")
            return
        }
        
        for arg in args {
            if arg.hasPrefix("char") {
                let parts = arg.split(separator: "=")
                if parts.count >= 2, let count = Int(parts[1]) {
                    charsToClear = count
                }
            } else if arg.hasPrefix("line") {
                let parts = arg.split(separator: "=")
                if parts.count >= 2, let count = Int(parts[1]) {
                    linesToClear = count
                }
            } else if arg == "all" {
                vm.text = ""
                Log.debug("[GhostManager] Cleared all text")
                return
            }
        }
        
        DispatchQueue.main.async {
            if charsToClear > 0 {
                let charsToRemove = min(charsToClear, vm.text.count)
                vm.text = String(vm.text.dropLast(charsToRemove))
                Log.debug("[GhostManager] Cleared \(charsToRemove) chars")
            } else if linesToClear > 0 {
                let lines = vm.text.components(separatedBy: .newlines)
                let linesToRemove = min(linesToClear, lines.count)
                vm.text = lines.dropLast(linesToRemove).joined(separator: "\n")
                Log.debug("[GhostManager] Cleared \(linesToRemove) lines")
            }
        }
    }

    /// Handle newline with custom height - \n[half] or \n[percent]
    func handleNewline(type: String) {
        guard let vm = balloonViewModels[currentScope] else { return }
        
        let typeLower = type.lowercased()
        
        DispatchQueue.main.async {
            switch typeLower {
            case "half":
                // Half-height newline - adjust line spacing
                vm.text += "\n"
                Log.debug("[GhostManager] Half-height newline")
            case let percent where typeLower.hasSuffix("%"):
                // Percentage-based newline - adjust line spacing
                if let pct = Double(percent.dropLast()) {
                    let fontSize = vm.fontSize
                    let lineHeight = fontSize * (pct / 100.0)
                    // For now, just append newline - custom spacing handled by text rendering
                    vm.text += "\n"
                    Log.debug("[GhostManager] \(percent) height newline")
                }
            default:
                // Regular newline
                vm.text += "\n"
            }
        }
    }
    
    
}
