import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Animation Engine Integration

extension GhostManager {
    // MARK: - Animation Engine Integration
    
    /// Setup animation engine callbacks
    func setupAnimationCallbacks() {
        animationEngine.onAnimationUpdate = { [weak self] animID, pattern in
            guard let self = self, let pattern = pattern else { return }
            
            // Update surface overlay based on animation pattern
            if pattern.surfaceID >= 0 {
                self.handleSurfaceOverlay(surfaceID: pattern.surfaceID)
                
                // Apply offset if specified
                if pattern.x != 0 || pattern.y != 0 {
                    self.offsetOverlay(id: pattern.surfaceID, x: Double(pattern.x), y: Double(pattern.y))
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
    }
    
    /// Play an animation
    func playAnimation(id: Int, wait: Bool) {
        // Load animations from surfaces.txt if not already loaded
        loadAnimationsForCurrentSurface()
        
        animationEngine.playAnimation(id: id, wait: wait)
    }
    
    /// Play an animation and wait for completion
    func playAnimationAndWait(id: Int) {
        waitingForAnimation = id
        playAnimation(id: id, wait: true)
        // Playback will resume when animation completes via callback
    }
    
    /// Load animations from surfaces.txt for the current surface
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
        Log.debug("[GhostManager] Loaded animations for surface \(surfaceID)")
    }
    
}
