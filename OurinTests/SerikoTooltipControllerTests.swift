import AppKit
import Testing
@testable import Ourin

/// `SerikoTooltipController` の当たり判定連動ツールチップ表示ロジックを検証する。
@MainActor
struct SerikoTooltipControllerTests {
    @Test
    func showsWindowWhenTooltipTextIsDefined() {
        let region = "TooltipTestRegion_\(UUID().uuidString)"
        let key = "currentghost.seriko.tooltip.scope(0).textlist(\(region)).text"
        _ = PropertyManager.shared.set(key, value: "テスト用ツールチップ本文")

        SerikoTooltipController.shared.show(scope: 0, region: region, at: NSPoint(x: 200, y: 200))
        #expect(SerikoTooltipController.shared.isVisible)

        SerikoTooltipController.shared.hide()
        #expect(!SerikoTooltipController.shared.isVisible)
    }

    @Test
    func staysHiddenWhenTooltipTextUndefined() {
        let region = "UndefinedTooltipRegion_\(UUID().uuidString)"
        SerikoTooltipController.shared.hide()
        SerikoTooltipController.shared.show(scope: 0, region: region, at: NSPoint(x: 200, y: 200))
        #expect(!SerikoTooltipController.shared.isVisible)
    }

    @Test
    func emptyRegionHidesTooltip() {
        let region = "TooltipTestRegionForEmptyCheck_\(UUID().uuidString)"
        let key = "currentghost.seriko.tooltip.scope(0).textlist(\(region)).text"
        _ = PropertyManager.shared.set(key, value: "表示されるはずのテキスト")
        SerikoTooltipController.shared.show(scope: 0, region: region, at: NSPoint(x: 200, y: 200))
        #expect(SerikoTooltipController.shared.isVisible)

        SerikoTooltipController.shared.show(scope: 0, region: "", at: NSPoint(x: 200, y: 200))
        #expect(!SerikoTooltipController.shared.isVisible)
    }
}
