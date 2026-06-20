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

    private let nowProvider: () -> Date
    private let randomProvider: () -> Double

    public var onPatternExecuted: ((Int, SerikoPattern) -> Void)?
    public var onAnimationFinished: ((Int) -> Void)?
    public var onMethodInvoked: ((Int, SerikoMethod, Int, Int, Int) -> Void)?

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
            // フレーム補間は未対応のため overlay 合成にフォールバック（対象フレームを表示）
            executeOverlay(animationID: animationID, pattern: pattern)
        case .stop, .alternativeStop:
            stopAnimation(id: animationID)
        case .asis, .unknown:
            onMethodInvoked?(animationID, pattern.method, pattern.surfaceID, pattern.x, pattern.y)
        }
        onPatternExecuted?(animationID, pattern)
    }

    public func executeOverlay(animationID: Int, pattern: SerikoPattern) {
        onMethodInvoked?(animationID, .overlay, pattern.surfaceID, pattern.x, pattern.y)
    }

    public func executeOverlayFast(animationID: Int, pattern: SerikoPattern) {
        onMethodInvoked?(animationID, .overlayFast, pattern.surfaceID, pattern.x, pattern.y)
    }

    public func executeBase(animationID: Int, pattern: SerikoPattern) {
        onMethodInvoked?(animationID, .base, pattern.surfaceID, pattern.x, pattern.y)
    }

    public func executeMove(animationID: Int, pattern: SerikoPattern) {
        if var state = activeAnimations[animationID] {
            state.offsetX += pattern.x
            state.offsetY += pattern.y
            activeAnimations[animationID] = state
        }
        onMethodInvoked?(animationID, .move, pattern.surfaceID, pattern.x, pattern.y)
    }

    public func executeReduce(animationID: Int, pattern: SerikoPattern) {
        onMethodInvoked?(animationID, .reduce, pattern.surfaceID, pattern.x, pattern.y)
    }

    public func executeReplace(animationID: Int, pattern: SerikoPattern) {
        onMethodInvoked?(animationID, .replace, pattern.surfaceID, pattern.x, pattern.y)
    }

    public func executeStart(animationID: Int, pattern: SerikoPattern) {
        onMethodInvoked?(animationID, .start, pattern.surfaceID, pattern.x, pattern.y)
    }

    public func executeAlternativeStart(animationID: Int, pattern: SerikoPattern) {
        onMethodInvoked?(animationID, .alternativeStart, pattern.surfaceID, pattern.x, pattern.y)
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
    public func triggerTalk() { pendingIntervalEvents.insert(.talk) }
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
            guard shouldStart(definition: definition, animationID: id) else { continue }
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

    private func shouldStart(definition: SerikoParser.AnimationDefinition, animationID: Int) -> Bool {
        switch definition.interval {
        case .always:
            return true
        case .sometimes:
            return randomProvider() < 0.2
        case .rarely:
            return randomProvider() < 0.05
        case .random(let threshold):
            let t = threshold ?? 10
            return Int(randomProvider() * Double(max(t, 1))) == 0
        case .periodic(let seconds):
            // periodic,N — 前回発火から N 秒経過するたびに必ず発火する（UKADOC）。
            // startLoop が高頻度（20Hz）で回るため、呼び出し回数ではなく実時間で判定する。
            let interval = Double(max(seconds ?? 1, 1))
            let now = nowProvider()
            if let last = lastPeriodicStart[animationID] {
                if now.timeIntervalSince(last) >= interval {
                    lastPeriodicStart[animationID] = now
                    return true
                }
                return false
            }
            // 初回評価時は基準時刻のみ記録し、最初の発火は N 秒後とする
            lastPeriodicStart[animationID] = now
            return false
        case .runonce:
            if triggeredRunonce.contains(animationID) { return false }
            triggeredRunonce.insert(animationID)
            return true
        case .yenE:
            return pendingIntervalEvents.contains(.yenE)
        case .talk:
            return pendingIntervalEvents.contains(.talk)
        case .bind:
            return pendingIntervalEvents.contains(.bind)
        case .never, .unknown:
            return false
        }
    }
}
