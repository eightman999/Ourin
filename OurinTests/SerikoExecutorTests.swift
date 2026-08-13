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
    func animationOffsetIsAppliedToFollowingSurfaceCoordinates() async throws {
        let executor = SerikoExecutor()
        let pattern = SerikoPattern(
            index: 0,
            method: .overlay,
            surfaceID: 7,
            duration: 10,
            x: 3,
            y: 4,
            rawArguments: []
        )
        let definition = SerikoParser.AnimationDefinition(
            id: 7,
            interval: .never,
            options: [],
            patterns: [pattern]
        )
        executor.register(animations: [7: definition])

        var coordinates: [(Int, Int)] = []
        executor.onMethodInvoked = { _, method, _, x, y in
            guard method == .overlay else { return }
            coordinates.append((x, y))
        }

        #expect(executor.executeAnimation(id: 7))
        executor.offsetAnimation(id: 7, x: 40, y: 50)
        executor.executePattern(animationID: 7, pattern: pattern)

        #expect(coordinates.count == 2)
        #expect(coordinates[0].0 == 3)
        #expect(coordinates[0].1 == 4)
        #expect(coordinates[1].0 == 43)
        #expect(coordinates[1].1 == 54)
    }

    @Test
    func scalingInvokesMethodAndPreservesFractionalCallbackValues() async throws {
        let executor = SerikoExecutor()
        let pattern = SerikoPattern(
            index: 0,
            method: .scaling,
            surfaceID: 0,
            duration: 10,
            x: 92,
            y: 87,
            rawArguments: ["scaling", "0", "10", "92.5", "87.25"],
            xValue: 92.5,
            yValue: 87.25
        )
        var invoked: SerikoMethod?
        var scalingValues: (Double, Double)?
        executor.onMethodInvoked = { _, method, _, _, _ in invoked = method }
        executor.onScalingInvoked = { _, x, y in scalingValues = (x, y) }

        executor.executePattern(animationID: 7, pattern: pattern)

        #expect(invoked == .scaling)
        #expect(scalingValues?.0 == 92.5)
        #expect(scalingValues?.1 == 87.25)
    }

    @Test
    func importInvokesFilenameTimingAndOffsetCallback() async throws {
        let executor = SerikoExecutor()
        let pattern = SerikoPattern(
            index: 0,
            method: .import,
            surfaceID: -1,
            duration: 250,
            x: 3,
            y: 4,
            rawArguments: ["import", "media/anim.gif", "250", "3", "4"]
        )
        var callback: (String, Int, Int, Int)?
        executor.onImportInvoked = { _, filename, wait, x, y in
            callback = (filename, wait, x, y)
        }

        executor.executePattern(animationID: 8, pattern: pattern)

        #expect(callback?.0 == "media/anim.gif")
        #expect(callback?.1 == 250)
        #expect(callback?.2 == 3)
        #expect(callback?.3 == 4)
    }

    @Test
    func alternativeMethodsSelectCandidateAnimationID() async throws {
        let executor = SerikoExecutor(randomProvider: { 0.51 })
        let start = SerikoPattern(
            index: 0,
            method: .alternativeStart,
            surfaceID: -1,
            duration: 0,
            x: 0,
            y: 0,
            rawArguments: ["alternativestart", "(2,4,6)"]
        )
        let stop = SerikoPattern(
            index: 1,
            method: .alternativeStop,
            surfaceID: -1,
            duration: 0,
            x: 0,
            y: 0,
            rawArguments: ["alternativestop", "[2,4,6]"]
        )

        var calls: [(SerikoMethod, Int)] = []
        executor.onMethodInvoked = { _, method, surfaceID, _, _ in
            calls.append((method, surfaceID))
        }

        executor.executePattern(animationID: 90, pattern: start)
        executor.executePattern(animationID: 90, pattern: stop)

        #expect(calls.map(\.0) == [.alternativeStart, .alternativeStop])
        #expect(calls.map(\.1) == [4, 4])
    }

    @Test
    func parallelMethodsStartAndStopEveryReferencedAnimation() async throws {
        let executor = SerikoExecutor()
        let first = makeDefinition(id: 101, interval: .never, methods: [.overlay])
        let second = makeDefinition(id: 102, interval: .never, methods: [.overlay])
        executor.register(animations: [101: first, 102: second])

        let start = SerikoPattern(
            index: 0,
            method: .parallelStart,
            surfaceID: -1,
            duration: 0,
            x: 0,
            y: 0,
            rawArguments: ["parallelstart", "(101,102)"]
        )
        executor.executePattern(animationID: 90, pattern: start)
        #expect(executor.activeAnimations[101] != nil)
        #expect(executor.activeAnimations[102] != nil)

        let stop = SerikoPattern(
            index: 1,
            method: .parallelStop,
            surfaceID: -1,
            duration: 0,
            x: 0,
            y: 0,
            rawArguments: ["parallelstop", "[101.102]"]
        )
        executor.executePattern(animationID: 90, pattern: stop)
        #expect(executor.activeAnimations[101] == nil)
        #expect(executor.activeAnimations[102] == nil)
    }

    @Test
    func replaceDefinitionsDropsPreviousSurfaceAnimations() async throws {
        let executor = SerikoExecutor()
        let previous = makeDefinition(id: 40, interval: .never, methods: [.overlay])
        let current = makeDefinition(id: 41, interval: .never, methods: [.overlay])

        executor.register(animations: [previous.id: previous])
        executor.replace(animations: [current.id: current])

        #expect(executor.definition(for: previous.id) == nil)
        #expect(executor.definition(for: current.id) == current)
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

    @Test
    func parameterizedTalkIntervalWaitsForCharacterCount() async throws {
        let executor = SerikoExecutor(nowProvider: Date.init, randomProvider: { 1.0 })
        let definition = makeDefinition(id: 23, interval: .talkCharacters(2), methods: [.overlay])
        executor.register(animations: [23: definition])

        executor.triggerTalk(characterCount: 1)
        executor.startLoop()
        #expect(executor.activeAnimations[23] == nil)

        executor.triggerTalk(characterCount: 1)
        executor.startLoop()
        #expect(executor.activeAnimations[23] != nil)
    }

    @Test
    func startTalkFiresOnceUntilEndTalkAndEndTalkRequiresHistory() async throws {
        let executor = SerikoExecutor(nowProvider: Date.init, randomProvider: { 0.0 })
        let start = makeDefinition(id: 27, interval: .startTalk, methods: [.overlay])
        let end = makeDefinition(id: 28, interval: .endTalk, methods: [.overlay])
        executor.register(animations: [27: start, 28: end])

        executor.triggerEndTalk()
        executor.startLoop()
        #expect(executor.activeAnimations.isEmpty)

        executor.triggerStartTalk()
        executor.startLoop()
        #expect(executor.activeAnimations[27] != nil)

        executor.stopAllAnimations()
        executor.triggerStartTalk()
        executor.startLoop()
        #expect(executor.activeAnimations[27] == nil)

        executor.triggerEndTalk()
        executor.startLoop()
        #expect(executor.activeAnimations[28] != nil)

        executor.stopAllAnimations()
        executor.triggerStartTalk()
        executor.startLoop()
        #expect(executor.activeAnimations[27] != nil)
    }

    @Test
    func combinedIntervalRequiresEventAndRunonceGate() async throws {
        let executor = SerikoExecutor(nowProvider: Date.init, randomProvider: { 0.0 })
        let definition = makeDefinition(
            id: 24,
            interval: .combined([.bind, .runonce]),
            methods: [.overlay]
        )
        executor.register(animations: [24: definition])

        executor.startLoop()
        #expect(executor.activeAnimations[24] == nil)

        executor.triggerBind()
        executor.startLoop()
        #expect(executor.activeAnimations[24] != nil)

        executor.stopAllAnimations()
        executor.triggerBind()
        executor.startLoop()
        #expect(executor.activeAnimations[24] == nil)
    }

    @Test
    func combinedRunonceCompletesAfterPatternsAndKeepsCompletionReason() async throws {
        var now = Date(timeIntervalSince1970: 0)
        let executor = SerikoExecutor(nowProvider: { now }, randomProvider: { 0.0 })
        let definition = SerikoParser.AnimationDefinition(
            id: 26,
            interval: .combined([.bind, .runonce]),
            options: [],
            patterns: [
                SerikoPattern(index: 0, method: .overlay, surfaceID: 10, duration: 10, x: 0, y: 0, rawArguments: []),
                SerikoPattern(index: 1, method: .bind, surfaceID: 11, duration: 10, x: 0, y: 0, rawArguments: [])
            ]
        )
        executor.register(animations: [26: definition])

        var finishReason: SerikoAnimationFinishReason?
        executor.onAnimationFinished = { id, reason in
            guard id == 26 else { return }
            finishReason = reason
        }

        executor.triggerBind()
        executor.startLoop()
        #expect(executor.activeAnimations[26] != nil)

        now = now.addingTimeInterval(0.02)
        executor.startLoop()
        #expect(executor.activeAnimations[26] != nil)

        now = now.addingTimeInterval(0.02)
        executor.startLoop()
        #expect(executor.activeAnimations[26] == nil)
        #expect(finishReason == .completed)
    }

    @Test
    func replacingDefinitionsResetsRunonceLifecycle() async throws {
        var now = Date(timeIntervalSince1970: 0)
        let executor = SerikoExecutor(nowProvider: { now }, randomProvider: { 0.0 })
        let definition = makeDefinition(id: 25, interval: .runonce, methods: [.overlay])
        executor.register(animations: [25: definition])

        executor.startLoop()
        #expect(executor.activeAnimations[25] != nil)
        now = now.addingTimeInterval(0.02)
        executor.startLoop()
        #expect(executor.activeAnimations[25] == nil)

        executor.replace(animations: [25: definition])
        executor.startLoop()
        #expect(executor.activeAnimations[25] != nil)
    }

    @Test
    func exclusiveOptionStopsOtherActiveAnimations() async throws {
        let executor = SerikoExecutor()
        let normal = SerikoParser.AnimationDefinition(
            id: 1,
            interval: .never,
            options: [],
            patterns: [SerikoPattern(index: 0, method: .overlay, surfaceID: 10, duration: 10, x: 0, y: 0, rawArguments: [])]
        )
        let exclusive = SerikoParser.AnimationDefinition(
            id: 2,
            interval: .never,
            options: ["exclusive"],
            patterns: [SerikoPattern(index: 0, method: .overlay, surfaceID: 20, duration: 10, x: 0, y: 0, rawArguments: [])]
        )
        executor.register(animations: [1: normal, 2: exclusive])

        _ = executor.executeAnimation(id: 1)
        #expect(executor.activeAnimations[1] != nil)
        _ = executor.executeAnimation(id: 2)

        #expect(executor.activeAnimations[1] == nil)
        #expect(executor.activeAnimations[2] != nil)
    }

    @Test
    func sharedOptionDoesNotRestartActiveAnimation() async throws {
        let executor = SerikoExecutor()
        let shared = SerikoParser.AnimationDefinition(
            id: 3,
            interval: .never,
            options: ["shared"],
            patterns: [SerikoPattern(index: 0, method: .overlay, surfaceID: 30, duration: 10, x: 0, y: 0, rawArguments: [])]
        )
        executor.register(animations: [3: shared])

        var executionCount = 0
        executor.onPatternExecuted = { _, _ in executionCount += 1 }

        _ = executor.executeAnimation(id: 3)
        _ = executor.executeAnimation(id: 3)

        #expect(executionCount == 1)
        #expect(executor.activeAnimations[3] != nil)
    }

    @Test
    func exclusiveOptionKeepsBackgroundAnimations() async throws {
        let executor = SerikoExecutor()
        let background = SerikoParser.AnimationDefinition(
            id: 4,
            interval: .never,
            options: ["background"],
            patterns: [SerikoPattern(index: 0, method: .overlay, surfaceID: 40, duration: 10, x: 0, y: 0, rawArguments: [])]
        )
        let exclusive = SerikoParser.AnimationDefinition(
            id: 5,
            interval: .never,
            options: ["exclusive"],
            patterns: [SerikoPattern(index: 0, method: .overlay, surfaceID: 50, duration: 10, x: 0, y: 0, rawArguments: [])]
        )
        executor.register(animations: [4: background, 5: exclusive])

        _ = executor.executeAnimation(id: 4)
        _ = executor.executeAnimation(id: 5)

        #expect(executor.activeAnimations[4] != nil)
        #expect(executor.activeAnimations[5] != nil)
    }

    @Test
    func seriesOptionReplacesExistingSeriesAnimation() async throws {
        let executor = SerikoExecutor()
        let a = SerikoParser.AnimationDefinition(
            id: 30,
            interval: .never,
            options: [],
            patterns: [SerikoPattern(index: 0, method: .overlay, surfaceID: 100, duration: 10, x: 0, y: 0, rawArguments: [])],
            surfaceOption: nil,
            seriesOption: "mouth"
        )
        let b = SerikoParser.AnimationDefinition(
            id: 31,
            interval: .never,
            options: [],
            patterns: [SerikoPattern(index: 0, method: .overlay, surfaceID: 101, duration: 10, x: 0, y: 0, rawArguments: [])],
            surfaceOption: nil,
            seriesOption: "mouth"
        )
        executor.register(animations: [30: a, 31: b])

        _ = executor.executeAnimation(id: 30)
        #expect(executor.activeAnimations[30] != nil)
        _ = executor.executeAnimation(id: 31)
        #expect(executor.activeAnimations[30] == nil)
        #expect(executor.activeAnimations[31] != nil)
    }
}
