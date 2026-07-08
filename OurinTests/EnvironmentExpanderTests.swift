import Testing
@testable import Ourin

@Suite(.serialized)
struct EnvironmentExpanderTests {
    @Test
    func lastGhostNameExpandsFromStaticContext() {
        let mgr = PropertyManager()
        let expander = EnvironmentExpander(propertyManager: mgr)
        EnvironmentExpander.lastInstalledGhostName = "TestGhost"
        EnvironmentExpander.lastInstalledObjectName = "TestObject"
        defer {
            EnvironmentExpander.lastInstalledGhostName = nil
            EnvironmentExpander.lastInstalledObjectName = nil
        }
        #expect(expander.expand(text: "installed: %lastghostname") == "installed: TestGhost")
        #expect(expander.expand(text: "object: %lastobjectname") == "object: TestObject")
    }

    @Test
    func lastGhostNameEmptyWhenUnset() {
        let mgr = PropertyManager()
        let expander = EnvironmentExpander(propertyManager: mgr)
        EnvironmentExpander.lastInstalledGhostName = nil
        #expect(expander.expand(text: "%lastghostname") == "")
    }

    @Test
    func defaultLexiconIsInjectedForSupportedWordClasses() {
        let mgr = PropertyManager()
        let expander = EnvironmentExpander(propertyManager: mgr)
        let keys = ["ms", "mz", "ml", "mc", "mh", "mt", "me", "mp", "m?", "dms"]

        for key in keys {
            #expect(expander.lexicon[key]?.isEmpty == false)
            let expanded = expander.expand(text: "%\(key)")
            #expect(!expanded.isEmpty)
            #expect(expanded != "%\(key)")
        }
    }

    @Test
    func sakuraScriptEngineExpandsDefaultWordClassesInText() {
        let engine = SakuraScriptEngine()

        let tokens = engine.parse(script: "%msが%mpの%mhで%meを食べた。")

        guard case .text(let text) = tokens.first else {
            Issue.record("Expected the first token to be text")
            return
        }
        #expect(!text.contains("%ms"))
        #expect(!text.contains("%mp"))
        #expect(!text.contains("%mh"))
        #expect(!text.contains("%me"))
    }
}
