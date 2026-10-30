import AppKit
import CryptoKit
import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
@MainActor
struct SurfaceBlendPerformanceTests {
    @Test func everyBlendModeMatchesPreOptimizationPixelVectors() {
        let modes: [SurfaceBlendMode] = [.normal, .overlayFast, .interpolate, .asis, .replace, .reduce]
            + SerikoBlendMode.allCases.flatMap {
                [.blend($0, destinationAlphaAware: false), .blend($0, destinationAlphaAware: true)]
            }
        var vectors: [UInt8] = []
        for mode in modes {
            for offset in [CGPoint.zero, CGPoint(x: -2.4, y: 1.2), CGPoint(x: 3.1, y: -2.1), CGPoint(x: 20, y: 0)] {
                for opacity in [0.0, 0.37, 1.0] {
                    vectors.append(contentsOf: SurfaceBlendRenderer.composite(
                        destinationPixels: randomPixels(width: 11, height: 7, seed: 91),
                        destinationSize: CGSize(width: 11, height: 7),
                        sourcePixels: randomPixels(width: 9, height: 8, seed: 54),
                        sourceSize: CGSize(width: 9, height: 8), offset: offset, mode: mode, opacity: opacity
                    ))
                }
            }
        }
        // Captured from the original scalar compositor, before any fast paths:
        // 744 cases include hidden RGB at alpha=0, opaque/partial alpha, clipping,
        // destination-aware blends, replace/reduce, and fractional offsets/opacity.
        #expect(digest(vectors) == "df4906d1d8a7c264e450b24657492624fc2bdff5252f4dc901e4951d53a9da47")
    }

    @Test func hiroSizedNineLayerCompositionPreservesPixels() {
        let size = CGSize(width: 421, height: 399)
        let layers = representativeLayers()
        var destination = [UInt8](repeating: 0, count: 421 * 399 * 4)
        let start = ProcessInfo.processInfo.systemUptime
        for (index, source) in layers.enumerated() {
            destination = SurfaceBlendRenderer.composite(
                destinationPixels: destination, destinationSize: size,
                sourcePixels: source, sourceSize: size, mode: index == 8 ? .overlayFast : .normal
            )
        }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        // Reference digest from the original compositor; no machine-specific time limit.
        #expect(digest(destination) == "034464dc8597ceef136acb1b2abb03c965a483989a497535eb96ab754ca60c32")
        print("SURFACE_BLEND_421x399_NINE_LAYERS_MS \(milliseconds)")
    }

    @Test func unchangedLayersReuseBitmapAndRenderingInputsInvalidateIt() throws {
        let cache = SurfaceCompositionCache()
        let base = try makeImage(pixels: [200, 30, 40, 255], size: CGSize(width: 1, height: 1))
        let source = try makeImage(pixels: [30, 100, 200, 128], size: CGSize(width: 1, height: 1))
        let original = SurfaceOverlay(id: "face", image: source, blendMode: .overlayFast)
        let first = try #require(cache.composite(base: base, overlays: [original]))
        for _ in 0..<100 {
            #expect(cache.composite(base: base, overlays: [original]) === first)
        }
        var variants: [SurfaceOverlay] = []
        var changed = original; changed.offset = CGPoint(x: 1, y: 0); variants.append(changed)
        changed = original; changed.alpha = 0.5; variants.append(changed)
        changed = original; changed.zOrder = -1; variants.append(changed)
        changed = original; changed.insertionOrder = 1; variants.append(changed)
        changed = original; changed.blendMode = .replace; variants.append(changed)
        changed = original; changed.image = try makeImage(pixels: [0, 255, 0, 255], size: source.size); variants.append(changed)
        for variant in variants {
            let baseline = try #require(cache.composite(base: base, overlays: [original]))
            let rendered = try #require(cache.composite(base: base, overlays: [variant]))
            #expect(rendered !== baseline)
            #expect(cache.composite(base: base, overlays: [variant]) === rendered)
        }
        let previous = try #require(cache.composite(base: base, overlays: [original]))
        source.size = CGSize(width: 2, height: 1)
        #expect(cache.composite(base: base, overlays: [original]) !== previous)
        let resized = try #require(cache.composite(base: base, overlays: [original]))
        let otherBase = try makeImage(pixels: [200, 30, 40, 255], size: CGSize(width: 1, height: 1))
        #expect(cache.composite(base: otherBase, overlays: [original]) !== resized)
        #expect(cache.composite(base: nil, overlays: []) == nil)
    }

    private func digest(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }

    private func randomPixels(width: Int, height: Int, seed: Int) -> [UInt8] {
        var state = UInt64(seed)
        var result = [UInt8](repeating: 0, count: width * height * 4)
        for index in result.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            result[index] = UInt8(truncatingIfNeeded: state >> 32)
        }
        for index in stride(from: 3, to: result.count, by: 4) {
            switch (index / 4) % 4 {
            case 0: result[index] = 0
            case 1: result[index] = 255
            default: break
            }
        }
        return result
    }

    private func representativeLayers() -> [[UInt8]] {
        let width = 421, height = 399
        return (0..<9).map { layer in
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for y in 0..<height {
                for x in 0..<width {
                    if (layer == 0 && x > 100 && x < 320 && y > 20)
                        || (layer > 0 && x > 60 + layer * 19 && x < 100 + layer * 19
                            && y > 30 + layer * 21 && y < 70 + layer * 21) {
                        let index = (y * width + x) * 4
                        pixels[index] = UInt8((layer * 29 + x) % 256)
                        pixels[index + 1] = UInt8(y % 256)
                        pixels[index + 2] = UInt8((x + y) % 256)
                        pixels[index + 3] = x % 17 == 0 ? 128 : 255
                    }
                }
            }
            return pixels
        }
    }

    private func makeImage(pixels: [UInt8], size: CGSize) throws -> NSImage {
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let cg = try #require(CGImage(
            width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: Int(size.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return NSImage(cgImage: cg, size: size)
    }
}
