import Foundation

public final class SerikoExecutor {
    public struct AnimationState: Equatable {
        public let animationID: Int
        public let definition: SerikoParser.AnimationDefinition
        public var currentPatternIndex: Int
        public var isPaused: Bool
        public var offsetX: Int
        public var offsetY: Int
        public var lastTickAt: Date
        public var stepDirection: Int  // 1: forward, -1: backward (for ping-pong)
    }

    public private(set) var activeAnimations: [Int: AnimationState] = [:]
    private var definitions: [Int: SerikoParser.AnimationDefinition] = [:]
    private var triggeredRunonce: Set<Int> = []
    /// periodic,N の前回発火時刻（animationID 毎）。実時間で N 秒間隔を判定するため保持する。
    private var lastPeriodicStart: [Int: Date] = [:]
    private var pendingIntervalEvents: Set<SerikoInterval> = []
    /// talk,N の判定に使う、現在サーフェスが表示されてからの文字数。
    private var talkCharacterCount = 0
    private var lastTalkTriggerCount: [Int: Int] = [:]

    private let nowProvider: () -> Date
    private let randomProvider: () -> Double

    public var onPatternExecuted: ((Int, SerikoPattern) -> Void)?
    public var onAnimationFinished: ((Int) -> Void)?
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
        definitions = animations
        // runonce / periodic / talk,N はサーフェス単位の状態であり、定義の
        // 置換（通常はサーフェス切替・再読込）をまたいで持ち越してはいけない。
        triggeredRunonce.removeAll()
        lastPeriodicStart.removeAll()
        pendingIntervalEvents.removeAll()
        talkCharacterCount = 0
        lastTalkTriggerCount.removeAll()
    }

    /// Return registered definition for an animation id
    public func definition(for id: Int) -> SerikoParser.AnimationDefinition? {
        definitions[id]
    }

    @discardableResult
    public func executeAnimation(id: Int) -> Bool {
        guard let definition = definitions[id], !definition.patterns.isEmpty else { return false }
        if hasOption("shared", in: definition), activeAnimations[id] != nil {
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
            stepDirection: 1
        )
        activeAnimations[id] = state
        executeCurrentPattern(for: id)
        return true
    }

    public func startLoop() {
        let now = nowProvider()
        startScheduledAnimations(now: now)

        for id in activeAnimations.keys.sorted() {
            guard var state = activeAnimations[id], !state.isPaused else { continue }
            guard state.currentPatternIndex < state.definition.patterns.count else {
                stopAnimation(id: id)
                continue
            }
            let pattern = state.definition.patterns[state.currentPatternIndex]
            let elapsed = now.timeIntervalSince(state.lastTickAt) * 1000
            if elapsed < Double(max(pattern.duration, 0)) {
                continue
            }

            // advance by step (supports ping-pong)
            state.currentPatternIndex += max(min(state.stepDirection, 1), -1)
            state.lastTickAt = now

            let count = state.definition.patterns.count
            if state.currentPatternIndex >= count || state.currentPatternIndex < 0 {
                if case .runonce = state.definition.interval {
                    // runonce: finish immediately
                    activeAnimations.removeValue(forKey: id)
                    onAnimationFinished?(id)
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
            activeAnimations[id] = state
            executeCurrentPattern(for: id)
        }
        pendingIntervalEvents.removeAll()
    }

    public func executePattern(animationID: Int, pattern: SerikoPattern) {
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
        }
        onPatternExecuted?(animationID, pattern)
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
            state.offsetX += pattern.x
            state.offsetY += pattern.y
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
        onAnimationFinished?(id)
    }

    public func stopAllAnimations() {
        let ids = Array(activeAnimations.keys)
        activeAnimations.removeAll()
        for id in ids {
            onAnimationFinished?(id)
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
                stepDirection: 1
            )
            activeAnimations[id] = state
            executeCurrentPattern(for: id)
        }
    }

    private func hasOption(_ option: String, in definition: SerikoParser.AnimationDefinition) -> Bool {
        let target = option.lowercased()
        return definition.options.contains { $0.lowercased() == target }
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
            case .bind:
                guard pendingIntervalEvents.contains(.bind) else { return false }
            case .never, .unknown, .combined:
                // `components` は複合値を平坦化するため combined には到達しない。
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
        return true
    }
}
