import AppKit
import Foundation
import Testing
@testable import Ourin

struct SurfaceBlendTests {
    @Test func renderedBitmapKeepsTopAndBottomOrientation() throws {
        let source = NSImage(size: NSSize(width: 100, height: 100))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 50).fill()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 50, width: 100, height: 50).fill()
        source.unlockFocus()

        let rendered = try #require(SurfaceBlendRenderer.composite(
            base: nil,
            overlays: [SurfaceOverlay(id: "orientation", image: source)]
        ))
        let tiff = try #require(rendered.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let top = try #require(bitmap.colorAt(x: 50, y: 25))
        let bottom = try #require(bitmap.colorAt(x: 50, y: 75))
        #expect(top.redComponent > top.blueComponent)
        #expect(bottom.blueComponent > bottom.redComponent)
    }

    @Test func overlayFastUsesDestinationAlpha() {
        let destination = [UInt8](arrayLiteral: 20, 30, 40, 255)
        let source = [UInt8](arrayLiteral: 200, 100, 50, 255)
        let result = SurfaceBlendRenderer.composite(
            destinationPixels: destination,
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: source,
            sourceSize: CGSize(width: 1, height: 1),
            mode: .overlayFast
        )
        #expect(result == source)
    }

    @Test func interpolateUsesDestinationTransparency() {
        let transparentDestination = [UInt8](arrayLiteral: 20, 30, 40, 0)
        let source = [UInt8](arrayLiteral: 200, 100, 50, 255)
        let transparentResult = SurfaceBlendRenderer.composite(
            destinationPixels: transparentDestination,
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: source,
            sourceSize: CGSize(width: 1, height: 1),
            mode: .interpolate
        )
        #expect(transparentResult == source)

        let opaqueDestination = [UInt8](arrayLiteral: 20, 30, 40, 255)
        let opaqueResult = SurfaceBlendRenderer.composite(
            destinationPixels: opaqueDestination,
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: source,
            sourceSize: CGSize(width: 1, height: 1),
            mode: .interpolate
        )
        #expect(opaqueResult == opaqueDestination)
    }

    @Test func overlayFastIgnoresFullyTransparentDestination() {
        let destination = [UInt8](arrayLiteral: 20, 30, 40, 0)
        let source = [UInt8](arrayLiteral: 200, 100, 50, 255)
        let result = SurfaceBlendRenderer.composite(
            destinationPixels: destination,
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: source,
            sourceSize: CGSize(width: 1, height: 1),
            mode: .overlayFast
        )
        #expect(result == [0, 0, 0, 0])
    }

    @Test func parserAcceptsOfficialOverlayFastSpelling() {
        #expect(SerikoMethod.parse("overlay-fast") == .overlayFast)
        #expect(SerikoMethod.parse("overlayfast") == .overlayFast)
    }

    @Test func parserAcceptsOfficialBlendMethodsAndLegacyAliases() {
        #expect(SerikoMethod.parse("blend-multiply") == .blend(.multiply, fast: false))
        #expect(SerikoMethod.parse("blend-screen-fast") == .blend(.screen, fast: true))
        #expect(SerikoMethod.parse("overlaymultiply") == .blend(.multiply, fast: true))
        #expect(SerikoMethod.parse("blend-color-dodge-glow") == .blend(.colorDodgeGlow, fast: false))
    }

    @Test func blendMultiplyUsesSourceAndDestinationColor() {
        let result = SurfaceBlendRenderer.composite(
            destinationPixels: [128, 128, 128, 255],
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: [128, 64, 255, 255],
            sourceSize: CGSize(width: 1, height: 1),
            mode: .blend(.multiply, destinationAlphaAware: false)
        )

        #expect(result == [64, 32, 128, 255])
    }

    @Test func fastBlendDoesNotAddToTransparentDestination() {
        let result = SurfaceBlendRenderer.composite(
            destinationPixels: [128, 128, 128, 0],
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: [255, 0, 0, 255],
            sourceSize: CGSize(width: 1, height: 1),
            mode: .blend(.screen, destinationAlphaAware: true)
        )

        #expect(result == [0, 0, 0, 0])
    }

    @Test func replaceClearsDestinationWithTransparentSourcePixels() {
        let result = SurfaceBlendRenderer.composite(
            destinationPixels: [20, 30, 40, 255],
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: [200, 100, 50, 0],
            sourceSize: CGSize(width: 1, height: 1),
            mode: .replace
        )

        #expect(result == [200, 100, 50, 0])
    }

    @Test func reduceMultipliesDestinationAlphaAndKeepsDestinationColor() {
        let result = SurfaceBlendRenderer.composite(
            destinationPixels: [20, 30, 40, 128],
            destinationSize: CGSize(width: 1, height: 1),
            sourcePixels: [200, 100, 50, 128],
            sourceSize: CGSize(width: 1, height: 1),
            mode: .reduce
        )

        #expect(result == [20, 30, 40, 64])
    }
}
