import Foundation
import Testing
@testable import Ourin

struct SerikoExecutorTests {
    private func makeDefinition(
        id: Int,
        interval: SerikoInterval,
        methods: [SerikoMethod]
    ) -> SerikoParser.AnimationDefinition {
        let patterns = methods.enumerated().map { idx, method in
            SerikoPattern(
                index: idx,
                method: method,
                surfaceID: 100 + idx,
                duration: 10,
                x: idx,
                y: idx + 1,
                rawArguments: []
            )
        }
        return SerikoParser.AnimationDefinition(id: id, interval: interval, options: [], patterns: patterns)
    }

    @Test
    func executeAnimationStartsAndRunsFirstPattern() async throws {
        let executor = SerikoExecutor(nowProvider: Date.init, randomProvider: { 0.0 })
        let def = makeDefinition(id: 1, interval: .never, methods: [.overlay, .base])
        executor.register(animations: [1: def])

        var invoked: [SerikoMethod] = []
        executor.onMethodInvoked = { _, method, _, _, _ in invoked.append(method) }

        let ok = executor.executeAnimation(id: 1)
        #expect(ok)
        #expect(executor.activeAnimations[1] != nil)
        #expect(invoked.first == .overlay)
    }

    @Test
    func runonceCompletesAfterPatterns() async throws {
        var now = Date(timeIntervalSince1970: 0)
        let executor = SerikoExecutor(
            nowProvider: { now },
            randomProvider: { 0.0 }
        )
        let def = makeDefinition(id: 10, interval: .runonce, methods: [.overlay, .replace])
        executor.register(animations: [10: def])

        _ = executor.executeAnimation(id: 10)
        #expect(executor.activeAnimations[10] != nil)

        now = now.addingTimeInterval(0.02)
        executor.startLoop()
        #expect(executor.activeAnimations[10] != nil)

        now = now.addingTimeInterval(0.02)
        executor.startLoop()
        #expect(executor.activeAnimations[10] == nil)
    }

    @Test
    func moveUpdatesOffsets() async throws {
        let executor = SerikoExecutor()
        let pattern = SerikoPattern(index: 0, method: .move, surfaceID: 1, duration: 10, x: 5, y: -3, rawArguments: [])
        let def = SerikoParser.AnimationDefinition(id: 5, interval: .never, options: [], patterns: [pattern])
        executor.register(animations: [5: def])
        _ = executor.executeAnimation(id: 5)

        #expect(executor.activeAnimations[5]?.offsetX == 5)
        #expect(executor.activeAnimations[5]?.offsetY == -3)
    }

    @Test
    func intervalTriggersForTalkBindYenE() async throws {
        let executor = SerikoExecutor(nowProvider: Date.init, randomProvider: { 1.0 })
        let talk = makeDefinition(id: 20, interval: .talk, methods: [.overlay])
        let bind = makeDefinition(id: 21, interval: .bind, methods: [.overlay])
        let yenE = makeDefinition(id: 22, interval: .yenE, methods: [.overlay])
        executor.register(animations: [20: talk, 21: bind, 22: yenE])

        executor.startLoop()
        #expect(executor.activeAnimations.isEmpty)

        executor.triggerTalk()
        executor.startLoop()
        #expect(executor.activeAnimations[20] != nil)

        executor.stopAllAnimations()
        executor.triggerBind()
        executor.startLoop()
        #expect(executor.activeAnimations[21] != nil)

        executor.stopAllAnimations()
        executor.triggerYenE()
        executor.startLoop()
        #expect(executor.activeAnimations[22] != nil)
    }
}

