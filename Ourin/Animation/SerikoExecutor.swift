import Foundation

public enum SerikoAnimationFinishReason: Equatable {
    case completed
    case stopped
}

public final class SerikoExecutor {
    public struct AnimationState: Equatable {
        public let animationID: Int
        public var definition: SerikoParser.AnimationDefinition
        public var currentPatternIndex: Int
        public var isPaused: Bool
        public var offsetX: Int
        public var offsetY: Int
        public var lastTickAt: Date
        public var stepDirection: Int  // 1: forward, -1: backward (for ping-pong)
        /// The wait selected for the currently displayed pattern.
        /// Random SERIKO ranges are sampled once when a pattern starts.
        public var currentDuration: Int
    }

    public private(set) var activeAnimations: [Int: AnimationState] = [:]
    private var definitions: [Int: SerikoParser.AnimationDefinition] = [:]
    /// 手動停止後に `interval,always` が次の tick で自動再起動するのを防ぐ。
    /// サーフェス定義の置換または明示的な再生で解除する。
    private var suppressedAlwaysAnimationIDs: Set<Int> = []
    private var triggeredRunonce: Set<Int> = []
    /// periodic,N の前回発火時刻（animationID 毎）。実時間で N 秒間隔を判定するため保持する。
    private var lastPeriodicStart: [Int: Date] = [:]
    private var pendingIntervalEvents: Set<SerikoInterval> = []
    /// talk,N の判定に使う、現在サーフェスが表示されてからの文字数。
    private var talkCharacterCount = 0
    private var lastTalkTriggerCount: [Int: Int] = [:]
    /// starttalk が発火済みの animation ID。各定義の再発火抑制に使う。
    private var startedTalkAnimations: Set<Int> = []
    /// 現在の会話スコープで starttalk が一度でも発火したか。
    private var hasStartedTalk = false

    private let nowProvider: () -> Date
    private let randomProvider: () -> Double

    public var onPatternExecuted: ((Int, SerikoPattern) -> Void)?
    public var onAnimationFinished: ((Int, SerikoAnimationFinishReason) -> Void)?
    public var onMethodInvoked: ((Int, SerikoMethod, Int, Int, Int) -> Void)?
    public var onScalingInvoked: ((Int, Double, Double) -> Void)?
    public var onImportInvoked: ((Int, String, Int, Int, Int) -> Void)?

    public init(
        nowProvider: @escaping () -> Date = Date.init,
        randomProvider: @escaping () -> Double = { Double.random(in: 0...1) }
    ) {
        self.nowProvider = nowProvider
        self.randomProvider = randomProvider
    }

    public func register(animations: [Int: SerikoParser.AnimationDefinition]) {
        definitions.merge(animations) { _, new in new }
    }

    /// 現在のサーフェスに属する定義へ置き換える。
    /// サーフェス切替後に前サーフェスの animation50 などを残すと、
    /// 旧サーフェス用の目元パッチが別表情の上で再生される。
    public func replace(animations: [Int: SerikoParser.AnimationDefinition]) {
        let previousDefinitions = definitions
        let now = nowProvider()
        var preserved: [Int: AnimationState] = [:]
        var stoppedIDs: [Int] = []

        // SSP's shared-index is the one exception to the normal surface
        // transition reset: both the source and destination definitions must
        // opt in, and the current pattern index must exist in the destination.
        for (animationID, var state) in activeAnimations {
            guard let previous = previousDefinitions[animationID],
                  let replacement = animations[animationID],
                  hasOption("shared-index", in: previous),
                  hasOption("shared-index", in: replacement),
                  state.currentPatternIndex >= 0,
                  state.currentPatternIndex < replacement.patterns.count else {
                stoppedIDs.append(animationID)
                continue
            }

            state.definition = replacement
            state.lastTickAt = now
            state.currentDuration = duration(for: replacement.patterns[state.currentPatternIndex])
            preserved[animationID] = state
        }

        definitions = animations
        activeAnimations = preserved
        // 抑制状態は現サーフェスに属するため、定義を置き換えたら新しい
        // サーフェスの always アニメーションを通常どおり自動起動できる。
        suppressedAlwaysAnimationIDs.removeAll()
        // runonce / periodic / talk,N はサーフェス単位の状態であり、定義の
        // 置換（通常はサーフェス切替・再読込）をまたいで持ち越してはいけない。
        triggeredRunonce.removeAll()
        lastPeriodicStart.removeAll()
        pendingIntervalEvents.removeAll()
        talkCharacterCount = 0
        lastTalkTriggerCount.removeAll()
        startedTalkAnimations.removeAll()
        hasStartedTalk = false

        for animationID in stoppedIDs {
            onAnimationFinished?(animationID, .stopped)
        }
        // Re-emit the current frame against the new base surface. The host
        // clears old overlays during a surface change, so this is required for
        // a shared-index animation to remain visible after the switch.
        for animationID in preserved.keys.sorted() {
            executeCurrentPattern(for: animationID)
        }
    }

    /// Return registered definition for an animation id
    public func definition(for id: Int) -> SerikoParser.AnimationDefinition? {
        definitions[id]
    }

    @discardableResult
    public func executeAnimation(id: Int) -> Bool {
        guard let definition = definitions[id], !definition.patterns.isEmpty else { return false }
        suppressedAlwaysAnimationIDs.remove(id)
        if (hasOption("shared", in: definition) || hasOption("shared-index", in: definition)),
           activeAnimations[id] != nil {
            return true
        }
        if let series = definition.seriesOption {
            stopAnimations(inSeries: series, except: id)
        }
        if hasOption("exclusive", in: definition) {
            stopAnimations(except: id)
        }
        let now = nowProvider()
        let state = AnimationState(
            animationID: id,
            definition: definition,
            currentPatternIndex: 0,
            isPaused: false,
            offsetX: 0,
            offsetY: 0,
            lastTickAt: now,
            stepDirection: 1,
            currentDuration: duration(for: definition.patterns[0])
        )
        activeAnimations[id] = state
        executeCurrentPattern(for: id)
        return true
    }

    public func startLoop() {
        let now = nowProvider()
        let endingTalk = pendingIntervalEvents.contains(.endTalk)
        startScheduledAnimations(now: now)

        for id in activeAnimations.keys.sorted() {
            guard var state = activeAnimations[id], !state.isPaused else { continue }
            guard state.currentPatternIndex < state.definition.patterns.count else {
                stopAnimation(id: id)
                continue
            }
            let elapsed = now.timeIntervalSince(state.lastTickAt) * 1000
            if elapsed < Double(state.currentDuration) {
                continue
            }

            // advance by step (supports ping-pong)
            state.currentPatternIndex += max(min(state.stepDirection, 1), -1)
            state.lastTickAt = now

            let count = state.definition.patterns.count
            if state.currentPatternIndex >= count || state.currentPatternIndex < 0 {
                if state.definition.interval.components.contains(.runonce) {
                    // runonce: finish immediately
                    finishAnimation(id: id, reason: .completed)
                    continue
                }
                if state.definition.pingPong && count > 1 {
                    // reverse direction and bounce inside range
                    state.stepDirection *= -1
                    if state.currentPatternIndex >= count {
                        state.currentPatternIndex = count - 2
                    } else if state.currentPatternIndex < 0 {
                        state.currentPatternIndex = 1
                    }
                } else {
                    // simple loop
                    state.currentPatternIndex = 0
                }
            }
            state.currentDuration = duration(for: state.definition.patterns[state.currentPatternIndex])
            activeAnimations[id] = state
            executeCurrentPattern(for: id)
        }
        pendingIntervalEvents.removeAll()
        if endingTalk {
            // endtalk はスコープ単位の境界イベント。対応する定義が無くても
            // 次のトークで starttalk が再び発火できるよう履歴を閉じる。
            startedTalkAnimations.removeAll()
            hasStartedTalk = false
        }
    }

    public func executePattern(animationID: Int, pattern: SerikoPattern) {
        // UKADOC: surfaceID -1 は自身のアニメーションを停止し、-2 は
        // 現在実行中の他のアニメーションを停止する制御フレームである。
        // 画像IDとして描画経路へ流すと、存在しない surface を読み込もうと
        // するだけでアニメーションが止まらず、後続フレームも再生される。
        if isSurfaceControlFrame(pattern), pattern.surfaceID == -1 {
            finishAnimation(id: animationID, reason: .stopped)
            onPatternExecuted?(animationID, pattern)
            return
        }
        if isSurfaceControlFrame(pattern), pattern.surfaceID == -2 {
            let otherAnimationIDs = activeAnimations.keys.filter { $0 != animationID }
            for otherAnimationID in otherAnimationIDs {
                stopAnimation(id: otherAnimationID)
            }
            onPatternExecuted?(animationID, pattern)
            return
        }

        switch pattern.method {
        case .overlay:
            executeOverlay(animationID: animationID, pattern: pattern)
        case .overlayFast:
            executeOverlayFast(animationID: animationID, pattern: pattern)
        case .base:
            executeBase(animationID: animationID, pattern: pattern)
        case .move:
            executeMove(animationID: animationID, pattern: pattern)
        case .scaling:
            onScalingInvoked?(animationID, pattern.xValue, pattern.yValue)
            emitMethod(
                animationID: animationID,
                method: pattern.method,
                surfaceID: pattern.surfaceID,
                x: pattern.x,
                y: pattern.y,
                includesAnimationOffset: false
            )
        case .add, .bind, .auto:
            emitMethod(animationID: animationID, method: pattern.method, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
        case .reduce:
            executeReduce(animationID: animationID, pattern: pattern)
        case .replace:
            executeReplace(animationID: animationID, pattern: pattern)
        case .start:
            executeStart(animationID: animationID, pattern: pattern)
        case .alternativeStart:
            executeAlternativeStart(animationID: animationID, pattern: pattern)
        case .insert:
            // 別アニメ列の割り込み再生は start に準じて対象アニメを起動する
            executeStart(animationID: animationID, pattern: pattern)
        case .interpolate:
            emitMethod(animationID: animationID, method: .interpolate, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
        case .blend:
            emitMethod(animationID: animationID, method: pattern.method, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
        case .parallelStart:
            for nestedID in pattern.referencedAnimationIDs {
                _ = executeAnimation(id: nestedID)
            }
        case .parallelStop:
            for nestedID in pattern.referencedAnimationIDs {
                stopAnimation(id: nestedID)
            }
        case .stop:
            stopAnimation(id: animationID)
        case .alternativeStop:
            executeAlternativeStop(animationID: animationID, pattern: pattern)
        case .import:
            guard pattern.rawArguments.count >= 2 else { break }
            let filename = pattern.rawArguments[1]
            let initialDelay = pattern.rawArguments.count > 2 ? Int(pattern.rawArguments[2]) ?? 0 : 0
            let x = pattern.rawArguments.count > 3 ? Int(pattern.rawArguments[3]) ?? 0 : 0
            let y = pattern.rawArguments.count > 4 ? Int(pattern.rawArguments[4]) ?? 0 : 0
            let adjustedCoordinates = coordinates(
                animationID: animationID,
                x: x,
                y: y,
                includesAnimationOffset: true
            )
            onImportInvoked?(animationID, filename, initialDelay, adjustedCoordinates.x, adjustedCoordinates.y)
        case .asis, .unknown:
            emitMethod(animationID: animationID, method: pattern.method, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
        case .noop:
            // SSP 0x7000051: 何もしない。
            break
        }
        onPatternExecuted?(animationID, pattern)
    }

    /// -1/-2 は画像を参照する描画パターンだけで意味を持つ。
    /// import や alternativestart/parallelstart などの制御パターンは、
    /// surfaceID に -1 をプレースホルダーとして使うため対象外とする。
    private func isSurfaceControlFrame(_ pattern: SerikoPattern) -> Bool {
        switch pattern.method {
        case .overlay, .overlayFast, .base, .move, .scaling, .add, .bind, .auto,
             .reduce, .replace, .interpolate, .blend, .asis, .unknown:
            return true
        case .import, .start, .alternativeStart, .stop, .alternativeStop, .insert,
             .parallelStart, .parallelStop, .noop:
            return false
        }
    }

    public func executeOverlay(animationID: Int, pattern: SerikoPattern) {
        emitMethod(animationID: animationID, method: .overlay, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
    }

    public func executeOverlayFast(animationID: Int, pattern: SerikoPattern) {
        emitMethod(animationID: animationID, method: .overlayFast, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
    }

    public func executeBase(animationID: Int, pattern: SerikoPattern) {
        emitMethod(
            animationID: animationID,
            method: .base,
            surfaceID: pattern.surfaceID,
            x: pattern.x,
            y: pattern.y,
            includesAnimationOffset: false
        )
    }

    public func executeMove(animationID: Int, pattern: SerikoPattern) {
        if var state = activeAnimations[animationID] {
            // SERIKO move の座標は前フレームからの差分ではなく、元位置からの
            // 相対位置。連続する move パターンでは毎回絶対値として置き換える。
            state.offsetX = pattern.x
            state.offsetY = pattern.y
            activeAnimations[animationID] = state
        }
        emitMethod(
            animationID: animationID,
            method: .move,
            surfaceID: pattern.surfaceID,
            x: pattern.x,
            y: pattern.y,
            includesAnimationOffset: false
        )
    }

    public func executeReduce(animationID: Int, pattern: SerikoPattern) {
        emitMethod(animationID: animationID, method: .reduce, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
    }

    public func executeReplace(animationID: Int, pattern: SerikoPattern) {
        emitMethod(animationID: animationID, method: .replace, surfaceID: pattern.surfaceID, x: pattern.x, y: pattern.y)
    }

    public func executeStart(animationID: Int, pattern: SerikoPattern) {
        emitMethod(
            animationID: animationID,
            method: .start,
            surfaceID: pattern.surfaceID,
            x: pattern.x,
            y: pattern.y,
            includesAnimationOffset: false
        )
    }

    public func executeAlternativeStart(animationID: Int, pattern: SerikoPattern) {
        let selected = selectReferencedAnimationID(for: pattern)
        guard selected >= 0 else { return }
        emitMethod(
            animationID: animationID,
            method: .alternativeStart,
            surfaceID: selected,
            x: pattern.x,
            y: pattern.y,
            includesAnimationOffset: false
        )
    }

    public func executeAlternativeStop(animationID: Int, pattern: SerikoPattern) {
        let selected = selectReferencedAnimationID(for: pattern)
        guard selected >= 0 else { return }
        emitMethod(
            animationID: animationID,
            method: .alternativeStop,
            surfaceID: selected,
            x: pattern.x,
            y: pattern.y,
            includesAnimationOffset: false
        )
    }

    private func emitMethod(
        animationID: Int,
        method: SerikoMethod,
        surfaceID: Int,
        x: Int,
        y: Int,
        includesAnimationOffset: Bool = true
    ) {
        let adjusted = coordinates(
            animationID: animationID,
            x: x,
            y: y,
            includesAnimationOffset: includesAnimationOffset
        )
        onMethodInvoked?(animationID, method, surfaceID, adjusted.x, adjusted.y)
    }

    private func coordinates(
        animationID: Int,
        x: Int,
        y: Int,
        includesAnimationOffset: Bool
    ) -> (x: Int, y: Int) {
        guard includesAnimationOffset, let state = activeAnimations[animationID] else {
            return (x, y)
        }
        return (x + state.offsetX, y + state.offsetY)
    }

    private func selectReferencedAnimationID(for pattern: SerikoPattern) -> Int {
        let candidates = pattern.referencedAnimationIDs
        guard !candidates.isEmpty else { return pattern.surfaceID }
        let randomValue = max(0, min(1, randomProvider()))
        let index = min(candidates.count - 1, Int(randomValue * Double(candidates.count)))
        return candidates[index]
    }

    public func stopAnimation(id: Int) {
        activeAnimations.removeValue(forKey: id)
        onAnimationFinished?(id, .stopped)
    }

    public func stopAllAnimations(suppressAlwaysAnimations: Bool = false) {
        if suppressAlwaysAnimations {
            suppressedAlwaysAnimationIDs.formUnion(
                definitions.compactMap { id, definition in
                    definition.interval.components.contains(.always) ? id : nil
                }
            )
        }
        let ids = Array(activeAnimations.keys)
        for id in ids {
            stopAnimation(id: id)
        }
    }

    public func pauseAnimation(id: Int) {
        guard var state = activeAnimations[id] else { return }
        state.isPaused = true
        activeAnimations[id] = state
    }

    public func resumeAnimation(id: Int) {
        guard var state = activeAnimations[id] else { return }
        state.isPaused = false
        state.lastTickAt = nowProvider()
        activeAnimations[id] = state
    }

    public func offsetAnimation(id: Int, x: Int, y: Int) {
        guard var state = activeAnimations[id] else { return }
        state.offsetX = x
        state.offsetY = y
        activeAnimations[id] = state
    }

    public func triggerYenE() { pendingIntervalEvents.insert(.yenE) }
    public func triggerTalk(characterCount: Int = 1) {
        pendingIntervalEvents.insert(.talk)
        if characterCount > 0 {
            talkCharacterCount += characterCount
        }
    }
    public func triggerStartTalk() { pendingIntervalEvents.insert(.startTalk) }
    public func triggerEndTalk() { pendingIntervalEvents.insert(.endTalk) }
    public func triggerBind() { pendingIntervalEvents.insert(.bind) }

    private func executeCurrentPattern(for id: Int) {
        guard let state = activeAnimations[id],
              state.currentPatternIndex < state.definition.patterns.count else { return }
        let pattern = state.definition.patterns[state.currentPatternIndex]
        executePattern(animationID: id, pattern: pattern)
    }

    private func startScheduledAnimations(now: Date) {
        for (id, definition) in definitions {
            guard activeAnimations[id] == nil else { continue }
            guard !suppressedAlwaysAnimationIDs.contains(id) else { continue }
            if let series = definition.seriesOption,
               hasActiveAnimation(inSeries: series, excluding: id) {
                continue
            }
            guard shouldStart(definition: definition, animationID: id, now: now) else { continue }
            if hasOption("exclusive", in: definition) {
                stopAnimations(except: id)
            }

            let state = AnimationState(
                animationID: id,
                definition: definition,
                currentPatternIndex: 0,
                isPaused: false,
                offsetX: 0,
                offsetY: 0,
                lastTickAt: now,
                stepDirection: 1,
                currentDuration: duration(for: definition.patterns[0])
            )
            activeAnimations[id] = state
            executeCurrentPattern(for: id)
        }
    }

    private func hasOption(_ option: String, in definition: SerikoParser.AnimationDefinition) -> Bool {
        let target = option.lowercased()
        return definition.options.contains { $0.lowercased() == target }
    }

    /// Select an inclusive SSP random wait. Fixed waits do not consume the
    /// executor's random source, which keeps interval randomness independent
    /// from ordinary pattern timing.
    private func duration(for pattern: SerikoPattern) -> Int {
        guard let range = pattern.durationRange,
              range.lowerBound < range.upperBound else {
            return max(pattern.duration, 0)
        }
        let value = max(0, min(1, randomProvider()))
        let count = range.upperBound - range.lowerBound + 1
        let offset = min(count - 1, Int(value * Double(count)))
        return range.lowerBound + offset
    }

    private func stopAnimations(except animationID: Int) {
        let targets = activeAnimations.keys.filter { id in
            id != animationID && !isBackgroundAnimation(id)
        }
        for id in targets {
            stopAnimation(id: id)
        }
    }

    private func stopAnimations(inSeries series: String, except animationID: Int) {
        let normalized = series.lowercased()
        let targets = activeAnimations.keys.filter { id in
            guard id != animationID else { return false }
            guard let definition = definitions[id], let currentSeries = definition.seriesOption else { return false }
            return currentSeries.lowercased() == normalized
        }
        for id in targets {
            stopAnimation(id: id)
        }
    }

    private func hasActiveAnimation(inSeries series: String, excluding animationID: Int) -> Bool {
        let normalized = series.lowercased()
        return activeAnimations.keys.contains { id in
            guard id != animationID else { return false }
            guard let definition = definitions[id], let currentSeries = definition.seriesOption else { return false }
            return currentSeries.lowercased() == normalized
        }
    }

    private func isBackgroundAnimation(_ animationID: Int) -> Bool {
        guard let state = activeAnimations[animationID] else { return false }
        return hasOption("background", in: state.definition)
    }

    private func finishAnimation(id: Int, reason: SerikoAnimationFinishReason) {
        activeAnimations.removeValue(forKey: id)
        onAnimationFinished?(id, reason)
    }

    private func shouldStart(
        definition: SerikoParser.AnimationDefinition,
        animationID: Int,
        now: Date
    ) -> Bool {
        let components = definition.interval.components
        guard !components.isEmpty else { return false }

        var hasRunonce = false
        var hasPeriodic = false
        var periodicNeedsBaseline = false
        var hasTalkCharacters = false
        var hasStartTalk = false
        var hasEndTalk = false

        // 複合 interval は各条件を同時に満たした場合だけ発火する。
        // 状態変更は全条件が通った後に行い、random の不成立で runonce を
        // 消費するような半端な遷移を防ぐ。
        for component in components {
            switch component {
            case .always:
                continue
            case .sometimes:
                guard randomProvider() < 0.2 else { return false }
            case .rarely:
                guard randomProvider() < 0.05 else { return false }
            case .random(let threshold):
                let t = threshold ?? 10
                guard Int(randomProvider() * Double(max(t, 1))) == 0 else { return false }
            case .periodic(let seconds):
                hasPeriodic = true
                let interval = Double(max(seconds ?? 1, 1))
                if let last = lastPeriodicStart[animationID] {
                    guard now.timeIntervalSince(last) >= interval else { return false }
                } else {
                    periodicNeedsBaseline = true
                }
            case .runonce:
                hasRunonce = true
                guard !triggeredRunonce.contains(animationID) else { return false }
            case .yenE:
                guard pendingIntervalEvents.contains(.yenE) else { return false }
            case .talk:
                guard pendingIntervalEvents.contains(.talk) else { return false }
            case .talkCharacters(let count):
                hasTalkCharacters = true
                guard pendingIntervalEvents.contains(.talk) else { return false }
                let last = lastTalkTriggerCount[animationID] ?? 0
                guard talkCharacterCount - last >= max(count, 1) else { return false }
            case .startTalk:
                hasStartTalk = true
                guard pendingIntervalEvents.contains(.startTalk) else { return false }
                guard !startedTalkAnimations.contains(animationID) else { return false }
            case .endTalk:
                hasEndTalk = true
                guard pendingIntervalEvents.contains(.endTalk) else { return false }
                guard hasStartedTalk else { return false }
            case .bind:
                guard pendingIntervalEvents.contains(.bind) else { return false }
            case .never, .unknown, .combined:
                // パーサーは複合から never を除外済みのため、ここへ到達する never は
                // 単独指定のみ（= 無効）。combined は平坦化済みなので到達しない。
                return false
            }
        }

        if periodicNeedsBaseline {
            // 初回評価は基準時刻だけ記録し、N 秒後の評価で発火する。
            lastPeriodicStart[animationID] = now
            return false
        }
        if hasRunonce {
            triggeredRunonce.insert(animationID)
        }
        if hasPeriodic {
            lastPeriodicStart[animationID] = now
        }
        if hasTalkCharacters {
            lastTalkTriggerCount[animationID] = talkCharacterCount
        }
        if hasStartTalk {
            startedTalkAnimations.insert(animationID)
            hasStartedTalk = true
        }
        if hasEndTalk {
            startedTalkAnimations.remove(animationID)
        }
        return true
    }
}
