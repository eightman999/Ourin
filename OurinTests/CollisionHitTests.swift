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

    /// 複数ゴースト同時起動時に、当たり判定と右クリックメニューの処理先が窓の持ち主になること。
    @MainActor
    @Test
    func owningGhostManagerIsResolvedFromInputWindow() throws {
        let rootA = try TestGhostFixture.makeRoot()
        let rootB = try TestGhostFixture.makeRoot()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let managerA = GhostManager(ghostURL: rootA)
        let managerB = GhostManager(ghostURL: rootB)
        defer {
            managerA.shutdown()
            managerB.shutdown()
        }

        func makeWindow() -> NSWindow {
            NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                     styleMask: .borderless, backing: .buffered, defer: false)
        }
        let windowA = makeWindow()
        let windowB = makeWindow()
        let strangerWindow = makeWindow()
        managerA.characterWindows[0] = windowA
        managerB.characterWindows[0] = windowB

        let managers = [managerA, managerB]
        #expect(InputMonitor.owningGhostManager(of: windowA, in: managers) === managerA)
        #expect(InputMonitor.owningGhostManager(of: windowB, in: managers) === managerB)
        #expect(InputMonitor.owningGhostManager(of: strangerWindow, in: managers) == nil)
        #expect(InputMonitor.owningGhostManager(of: nil, in: managers) == nil)
    }

    /// 標準ゴーストの各判定領域が、サーフェス画像の不透明部分にある程度乗っていること。
    /// 絵を差し替えたときに、判定だけが空白へずれたままになるのを検出する。
    @Test
    func defaultGhostCollisionsOverlapOpaqueArtwork() throws {
        let shell = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DefaultGhost/sakura/shell/master")
        let text = try String(contentsOf: shell.appendingPathComponent("surfaces.txt"), encoding: .utf8)
        let blockRegex = try NSRegularExpression(pattern: #"surface(\d+)\n\{\n(.*?)\n\}"#, options: [.dotMatchesLineSeparators])
        let collisionRegex = try NSRegularExpression(pattern: #"collision\d+,(\d+),(\d+),(\d+),(\d+),(\w+)"#)
        let whole = NSRange(text.startIndex..., in: text)
        var checked = 0
        for block in blockRegex.matches(in: text, range: whole) {
            let id = String(text[Range(block.range(at: 1), in: text)!])
            let body = String(text[Range(block.range(at: 2), in: text)!])
            guard let image = NSImage(contentsOf: shell.appendingPathComponent("surface\(id).png")),
                  let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            for hit in collisionRegex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                func value(_ n: Int) -> Int { Int(body[Range(hit.range(at: n), in: body)!])! }
                let (x1, y1, x2, y2) = (value(1), value(2), value(3), value(4))
                let name = String(body[Range(hit.range(at: 5), in: body)!])
                var opaque = 0, total = 0
                for y in y1..<min(y2, bitmap.pixelsHigh) {
                    for x in x1..<min(x2, bitmap.pixelsWide) {
                        total += 1
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 }
                    }
                }
                #expect(total > 0 && Double(opaque) / Double(total) >= 0.4,
                        "surface\(id) \(name) covers too little artwork: \(opaque)/\(total)")
                checked += 1
            }
        }
        #expect(checked > 100)
    }
}
