import AppKit
import Testing
@testable import Ourin

struct GhostWindowClampTests {
    // 1728x1117 の内蔵ディスプレイ（下 Dock 63pt、メニューバー 33pt）
    private let builtIn = NSRect(x: 0, y: 63, width: 1728, height: 1021)

    @Test
    func onScreenFrameIsUnchanged() {
        let frame = NSRect(x: 1400, y: 100, width: 300, height: 400)
        #expect(GhostManager.clampToVisibleScreens(frame, visibleFrames: [builtIn]) == frame)
    }

    @Test
    func farBelowScreenIsPulledUpToVisibleBottom() {
        // 実際に保存されていた sakura.defaulttop=-4194 の再現
        let frame = NSRect(x: 1481, y: -4194, width: 300, height: 400)
        let clamped = GhostManager.clampToVisibleScreens(frame, visibleFrames: [builtIn])
        #expect(clamped == NSRect(x: 1428, y: 63, width: 300, height: 400))
    }

    @Test
    func partiallyOffRightAndBottomIsPulledInside() {
        let frame = NSRect(x: 1600, y: -237, width: 300, height: 400)
        let clamped = GhostManager.clampToVisibleScreens(frame, visibleFrames: [builtIn])
        #expect(clamped.minX == 1428)
        #expect(clamped.minY == 63)
        #expect(clamped.size == frame.size)
    }

    @Test
    func choosesScreenWithLargestOverlap() {
        let external = NSRect(x: 1728, y: 0, width: 2560, height: 1415)
        let frame = NSRect(x: 2000, y: 1300, width: 300, height: 400)
        let clamped = GhostManager.clampToVisibleScreens(frame, visibleFrames: [builtIn, external])
        #expect(clamped == NSRect(x: 2000, y: 1015, width: 300, height: 400))
    }

    @Test
    func noScreensKeepsFrame() {
        let frame = NSRect(x: -5000, y: -5000, width: 300, height: 400)
        #expect(GhostManager.clampToVisibleScreens(frame, visibleFrames: []) == frame)
    }
}
