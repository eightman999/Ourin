import AppKit
import Foundation
import Testing
@testable import Ourin

struct CollisionHitTests {
    @Test
    func windowPointIsConvertedToTopLeftSurfacePoint() {
        // AppKit の左下原点 (10, 90) は、高さ 100 のウィンドウでは左上原点の (10, 10)。
        let point = InputMonitor.surfacePoint(fromWindowPoint: CGPoint(x: 10, y: 90), windowHeight: 100)
        #expect(point == CGPoint(x: 10, y: 10))
    }

    @MainActor
    @Test
    func collisionRegionIsResolvedInTopLeftSurfaceCoordinates() throws {
        let root = try TestGhostFixture.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let shell = try TestGhostFixture.makeShell(in: root)
        try """
        surface0
        {
        collision0,0,0,100,30,Head
        collision1,0,30,100,100,Body
        }
        """.write(to: shell.appendingPathComponent("surfaces.txt"), atomically: true, encoding: .utf8)
        try TestGhostFixture.writeSolidPNG(to: shell.appendingPathComponent("surface0.png"), width: 100, height: 100)

        let manager = GhostManager(ghostURL: root)
        defer { manager.shutdown() }
        manager.characterViewModels[0] = CharacterViewModel()
        manager.loadAnimationsForCurrentSurface(surfaceID: 0, scope: 0)

        // 画面上の見た目で上端付近をクリックした場合は、ウィンドウ座標では y が大きい側になる。
        let top = InputMonitor.surfacePoint(fromWindowPoint: CGPoint(x: 50, y: 95), windowHeight: 100)
        let bottom = InputMonitor.surfacePoint(fromWindowPoint: CGPoint(x: 50, y: 5), windowHeight: 100)
        #expect(manager.collisionRegionName(at: top, scope: 0) == "Head")
        #expect(manager.collisionRegionName(at: bottom, scope: 0) == "Body")
    }
}
