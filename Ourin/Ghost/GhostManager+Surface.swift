import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Surface Loading and Compositing

extension GhostManager {
    func updateSurface(id: Int) {
        let scope = currentScope
        
        // Clear overlays when surface changes (per UKADOC spec)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let vm = self.characterViewModels[scope] {
                vm.overlays.removeAll()
                Log.debug("[GhostManager] Cleared overlays for scope \(scope) due to surface change")
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let image = self.loadImage(surfaceId: id, scope: scope)
            DispatchQueue.main.async {
                // If the requested surface doesn't exist, keep the current surface
                guard let image = image else {
                    Log.info("[GhostManager] Surface \(id) not found for scope \(scope), keeping current surface")
                    return
                }

                if let vm = self.characterViewModels[scope] {
                    vm.image = image
                }
                if let win = self.characterWindows[scope] {
                    // Resize window to fit the new surface
                    win.setContentSize(image.size)
                    self.positionBalloonWindow()
                }
            }
        }
    }

    func loadImage(surfaceId: Int, scope: Int) -> NSImage? {
        let shellURL = ghostURL.appendingPathComponent("shell/master")
        // いくつかのシェルは surface0000.png のような4桁ゼロ埋めを使う。
        func pad4(_ n: Int) -> String { String(format: "%04d", n) }

        var candidates: [String] = []
        // スコープ付きの命名: surface{scope}{id}.png / surface{scope}{0000id}.png
        if scope == 1 {
            candidates.append("surface1\(surfaceId).png")
            candidates.append("surface1\(pad4(surfaceId)).png")
        }
        // 共通命名: surface{n}.png / surface{000n}.png
        candidates.append("surface\(surfaceId).png")
        candidates.append("surface\(pad4(surfaceId)).png")

        for name in candidates {
            let url = shellURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                // PNA マスクがあれば適用（白=不透明、黒=透明として扱う想定）
                let pnaURL = url.deletingPathExtension().appendingPathExtension("pna")
                if FileManager.default.fileExists(atPath: pnaURL.path),
                   let masked = applyPNAMask(baseURL: url, maskURL: pnaURL) {
                    Log.debug("[GhostManager] Image loaded with PNA mask: \(name)")
                    return masked
                }
                Log.debug("[GhostManager] Image loaded: \(name)")
                return img
            }
        }
        Log.info("[GhostManager] No surface image found for id=\(surfaceId) scope=\(scope). Tried: \(candidates)")
        return nil
    }

    // PNA マスクを適用して透過画像を生成
    func applyPNAMask(baseURL: URL, maskURL: URL) -> NSImage? {
        guard let baseCI = CIImage(contentsOf: baseURL),
              let maskCI = CIImage(contentsOf: maskURL) else { return nil }
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: baseCI.extent)
        guard let output = CIFilter(name: "CIBlendWithMask",
                                    parameters: [kCIInputImageKey: baseCI,
                                                 kCIInputBackgroundImageKey: clear,
                                                 kCIInputMaskImageKey: maskCI])?.outputImage else { return nil }
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(output, from: baseCI.extent) else { return nil }
        let size = NSSize(width: cg.width, height: cg.height)
        let nsimg = NSImage(size: size)
        nsimg.lockFocus()
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(origin: .zero, size: size))
        nsimg.unlockFocus()
        return nsimg
    }

    // MARK: - Surface Compositing
    
    /// Handle surface overlay/compositing - \![anim,add,overlay,ID]
    func handleSurfaceOverlay(surfaceID: Int) {
        Log.debug("[GhostManager] Adding surface overlay: \(surfaceID)")
        
        // Load the surface image from the shell directory
        guard let shellPath = loadShellPath() else {
            Log.info("[GhostManager] Cannot add overlay - shell path not found")
            return
        }
        
        // Surface files are named surface<ID>.png
        let surfaceFileName = "surface\(surfaceID).png"
        let surfacePath = shellPath.appendingPathComponent(surfaceFileName)
        
        guard FileManager.default.fileExists(atPath: surfacePath.path) else {
            Log.info("[GhostManager] Surface file not found: \(surfacePath.path)")
            return
        }
        
        guard let image = NSImage(contentsOf: surfacePath) else {
            Log.info("[GhostManager] Failed to load surface image: \(surfaceFileName)")
            return
        }
        
        // Add overlay to current scope's character view model
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            let overlay = CharacterViewModel.SurfaceOverlay(
                id: surfaceID,
                image: image,
                offset: .zero,
                alpha: 1.0
            )
            
            vm.overlays.append(overlay)
            Log.debug("[GhostManager] Added surface overlay \(surfaceID) to scope \(self.currentScope)")
        }
    }
    
    /// Get the current shell directory path
    func loadShellPath() -> URL? {
        // Try to get shell path from ghost configuration
        // Default to "master" shell if not specified
        let shellName = "master" // TODO: Get from ghost config
        return ghostURL.appendingPathComponent("shell").appendingPathComponent(shellName)
    }
    
    /// Clear all overlays for the current scope
    func clearSurfaceOverlays() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.overlays.removeAll()
            Log.debug("[GhostManager] Cleared all surface overlays for scope \(self.currentScope)")
        }
    }
    
    /// Clear a specific overlay by ID
    func clearSpecificOverlay(id: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.overlays.removeAll { $0.id == id }
            Log.debug("[GhostManager] Cleared overlay \(id) for scope \(self.currentScope)")
        }
    }
    
    /// Offset a specific overlay
    func offsetOverlay(id: Int, x: Double, y: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            if let index = vm.overlays.firstIndex(where: { $0.id == id }) {
                vm.overlays[index].offset = CGPoint(x: x, y: y)
                Log.debug("[GhostManager] Offset overlay \(id) by (\(x), \(y))")
            }
        }
    }
    
}
