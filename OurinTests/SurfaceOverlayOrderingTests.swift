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

    @MainActor
    @Test
    func greenChromakeyKeepsAnimationAssetOrientation() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetURL = repositoryRoot
            .appendingPathComponent("emily4/shell/master/surface4100.png")
        let manager = GhostManager(ghostURL: repositoryRoot)
        defer { manager.shutdown() }

        let source = try #require(RetinaImageLoader.image(contentsOf: assetURL))
        let keyed = try #require(manager.loadSurfaceFile(url: assetURL))

        func redBounds(for image: NSImage) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
            var proposedRect = NSRect(origin: .zero, size: image.size)
            let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            var bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y),
                          let rgb = color.usingColorSpace(.deviceRGB),
                          rgb.alphaComponent > 0.5,
                          rgb.redComponent > rgb.greenComponent * 1.5,
                          rgb.redComponent > rgb.blueComponent * 1.5 else {
                        continue
                    }
                    if let current = bounds {
                        bounds = (
                            min(current.minX, x),
                            min(current.minY, y),
                            max(current.maxX, x),
                            max(current.maxY, y)
                        )
                    } else {
                        bounds = (x, y, x, y)
                    }
                }
            }
            return try #require(bounds)
        }

        #expect(try redBounds(for: keyed) == redBounds(for: source))
    }

    @MainActor
    @Test
    func animationOverlayUsesSurfaceAliasAndNormalSurfaceResolver() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = GhostManager(ghostURL: repositoryRoot.appendingPathComponent("emily4"))
        defer { manager.shutdown() }

        // Emily4 defines sakura surface alias 35 -> 55. There is no surface35.png,
        // so a direct filename lookup would silently drop this overlay.
        manager.characterViewModels[0] = CharacterViewModel()
        manager.loadAnimationsForCurrentSurface(surfaceID: 0, scope: 0)
        manager.handleAnimAddOverlay(id: 35)
        try await Task.sleep(nanoseconds: 50_000_000)

        let overlays = manager.characterViewModels[0]?.overlays ?? []
        let overlay = try #require(overlays.last)
        #expect(overlay.surfaceID == 55)
        #expect(overlay.image.size.width > 0 && overlay.image.size.height > 0)
    }
}
