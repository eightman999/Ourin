import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications
import ObjectiveC

// MARK: - Animation Engine Integration

extension GhostManager {
    // MARK: - Animation Engine Integration

    // objc runtimeの関連オブジェクトを使う。GhostManager(NSObject)のdealloc時に
    // ランタイムが自動的に関連オブジェクトを解放するため、静的Dictionary+ObjectIdentifierキー方式で
    // 起きていた「エントリが解放されずリークし続ける」「解放後に同じアドレスへ新インスタンスが
    // 割り当たるとキー衝突して別インスタンスの古いexecutorを返す」の両方を回避できる。
    private final class SerikoAnimationState {
        let lock = NSLock()
        var executor: SerikoExecutor?
        var loopTimer: Timer?
    }

    private static var serikoStateKey: UInt8 = 0
    private static let serikoStateLock = NSLock()

    private var serikoState: SerikoAnimationState {
        GhostManager.serikoStateLock.lock()
        defer { GhostManager.serikoStateLock.unlock() }
        if let state = objc_getAssociatedObject(self, &GhostManager.serikoStateKey) as? SerikoAnimationState {
            return state
        }
        let state = SerikoAnimationState()
        objc_setAssociatedObject(self, &GhostManager.serikoStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }

    var serikoExecutor: SerikoExecutor {
        let state = serikoState
        state.lock.lock()
        defer { state.lock.unlock() }
        if let existing = state.executor {
            return existing
        }
        let created = SerikoExecutor()
        state.executor = created
        return created
    }

    private var serikoLoopTimer: Timer? {
        get {
            let state = serikoState
            state.lock.lock()
            defer { state.lock.unlock() }
            return state.loopTimer
        }
        set {
            let state = serikoState
            state.lock.lock()
            defer { state.lock.unlock() }
            state.loopTimer = newValue
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
            guard let self = self else { return }

            guard let pattern = pattern else {
                self.clearAnimationOverlays(animationID: animID)
                return
            }

            // Update surface overlay based on animation pattern and type
            if pattern.surfaceID >= 0 {
                self.handleSurfaceOverlay(
                    surfaceID: pattern.surfaceID,
                    type: pattern.type,
                    animationID: animID,
                    initialOffset: CGPoint(x: CGFloat(pattern.x), y: CGFloat(pattern.y))
                )
            } else {
                // -1 はフレーム終了/待機。前フレームを残さない。
                self.clearAnimationOverlays(animationID: animID)
            }
        }

        animationEngine.onAnimationComplete = { [weak self] animID in
            guard let self = self else { return }
            self.clearAnimationOverlays(animationID: animID)

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
            self.handleSerikoMethod(animationID: animID, method: method, surfaceID: surfaceID, x: x, y: y)
        }

        serikoExecutor.onPatternExecuted = { [weak self] animID, pattern in
            guard let self = self else { return }
            self.handleSerikoPattern(animationID: animID, pattern: pattern)
        }

        serikoExecutor.onAnimationFinished = { [weak self] animID in
            guard let self = self else { return }
            self.handleAnimationFinished(animationID: animID)
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
    func loadAnimationsForCurrentSurface(surfaceID requestedSurfaceID: Int? = nil, scope requestedScope: Int? = nil) {
        guard let shellPath = loadShellPath() else { return }

        guard let definitionBundle = SurfaceDefinitionLoader.load(from: shellPath) else {
            Log.info("[GhostManager] No readable surfaces*.txt or alias.txt in: \(shellPath.path)")
            return
        }
        let combined = definitionBundle.content
        Log.debug("[GhostManager] Loaded surface definition files: \(definitionBundle.sourceFileNames.joined(separator: ", "))")

        // surfacetable.txt は surfaces.txt と書式が非互換のため別途ロード。
        if let table = SurfaceDefinitionLoader.loadSurfaceTable(from: shellPath) {
            surfaceTable = table
            Log.debug("[GhostManager] Loaded surfacetable.txt: \(table.groups.count) groups, disableNoDefineSurfaces=\(table.disableNoDefineSurfaces)")
        } else {
            surfaceTable = nil
        }

        if surfaceAliases.isEmpty {
            surfaceAliases = SerikoParser.parseSurfaceAliases(combined)
            if !surfaceAliases.isEmpty {
                Log.debug("[GhostManager] Loaded \(surfaceAliases.count) numeric surface aliases")
            }
        }
        if surfaceNameAliases.isEmpty {
            surfaceNameAliases = SerikoParser.parseNamedSurfaceAliases(combined)
            if !surfaceNameAliases.isEmpty {
                Log.debug("[GhostManager] Loaded \(surfaceNameAliases.count) named surface aliases")
            }
        }
        // 全サーフェス定義（element 合成・surface.append マージ込み）をキャッシュ
        parsedSurfaceDefs = SerikoParser.parseSurfaces(combined)

        let scope = requestedScope ?? currentScope
        guard let vm = characterViewModels[scope] else { return }
        let surfaceID = requestedSurfaceID ?? vm.currentSurfaceID

        animationEngine.loadAnimations(surfaceID: surfaceID, content: combined)
        if let surface = parsedSurfaceDefs[surfaceID] {
            serikoExecutor.replace(animations: surface.animations)
        } else {
            serikoExecutor.replace(animations: [:])
        }
        Log.debug("[GhostManager] Loaded animations for surface \(surfaceID)")
    }

    func reloadSurfacesDefinition() {
        animationEngine.stopAllAnimations()
        shutdownSerikoLoop()
        loadAnimationsForCurrentSurface()
        EventBridge.shared.notifyCustom("OnSurfacesReloaded", refs: ["shellName": activeShellName])
        Log.debug("[GhostManager] Reloaded surfaces*.txt definitions")
    }

    func triggerSerikoTalkAnimationIfEnabled() {
        let enabled = UserDefaults.standard.object(forKey: "OurinSerikoTalkEnabled") as? Bool ?? true
        guard enabled else { return }
        serikoExecutor.triggerTalk()
        startSerikoLoopIfNeeded()
    }

    // MARK: - Animation Control Handlers

    /// 指定アニメーションが生成した一時オーバーレイだけを、対象スコープから除去する。
    /// surface ID はフレームごとに変化するため、surface ID ではなく所有 animationID で追跡する。
    private func clearAnimationOverlays(animationID: Int, scope: Int? = nil) {
        let targetScope = scope ?? currentScope
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let vm = self.characterViewModels[targetScope] else { return }
            let before = vm.overlays.count
            vm.overlays.removeAll { $0.animationID == animationID }
            if vm.overlays.count != before {
                Log.debug("[GhostManager] Cleared animation overlays for anim=\(animationID), scope=\(targetScope)")
            }
        }
    }

    /// Handle \![anim,clear,ID] command
    func handleAnimClear(id: Int) {
        serikoExecutor.stopAnimation(id: id)
        animationEngine.clearAnimation(id: id)
        clearAnimationOverlays(animationID: id)
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
        let scope = currentScope
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[scope] else { return }

            let indices = vm.overlays.indices.filter { vm.overlays[$0].animationID == id }
            if !indices.isEmpty {
                for index in indices {
                    vm.overlays[index].offset = CGPoint(x: CGFloat(x), y: CGFloat(y))
                }
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

    private func handleSerikoMethod(animationID: Int, method: SerikoMethod, surfaceID: Int, x: Int, y: Int) {
        switch method {
        case .overlay:
            var offset: CGPoint? = CGPoint(x: CGFloat(x), y: CGFloat(y))
            if let def = serikoExecutor.definition(for: animationID),
               (def.alignX != nil || def.alignY != nil),
               let vm = characterViewModels[currentScope], let base = vm.image {
                if let shellPath = loadShellPath() {
                    let surfaceFileName = "surface\(surfaceID).png"
                    let overlayURL = shellPath.appendingPathComponent(surfaceFileName)
                    if let overlayImage = NSImage(contentsOf: overlayURL) {
                        let bw = base.size.width, bh = base.size.height
                        let ow = overlayImage.size.width, oh = overlayImage.size.height
                        var ox: CGFloat = 0
                        var oy: CGFloat = 0
                        if let ax = def.alignX {
                            switch ax {
                            case .left: ox = 0
                            case .center: ox = (bw - ow) / 2
                            case .right: ox = (bw - ow)
                            }
                        }
                        if let ay = def.alignY {
                            switch ay {
                            case .bottom: oy = 0
                            case .center: oy = (bh - oh) / 2
                            case .top: oy = (bh - oh)
                            }
                        }
                        offset = CGPoint(x: ox, y: oy)
                    }
                }
            }
            handleSurfaceOverlay(surfaceID: surfaceID, type: .overlay, animationID: animationID, initialOffset: offset)
        case .overlayFast:
            // Treat as overlay; could skip certain redraw costs in future.
            var offset: CGPoint? = CGPoint(x: CGFloat(x), y: CGFloat(y))
            if let def = serikoExecutor.definition(for: animationID),
               (def.alignX != nil || def.alignY != nil),
               let vm = characterViewModels[currentScope], let base = vm.image {
                if let shellPath = loadShellPath() {
                    let surfaceFileName = "surface\(surfaceID).png"
                    let overlayURL = shellPath.appendingPathComponent(surfaceFileName)
                    if let overlayImage = NSImage(contentsOf: overlayURL) {
                        let bw = base.size.width, bh = base.size.height
                        let ow = overlayImage.size.width, oh = overlayImage.size.height
                        var ox: CGFloat = 0
                        var oy: CGFloat = 0
                        if let ax = def.alignX {
                            switch ax {
                            case .left: ox = 0
                            case .center: ox = (bw - ow) / 2
                            case .right: ox = (bw - ow)
                            }
                        }
                        if let ay = def.alignY {
                            switch ay {
                            case .bottom: oy = 0
                            case .center: oy = (bh - oh) / 2
                            case .top: oy = (bh - oh)
                            }
                        }
                        offset = CGPoint(x: ox, y: oy)
                    }
                }
            }
            handleSurfaceOverlay(surfaceID: surfaceID, type: .overlay, animationID: animationID, initialOffset: offset)
        case .base:
            handleAnimAddBase(id: surfaceID)
        case .move:
            handleAnimAddMove(x: x, y: y)
        case .reduce:
            handleSurfaceReduce(surfaceID: surfaceID)
        case .replace:
            handleSurfaceOverlay(surfaceID: surfaceID, type: .replace, animationID: animationID)
        case .start:
            _ = serikoExecutor.executeAnimation(id: surfaceID)
            startSerikoLoopIfNeeded()
        case .alternativeStart:
            _ = serikoExecutor.executeAnimation(id: surfaceID)
            startSerikoLoopIfNeeded()
        case .stop, .alternativeStop:
            serikoExecutor.stopAnimation(id: animationID)
        case .insert:
            // insert は executor 側で start に変換されるためここには到達しないが、網羅性のため処理する
            _ = serikoExecutor.executeAnimation(id: surfaceID)
            startSerikoLoopIfNeeded()
        case .interpolate, .asis, .unknown:
            break
        }
    }

    private func handleSerikoPattern(animationID: Int, pattern: SerikoPattern) {
        if pattern.surfaceID < 0 {
            // SERIKO の終了フレームは画像を追加しないため、前フレームを明示的に消す。
            clearAnimationOverlays(animationID: animationID)
        }
        Log.debug("[GhostManager] SERIKO pattern executed: anim=\(animationID), method=\(pattern.method), surface=\(pattern.surfaceID)")
    }

    private func handleAnimationFinished(animationID: Int) {
        clearAnimationOverlays(animationID: animationID)
        if waitingForAnimation == animationID {
            waitingForAnimation = nil
            if isPlaying {
                processNextUnit()
            }
        }
        stopSerikoLoopIfIdle()
        EventBridge.shared.notifyCustom("OnAnimationFinished", refs: ["animationID": String(animationID)], ignoreResponseScript: true)
    }

    private func handleSurfaceReduce(surfaceID: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            let prefix = "surface_\(surfaceID)_"
            vm.overlays.removeAll { $0.id.hasPrefix(prefix) }
            Log.debug("[GhostManager] Reduced overlays for surface \(surfaceID)")
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
