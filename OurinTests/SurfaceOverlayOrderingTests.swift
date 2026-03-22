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
}
