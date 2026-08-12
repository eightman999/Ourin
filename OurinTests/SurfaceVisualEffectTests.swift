import Testing
import AppKit
import CoreImage
@testable import Ourin

struct SurfaceVisualEffectTests {
    @Test
    func rendererRecognizesOnlyExplicitBuiltins() {
        #expect(SurfaceVisualEffectRenderer.isSupported(plugin: "gaussian-blur"))
        #expect(SurfaceVisualEffectRenderer.isSupported(plugin: "CIColorControls"))
        #expect(!SurfaceVisualEffectRenderer.isSupported(plugin: "ghost-specific-transition"))
    }

    @Test
    func rendererAppliesFilterToImage() {
        let image = makeSolidImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
        let result = SurfaceVisualEffectRenderer.applying(
            image: image,
            plugin: "grayscale",
            params: []
        )

        #expect(result != nil)
        #expect(result?.size == image.size)
    }

    @Test
    func rendererKeepsUnknownPluginImageUnchanged() {
        let image = makeSolidImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        let result = SurfaceVisualEffectRenderer.applying(
            image: image,
            plugin: "external-effect-plugin",
            params: ["opaque-plugin-parameter"]
        )

        #expect(result != nil)
        #expect(result?.size == image.size)
    }
}

private func makeSolidImage(color: CIColor) -> NSImage {
    let extent = CGRect(x: 0, y: 0, width: 4, height: 4)
    let ciImage = CIImage(color: color).cropped(to: extent)
    let cgImage = CIContext().createCGImage(ciImage, from: extent)!
    return NSImage(cgImage: cgImage, size: extent.size)
}
