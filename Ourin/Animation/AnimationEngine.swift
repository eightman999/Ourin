//
//  AnimationEngine.swift
//  Ourin
//
//  Animation engine for surface animations with Metal acceleration support
//

import Foundation
import AppKit
import Metal
import MetalKit

/// Animation pattern type from surfaces.txt
enum AnimationPatternType {
    case overlay       // Add overlay surface (default)
    case base          // Replace base surface
    case replace       // Replace current surface
    case bind          // Bind dressup part
}

/// Animation pattern definition from surfaces.txt
struct AnimationPattern {
    let surfaceID: Int              // Surface overlay ID (-1 for end/wait)
    let duration: Int               // Duration in milliseconds
    let x: Int                      // X offset
    let y: Int                      // Y offset
    let type: AnimationPatternType    // Pattern type (overlay/base/replace/bind)
}

/// Animation definition from surfaces.txt
struct AnimationDefinition {
    let id: Int                              // Animation ID
    let interval: AnimationInterval          // When to run
    let patterns: [AnimationPattern]         // Animation frames
    
    enum AnimationInterval: Equatable {
        case always        // Run continuously
        case sometimes     // Run randomly
        case rarely        // Run very rarely
        case runonce       // Run once then stop
        case never         // Don't run automatically
        case random(Int)   // Custom random interval
        case periodic(Int) // Fixed periodic interval

        init(from string: String) {
            if string.hasPrefix("random,") {
                let valueStr = string.replacingOccurrences(of: "random,", with: "")
                if let value = Int(valueStr) {
                    self = .random(value)
                    return
                }
            }

            if let value = Int(string) {
                self = .periodic(value)
            } else {
                switch string {
                case "always":
                    self = .always
                case "sometimes":
                    self = .sometimes
                case "rarely":
                    self = .rarely
                case "runonce":
                    self = .runonce
                default:
                    self = .never
                }
            }
        }
    }
}

/// Collision region for mouse event handling
struct CollisionRegion {
    let name: String
    let rect: CGRect
}

/// Active animation instance
class ActiveAnimation {
    let definition: AnimationDefinition
    var currentPatternIndex: Int = 0
    var startTime: Date
    var isPaused: Bool = false
    var offset: CGPoint = .zero
    
    init(definition: AnimationDefinition) {
        self.definition = definition
        self.startTime = Date()
    }
    
    /// Get current pattern
    var currentPattern: AnimationPattern? {
        guard currentPatternIndex < definition.patterns.count else { return nil }
        return definition.patterns[currentPatternIndex]
    }
    
    /// Advance to next pattern if duration elapsed
    func update() -> Bool {
        guard !isPaused else { return false }
        guard let pattern = currentPattern else { return false }
        
        let elapsed = Date().timeIntervalSince(startTime) * 1000 // ms
        if elapsed >= Double(pattern.duration) {
            currentPatternIndex += 1
            startTime = Date()
            
            // Check if animation finished
            if currentPatternIndex >= definition.patterns.count {
                if definition.interval == .runonce {
                    return true // Animation complete
                } else {
                    currentPatternIndex = 0 // Loop
                }
            }
        }
        return false
    }
}

/// Animation engine with Metal acceleration
class AnimationEngine {
    // Metal resources
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    
    // Animation state
    private var animations: [Int: AnimationDefinition] = [:]
    private var activeAnimations: [Int: ActiveAnimation] = [:]
    private var displayLink: CVDisplayLink?
    private var isRunning: Bool = false
    
    // Collision and point data
    private var collisions: [Int: [CollisionRegion]] = [:]
    private var points: [Int: [String: CGPoint]] = [:]
    
    // Callbacks
    var onAnimationUpdate: ((Int, AnimationPattern?) -> Void)?
    var onAnimationComplete: ((Int) -> Void)?
    
    init() {
        setupMetal()
    }
    
    // MARK: - Metal Setup
    
    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Log.info("[AnimationEngine] Metal is not supported on this device")
            return
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()

        Log.info("[AnimationEngine] Metal initialized: \(device.name)")
    }
    
    // MARK: - Animation Management
    
    /// Load animations from surfaces.txt content
    func loadAnimations(surfaceID: Int, content: String) {
        let lines = content.components(separatedBy: .newlines)
        var currentSurface: Int? = nil
        var currentAnimationID: Int? = nil
        var animationPatterns: [AnimationPattern] = []
        var animationInterval: AnimationDefinition.AnimationInterval = .never
        
        // Initialize collision and point data for this surface
        if !collisions.keys.contains(surfaceID) {
            collisions[surfaceID] = []
            points[surfaceID] = [:]
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Parse surface definition
            if trimmed.hasPrefix("surface") {
                let surfaceStr = trimmed.replacingOccurrences(of: "surface", with: "")
                    .components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .joined()
                currentSurface = Int(surfaceStr)
                continue
            }
            
            // Only process animations for the current surface
            guard currentSurface == surfaceID else { continue }
            
            // Parse animation interval
            if trimmed.contains(".interval,") {
                let parts = trimmed.components(separatedBy: ",")
                if parts.count >= 2 {
                    let animIDStr = parts[0].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    currentAnimationID = Int(animIDStr)
                    animationInterval = AnimationDefinition.AnimationInterval(from: parts[1])
                }
            }
            
            // Parse animation pattern
            if trimmed.contains(".pattern") {
                let parts = trimmed.components(separatedBy: ",")
                if parts.count >= 5 {
                    let surfaceID = Int(parts[1]) ?? -1
                    let duration = Int(parts[2]) ?? 0
                    let x = Int(parts[3]) ?? 0
                    let y = Int(parts[4]) ?? 0
                    
                    let pattern = AnimationPattern(
                        surfaceID: surfaceID,
                        duration: duration,
                        x: x,
                        y: y,
                        type: .overlay
                    )
                    animationPatterns.append(pattern)
                }
            }
            
            // Parse collision region
            if trimmed.contains(".collision,") {
                let parts = trimmed.components(separatedBy: ",")
                if parts.count >= 6 {
                    let indexStr = parts[0].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    let x1 = Int(parts[1]) ?? 0
                    let y1 = Int(parts[2]) ?? 0
                    let x2 = Int(parts[3]) ?? 0
                    let y2 = Int(parts[4]) ?? 0
                    let name = parts.count > 6 ? parts[6] : ""
                    
                    if let surface = currentSurface {
                        let region = CollisionRegion(
                            name: name,
                            rect: CGRect(x: CGFloat(min(x1, x2)), 
                                       y: CGFloat(min(y1, y2)), 
                                       width: CGFloat(abs(x2 - x1)), 
                                       height: CGFloat(abs(y2 - y1)))
                        )
                        collisions[surface]?.append(region)
                    }
                }
            }
            
            // Parse point definition
            if trimmed.contains(".centerx,") || trimmed.contains(".centery,") {
                let parts = trimmed.components(separatedBy: ",")
                if parts.count >= 3 {
                    let fullKey = parts[0]
                    var pointName = ""
                    if let dot = fullKey.firstIndex(of: ".") {
                        pointName = String(fullKey[fullKey.startIndex..<dot])
                    }
                    let value = Int(parts[1]) ?? 0
                    
                    if let surface = currentSurface, !pointName.isEmpty {
                        if points[surface] == nil {
                            points[surface] = [:]
                        }
                        if fullKey.hasSuffix("centerx") {
                            var existing = points[surface]?[pointName] ?? CGPoint(x: 0, y: 0)
                            points[surface]?[pointName] = CGPoint(x: CGFloat(value), y: existing.y)
                        } else {
                            var existing = points[surface]?[pointName] ?? CGPoint(x: 0, y: 0)
                            points[surface]?[pointName] = CGPoint(x: existing.x, y: CGFloat(value))
                        }
                    }
                }
            }
            
            // End of surface block
            if trimmed == "}" && currentAnimationID != nil && !animationPatterns.isEmpty {
                let animation = AnimationDefinition(
                    id: currentAnimationID!,
                    interval: animationInterval,
                    patterns: animationPatterns
                )
                animations[currentAnimationID!] = animation
                
                currentAnimationID = nil
                animationPatterns = []
                animationInterval = .never
            }
        }
    }
    
    /// Start playing an animation
    func playAnimation(id: Int, wait: Bool = false) {
        guard let definition = animations[id] else {
            Log.info("[AnimationEngine] Animation \(id) not found")
            return
        }

        let active = ActiveAnimation(definition: definition)
        activeAnimations[id] = active

        startUpdateLoop()

        Log.debug("[AnimationEngine] Started animation \(id), wait: \(wait)")
    }
    
    /// Pause an animation
    func pauseAnimation(id: Int) {
        activeAnimations[id]?.isPaused = true
        Log.debug("[AnimationEngine] Paused animation \(id)")
    }
    
    /// Resume an animation
    func resumeAnimation(id: Int) {
        activeAnimations[id]?.isPaused = false
        Log.debug("[AnimationEngine] Resumed animation \(id)")
    }
    
    /// Clear/stop an animation
    func clearAnimation(id: Int) {
        activeAnimations.removeValue(forKey: id)
        onAnimationComplete?(id)
        Log.debug("[AnimationEngine] Cleared animation \(id)")
        
        if activeAnimations.isEmpty {
            stopUpdateLoop()
        }
    }
    
    /// Offset an animation
    func offsetAnimation(id: Int, x: Double, y: Double) {
        activeAnimations[id]?.offset = CGPoint(x: x, y: y)
        Log.debug("[AnimationEngine] Offset animation \(id) by (\(x), \(y))")
    }
    
    /// Stop all animations
    func stopAllAnimations() {
        activeAnimations.removeAll()
        stopUpdateLoop()
        Log.debug("[AnimationEngine] Stopped all animations")
    }
    
    /// Get collision regions for a surface
    func getCollisions(for surfaceID: Int) -> [CollisionRegion] {
        return collisions[surfaceID] ?? []
    }
    
    /// Get point definition for a surface
    func getPoint(named pointName: String, for surfaceID: Int) -> CGPoint? {
        return points[surfaceID]?[pointName]
    }
    
    /// Get all point definitions for a surface
    func getAllPoints(for surfaceID: Int) -> [String: CGPoint]? {
        return points[surfaceID]
    }
    
    // MARK: - Update Loop
    
    private func startUpdateLoop() {
        guard !isRunning else { return }
        isRunning = true
        
        // Use CADisplayLink equivalent for macOS
        Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self, self.isRunning else {
                timer.invalidate()
                return
            }
            self.update()
        }
    }
    
    private func stopUpdateLoop() {
        isRunning = false
    }
    
    private func update() {
        var completedAnimations: [Int] = []
        
        for (id, animation) in activeAnimations {
            let isComplete = animation.update()
            
            // Notify of current pattern
            if let pattern = animation.currentPattern {
                var adjustedPattern = pattern
                // Apply offset if set
                if animation.offset != .zero {
                    adjustedPattern = AnimationPattern(
                        surfaceID: pattern.surfaceID,
                        duration: pattern.duration,
                        x: pattern.x + Int(animation.offset.x),
                        y: pattern.y + Int(animation.offset.y),
                        type: pattern.type
                    )
                }
                onAnimationUpdate?(id, adjustedPattern)
            }
            
            if isComplete {
                completedAnimations.append(id)
            }
        }
        
        // Clean up completed animations
        for id in completedAnimations {
            clearAnimation(id: id)
        }
    }
    
    // MARK: - Metal Rendering (for future GPU acceleration)
    
    /// Prepare Metal textures for animation frames (future enhancement)
    func prepareMetalTextures(for images: [NSImage]) {
        guard device != nil else { return }

        // TODO: Convert NSImages to Metal textures
        // This would allow GPU-accelerated compositing
        Log.debug("[AnimationEngine] Preparing \(images.count) textures for Metal rendering")
    }
    
    deinit {
        stopAllAnimations()
    }
}
