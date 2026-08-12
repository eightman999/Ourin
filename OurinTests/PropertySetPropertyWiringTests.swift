import AppKit
import Testing
@testable import Ourin

/// `\![set,property,...]` が実際に `PropertyManager.shared` へ届き、SSTP/ResourceBridge 等の
/// 他の読み取り経路から見えることを検証する回帰テスト。
///
/// 背景: `SakuraScriptEngine()` のデフォルト初期化子は独立した `PropertyManager()` インスタンスを
/// 持つため、`GhostManager.init` で `sakuraEngine.propertyManager = PropertyManager.shared` に
/// 差し替えていないと、ゴーストスクリプトが SET した値は `PropertyManager.shared` を読む
/// SSTPDispatcher/ResourceBridge から一切見えなくなる（サイレントな配線切れ）。
/// これは `currentghost.seriko.cursor.*`/`tooltip.*` に限らず、SET可能な全プロパティに影響する。
@MainActor
struct PropertySetPropertyWiringTests {
    private func makeGhostManager() -> GhostManager {
        let url = URL(fileURLWithPath: "/tmp/ghost-test-property-wiring")
        return GhostManager(ghostURL: url)
    }

    @Test
    func setPropertyViaSakuraScriptIsVisibleThroughPropertyManagerShared() throws {
        let gm = makeGhostManager()
        // GhostManager.sakuraEngine.propertyManager must be the same instance PropertyManager.shared is.
        #expect(gm.sakuraEngine.propertyManager === PropertyManager.shared)

        let key = "currentghost.seriko.cursor.scope(0).mouseuplist(RegressionTestRegion).path"
        gm.sakuraEngine.run(script: "\\![set,property,\(key),regression_cursor.cur]")

        #expect(PropertyManager.shared.get(key) == "regression_cursor.cur")
    }

    @Test
    func setPropertyViaSakuraScriptIsVisibleToToolTipTextLookup() throws {
        let gm = makeGhostManager()
        let key = "currentghost.seriko.tooltip.scope(0).textlist(RegressionTestRegion).text"
        gm.sakuraEngine.run(script: "\\![set,property,\(key),テスト用ツールチップ]")

        #expect(PropertyManager.shared.get(key) == "テスト用ツールチップ")
    }

    @Test
    func liveScalingPropertiesFollowGhostAndBalloonViewModels() async throws {
        let gm = makeGhostManager()
        _ = gm.ensureCharacterWindow(for: 0)
        var config = GhostConfiguration(name: "PropertyScalingTest")
        config.balloonSyncScale = true
        gm.ghostConfig = config
        _ = gm.getBalloonVM(for: 0)

        gm.executeSetScalingCommand(args: ["set", "scaling", "50", "75"])
        for _ in 0..<20 {
            if gm.characterViewModels[0]?.scaleX == 0.5,
               gm.characterViewModels[0]?.scaleY == 0.75 {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(PropertyManager.shared.get("currentghost.scope(0).scaling") == "50.0,75.0")
        #expect(PropertyManager.shared.get("currentghost.balloon.scope(0).scaling") == "50.0,75.0")
    }

    @Test
    func liveScopeSurfaceAndAnimationPropertiesUseRuntimeState() throws {
        let gm = makeGhostManager()
        _ = gm.ensureCharacterWindow(for: 0)
        gm.characterViewModels[0]?.currentSurfaceID = 17

        #expect(PropertyManager.shared.get("currentghost.scope(0).surface.num") == "17")

        let pattern = SerikoPattern(
            index: 0,
            method: .overlay,
            surfaceID: 0,
            duration: 10_000,
            x: 0,
            y: 0,
            rawArguments: []
        )
        gm.serikoExecutor.register(animations: [
            41: SerikoParser.AnimationDefinition(id: 41, interval: .never, options: [], patterns: [pattern]),
            42: SerikoParser.AnimationDefinition(id: 42, interval: .never, options: [], patterns: [pattern])
        ])

        #expect(PropertyManager.shared.set("currentghost.scope(0).surface.num", value: "18"))
        #expect(PropertyManager.shared.set("currentghost.scope(0).animation.num", value: "41, 42"))
        #expect(PropertyManager.shared.get("currentghost.scope(0).animation.num") == "41,42")
    }
}
