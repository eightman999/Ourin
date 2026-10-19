import AppKit
import Foundation
import SwiftUI
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

        let composited = try #require(SurfaceBlendRenderer.composite(base: masked, overlays: []))
        var compositedRect = NSRect(origin: .zero, size: composited.size)
        let compositedCGImage = try #require(composited.cgImage(forProposedRect: &compositedRect, context: nil, hints: nil))
        let compositedBitmap = NSBitmapImageRep(cgImage: compositedCGImage)
        let directTop = try #require(bitmap.colorAt(x: 126, y: 25))
        let directBottom = try #require(bitmap.colorAt(x: 126, y: 360))
        let compositedTop = try #require(compositedBitmap.colorAt(x: 126, y: 25))
        let compositedBottom = try #require(compositedBitmap.colorAt(x: 126, y: 360))
        #expect(directTop.alphaComponent < 0.1)
        #expect(directBottom.alphaComponent > 0.5)
        #expect(compositedTop.alphaComponent < 0.1)
        #expect(compositedBottom.alphaComponent > 0.5)

        let overlayComposite = try #require(SurfaceBlendRenderer.composite(
            base: nil,
            overlays: [SurfaceOverlay(id: "orientation-overlay", image: masked)]
        ))
        var overlayRect = NSRect(origin: .zero, size: overlayComposite.size)
        let overlayCGImage = try #require(overlayComposite.cgImage(forProposedRect: &overlayRect, context: nil, hints: nil))
        let overlayBitmap = NSBitmapImageRep(cgImage: overlayCGImage)
        let overlayTop = try #require(overlayBitmap.colorAt(x: 126, y: 25))
        let overlayBottom = try #require(overlayBitmap.colorAt(x: 126, y: 360))
        #expect(overlayTop.alphaComponent < 0.1)
        #expect(overlayBottom.alphaComponent > 0.5)
    }

    @MainActor
    @Test
    func characterViewKeepsPnaSurfaceOrientation() throws {
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
        let image = try #require(manager.applyPNAMask(baseURL: baseURL, maskURL: maskURL))
        var sourceRect = NSRect(origin: .zero, size: image.size)
        let sourceCGImage = try #require(image.cgImage(forProposedRect: &sourceRect, context: nil, hints: nil))
        let sourceBitmap = NSBitmapImageRep(cgImage: sourceCGImage)
        let viewModel = CharacterViewModel()
        viewModel.image = image
        let host = NSHostingView(rootView: CharacterView(viewModel: viewModel))
        host.frame = NSRect(origin: .zero, size: image.size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let sourceX = 126
        let renderedX = Int((Double(sourceX) / image.size.width) * Double(bitmap.pixelsWide))
        let sampleYs = [25, 50, 334, 360]
        for sourceY in sampleYs {
            let sourceAlpha = sourceBitmap.colorAt(x: sourceX, y: sourceY)?.alphaComponent ?? 0
            let renderedY = Int((Double(sourceY) / image.size.height) * Double(bitmap.pixelsHigh))
            let renderedAlpha = bitmap.colorAt(x: renderedX, y: renderedY)?.alphaComponent ?? 0
            #expect(abs(renderedAlpha - sourceAlpha) < 0.2)
        }
    }
}
