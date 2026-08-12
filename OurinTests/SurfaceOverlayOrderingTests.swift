import Testing
import AppKit
@testable import Ourin

struct SurfaceOverlayOrderingTests {
    @Test
    func overlaysSortByZOrderThenInsertion() async throws {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        let overlays = [
            SurfaceOverlay(id: "c", image: img, zOrder: 100, insertionOrder: 2),
            SurfaceOverlay(id: "a", image: img, zOrder: 0, insertionOrder: 5),
            SurfaceOverlay(id: "b", image: img, zOrder: 100, insertionOrder: 1)
        ]

        let sorted = SurfaceOverlay.sortedForDisplay(overlays)
        #expect(sorted.map(\.id) == ["a", "b", "c"])
    }

    @MainActor
    @Test
    func animationSurfaceAssetRemovesPureGreenBackground() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetURL = repositoryRoot
            .appendingPathComponent("emily4/shell/master/surface5006.png")
        let manager = GhostManager(ghostURL: repositoryRoot)

        let image = try #require(manager.loadSurfaceFile(url: assetURL))
        var proposedRect = NSRect.zero
        let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        // NSBitmapImageRep の y=0 が、この PNG の緑背景側の角に対応する。
        let greenCorner = try #require(bitmap.colorAt(x: 0, y: 0))

        #expect(greenCorner.alphaComponent < 0.01)
    }
}
