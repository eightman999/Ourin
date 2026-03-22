import Testing
@testable import Ourin

struct SakuraScriptAnimationWaitTests {
    @Test
    func parseDoubleUnderscoreWAnimation() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\__w[animation,400]")
        #expect(tokens.count == 1)
        if case .command(let name, let args) = tokens[0] {
            #expect(name == "__w")
            #expect(args == ["animation", "400"])
        } else {
            Issue.record("Expected command token for __w[animation,ID]")
        }
    }
}

