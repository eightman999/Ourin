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

    @Test
    func scriptExpansionKeepsEscapedPercentFollowedByVariableName() {
        let expander = EnvironmentExpander(propertyManager: PropertyManager())

        // \% の直後が変数名でも展開しない（\% 自体は後段のパーサーが % に戻す）
        #expect(expander.expand(script: "\\%month") == "\\%month")
        #expect(expander.expand(script: "100\\% complete") == "100\\% complete")
        #expect(expander.expand(script: "\\%month と \\%day") == "\\%month と \\%day")

        // % そのものの展開は従来どおり
        let expanded = expander.expand(script: "%month")
        #expect(expanded != "%month")
        #expect(Int(expanded) != nil)
        #expect(expander.expand(script: "%month") == expander.expand(text: "%month"))
    }

    @Test
    func scriptExpansionTreatsEscapedBackslashAsOnePair() {
        let expander = EnvironmentExpander(propertyManager: PropertyManager())

        // \\ の直後の %month は展開される（\\ + \% の並びは \\ を先に読む）
        let expanded = expander.expand(script: "\\\\%month")
        #expect(expanded.hasPrefix("\\\\"))
        #expect(!expanded.contains("%month"))
        #expect(expander.expand(script: "\\\\\\%month") == "\\\\\\%month")
        // 後ろに文字が無い末尾の \ はそのまま
        #expect(expander.expand(script: "abc\\") == "abc\\")
    }

    @Test
    func percentStarExpandsToCommunicationMarkerCommand() {
        let engine = SakuraScriptEngine()

        #expect(engine.expandEnvironment(in: "本文%*") == "本文\\![*]")
        #expect(
            engine.parse(script: engine.expandEnvironment(in: "本文%*"), expandEnvironment: false)
                == [.text("本文"), .command(name: "!", args: ["*"])]
        )
    }
}
