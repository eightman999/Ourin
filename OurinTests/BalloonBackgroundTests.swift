import AppKit
import Foundation
import Testing
@testable import Ourin

struct BalloonBackgroundTests {
    @Test
    func imageTypeFollowsScope() {
        #expect(BalloonView.imageType(forScope: 0) == "s")
        #expect(BalloonView.imageType(forScope: 1) == "k")
        #expect(BalloonView.imageType(forScope: 2) == "d")
        #expect(BalloonView.imageType(forScope: 5) == "d")
    }

    @Test
    func backgroundUsesScopeImageAndFallsBackToSakuraSide() throws {
        let root = try TestGhostFixture.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // さくら用は 10x10、kero 用は 20x20 と大きさを変えて、どちらが選ばれたかを判別する。
        try TestGhostFixture.writeSolidPNG(to: root.appendingPathComponent("balloons0.png"), width: 10, height: 10)
        try TestGhostFixture.writeSolidPNG(to: root.appendingPathComponent("balloonk0.png"), width: 20, height: 20)
        let loader = BalloonImageLoader(balloonPath: root.path)

        func width(scope: Int) -> CGFloat? {
            BalloonView.loadBackgroundImage(loader: loader, index: 0, scope: scope)?.size.width
        }
        #expect(width(scope: 0) == 10)
        #expect(width(scope: 1) == 20)
        // balloond* が無い追加キャラは balloons* を使う。
        #expect(width(scope: 2) == 10)

        // balloonk* が無いゴーストでは、kero も balloons* を使う。
        try FileManager.default.removeItem(at: root.appendingPathComponent("balloonk0.png"))
        let plain = BalloonImageLoader(balloonPath: root.path)
        #expect(BalloonView.loadBackgroundImage(loader: plain, index: 0, scope: 1)?.size.width == 10)
    }
}
