import Testing
@testable import Ourin

struct SakuraScriptScalarTests {
    @Test func scalarLiteralUsesDecimalWithoutHexPrefix() {
        #expect(GhostManager.parseScalarLiteral("8942") == 8942)
        #expect(GhostManager.parseScalarLiteral("0x22EE") == 0x22EE)
    }

    @Test func scalarLiteralRejectsInvalidInput() {
        #expect(GhostManager.parseScalarLiteral("0x") == nil)
        #expect(GhostManager.parseScalarLiteral("not-a-number") == nil)
    }
}
