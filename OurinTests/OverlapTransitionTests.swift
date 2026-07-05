import Testing
import Foundation
import CoreGraphics
@testable import Ourin

/// OnOffscreen / OnOverlap の Reference0 生成純関数の検証
/// （UKADOC: OnOffscreen は "ID\x01ID..."、OnOverlap は "ID-ID\x01ID-ID..."、該当なしは空文字列）
struct OverlapTransitionTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test
    func offscreenRef0ListsClippedScopesSortedWithByte1Separator() {
        let frames: [(scope: Int, frame: CGRect, screenVisible: CGRect)] = [
            // scope 0: 画面内に完全に収まっている → 対象外
            (0, CGRect(x: 100, y: 100, width: 200, height: 300), screen),
            // scope 2: 右端からはみ出し → 見切れ
            (2, CGRect(x: 1800, y: 100, width: 300, height: 300), screen),
            // scope 1: 下端からはみ出し → 見切れ
            (1, CGRect(x: 500, y: -50, width: 200, height: 300), screen),
        ]
        let ref0 = GhostManager.offscreenRef0(frames: frames)
        #expect(ref0 == "1\u{01}2")
    }

    @Test
    func offscreenRef0IsEmptyWhenAllInside() {
        let frames: [(scope: Int, frame: CGRect, screenVisible: CGRect)] = [
            (0, CGRect(x: 10, y: 10, width: 100, height: 100), screen),
            (1, CGRect(x: 200, y: 10, width: 100, height: 100), screen),
        ]
        #expect(GhostManager.offscreenRef0(frames: frames) == "")
    }

    @Test
    func overlapRef0ListsPairsInLowHighOrder() {
        let frames: [(scope: Int, frame: CGRect, screenVisible: CGRect)] = [
            // scope 1 と scope 0 が交差（登録順に依らず "0-1" と正規化されること）
            (1, CGRect(x: 150, y: 100, width: 200, height: 200), screen),
            (0, CGRect(x: 100, y: 100, width: 200, height: 200), screen),
            // scope 5 は独立
            (5, CGRect(x: 1000, y: 500, width: 100, height: 100), screen),
        ]
        #expect(GhostManager.overlapRef0(frames: frames) == "0-1")
    }

    @Test
    func overlapRef0ListsMultiplePairsSorted() {
        let frames: [(scope: Int, frame: CGRect, screenVisible: CGRect)] = [
            (0, CGRect(x: 0, y: 0, width: 300, height: 300), screen),
            (1, CGRect(x: 100, y: 100, width: 300, height: 300), screen), // 0 と交差
            (2, CGRect(x: 250, y: 250, width: 300, height: 300), screen), // 0, 1 と交差
        ]
        #expect(GhostManager.overlapRef0(frames: frames) == "0-1\u{01}0-2\u{01}1-2")
    }

    @Test
    func overlapRef0EdgeTouchingIsNotOverlap() {
        // 辺が接しているだけ（交差面積ゼロ）は重なりとしない
        let frames: [(scope: Int, frame: CGRect, screenVisible: CGRect)] = [
            (0, CGRect(x: 0, y: 0, width: 100, height: 100), screen),
            (1, CGRect(x: 100, y: 0, width: 100, height: 100), screen),
        ]
        #expect(GhostManager.overlapRef0(frames: frames) == "")
    }
}
