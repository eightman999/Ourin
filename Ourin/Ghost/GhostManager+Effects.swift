import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Effects, Filters, Dressup, and Text Animations

extension GhostManager {
    // MARK: - Effect and Filter Commands
    
    /// Apply effect plugin
    func applyEffect(plugin: String, speed: Double, params: [String], surfaceID: Int?) {
        Log.debug("[GhostManager] Applying effect: \(plugin), speed: \(speed), surface: \(surfaceID?.description ?? "current")")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            // Store effect parameters
            let effect = EffectConfig(plugin: plugin, speed: speed, params: params, surfaceID: surfaceID)
            vm.activeEffects.append(effect)
            
            // TODO: Implement actual effect rendering through plugin system
            Log.info("[GhostManager] Effect '\(plugin)' applied (rendering not yet implemented)")
        }
    }
    
    /// Apply filter plugin
    func applyFilter(plugin: String, time: Double, params: [String]) {
        Log.debug("[GhostManager] Applying filter: \(plugin), time: \(time)")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            // Store filter parameters
            let filter = FilterConfig(plugin: plugin, time: time, params: params)
            vm.activeFilters.append(filter)
            
            // Schedule filter removal if time specified
            if time > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + time / 1000.0) {
                    vm.activeFilters.removeAll { $0.plugin == plugin }
                }
            }
            
            // TODO: Implement actual filter rendering through plugin system
            Log.info("[GhostManager] Filter '\(plugin)' applied (rendering not yet implemented)")
        }
    }
    
    /// Clear all filters
    func clearFilters() {
        Log.debug("[GhostManager] Clearing all filters")
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.activeFilters.removeAll()
            Log.info("[GhostManager] All filters cleared")
        }
    }
    
    // MARK: - Dressup Command
    
    /// Handle bind/dressup command
    func handleBindDressup(category: String, part: String, value: String) {
        Log.debug("[GhostManager] Bind dressup: category=\(category), part=\(part), value=\(value)")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            let lowered = value.lowercased()
            let disable = lowered == "0" || lowered == "false" || lowered == "off" || lowered == "none" || lowered == "default"
            if disable {
                vm.dressupBindings[category]?[part] = nil
                if vm.dressupBindings[category]?.isEmpty == true {
                    vm.dressupBindings[category] = nil
                }
            } else {
                if vm.dressupBindings[category] == nil {
                    vm.dressupBindings[category] = [:]
                }
                vm.dressupBindings[category]?[part] = value
            }
            
            // TODO: Implement actual dressup rendering
            // This would load additional surface layers based on bindings
            Log.info("[GhostManager] Dressup binding set (rendering not yet implemented)")
        }
    }

    func executeBindCommand(args: [String]) {
        guard args.count >= 2 else { return }
        let subcmd = args[1].lowercased()

        if subcmd == "category" {
            // \![bind,category,part,value]
            if args.count >= 4 {
                let category = args[2]
                let part = args[3]
                let value = args.count >= 5 ? args[4] : "true"
                applyDressup(category: category, part: part, value: value)
            }
            return
        }

        // Supports repeated tuples: \![bind,cat,part,val,cat2,part2,val2,...]
        if args.count >= 4 {
            var idx = 1
            while idx + 2 < args.count {
                let category = args[idx]
                let part = args[idx + 1]
                let value = args[idx + 2]
                handleBindDressup(category: category, part: part, value: value)
                idx += 3
            }
            return
        }

        // Fallback: \![bind,cat,part] => true
        if args.count == 3 {
            handleBindDressup(category: args[1], part: args[2], value: "true")
        }
    }
    
    // MARK: - Text Animation Command
    
    /// Add text animation overlay
    func addTextAnimation(x: Int, y: Int, width: Int, height: Int, text: String, 
                                 time: Int, r: Int, g: Int, b: Int, size: Int, font: String) {
        Log.debug("[GhostManager] Adding text animation: '\(text)' at (\(x),\(y))")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            let textAnim = TextAnimationConfig(
                x: x, y: y, width: width, height: height,
                text: text, duration: time,
                r: r, g: g, b: b,
                fontSize: size, fontName: font
            )
            
            vm.textAnimations.append(textAnim)
            
            // Schedule removal after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(time) / 1000.0) {
                vm.textAnimations.removeAll { $0.text == text && $0.x == x && $0.y == y }
            }
            
            // TODO: Implement actual text rendering overlay
            Log.info("[GhostManager] Text animation added (rendering not yet implemented)")
        }
    }
    
    // MARK: - Balloon Switching
    
    /// Switch to a different balloon style
    func switchBalloon(to balloonID: Int, scope: Int) {
        guard let vm = characterViewModels[scope] else {
            Log.info("[GhostManager] Cannot switch balloon: no viewmodel for scope \(scope)")
            return
        }
        
        // Hide balloon if ID is -1
        if balloonID == -1 {
            DispatchQueue.main.async {
                if let balloonWindow = self.balloonWindows[scope] {
                    balloonWindow.orderOut(nil)
                    Log.info("[GhostManager] Hiding balloon for scope \(scope)")
                }
            }
            return
        }
        
        DispatchQueue.main.async {
            vm.currentBalloonID = balloonID
            
            // Also update the BalloonViewModel's balloonID
            if let balloonVM = self.balloonViewModels[scope] {
                balloonVM.balloonID = balloonID
            }
            
            Log.info("[GhostManager] Switched to balloon ID \(balloonID) for scope \(scope)")
        }
    }

    /// Switch balloon by numeric ID or balloon directory/name.
    @discardableResult
    func switchBalloon(named identifier: String, scope: Int, raiseEvent: Bool = false) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.info("[GhostManager] change,balloon ignored: empty identifier")
            return false
        }

        let previousBalloon = balloonConfig?.name ?? ""
        if raiseEvent {
            EventBridge.shared.notify(.OnBalloonChange, params: ["Reference0": previousBalloon, "Reference1": trimmed, "Reference2": "changing"])
        }

        if let id = Int(trimmed) {
            switchBalloon(to: id, scope: scope)
            EventBridge.shared.notify(.OnBalloonChange, params: ["Reference0": previousBalloon, "Reference1": trimmed, "Reference2": "changed"])
            return true
        }

        let baseBalloonDir = ghostURL.appendingPathComponent("balloon", isDirectory: true)
        let namedBalloonDir = baseBalloonDir.appendingPathComponent(trimmed, isDirectory: true)
        let descriptCandidates = [
            namedBalloonDir.appendingPathComponent("descript.txt").path,
            baseBalloonDir.appendingPathComponent("descript.txt").path
        ]

        for path in descriptCandidates {
            guard let config = BalloonConfig.load(from: path) else { continue }
            let dirPath = (path as NSString).deletingLastPathComponent
            balloonConfig = config
            balloonImageLoader = BalloonImageLoader(balloonPath: dirPath)
            Log.info("[GhostManager] Switched balloon config to \(config.name)")
            EventBridge.shared.notify(.OnBalloonChange, params: ["Reference0": previousBalloon, "Reference1": config.name, "Reference2": "changed"])
            return true
        }

        Log.info("[GhostManager] Balloon not found: \(trimmed)")
        return false
    }

    // MARK: - Desktop Alignment
}
