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
    enum Shape {
        case rectangle
        case ellipse(rect: CGRect)
        case circle(center: CGPoint, radius: CGFloat)
        case polygon(points: [CGPoint])
    }

    let name: String
    let rect: CGRect
    let shape: Shape

    init(name: String, rect: CGRect) {
        self.name = name
        self.rect = rect
        self.shape = .rectangle
    }

    init(name: String, ellipseRect: CGRect) {
        self.name = name
        self.rect = ellipseRect
        self.shape = .ellipse(rect: ellipseRect)
    }

    init(name: String, circleCenter: CGPoint, radius: CGFloat) {
        self.name = name
        self.rect = CGRect(
            x: circleCenter.x - radius,
            y: circleCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        self.shape = .circle(center: circleCenter, radius: radius)
    }

    init(name: String, polygonPoints points: [CGPoint]) {
        self.name = name
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        self.rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        self.shape = .polygon(points: points)
    }

    func contains(_ point: CGPoint) -> Bool {
        guard rect.contains(point) else { return false }

        switch shape {
        case .rectangle:
            return true
        case .ellipse(let ellipseRect):
            guard ellipseRect.width > 0, ellipseRect.height > 0 else { return false }
            let center = CGPoint(x: ellipseRect.midX, y: ellipseRect.midY)
            let radiusX = ellipseRect.width / 2
            let radiusY = ellipseRect.height / 2
            let normalizedX = (point.x - center.x) / radiusX
            let normalizedY = (point.y - center.y) / radiusY
            return normalizedX * normalizedX + normalizedY * normalizedY <= 1
        case .circle(let center, let radius):
            let dx = point.x - center.x
            let dy = point.y - center.y
            return dx * dx + dy * dy <= radius * radius
        case .polygon(let points):
            guard points.count >= 3 else { return false }
            var inside = false
            var previous = points[points.count - 1]
            for current in points {
                let crossesY = (current.y > point.y) != (previous.y > point.y)
                if crossesY {
                    let xAtPointY = (previous.x - current.x) * (point.y - current.y)
                        / (previous.y - current.y) + current.x
                    if point.x < xAtPointY {
                        inside.toggle()
                    }
                }
                previous = current
            }
            return inside
        }
    }
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
    private var preparedTextures: [Int: MTLTexture] = [:]
    
    // Animation state
    private var animations: [Int: AnimationDefinition] = [:]
    private var activeAnimations: [Int: ActiveAnimation] = [:]

    /// PROPERTY `currentghost.scope(ID).animation.num` 用の実行中ID一覧。
    var activeAnimationIDs: [Int] {
        activeAnimations.keys.sorted()
    }
    private var displayLink: CVDisplayLink?
    private var isRunning: Bool = false
    
    // Collision and point data
    private var collisions: [Int: [CollisionRegion]] = [:]
    /// surfaceID -> animationID -> regions. These regions are only returned
    /// while the corresponding animation is active.
    private var animationCollisions: [Int: [Int: [CollisionRegion]]] = [:]
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

    // MARK: - Collision Parsing

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func integer(_ value: String) -> Int? {
        Int(trimmed(value))
    }

    /// Returns true for collisionex headers and false for regular collision
    /// headers. Both the standard numbered form (`collisionex0`) and the
    /// legacy dotted form (`surface0.collision`) are accepted.
    private func collisionHeaderKind(_ header: String) -> Bool? {
        let key = String(header.split(separator: ".").last ?? "")
        if key == "collisionex" || key.hasPrefix("collisionex") {
            let suffix = key.dropFirst("collisionex".count)
            return suffix.isEmpty || suffix.allSatisfy(\.isNumber) ? true : nil
        }
        if key == "collision" || key.hasPrefix("collision") {
            let suffix = key.dropFirst("collision".count)
            return suffix.isEmpty || suffix.allSatisfy(\.isNumber) ? false : nil
        }
        return nil
    }

    private func collisionShape(_ value: String) -> String? {
        switch trimmed(value).lowercased() {
        case "rect", "rectangle": return "rect"
        case "ellipse": return "ellipse"
        case "circle": return "circle"
        case "polygon", "poly": return "polygon"
        case "region": return "region"
        default: return nil
        }
    }

    private func makeRect(from values: [String]) -> CGRect? {
        guard values.count == 4,
              let x1 = integer(values[0]),
              let y1 = integer(values[1]),
              let x2 = integer(values[2]),
              let y2 = integer(values[3]) else { return nil }
        return CGRect(
            x: CGFloat(min(x1, x2)),
            y: CGFloat(min(y1, y2)),
            width: CGFloat(abs(x2 - x1)),
            height: CGFloat(abs(y2 - y1))
        )
    }

    /// Parses the standard `collisionexN,ID,type,...` form and the historical
    /// Ourin test form `collisionex,type,...,ID`.
    private func parseExtendedCollisionRegion(_ values: [String]) -> CollisionRegion? {
        guard values.count >= 2 else { return nil }

        let shape: String
        let name: String
        let coordinates: [String]
        if let shapeFirst = collisionShape(values[0]) {
            shape = shapeFirst
            name = trimmed(values.last ?? "")
            coordinates = Array(values.dropFirst().dropLast())
        } else {
            guard let standardShape = collisionShape(values[1]) else { return nil }
            shape = standardShape
            name = trimmed(values[0])
            coordinates = Array(values.dropFirst(2))
        }
        guard !name.isEmpty else { return nil }

        switch shape {
        case "rect":
            guard let rect = makeRect(from: coordinates) else { return nil }
            return CollisionRegion(name: name, rect: rect)
        case "ellipse":
            guard let rect = makeRect(from: coordinates) else { return nil }
            return CollisionRegion(name: name, ellipseRect: rect)
        case "circle":
            guard coordinates.count == 3,
                  let cx = integer(coordinates[0]),
                  let cy = integer(coordinates[1]),
                  let radius = integer(coordinates[2]),
                  radius >= 0 else { return nil }
            return CollisionRegion(
                name: name,
                circleCenter: CGPoint(x: CGFloat(cx), y: CGFloat(cy)),
                radius: CGFloat(radius)
            )
        case "polygon":
            guard coordinates.count >= 6, coordinates.count.isMultiple(of: 2) else { return nil }
            var points: [CGPoint] = []
            for index in stride(from: 0, to: coordinates.count, by: 2) {
                guard let x = integer(coordinates[index]),
                      let y = integer(coordinates[index + 1]) else { return nil }
                points.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
            return CollisionRegion(name: name, polygonPoints: points)
        case "region":
            // Image-colour regions require the loaded surface bitmap and are
            // intentionally kept out of this geometry-only parser.
            return nil
        default:
            return nil
        }
    }

    private func parseCollisionLine(_ line: String) -> CollisionRegion? {
        let parts = line.components(separatedBy: ",")
        guard let header = parts.first,
              let isExtended = collisionHeaderKind(header) else { return nil }
        let values = Array(parts.dropFirst())
        if isExtended {
            return parseExtendedCollisionRegion(values)
        }

        // collisionN,x1,y1,x2,y2,name
        guard values.count >= 5,
              let rect = makeRect(from: Array(values.prefix(4))) else { return nil }
        let name = trimmed(values[4])
        guard !name.isEmpty else { return nil }
        return CollisionRegion(name: name, rect: rect)
    }

    private func parseAnimationCollisionLine(
        _ line: String
    ) -> (animationID: Int, region: CollisionRegion)? {
        let parts = line.components(separatedBy: ",")
        guard let header = parts.first,
              let dot = header.firstIndex(of: ".") else { return nil }
        let animationPart = String(header[..<dot])
        guard animationPart.hasPrefix("animation"),
              let animationID = Int(String(animationPart.dropFirst("animation".count))),
              collisionHeaderKind(String(header[header.index(after: dot)...])) != nil else {
            return nil
        }
        let normalizedLine = (
            [String(header[header.index(after: dot)...])] + Array(parts.dropFirst())
        ).joined(separator: ",")
        guard let region = parseCollisionLine(normalizedLine) else { return nil }
        return (animationID, region)
    }
    
    // MARK: - Animation Management
    
    /// Load animations from surfaces.txt content
    func loadAnimations(surfaceID: Int, content: String) {
        // アニメーション定義は現在のサーフェスに限定する。前回のサーフェスの定義を
        // 残すと、旧サーフェス用のオーバーレイが新しい表情へ混入する。
        animations.removeAll()
        let lines = content.components(separatedBy: .newlines)
        var currentSurfaceIDs: Set<Int> = []
        var currentAnimationID: Int? = nil
        var animationPatterns: [AnimationPattern] = []
        var animationInterval: AnimationDefinition.AnimationInterval = .never

        // Reloading a surface definition must replace, rather than append to,
        // collision and point data. Otherwise a shell reload duplicates regions
        // and leaves stale animation-only regions behind.
        collisions[surfaceID] = []
        animationCollisions[surfaceID] = [:]
        points[surfaceID] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse surface definition (supports groups: surface0,3,5,6)
            if trimmed.hasPrefix("surface") && !trimmed.contains("{") {
                let ids = SerikoParser.parseSurfaceIDs(from: trimmed)
                currentSurfaceIDs = Set(ids)
                continue
            }

            // Only process animations for the target surface
            guard currentSurfaceIDs.contains(surfaceID) else { continue }
            
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
            
            // Parse animation-only collision regions before regular collision
            // regions. UKADOC defines these as active only while animationID is
            // running; they must not leak into the base surface hit-test.
            if let animationCollision = parseAnimationCollisionLine(trimmed) {
                animationCollisions[surfaceID, default: [:]][animationCollision.animationID, default: []]
                    .append(animationCollision.region)
                continue
            }
            if let region = parseCollisionLine(trimmed) {
                collisions[surfaceID, default: []].append(region)
            }
            
            // Parse point definition
            if trimmed.contains("centerx,") || trimmed.contains("centery,") {
                let parts = trimmed.components(separatedBy: ",")
                if parts.count >= 2 {
                    let fullKey = parts[0]
                    let keyParts = fullKey.split(separator: ".").map(String.init)
                    let pointName: String
                    if keyParts.count >= 2, keyParts[0] == "point" {
                        pointName = keyParts.count == 2 ? "center" : keyParts[1]
                    } else {
                        pointName = ""
                    }
                    let value = Int(parts[1]) ?? 0
                    
                    if !pointName.isEmpty {
                        if points[surfaceID] == nil {
                            points[surfaceID] = [:]
                        }
                        if fullKey.hasSuffix("centerx") {
                            var existing = points[surfaceID]?[pointName] ?? CGPoint(x: 0, y: 0)
                            points[surfaceID]?[pointName] = CGPoint(x: CGFloat(value), y: existing.y)
                        } else {
                            var existing = points[surfaceID]?[pointName] ?? CGPoint(x: 0, y: 0)
                            points[surfaceID]?[pointName] = CGPoint(x: existing.x, y: CGFloat(value))
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

    /// Return the currently configured offset for an active animation.
    func offset(for id: Int) -> CGPoint? {
        activeAnimations[id]?.offset
    }
    
    /// Stop all animations
    func stopAllAnimations() {
        activeAnimations.removeAll()
        stopUpdateLoop()
        Log.debug("[AnimationEngine] Stopped all animations")
    }
    
    /// Get collision regions for a surface. Animation-only regions are
    /// prepended in animation ID order so they take precedence over the base
    /// surface when regions overlap.
    func getCollisions(for surfaceID: Int, activeAnimationIDs: Set<Int> = []) -> [CollisionRegion] {
        let activeRegions = activeAnimationIDs.sorted().flatMap {
            animationCollisions[surfaceID]?[$0] ?? []
        }
        return activeRegions + (collisions[surfaceID] ?? [])
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
        guard let device else { return }
        let loader = MTKTextureLoader(device: device)
        var generated: [Int: MTLTexture] = [:]
        for (index, image) in images.enumerated() {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cgImage = rep.cgImage else {
                continue
            }
            do {
                let texture = try loader.newTexture(cgImage: cgImage, options: [.SRGB: false])
                generated[index] = texture
            } catch {
                Log.info("[AnimationEngine] Failed to create Metal texture for frame \(index): \(error.localizedDescription)")
            }
        }
        preparedTextures = generated
        Log.debug("[AnimationEngine] Prepared \(generated.count)/\(images.count) textures for Metal rendering")
    }
    
    deinit {
        stopAllAnimations()
    }
}
