import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications

// MARK: - Animation Engine Integration

extension GhostManager {
    // MARK: - Animation Engine Integration

    private struct SerikoStorage {
        static var executors: [ObjectIdentifier: SerikoExecutor] = [:]
        static var timers: [ObjectIdentifier: Timer] = [:]
    }

    private var serikoExecutor: SerikoExecutor {
        let key = ObjectIdentifier(self)
        if let existing = SerikoStorage.executors[key] {
            return existing
        }
        let created = SerikoExecutor()
        SerikoStorage.executors[key] = created
        return created
    }

    private var serikoLoopTimer: Timer? {
        get { SerikoStorage.timers[ObjectIdentifier(self)] }
        set {
            let key = ObjectIdentifier(self)
            if let timer = newValue {
                SerikoStorage.timers[key] = timer
            } else {
                SerikoStorage.timers.removeValue(forKey: key)
            }
        }
    }

    func shutdownSerikoLoop() {
        serikoLoopTimer?.invalidate()
        serikoLoopTimer = nil
        serikoExecutor.stopAllAnimations()
    }

    /// Setup animation engine callbacks
    func setupAnimationCallbacks() {
        animationEngine.onAnimationUpdate = { [weak self] animID, pattern in
            guard let self = self, let pattern = pattern else { return }

            // Update surface overlay based on animation pattern and type
            if pattern.surfaceID >= 0 {
                self.handleSurfaceOverlay(surfaceID: pattern.surfaceID, type: pattern.type)

                // Apply offset if specified
                if pattern.x != 0 || pattern.y != 0 {
                    self.offsetOverlay(id: "surface_\(pattern.surfaceID)_", x: Double(pattern.x), y: Double(pattern.y))
                }
            }
        }

        animationEngine.onAnimationComplete = { [weak self] animID in
            guard let self = self else { return }

            // If we were waiting for this animation, resume playback
            if self.waitingForAnimation == animID {
                self.waitingForAnimation = nil
                if self.isPlaying {
                    self.processNextUnit()
                }
            }
        }

        serikoExecutor.onMethodInvoked = { [weak self] animID, method, surfaceID, x, y in
            guard let self = self else { return }
            switch method {
            case .overlay:
                self.handleSurfaceOverlay(surfaceID: surfaceID, type: .overlay)
            case .overlayFast:
                self.handleSurfaceOverlay(surfaceID: surfaceID, type: .overlay)
            case .base:
                self.handleAnimAddBase(id: surfaceID)
            case .move:
                self.handleAnimAddMove(x: x, y: y)
            case .replace:
                self.handleSurfaceOverlay(surfaceID: surfaceID, type: .replace)
            case .start:
                _ = self.serikoExecutor.executeAnimation(id: surfaceID)
            case .alternativeStart:
                _ = self.serikoExecutor.executeAnimation(id: surfaceID)
            case .stop:
                self.serikoExecutor.stopAnimation(id: animID)
            case .reduce, .asis, .unknown:
                break
            }
        }

        serikoExecutor.onAnimationFinished = { [weak self] animID in
            guard let self = self else { return }
            if self.waitingForAnimation == animID {
                self.waitingForAnimation = nil
                if self.isPlaying {
                    self.processNextUnit()
                }
            }
            self.stopSerikoLoopIfIdle()
        }
    }

    /// Play an animation
    func playAnimation(id: Int, wait: Bool) {
        // Load animations from surfaces.txt if not already loaded
        loadAnimationsForCurrentSurface()

        if serikoExecutor.executeAnimation(id: id) {
            startSerikoLoopIfNeeded()
            return
        }
        animationEngine.playAnimation(id: id, wait: wait)
    }

    /// Play an animation and wait for completion
    func playAnimationAndWait(id: Int) {
        waitingForAnimation = id
        if serikoExecutor.activeAnimations[id] != nil {
            return
        }
        playAnimation(id: id, wait: true)
        // Playback will resume when animation completes via callback
    }

    func waitForAnimation(id: Int) {
        waitingForAnimation = id
        if serikoExecutor.activeAnimations[id] == nil {
            _ = serikoExecutor.executeAnimation(id: id)
            startSerikoLoopIfNeeded()
        }
    }

    /// Load animations from surfaces.txt for current surface
    func loadAnimationsForCurrentSurface() {
        guard let shellPath = loadShellPath() else { return }

        let surfacesPath = shellPath.appendingPathComponent("surfaces.txt")
        guard FileManager.default.fileExists(atPath: surfacesPath.path) else {
            Log.info("[GhostManager] surfaces.txt not found at: \(surfacesPath.path)")
            return
        }

        // Try to load with different encodings
        var content: String?
        if let utf8Content = try? String(contentsOf: surfacesPath, encoding: .utf8) {
            content = utf8Content
        } else if let shiftJISContent = try? String(contentsOf: surfacesPath, encoding: .shiftJIS) {
            content = shiftJISContent
        }

        guard let surfacesContent = content else {
            Log.info("[GhostManager] Failed to read surfaces.txt")
            return
        }

        // Get current surface ID from character view model
        guard characterViewModels[currentScope] != nil else { return }

        // Parse surface ID from image if available
        // For now, assume surface 0 - in production, track current surface ID
        let surfaceID = 0 // TODO: Track actual current surface ID

        animationEngine.loadAnimations(surfaceID: surfaceID, content: surfacesContent)
        let parsed = SerikoParser.parseSurfaces(surfacesContent)
        if let surface = parsed[surfaceID] {
            serikoExecutor.register(animations: surface.animations)
        }
        Log.debug("[GhostManager] Loaded animations for surface \(surfaceID)")
    }

    // MARK: - Animation Control Handlers

    /// Handle \![anim,clear,ID] command
    func handleAnimClear(id: Int) {
        serikoExecutor.stopAnimation(id: id)
        animationEngine.clearAnimation(id: id)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            vm.overlays.removeAll { $0.id.hasPrefix("surface_\(id)_") }
            Log.debug("[GhostManager] Cleared animation overlays for \(id)")
        }
    }

    /// Handle \![anim,pause,ID] command
    func handleAnimPause(id: Int) {
        serikoExecutor.pauseAnimation(id: id)
        animationEngine.pauseAnimation(id: id)
        Log.debug("[GhostManager] Paused animation \(id)")
    }

    /// Handle \![anim,resume,ID] command
    func handleAnimResume(id: Int) {
        serikoExecutor.resumeAnimation(id: id)
        startSerikoLoopIfNeeded()
        animationEngine.resumeAnimation(id: id)
        Log.debug("[GhostManager] Resumed animation \(id)")
    }

    /// Handle \![anim,offset,ID,x,y] command
    func handleAnimOffset(id: Int, x: Int, y: Int) {
        serikoExecutor.offsetAnimation(id: id, x: x, y: y)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            if let index = vm.overlays.firstIndex(where: { $0.id.hasPrefix("surface_\(id)_") }) {
                vm.overlays[index].offset = CGPoint(x: CGFloat(x), y: CGFloat(y))
                Log.debug("[GhostManager] Set offset for animation \(id) to (\(x), \(y))")
            }
        }
    }

    /// Handle \![anim,stop] command
    func handleAnimStop() {
        serikoExecutor.stopAllAnimations()
        stopSerikoLoopIfIdle()
        animationEngine.stopAllAnimations()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            vm.overlays.removeAll()
            Log.debug("[GhostManager] Stopped all animations and cleared overlays")
        }
    }

    /// Handle \![anim,add,overlay,ID] command
    func handleAnimAddOverlay(id: Int) {
        handleSurfaceOverlay(surfaceID: id)
        Log.debug("[GhostManager] Added overlay \(id)")
    }

    /// Handle \![anim,add,overlayfast,ID] command
    func handleAnimAddOverlayFast(id: Int) {
        handleSurfaceOverlay(surfaceID: id)
        Log.debug("[GhostManager] Added fast overlay \(id)")
    }

    /// Handle \![anim,add,base,ID] command
    func handleAnimAddBase(id: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            // Load base surface image
            if let shellPath = self.loadShellPath() {
                let imagePath = shellPath.appendingPathComponent("surface\(id).png")
                if let image = NSImage(contentsOf: imagePath) {
                    vm.image = image
                    Log.debug("[GhostManager] Set base surface to \(id)")
                }
            }
        }
    }

    /// Handle \![anim,add,move,x,y] command
    func handleAnimAddMove(x: Int, y: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            // Move all overlays
            for i in vm.overlays.indices {
                vm.overlays[i].offset.x += CGFloat(x)
                vm.overlays[i].offset.y += CGFloat(y)
            }
            Log.debug("[GhostManager] Moved all overlays by (\(x), \(y))")
        }
    }

    private func startSerikoLoopIfNeeded() {
        guard serikoLoopTimer == nil else { return }
        serikoLoopTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.serikoExecutor.startLoop()
            self.stopSerikoLoopIfIdle()
        }
    }

    private func stopSerikoLoopIfIdle() {
        guard serikoExecutor.activeAnimations.isEmpty else { return }
        serikoLoopTimer?.invalidate()
        serikoLoopTimer = nil
    }
}
