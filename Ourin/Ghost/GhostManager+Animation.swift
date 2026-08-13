import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications
import ObjectiveC

// MARK: - Animation Engine Integration

extension GhostManager {
    struct AnimAddSurfaceFrame {
        let surfaceID: Int
        let x: Int
        let y: Int
        let durationMilliseconds: Int
    }

    enum AnimAddSurfaceTiming: Equatable {
        case runonce
        case always
    }

    typealias AnimAddSurfaceSequence = (
        frames: [AnimAddSurfaceFrame],
        timing: AnimAddSurfaceTiming
    )

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
        let scope = currentScope
        serikoLoopTimer?.invalidate()
        serikoLoopTimer = nil
        serikoExecutor.stopAllAnimations()
        activeAnimationIDsByScope.removeAll()
        persistentSerikoAnimationIDsByScope.removeAll()
        characterViewModels[scope]?.serikoMoveOffset = .zero
        serikoScaleFactorsByScope[scope] = nil
        applyEffectiveSerikoScale(scope: scope)
    }

    /// Stop legacy and command-defined animation sources before a surface
    /// transition, while leaving SERIKO state available for `shared-index`
    /// migration. `SerikoExecutor.replace(animations:)` decides which IDs can
    /// continue once both source and destination definitions are known.
    func prepareSerikoForSurfaceTransition(scope: Int) {
        serikoLoopTimer?.invalidate()
        serikoLoopTimer = nil
        animationEngine.stopAllAnimations()
        stopImportedSurfaceAnimations(scope: scope)
        stopAllAnimAddSurfaceAnimations(scope: scope)
        persistentSerikoAnimationIDsByScope[scope] = nil
    }

    private func applyEffectiveSerikoScale(
        scope: Int,
        emitEvents: Bool = true,
        balloonEventBeforeX: Double? = nil,
        balloonEventBeforeY: Double? = nil
    ) {
        guard let vm = characterViewModels[scope] else { return }
        let factors = Array(serikoScaleFactorsByScope[scope]?.values ?? Dictionary<Int, CGPoint>().values)
        let factorX = factors.reduce(1.0) { $0 * Double($1.x) }
        let factorY = factors.reduce(1.0) { $0 * Double($1.y) }
        vm.scaleX = vm.userScaleX * factorX
        vm.scaleY = vm.userScaleY * factorY
        if ghostConfig?.balloonSyncScale == true {
            applySynchronizedBalloonScale(
                scope: scope,
                x: vm.scaleX,
                y: vm.scaleY,
                emitEvent: emitEvents,
                eventBeforeX: balloonEventBeforeX,
                eventBeforeY: balloonEventBeforeY
            )
        }
    }

    /// `balloon.syncscale,true` によるバルーン倍率の実反映とイベント送出。
    /// バルーンはシェルとは別ウィンドウなので、ViewModel の倍率とウィンドウの
    /// fittingSize の両方を更新し、変更時だけ OnBalloonScaling を発火する。
    private func applySynchronizedBalloonScale(
        scope: Int,
        x: Double,
        y: Double,
        emitEvent: Bool = true,
        eventBeforeX: Double? = nil,
        eventBeforeY: Double? = nil
    ) {
        guard let balloonVM = balloonViewModels[scope] else { return }
        let previousX = balloonVM.scaleX
        let previousY = balloonVM.scaleY
        guard previousX != x || previousY != y else { return }

        balloonVM.scaleX = x
        balloonVM.scaleY = y
        guard emitEvent else { return }
        _ = EventBridge.shared.request(
            .OnBalloonScaling,
            refs: [
                "afterX": String(x * 100.0),
                "beforeX": String((eventBeforeX ?? previousX) * 100.0),
                "afterY": String(y * 100.0),
                "beforeY": String((eventBeforeY ?? previousY) * 100.0)
            ],
            to: self
        )
    }

    /// ゴースト設定の再読込時にも、既存のバルーンへ同期倍率を反映する。
    func refreshBalloonScalingSynchronization() {
        for scope in Set(characterViewModels.keys).union(balloonViewModels.keys) {
            guard balloonViewModels[scope] != nil else { continue }
            if ghostConfig?.balloonSyncScale == true, let characterVM = characterViewModels[scope] {
                applySynchronizedBalloonScale(scope: scope, x: characterVM.scaleX, y: characterVM.scaleY)
            } else {
                applySynchronizedBalloonScale(scope: scope, x: 1.0, y: 1.0)
            }
        }
    }

    func setUserScaling(
        scope: Int,
        x: Double,
        y: Double,
        emitEvent: Bool = true,
        eventBeforeXPercent: Double? = nil,
        eventBeforeYPercent: Double? = nil,
        eventBeforeBalloonX: Double? = nil,
        eventBeforeBalloonY: Double? = nil
    ) {
        guard let vm = characterViewModels[scope] else { return }
        let previousXPercent = vm.userScaleX * 100.0
        let previousYPercent = vm.userScaleY * 100.0
        let changed = vm.userScaleX != x || vm.userScaleY != y
        vm.userScaleX = x
        vm.userScaleY = y
        applyEffectiveSerikoScale(
            scope: scope,
            emitEvents: emitEvent,
            balloonEventBeforeX: eventBeforeBalloonX,
            balloonEventBeforeY: eventBeforeBalloonY
        )

        guard emitEvent, changed else { return }
        _ = EventBridge.shared.request(
            .OnShellScaling,
            refs: [
                "afterX": String(x * 100.0),
                "beforeX": String(eventBeforeXPercent ?? previousXPercent),
                "afterY": String(y * 100.0),
                "beforeY": String(eventBeforeYPercent ?? previousYPercent)
            ],
            to: self
        )
    }

    private func setSerikoScaling(animationID: Int, x: Double, y: Double, scope: Int) {
        serikoScaleFactorsByScope[scope, default: [:]][animationID] = CGPoint(x: x, y: y)
        applyEffectiveSerikoScale(scope: scope)
    }

    private func clearSerikoScaling(animationID: Int, scope: Int) {
        serikoScaleFactorsByScope[scope]?[animationID] = nil
        if serikoScaleFactorsByScope[scope]?.isEmpty == true {
            serikoScaleFactorsByScope[scope] = nil
        }
        applyEffectiveSerikoScale(scope: scope)
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
            self.removeActiveAnimationID(animID)

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

        serikoExecutor.onScalingInvoked = { [weak self] animID, x, y in
            guard let self = self else { return }
            self.setSerikoScaling(
                animationID: animID,
                x: x / 100.0,
                y: y / 100.0,
                scope: self.currentScope
            )
        }

        serikoExecutor.onImportInvoked = { [weak self] animID, filename, initialDelay, x, y in
            guard let self = self else { return }
            self.importAnimatedSurface(
                filename: filename,
                initialDelayMilliseconds: initialDelay,
                x: x,
                y: y,
                ownerAnimationID: animID,
                scope: self.currentScope
            )
        }

        serikoExecutor.onPatternExecuted = { [weak self] animID, pattern in
            guard let self = self else { return }
            self.handleSerikoPattern(animationID: animID, pattern: pattern)
        }

        serikoExecutor.onAnimationFinished = { [weak self] animID, reason in
            guard let self = self else { return }
            self.handleAnimationFinished(animationID: animID, reason: reason)
        }
    }

    /// Play an animation
    func playAnimation(id: Int, wait: Bool) {
        // Load animations from surfaces.txt if not already loaded
        loadAnimationsForCurrentSurface()

        if serikoExecutor.executeAnimation(id: id) {
            activeAnimationIDsByScope[currentScope, default: []].insert(id)
            startSerikoLoopIfNeeded()
            return
        }
        animationEngine.playAnimation(id: id, wait: wait)
        if animationEngine.activeAnimationIDs.contains(id) {
            activeAnimationIDsByScope[currentScope, default: []].insert(id)
        }
    }

    /// Play an animation and wait for completion
    func playAnimationAndWait(id: Int) {
        waitingForAnimation = id
        if serikoExecutor.activeAnimations[id] != nil {
            activeAnimationIDsByScope[currentScope, default: []].insert(id)
            return
        }
        playAnimation(id: id, wait: true)
        // Playback will resume when animation completes via callback
    }

    func waitForAnimation(id: Int) {
        waitingForAnimation = id
        if serikoExecutor.activeAnimations[id] == nil {
            if serikoExecutor.executeAnimation(id: id) {
                activeAnimationIDsByScope[currentScope, default: []].insert(id)
                startSerikoLoopIfNeeded()
            }
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
        if !serikoExecutor.activeAnimations.isEmpty {
            startSerikoLoopIfNeeded()
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

    func triggerSerikoTalkAnimationIfEnabled(characterCount: Int = 1) {
        let enabled = serikoTalkEnabledForScript
            ?? (UserDefaults.standard.object(forKey: "OurinSerikoTalkEnabled") as? Bool ?? true)
        guard enabled else { return }
        serikoExecutor.triggerTalk(characterCount: characterCount)
        // starttalk は改行や空の表示ではなく、実際の本文が表示された時だけ発火する。
        if characterCount > 0 {
            serikoExecutor.triggerStartTalk()
        }
        startSerikoLoopIfNeeded()
    }

    /// 現在スコープのトーク終了を SERIKO へ通知する。
    /// Executor 側で starttalk の発火履歴が無い animation は無視される。
    func triggerSerikoEndTalkAnimation() {
        let enabled = serikoTalkEnabledForScript
            ?? (UserDefaults.standard.object(forKey: "OurinSerikoTalkEnabled") as? Bool ?? true)
        guard enabled else { return }
        serikoExecutor.triggerEndTalk()
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

    /// SERIKO import は元アニメーションのフレーム管理とは独立して再生する。
    /// 同じ animationID が再実行された場合は、前回のインポートを置き換える。
    func importAnimatedSurface(
        filename: String,
        initialDelayMilliseconds: Int,
        x: Int,
        y: Int,
        ownerAnimationID: Int,
        scope: Int
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.importAnimatedSurface(
                    filename: filename,
                    initialDelayMilliseconds: initialDelayMilliseconds,
                    x: x,
                    y: y,
                    ownerAnimationID: ownerAnimationID,
                    scope: scope
                )
            }
            return
        }

        guard let shellPath = loadShellPath() else {
            Log.info("[GhostManager] SERIKO import ignored: shell path unavailable")
            return
        }
        let root = shellPath.standardizedFileURL
        let url = root.appendingPathComponent(filename).standardizedFileURL
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            Log.info("[GhostManager] SERIKO import rejected outside shell: \(filename)")
            return
        }
        let frames = AnimatedSurfaceLoader.load(from: url)
        guard !frames.isEmpty else {
            Log.info("[GhostManager] SERIKO import file has no decodable frames: \(filename)")
            return
        }

        let ownerKey = "\(scope):\(ownerAnimationID)"
        if let previousToken = importedSurfaceTokensByOwner[ownerKey] {
            stopImportedSurfaceAnimation(token: previousToken)
        }
        let token = "scope\(scope)_seriko_import_\(UUID().uuidString)"
        importedSurfaceTokensByOwner[ownerKey] = token

        func updateFrame(_ index: Int) {
            guard let vm = characterViewModels[scope], index < frames.count else { return }
            let rawImage = frames[index].image
            let image = applyGreenChromakey(to: rawImage) ?? rawImage
            if let existing = vm.overlays.firstIndex(where: { $0.id == token }) {
                vm.overlays[existing].image = image
            } else {
                let insertionOrder = (vm.overlays.map(\.insertionOrder).max() ?? -1) + 1
                vm.overlays.append(SurfaceOverlay(
                    id: token,
                    image: image,
                    offset: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                    alpha: 1,
                    zOrder: 100,
                    insertionOrder: insertionOrder,
                    blendMode: .normal,
                    surfaceID: nil,
                    animationID: nil
                ))
            }
        }

        func finish() {
            importedSurfaceTimers[token]?.invalidate()
            importedSurfaceTimers[token] = nil
            importedSurfaceTokensByOwner = importedSurfaceTokensByOwner.filter { $0.value != token }
            characterViewModels[scope]?.overlays.removeAll { $0.id == token }
        }

        func schedule(nextIndex: Int) {
            guard nextIndex < frames.count else {
                // Keep the final frame visible for its declared duration. This
                // also gives a one-frame GIF/APNG a real visible lifetime.
                let delay = max(0.01, frames.last?.duration ?? 0.1)
                let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.importedSurfaceTimers[token] = nil
                    guard self.importedSurfaceTokensByOwner.values.contains(token) else { return }
                    finish()
                }
                importedSurfaceTimers[token] = timer
                return
            }
            let previousIndex = max(0, nextIndex - 1)
            let requestedDelay = nextIndex == 1
                ? Double(max(0, initialDelayMilliseconds)) / 1000.0
                : frames[previousIndex].duration
            let delay = requestedDelay > 0 ? requestedDelay : frames[previousIndex].duration
            let timer = Timer.scheduledTimer(withTimeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.importedSurfaceTimers[token] = nil
                guard self.importedSurfaceTokensByOwner.values.contains(token) else { return }
                updateFrame(nextIndex)
                schedule(nextIndex: nextIndex + 1)
            }
            importedSurfaceTimers[token] = timer
        }

        updateFrame(0)
        schedule(nextIndex: 1)
    }

    func stopImportedSurfaceAnimation(token: String) {
        importedSurfaceTimers[token]?.invalidate()
        importedSurfaceTimers[token] = nil
        importedSurfaceTokensByOwner = importedSurfaceTokensByOwner.filter { $0.value != token }
        for vm in characterViewModels.values {
            vm.overlays.removeAll { $0.id == token }
        }
    }

    func stopImportedSurfaceAnimations(scope: Int) {
        let prefix = "\(scope):"
        let tokens = importedSurfaceTokensByOwner
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
        for token in tokens {
            stopImportedSurfaceAnimation(token: token)
        }
    }

    func stopAllImportedSurfaceAnimations() {
        let tokens = Set(importedSurfaceTimers.keys).union(importedSurfaceTokensByOwner.values)
        for token in tokens {
            stopImportedSurfaceAnimation(token: token)
        }
        importedSurfaceTokensByOwner.removeAll()
    }

    /// Handle \![anim,clear,ID] command
    func handleAnimClear(id: Int) {
        serikoExecutor.stopAnimation(id: id)
        animationEngine.clearAnimation(id: id)
        if let token = importedSurfaceTokensByOwner["\(currentScope):\(id)"] {
            stopImportedSurfaceAnimation(token: token)
        }
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
        let previousOffset: CGPoint
        if let state = serikoExecutor.activeAnimations[id] {
            previousOffset = CGPoint(x: state.offsetX, y: state.offsetY)
        } else {
            previousOffset = animationEngine.offset(for: id) ?? .zero
        }
        serikoExecutor.offsetAnimation(id: id, x: x, y: y)
        animationEngine.offsetAnimation(id: id, x: Double(x), y: Double(y))
        let delta = CGPoint(
            x: CGFloat(x) - previousOffset.x,
            y: CGFloat(y) - previousOffset.y
        )
        let scope = currentScope
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[scope] else { return }

            let indices = vm.overlays.indices.filter { vm.overlays[$0].animationID == id }
            if !indices.isEmpty {
                for index in indices {
                    vm.overlays[index].offset.x += delta.x
                    vm.overlays[index].offset.y += delta.y
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
        activeAnimationIDsByScope.removeAll()
        stopImportedSurfaceAnimations(scope: currentScope)
        stopAllAnimAddSurfaceAnimations(scope: currentScope)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            vm.overlays.removeAll()
            Log.debug("[GhostManager] Stopped all animations and cleared overlays")
        }
    }

    /// Handle `\![anim,add,overlay,ID]` and its coordinate form.
    func handleAnimAddOverlay(id: Int, x: Int? = nil, y: Int? = nil) {
        let offset: CGPoint?
        if let x, let y {
            offset = CGPoint(x: CGFloat(x), y: CGFloat(y))
        } else {
            offset = nil
        }
        handleSurfaceOverlay(surfaceID: id, initialOffset: offset)
        Log.debug("[GhostManager] Added overlay \(id)")
    }

    /// Handle `\![anim,add,overlayfast,ID]` and its coordinate form.
    func handleAnimAddOverlayFast(id: Int, x: Int? = nil, y: Int? = nil) {
        let offset: CGPoint?
        if let x, let y {
            offset = CGPoint(x: CGFloat(x), y: CGFloat(y))
        } else {
            offset = nil
        }
        handleSurfaceOverlay(surfaceID: id, initialOffset: offset, blendMode: .overlayFast)
        Log.debug("[GhostManager] Added fast overlay \(id)")
    }

    /// Parse `ID,x,y,time,...[,runonce|always]` without accepting a partial frame.
    func parseAnimAddOverlaySequence(args: [String]) -> AnimAddSurfaceSequence? {
        guard args.count >= 4 else { return nil }

        var numericArgs = args
        let timing: AnimAddSurfaceTiming
        if let last = numericArgs.last?.lowercased() {
            switch last {
            case "always":
                timing = .always
                numericArgs.removeLast()
            case "runonce":
                timing = .runonce
                numericArgs.removeLast()
            default:
                timing = .runonce
            }
        } else {
            timing = .runonce
        }

        guard numericArgs.count >= 4, numericArgs.count.isMultiple(of: 4) else { return nil }
        var frames: [AnimAddSurfaceFrame] = []
        frames.reserveCapacity(numericArgs.count / 4)
        for index in stride(from: 0, to: numericArgs.count, by: 4) {
            guard let surfaceID = Int(numericArgs[index]),
                  let x = Int(numericArgs[index + 1]),
                  let y = Int(numericArgs[index + 2]),
                  let durationMilliseconds = Int(numericArgs[index + 3]) else {
                return nil
            }
            frames.append(AnimAddSurfaceFrame(
                surfaceID: surfaceID,
                x: x,
                y: y,
                durationMilliseconds: max(0, durationMilliseconds)
            ))
        }
        return frames.isEmpty ? nil : (frames, timing)
    }

    /// Play a command-defined overlay frame sequence independently of SERIKO.
    func handleAnimAddOverlaySequence(
        frames: [AnimAddSurfaceFrame],
        timing: AnimAddSurfaceTiming,
        blendMode: SurfaceBlendMode
    ) {
        guard !frames.isEmpty else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.handleAnimAddOverlaySequence(frames: frames, timing: timing, blendMode: blendMode)
            }
            return
        }

        nextAnimAddSurfaceToken &+= 1
        let scope = currentScope
        let token = "anim_add_\(scope)_\(nextAnimAddSurfaceToken)"
        animAddSurfaceTokensByScope[scope, default: []].insert(token)

        func render(_ frame: AnimAddSurfaceFrame) {
            guard animAddSurfaceTokensByScope[scope]?.contains(token) == true else { return }
            let resolvedSurfaceID = surfaceAliases[frame.surfaceID] ?? frame.surfaceID
            guard let image = loadImage(surfaceId: resolvedSurfaceID, scope: scope) else {
                Log.info("[GhostManager] Surface image not found for anim/add overlay id=\(frame.surfaceID), resolved=\(resolvedSurfaceID), scope=\(scope)")
                return
            }
            guard let vm = characterViewModels[scope] else { return }
            vm.overlays.removeAll { $0.id == token }
            let insertionOrder = (vm.overlays.map(\.insertionOrder).max() ?? -1) + 1
            vm.overlays.append(SurfaceOverlay(
                id: token,
                image: image,
                offset: CGPoint(x: CGFloat(frame.x), y: CGFloat(frame.y)),
                alpha: 1.0,
                zOrder: 100,
                insertionOrder: insertionOrder,
                blendMode: blendMode,
                surfaceID: resolvedSurfaceID,
                animationID: nil
            ))
        }

        func stop() {
            animAddSurfaceTimers[token]?.invalidate()
            animAddSurfaceTimers[token] = nil
            animAddSurfaceTokensByScope[scope]?.remove(token)
            if animAddSurfaceTokensByScope[scope]?.isEmpty == true {
                animAddSurfaceTokensByScope[scope] = nil
            }
            characterViewModels[scope]?.overlays.removeAll { $0.id == token }
        }

        func schedule(_ index: Int) {
            guard animAddSurfaceTokensByScope[scope]?.contains(token) == true else { return }
            if index >= frames.count {
                if timing == .always {
                    schedule(0)
                } else {
                    stop()
                }
                return
            }

            let frame = frames[index]
            render(frame)
            let delay = max(0.01, Double(frame.durationMilliseconds) / 1000.0)
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.animAddSurfaceTimers[token] = nil
                schedule(index + 1)
            }
            animAddSurfaceTimers[token] = timer
        }

        schedule(0)
    }

    /// Stop one command-defined overlay sequence.
    private func stopAnimAddSurfaceAnimation(token: String) {
        animAddSurfaceTimers[token]?.invalidate()
        animAddSurfaceTimers[token] = nil
        for scope in Array(animAddSurfaceTokensByScope.keys) {
            animAddSurfaceTokensByScope[scope]?.remove(token)
            if animAddSurfaceTokensByScope[scope]?.isEmpty == true {
                animAddSurfaceTokensByScope[scope] = nil
            }
        }
        for vm in characterViewModels.values {
            vm.overlays.removeAll { $0.id == token }
        }
    }

    /// Stop command-defined overlay sequences for a scope, or all scopes.
    func stopAllAnimAddSurfaceAnimations(scope: Int? = nil) {
        let tokens: Set<String>
        if let scope {
            tokens = animAddSurfaceTokensByScope[scope] ?? []
        } else {
            tokens = Set(animAddSurfaceTimers.keys).union(animAddSurfaceTokensByScope.values.flatMap { $0 })
        }
        for token in tokens {
            stopAnimAddSurfaceAnimation(token: token)
        }
    }

    /// Handle \![anim,add,base,ID] command
    func handleAnimAddBase(id: Int) {
        // 通常の \s[ID] と同じ解決経路を使う。直接 surface<ID>.png を読むと、
        // surface alias、surface1 系の命名、4桁ゼロ埋め、PNA/透過色、element
        // 合成、SERIKO 定義の再読込をすべて取りこぼす。
        updateSurface(id: id)
        Log.debug("[GhostManager] Set base surface to \(id)")
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
        let isBackgroundAnimation = serikoExecutor.definition(for: animationID)?.options.contains {
            $0.caseInsensitiveCompare("background") == .orderedSame
        } == true
        let overlayZOrder = isBackgroundAnimation ? -100 : nil

        switch method {
        case .overlay, .overlayFast, .interpolate, .asis, .blend, .add, .bind, .auto:
            var offset: CGPoint? = CGPoint(x: CGFloat(x), y: CGFloat(y))
            if let def = serikoExecutor.definition(for: animationID),
               (def.alignX != nil || def.alignY != nil),
               let vm = characterViewModels[currentScope], let base = vm.image {
                // Alignment must use the same surface resolver as normal
                // surface changes; direct surface<ID>.png lookup misses aliases,
                // PNA/key transparency, elements, and surface-table naming.
                let resolvedSurfaceID = surfaceAliases[surfaceID] ?? surfaceID
                if let overlayImage = loadImage(surfaceId: resolvedSurfaceID, scope: currentScope) {
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
            let blendMode: SurfaceBlendMode
            switch method {
            case .overlay: blendMode = .normal
            case .overlayFast: blendMode = .overlayFast
            case .interpolate: blendMode = .interpolate
            case .asis: blendMode = .asis
            case .blend(let operation, let fast):
                blendMode = .blend(operation, destinationAlphaAware: fast)
            default: blendMode = .normal
            }
            handleSurfaceOverlay(
                surfaceID: surfaceID,
                type: method == .bind ? .bind : .overlay,
                animationID: animationID,
                initialOffset: offset,
                blendMode: blendMode,
                zOrder: overlayZOrder
            )
        case .scaling:
            // 小数を含む倍率は onScalingInvoked で先に適用する。
            break
        case .base:
            handleAnimAddBase(id: surfaceID)
        case .move:
            let scope = animationScopes(for: animationID).sorted().first ?? currentScope
            characterViewModels[scope]?.serikoMoveOffset = CGPoint(x: CGFloat(x), y: CGFloat(y))
            Log.debug("[GhostManager] SERIKO move animation=\(animationID) scope=\(scope) offset=(\(x), \(y))")
        case .reduce:
            handleSurfaceOverlay(
                surfaceID: surfaceID,
                type: .overlay,
                animationID: animationID,
                initialOffset: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                blendMode: .reduce,
                zOrder: overlayZOrder
            )
        case .replace:
            handleSurfaceOverlay(
                surfaceID: surfaceID,
                type: .replace,
                animationID: animationID,
                initialOffset: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                zOrder: overlayZOrder
            )
        case .start:
            if serikoExecutor.executeAnimation(id: surfaceID) {
                activeAnimationIDsByScope[currentScope, default: []].insert(surfaceID)
                startSerikoLoopIfNeeded()
            }
        case .alternativeStart:
            if serikoExecutor.executeAnimation(id: surfaceID) {
                activeAnimationIDsByScope[currentScope, default: []].insert(surfaceID)
                startSerikoLoopIfNeeded()
            }
        case .stop:
            serikoExecutor.stopAnimation(id: animationID)
            removeActiveAnimationID(animationID)
        case .alternativeStop:
            serikoExecutor.stopAnimation(id: surfaceID)
            removeActiveAnimationID(surfaceID)
        case .parallelStart, .parallelStop:
            // 並列開始/停止は executor が全対象IDへ直接適用する。
            break
        case .insert:
            // insert は executor 側で start に変換されるためここには到達しないが、網羅性のため処理する
            if serikoExecutor.executeAnimation(id: surfaceID) {
                activeAnimationIDsByScope[currentScope, default: []].insert(surfaceID)
                startSerikoLoopIfNeeded()
            }
        case .import:
            // 実フレームの読み込みは executor の onImportInvoked で行う。
            break
        case .unknown:
            break
        }
    }

    private func handleSerikoPattern(animationID: Int, pattern: SerikoPattern) {
        if pattern.surfaceID == -1, pattern.method != .import {
            // SERIKO の終了フレームは画像を追加しないため、前フレームを明示的に消す。
            // -2 は他アニメーション停止用の制御フレームであり、現在の
            // アニメーション自身のオーバーレイを消してはいけない。
            clearAnimationOverlays(animationID: animationID)
        }
        if pattern.method != .scaling {
            clearSerikoScaling(animationID: animationID, scope: currentScope)
        }
        Log.debug("[GhostManager] SERIKO pattern executed: anim=\(animationID), method=\(pattern.method), surface=\(pattern.surfaceID)")
    }

    func clearPersistentSerikoOverlays(scope: Int) {
        let animationIDs = persistentSerikoAnimationIDsByScope.removeValue(forKey: scope) ?? []
        guard !animationIDs.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let vm = self.characterViewModels[scope] else { return }
            vm.overlays.removeAll { overlay in
                guard let animationID = overlay.animationID else { return false }
                return animationIDs.contains(animationID)
            }
            Log.debug("[GhostManager] Cleared persistent SERIKO overlays for scope=\(scope), animations=\(animationIDs.sorted())")
        }
    }

    private func animationScopes(for animationID: Int) -> Set<Int> {
        var scopes = Set(activeAnimationIDsByScope.compactMap { scope, animationIDs in
            animationIDs.contains(animationID) ? scope : nil
        })
        for (scope, animationIDs) in persistentSerikoAnimationIDsByScope where animationIDs.contains(animationID) {
            scopes.insert(scope)
        }
        if scopes.isEmpty {
            scopes.insert(currentScope)
        }
        return scopes
    }

    private func handleAnimationFinished(
        animationID: Int,
        reason: SerikoAnimationFinishReason
    ) {
        let scopes = animationScopes(for: animationID)
        let intervalComponents = serikoExecutor.definition(for: animationID)?.interval.components ?? []
        let hasMovePattern = serikoExecutor.definition(for: animationID)?.patterns.contains {
            $0.method == .move
        } == true
        let keepsFinalPattern = reason == .completed
            && intervalComponents.contains(.bind)
            && intervalComponents.contains(.runonce)

        if keepsFinalPattern {
            for scope in scopes {
                persistentSerikoAnimationIDsByScope[scope, default: []].insert(animationID)
            }
        } else {
            for scope in scopes {
                persistentSerikoAnimationIDsByScope[scope]?.remove(animationID)
                clearAnimationOverlays(animationID: animationID, scope: scope)
            }
        }
        for scope in scopes {
            clearSerikoScaling(animationID: animationID, scope: scope)
            if hasMovePattern {
                characterViewModels[scope]?.serikoMoveOffset = .zero
            }
        }
        removeActiveAnimationID(animationID)
        if waitingForAnimation == animationID {
            waitingForAnimation = nil
            if isPlaying {
                processNextUnit()
            }
        }
        stopSerikoLoopIfIdle()
        EventBridge.shared.notifyCustom("OnAnimationFinished", refs: ["animationID": String(animationID)], ignoreResponseScript: true)
    }

    private func removeActiveAnimationID(_ animationID: Int) {
        for scope in Array(activeAnimationIDsByScope.keys) {
            activeAnimationIDsByScope[scope]?.remove(animationID)
            if activeAnimationIDsByScope[scope]?.isEmpty == true {
                activeAnimationIDsByScope[scope] = nil
            }
        }
    }

    func startSerikoLoopIfNeeded() {
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
