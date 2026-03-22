import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Surface Loading and Compositing

extension GhostManager {
    func updateSurface(id: Int) {
        let scope = currentScope
        let oldSurfaceID = characterViewModels[scope]?.currentSurfaceID ?? 0
        
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
                // If requested surface doesn't exist, keep current surface
                guard let image = image else {
                    Log.info("[GhostManager] Surface \(id) not found for scope \(scope), keeping current surface")
                    return
                }

                if let vm = self.characterViewModels[scope] {
                    vm.image = image
                    vm.currentSurfaceID = id
                }
                if let win = self.characterWindows[scope] {
                    // Resize window to fit to new surface
                    win.setContentSize(image.size)
                    self.positionBalloonWindow()
                }
                
                // Dispatch OnSurfaceChange event
                let params: [String: String] = [
                    "Reference0": String(oldSurfaceID),
                    "Reference1": String(id)
                ]
                EventBridge.shared.notify(.OnSurfaceChange, params: params)
                Log.debug("[GhostManager] OnSurfaceChange dispatched: \(oldSurfaceID) -> \(id)")
            }
        }
        
        // Schedule OnSurfaceRestore after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            guard self != nil else { return }
            let params: [String: String] = [
                "Reference0": oldSurfaceID >= 0 ? String(oldSurfaceID) : "0",
                "Reference1": String(id)
            ]
            EventBridge.shared.notify(.OnSurfaceRestore, params: params)
            Log.debug("[GhostManager] OnSurfaceRestore dispatched")
        }
    }

    func loadImage(surfaceId: Int, scope: Int) -> NSImage? {
        guard let shellURL = loadShellPath() else {
            Log.info("[GhostManager] Cannot load surface: shell path unavailable")
            return nil
        }
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
    /// - Parameters:
    ///   - surfaceID: The surface ID to overlay
    ///   - type: The animation pattern type (overlay/base/replace/bind)
    ///   - animationID: Optional owner animation ID for deterministic overlay tracking
    func handleSurfaceOverlay(surfaceID: Int, type: AnimationPatternType = .overlay, animationID: Int? = nil, initialOffset: CGPoint? = nil) {
        Log.debug("[GhostManager] Adding surface overlay: \(surfaceID), type: \(type)")
        
        // Process based on pattern type
        switch type {
        case .base:
            // Replace base surface
            updateSurface(id: surfaceID)
            return
            
        case .replace:
            // Replace current surface with this one
            updateSurface(id: surfaceID)
            return
            
        case .bind:
            // Bind dressup part as a persistent overlay that can coexist with base surface.
            break
            
        case .overlay:
            // Default overlay behavior - continue to load surface
            break
        }
        
        // Load surface image from shell directory
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
            let insertionOrder = (vm.overlays.map(\.insertionOrder).max() ?? -1) + 1
            let zOrder: Int
            switch type {
            case .base, .replace:
                zOrder = 0
            case .overlay:
                zOrder = 100
            case .bind:
                zOrder = 200
            }
            let idPrefix = type == .bind ? "dressup_bind_\(surfaceID)_" : "surface_\(surfaceID)_"
            let animationMarker = animationID.map { "anim_\($0)_" } ?? ""
            
        let overlay = SurfaceOverlay(
            id: "\(idPrefix)\(animationMarker)\(UUID().uuidString)",
            image: image,
            offset: initialOffset ?? CGPoint.zero,
            alpha: 1.0,
            zOrder: zOrder,
            insertionOrder: insertionOrder
        )
            
            vm.overlays.append(overlay)
            Log.debug("[GhostManager] Added surface overlay \(surfaceID) to scope \(self.currentScope)")
        }
    }
    
    /// Get the current shell directory path
    func loadShellPath() -> URL? {
        let shellName = activeShellName.isEmpty ? "master" : activeShellName
        return ghostURL.appendingPathComponent("shell").appendingPathComponent(shellName)
    }

    /// Switch active shell directory and refresh current surfaces.
    @discardableResult
    func switchShell(named shellName: String, raiseEvent: Bool = false) -> Bool {
        let trimmed = shellName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.info("[GhostManager] change,shell ignored: empty shell name")
            return false
        }

        let shellPath = ghostURL.appendingPathComponent("shell").appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: shellPath.path) else {
            Log.info("[GhostManager] Shell not found: \(trimmed)")
            return false
        }

        let previousShell = activeShellName
        if raiseEvent {
            EventBridge.shared.notify(.OnShellChanging, params: ["Reference0": previousShell, "Reference1": trimmed])
        }
        activeShellName = trimmed
        loadDressupConfiguration()

        let sakuraSurface = ghostConfig?.sakuraDefaultSurface ?? 0
        let keroSurface = ghostConfig?.keroDefaultSurface ?? 10
        let previousScope = currentScope

        currentScope = 0
        updateSurface(id: sakuraSurface)
        currentScope = 1
        updateSurface(id: keroSurface)
        currentScope = previousScope
        EventBridge.shared.notify(.OnShellChanged, params: ["Reference0": previousShell, "Reference1": trimmed])
        return true
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
    func clearSpecificOverlay(id: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.overlays.removeAll { $0.id == id }
            Log.debug("[GhostManager] Cleared overlay \(id) for scope \(self.currentScope)")
        }
    }

    /// Offset a specific overlay
    func offsetOverlay(id: String, x: Double, y: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            let exactMatches = vm.overlays.indices.filter { vm.overlays[$0].id == id }
            let targetIndices = exactMatches.isEmpty
                ? vm.overlays.indices.filter { vm.overlays[$0].id.hasPrefix(id) }
                : exactMatches
            guard !targetIndices.isEmpty else { return }
            for index in targetIndices {
                vm.overlays[index].offset = CGPoint(x: x, y: y)
            }
            Log.debug("[GhostManager] Offset overlay \(id) by (\(x), \(y)) targets=\(targetIndices.count)")
        }
    }

    // MARK: - SERIKO Collision Helpers
    /// 現在のサーフェスのコリジョン領域に、与えられたウィンドウ座標の点が含まれる場合はその領域名を返す。
    /// サーフェス座標系=ウィンドウ座標系として扱う（将来的に拡張時はスケール/オフセットを考慮）。
    func collisionRegionName(at pointInWindow: CGPoint, scope: Int) -> String? {
        guard let vm = characterViewModels[scope] else { return nil }
        let surfaceID = vm.currentSurfaceID
        let regions = animationEngine.getCollisions(for: surfaceID)
        for region in regions {
            if region.rect.contains(pointInWindow) {
                return region.name
            }
        }
        return nil
    }
}
