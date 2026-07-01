import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Surface Loading and Compositing

extension GhostManager {
    /// `\![set,property,currentghost.scope(N).surface.num,ID]` 等の SET を実サーフェス/アニメへ反映する。
    /// UKADOC では surface.num / animation.num / seriko.defaultsurface は WRITE 可。プロパティの
    /// 読み戻し配線（live scopeData）とは独立に、ここでは SET の副作用（表示変更）のみを適用する。
    func applyScopePropertySideEffect(key: String, value: String) {
        var k = key
        if k.hasPrefix("currentghost.") { k = String(k.dropFirst("currentghost.".count)) }
        guard k.hasPrefix("scope(") else { return }
        let afterParen = k.dropFirst("scope(".count)
        guard let close = afterParen.firstIndex(of: ")") else { return }
        guard let scopeID = Int(afterParen[..<close]) else { return }
        var rest = String(afterParen[afterParen.index(after: close)...])
        guard rest.first == "." else { return }
        rest.removeFirst()

        // 対象スコープを一時的に currentScope にして既存 API を再利用する（\4/\5 と同じ手法）。
        // updateSurface / playAnimation は currentScope を同期的に読むため、直後の復元で問題ない。
        func withScope(_ body: () -> Void) {
            let previousScope = currentScope
            currentScope = scopeID
            body()
            currentScope = previousScope
        }

        switch rest {
        case "surface.num", "seriko.defaultsurface":
            guard let sid = Int(value) else { return }
            withScope { updateSurface(id: sid) }
        case "animation.num":
            guard let aid = Int(value) else { return }
            withScope { playAnimation(id: aid, wait: false) }
        default:
            break
        }
    }

    func updateSurface(id rawID: Int) {
        let id = surfaceAliases[rawID] ?? rawID
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

                // 遅延生成: 未作成スコープのウィンドウ/VM をここで生成する（大量キャラ対応）
                self.ensureCharacterWindow(for: scope)

                if let vm = self.characterViewModels[scope] {
                    vm.image = image
                    vm.currentSurfaceID = id
                }
                if let win = self.characterWindows[scope] {
                    // Resize window to fit to new surface
                    win.setContentSize(image.size)
                    self.positionBalloonWindow()
                }
                
                // Dispatch OnSurfaceChange event.
                // UKADOC: Reference0 = sakura(scope0) の現在サーフェスID,
                //         Reference1 = kero(scope1) の現在サーフェスID,
                //         Reference2 = 変化したキャラのスコープ,サーフェスID。
                let sakuraSurface = self.characterViewModels[0]?.currentSurfaceID ?? (scope == 0 ? id : 0)
                let keroSurface = self.characterViewModels[1]?.currentSurfaceID ?? (scope == 1 ? id : 0)
                let params: [String: String] = [
                    "sakuraSurface": String(sakuraSurface),
                    "keroSurface": String(keroSurface),
                    "changedScope": "\(scope),\(id)"
                ]
                EventBridge.shared.notify(.OnSurfaceChange, refs: params)
                NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
                Log.debug("[GhostManager] OnSurfaceChange dispatched: sakura=\(sakuraSurface) kero=\(keroSurface) (changed scope\(scope) \(oldSurfaceID)->\(id))")
            }
        }
        
        // Schedule OnSurfaceRestore after a delay
        // UKADOC: Reference0 = 本体側(scope0)の現在サーフェス, Reference1 = 相方側(scope1)の現在サーフェス
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            guard let self = self else { return }
            let sakuraSurface = self.characterViewModels[0]?.currentSurfaceID ?? 0
            let keroSurface = self.characterViewModels[1]?.currentSurfaceID ?? 0
            let params: [String: String] = [
                "sakuraSurface": String(sakuraSurface),
                "keroSurface": String(keroSurface)
            ]
            EventBridge.shared.notify(.OnSurfaceRestore, refs: params)
            Log.debug("[GhostManager] OnSurfaceRestore dispatched")
        }
    }

    func loadImage(surfaceId: Int, scope: Int) -> NSImage? {
        guard let shellURL = loadShellPath() else {
            Log.info("[GhostManager] Cannot load surface: shell path unavailable")
            return nil
        }
        // surfacetable.txt の option,DisableNoDefineSurfaces:
        // surfaces.txt にも surfacetable.txt にも定義がないサーフェスIDは描画しない（UKADOC）。
        if let table = surfaceTable, table.disableNoDefineSurfaces,
           parsedSurfaceDefs[surfaceId] == nil,
           !table.definedSurfaceIDs.contains(surfaceId) {
            Log.debug("[GhostManager] Surface \(surfaceId) suppressed by DisableNoDefineSurfaces")
            return nil
        }
        // SERIKO/2.0: element 合成で定義されるサーフェスは複数画像を重ねて生成する
        if let elements = parsedSurfaceDefs[surfaceId]?.elements, !elements.isEmpty,
           let composed = compositeSurfaceElements(elements, shellURL: shellURL) {
            Log.debug("[GhostManager] Surface \(surfaceId) composed from \(elements.count) elements")
            return composed
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
            // @2x/@3x バリアントがあれば高解像度 rep を取り込む（Retina 対応）
            if FileManager.default.fileExists(atPath: url.path), let img = RetinaImageLoader.image(contentsOf: url) {
                // PNA マスクがあれば適用（白=不透明、黒=透明として扱う想定）
                let pnaURL = url.deletingPathExtension().appendingPathExtension("pna")
                if FileManager.default.fileExists(atPath: pnaURL.path),
                   let masked = applyPNAMask(baseURL: url, maskURL: pnaURL) {
                    Log.debug("[GhostManager] Image loaded with PNA mask: \(name)")
                    return masked
                }
                if let keyed = applyGreenChromakey(to: img) {
                    Log.debug("[GhostManager] Image loaded with green chromakey: \(name)")
                    return keyed
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

    /// PNA/alpha を持たない古いシェル素材向けに、純緑 (0,255,0) 背景を透明化する。
    func applyGreenChromakey(to image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var changed = false
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            if red <= 8 && green >= 248 && blue <= 8 {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
                changed = true
            }
        }
        guard changed else { return nil }

        guard let outputContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let outputCG = outputContext.makeImage() else {
            return nil
        }

        return NSImage(cgImage: outputCG, size: image.size)
    }

    /// 任意ファイルのサーフェス画像を読み込む（Retina + 同名 PNA マスク対応）。element 合成で使用。
    func loadSurfaceFile(url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let img = RetinaImageLoader.image(contentsOf: url) else { return nil }
        let pnaURL = url.deletingPathExtension().appendingPathExtension("pna")
        if FileManager.default.fileExists(atPath: pnaURL.path),
           let masked = applyPNAMask(baseURL: url, maskURL: pnaURL) {
            return masked
        }
        if let keyed = applyGreenChromakey(to: img) {
            return keyed
        }
        return img
    }

    /// SERIKO/2.0 element 定義を index 順に重ねて1枚の基底サーフェス画像を合成する。
    func compositeSurfaceElements(_ elements: [SerikoElement], shellURL: URL) -> NSImage? {
        guard !elements.isEmpty else { return nil }
        struct Loaded { let img: NSImage; let x: Int; let y: Int; let method: SerikoMethod }
        var loaded: [Loaded] = []
        for el in elements.sorted(by: { $0.index < $1.index }) {
            let url = shellURL.appendingPathComponent(el.filename)
            guard let img = loadSurfaceFile(url: url) else {
                Log.info("[GhostManager] element image not found: \(el.filename)")
                continue
            }
            loaded.append(Loaded(img: img, x: el.x, y: el.y, method: el.method))
        }
        guard !loaded.isEmpty else { return nil }
        // キャンバスサイズ = 全 element の包含矩形（原点(0,0)基準）
        var maxW = 0, maxH = 0
        for l in loaded {
            maxW = max(maxW, l.x + Int(l.img.size.width.rounded()))
            maxH = max(maxH, l.y + Int(l.img.size.height.rounded()))
        }
        guard maxW > 0, maxH > 0 else { return nil }
        let canvasSize = NSSize(width: maxW, height: maxH)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()
        for l in loaded {
            // SERIKO は左上原点・y 下方向。NSImage は左下原点なので変換する。
            let drawPoint = NSPoint(x: CGFloat(l.x),
                                    y: canvasSize.height - CGFloat(l.y) - l.img.size.height)
            // reduce はアルファ間引き(destinationIn)、その他は通常の上書き合成(sourceOver)で近似
            let op: NSCompositingOperation = (l.method == .reduce) ? .destinationIn : .sourceOver
            l.img.draw(at: drawPoint, from: .zero, operation: op, fraction: 1.0)
        }
        canvas.unlockFocus()
        return canvas
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
            EventBridge.shared.notify(.OnShellChanging, refs: ["prevShellName": previousShell, "newShellName": trimmed])
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
        EventBridge.shared.notify(.OnShellChanged, refs: ["prevShellName": previousShell, "newShellName": trimmed])
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
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
