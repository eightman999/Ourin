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
}
