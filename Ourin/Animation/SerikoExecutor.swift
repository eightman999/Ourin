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
    }

    public private(set) var activeAnimations: [Int: AnimationState] = [:]
    private var definitions: [Int: SerikoParser.AnimationDefinition] = [:]
    private var triggeredRunonce: Set<Int> = []
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

    @discardableResult
    public func executeAnimation(id: Int) -> Bool {
        guard let definition = definitions[id], !definition.patterns.isEmpty else { return false }
        let now = nowProvider()
        let state = AnimationState(
            animationID: id,
            definition: definition,
            currentPatternIndex: 0,
            isPaused: false,
            offsetX: 0,
            offsetY: 0,
            lastTickAt: now
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

            state.currentPatternIndex += 1
            state.lastTickAt = now

            if state.currentPatternIndex >= state.definition.patterns.count {
                if case .runonce = state.definition.interval {
                    activeAnimations.removeValue(forKey: id)
                    onAnimationFinished?(id)
                    continue
                }
                state.currentPatternIndex = 0
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
        case .stop:
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
            guard shouldStart(definition: definition, animationID: id) else { continue }

            let state = AnimationState(
                animationID: id,
                definition: definition,
                currentPatternIndex: 0,
                isPaused: false,
                offsetX: 0,
                offsetY: 0,
                lastTickAt: now
            )
            activeAnimations[id] = state
            executeCurrentPattern(for: id)
        }
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
