import AppKit
import Foundation
import Testing
@testable import Ourin

struct SurfaceImageOrientationTests {
    @Test
    func pnaMaskedShellKeepsTopOfSurfaceAtTop() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellRoot = repositoryRoot.appendingPathComponent("emily4/shell/master")
        let baseURL = shellRoot.appendingPathComponent("surface0000.png")
        let maskURL = shellRoot.appendingPathComponent("surface0000.pna")
        guard FileManager.default.fileExists(atPath: baseURL.path),
              FileManager.default.fileExists(atPath: maskURL.path) else {
            print("[skip] Emily4 surface0000 PNA fixture not found")
            return
        }

        let manager = GhostManager(ghostURL: repositoryRoot)
        defer { manager.shutdown() }
        let masked = try #require(manager.applyPNAMask(baseURL: baseURL, maskURL: maskURL))
        var proposedRect = NSRect(origin: .zero, size: masked.size)
        let cgImage = try #require(masked.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)

        // surface0000's upper hair/face area is opaque around this point. The
        // old lockFocus conversion placed that area at the bottom instead.
        let upperSurface = try #require(bitmap.colorAt(x: 126, y: 50))
        #expect(upperSurface.alphaComponent > 0.5)
    }
}
