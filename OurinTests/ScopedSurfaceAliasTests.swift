import AppKit
import Foundation
import Testing
@testable import Ourin

@MainActor
struct ScopedSurfaceAliasTests {
    private let definitions = """
    sakura.surface.alias
    {
    通常,[11]
    0,[11]
    11,[99]
    mixed,[11,11,12]
    }
    kero.surface.alias
    {
    通常,[22]
    0,[22]
    }
    char2.surface.alias {
    通常,[33]
    }
    """

    @Test func parserPreservesScopeAndWeightedCandidates() {
        let aliases = SerikoParser.parseScopedSurfaceAliases(definitions)
        #expect(aliases[0]?["通常"] == [11])
        #expect(aliases[1]?["通常"] == [22])
        #expect(aliases[2]?["通常"] == [33])
        #expect(aliases[0]?["mixed"] == [11,11,12])
        #expect(aliases[3] == nil)
    }

    @Test func queuedNamedSurfacesUsePlaybackScopeAndDoNotResolveTargetsTwice() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = GhostManager(ghostURL: root)
        defer { _ = manager.shutdown() }
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .scope(1))
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .surfaceNamed("通常"))
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .scope(0))
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .surfaceNamed("通常"))
        manager.processNextUnit()
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while manager.characterViewModels[0]?.currentSurfaceID != 11 || manager.characterViewModels[1]?.currentSurfaceID != 22 {
            try #require(ProcessInfo.processInfo.systemUptime < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(manager.resolveNumericSurfaceAlias(0, scope: 0) == 11)
        #expect(manager.resolveNumericSurfaceAlias(0, scope: 1) == 22)
        #expect(manager.resolveNamedSurfaceAlias("通常", scope: 3) == nil)
        for _ in 0..<20 { #expect([11,12].contains(manager.resolveNamedSurfaceAlias("mixed", scope: 0) ?? -1)) }
    }

    @Test func changingShellInvalidatesAliasesBeforeFirstImage() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("shell/other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "sakura.surface.alias\n{\n通常,[44]\n}\n".write(to: other.appendingPathComponent("surfaces.txt"), atomically: true, encoding: .utf8)
        let manager = GhostManager(ghostURL: root)
        defer { _ = manager.shutdown() }
        #expect(manager.resolveNamedSurfaceAlias("通常", scope: 0) == 11)
        manager.activeShellName = "other"
        #expect(manager.resolveNamedSurfaceAlias("通常", scope: 0) == 44)
        #expect(manager.resolveNamedSurfaceAlias("通常", scope: 1) == nil)
        #expect(manager.resolveNumericSurfaceAlias(0, scope: 1) == 0)
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-ScopedAlias-\(UUID().uuidString)")
        let shell = root.appendingPathComponent("shell/master")
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        try definitions.write(to: shell.appendingPathComponent("surfaces.txt"), atomically: true, encoding: .utf8)
        let image = NSImage(size: NSSize(width: 12, height: 16))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0,y: 0,width: 12,height: 16).fill(); image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        for id in [11,22,99] { try data.write(to: shell.appendingPathComponent("surface\(id).png")) }
        return root
    }
}
