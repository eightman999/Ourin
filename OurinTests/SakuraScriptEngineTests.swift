import Testing
@testable import Ourin

struct SakuraScriptEngineTests {
    @Test
    func parseBasics() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\0Hello\\n\\s[1]\\i[2,wait]\\e")
        #expect(tokens == [
            .scope(0),
            .text("Hello"),
            .newline,
            .surface(1),
            .animation(2, wait: true),
            .end
        ])
    }

    @Test
    func propertyExpand() async throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "Name %property[baseware.name]")
        #expect(tokens == [.text("Name Ourin")])
    }
}
