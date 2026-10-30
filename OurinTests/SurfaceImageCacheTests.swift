import AppKit
import Foundation
import Testing
@testable import Ourin

@MainActor
struct SurfaceImageCacheTests {
    @Test func repeatedFramesReusePixelsAndSourceChangesInvalidateThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-SurfaceCache-\(UUID().uuidString)")
        let shell = root.appendingPathComponent("shell/master")
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = shell.appendingPathComponent("part.png")
        func write(_ color: NSColor, revision: TimeInterval) throws {
            let image = NSImage(size: NSSize(width: 64, height: 64))
            image.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: 64, height: 64).fill(); image.unlockFocus()
            let tiff = try #require(image.tiffRepresentation)
            let data = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try data.write(to: file)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: revision)], ofItemAtPath: file.path)
        }
        try write(.red, revision: 100)
        let manager = GhostManager(ghostURL: root)
        defer { _ = manager.shutdown() }
        manager.parsedSurfaceDefs = SerikoParser.parseSurfaces("surface0\n{\nelement0,base,part.png,0,0\n}\n")
        let coldStart = ProcessInfo.processInfo.systemUptime
        let first = try #require(manager.loadImage(surfaceId: 0, scope: 0))
        let cold = ProcessInfo.processInfo.systemUptime - coldStart
        let warmStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 { #expect(manager.loadImage(surfaceId: 0, scope: 0) === first) }
        print("Surface cache: cold=\(cold * 1000)ms, warm-average=\((ProcessInfo.processInfo.systemUptime - warmStart) * 50)ms")
        #expect(manager.loadImage(surfaceId: 0, scope: 0, applyTransparency: false) !== first)
        try write(.blue, revision: 200)
        let revised = try #require(manager.loadImage(surfaceId: 0, scope: 0))
        #expect(revised !== first)
        let revisedTIFF = try #require(revised.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: revisedTIFF))
        let color = try #require(bitmap.colorAt(x: 32, y: 32)?.usingColorSpace(.deviceRGB))
        #expect(color.blueComponent > 0.9 && color.redComponent < 0.1)
        manager.parsedSurfaceDefs = SerikoParser.parseSurfaces("surface0\n{\nelement0,base,part.png,8,0\n}\n")
        #expect(manager.loadImage(surfaceId: 0, scope: 0) !== revised)
    }
}
