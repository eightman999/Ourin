import AppKit
import Foundation
import Testing
@testable import Ourin

@MainActor
struct InitialElementSurfaceTests {
    @Test func firstImageLoadsElementDefinitionBeforeAnimationSetup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-InitialElement-\(UUID().uuidString)")
        let shell = root.appendingPathComponent("shell/master")
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 48, bitsPerPixel: 32))
        for x in 0..<12 { for y in 0..<16 { bitmap.setColor(.red, atX: x, y: y) } }
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: shell.appendingPathComponent("part.png"))
        try """
        charset,UTF-8
        surface0
        {
          element0,base,part.png,0,0
        }
        """.write(to: shell.appendingPathComponent("surfaces.txt"), atomically: true, encoding: .utf8)
        let manager = GhostManager(ghostURL: root)
        #expect(manager.parsedSurfaceDefs.isEmpty)
        let result = try #require(manager.loadImage(surfaceId: 0, scope: 0, applyTransparency: false))
        #expect(result.size == NSSize(width: 12, height: 16))
        #expect(manager.parsedSurfaceDefs.isEmpty) // off-main image reads do not mutate the shared animation cache
        #expect(manager.loadImage(surfaceId: 1, scope: 0, applyTransparency: false) == nil)
        #expect(!FileManager.default.fileExists(atPath: shell.appendingPathComponent("surface0.png").path))
    }
}
