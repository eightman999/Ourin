import Foundation
import Testing
@testable import Ourin

struct SerikoParserTests {
    private func makeTemporaryShellDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinSerikoParserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, named fileName: String, to directory: URL) throws {
        try text.write(
            to: directory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    @Test
    func parseSurfaceScopeAndAnimationEntries() async throws {
        let text = """
        surface2
        {
          animation51.interval,runonce
          animation51.option,exclusive
          animation51.pattern0,overlay,4002,250,50,120
          animation51.pattern1,overlay,-1,180,50,120
        }
        """

        let parsed = SerikoParser.parseSurfaces(text)
        #expect(parsed[2] != nil)
        let anim = parsed[2]?.animations[51]
        #expect(anim != nil)
        #expect(anim?.interval == .runonce)
        #expect(anim?.options == ["exclusive"])
        #expect(anim?.patterns.count == 2)
        #expect(anim?.patterns.first?.method == .overlay)
        #expect(anim?.patterns.first?.surfaceID == 4002)
    }

    @Test
    func parsePatternLegacyFormat() async throws {
        let text = """
        surface0
        {
          animation0.interval,always
          animation0.pattern0,10,100,0,0
        }
        """
        let parsed = SerikoParser.parseSurfaces(text)
        let pattern = parsed[0]?.animations[0]?.patterns.first
        #expect(pattern != nil)
        #expect(pattern?.method == .overlay)
        #expect(pattern?.surfaceID == 10)
        #expect(pattern?.duration == 100)
        #expect(pattern?.x == 0)
        #expect(pattern?.y == 0)
    }

    @Test
    func parseRealShellSurfacesTxt() async throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDir.deletingLastPathComponent()
        let surfaces = repoRoot.appendingPathComponent("emily4/shell/master/surfaces.txt")
        let content = try String(contentsOf: surfaces, encoding: .shiftJIS)
        let parsed = SerikoParser.parseSurfaces(content)

        #expect(parsed.isEmpty == false)
        #expect(parsed[0]?.animations[50]?.patterns.isEmpty == false)
    }

    @Test
    func parseAnimationOptionSplitsCompositeTokens() async throws {
        let text = """
        surface1
        {
          animation10.interval,always
          animation10.option,exclusive+background,shared
        }
        """
        let parsed = SerikoParser.parseSurfaces(text)
        let options = parsed[1]?.animations[10]?.options ?? []
        #expect(options.contains("exclusive"))
        #expect(options.contains("background"))
        #expect(options.contains("shared"))
    }

    @Test
    func parseAnimationOptionKeyValuePairs() async throws {
        let text = """
        surface3
        {
          animation12.option,interval=talk,surface=3,series=mouth,exclusive
        }
        """
        let parsed = SerikoParser.parseSurfaces(text)
        let animation = parsed[3]?.animations[12]
        #expect(animation?.interval == .talk)
        #expect(animation?.surfaceOption == 3)
        #expect(animation?.seriesOption == "mouth")
        #expect(animation?.options.contains("exclusive") == true)
    }

    @Test
    func parseAnimationOverlayExtensionLine() async throws {
        let text = """
        surface5
        {
          animation90.overlay,4200,150,8,9
        }
        """
        let parsed = SerikoParser.parseSurfaces(text)
        let pattern = parsed[5]?.animations[90]?.patterns.first
        #expect(pattern?.method == .overlay)
        #expect(pattern?.surfaceID == 4200)
        #expect(pattern?.duration == 150)
        #expect(pattern?.x == 8)
        #expect(pattern?.y == 9)
    }

    @Test
    func loadSurfacesWildcardFilesInFilenameOrder() async throws {
        let shell = try makeTemporaryShellDirectory()
        defer { try? FileManager.default.removeItem(at: shell) }

        try write("""
        surface0
        {
          animation0.interval,always
        }
        """, named: "surfaces2.txt", to: shell)

        try write("""
        surface0
        {
          animation0.interval,rarely
        }
        """, named: "surfaces10.txt", to: shell)

        try write("""
        surface0
        {
          animation0.interval,never
        }
        """, named: "surfaces.txt", to: shell)

        // surfacetable.txt は surfaces*.txt バンドルから分離されている（書式非互換のため）。
        let bundle = try #require(SurfaceDefinitionLoader.load(from: shell))
        #expect(bundle.sourceFileNames == ["surfaces.txt", "surfaces10.txt", "surfaces2.txt"])

        let parsed = SerikoParser.parseSurfaces(bundle.content)
        #expect(parsed[0]?.animations[0]?.interval == .always)
    }

    @Test
    func loadSurfacesWildcardWithoutBaseSurfacesTxt() async throws {
        let shell = try makeTemporaryShellDirectory()
        defer { try? FileManager.default.removeItem(at: shell) }

        try write("""
        surface7
        {
          animation3.interval,talk
        }
        """, named: "surfaces-extra.txt", to: shell)

        try FileManager.default.createDirectory(
            at: shell.appendingPathComponent("surfaces-dir.txt"),
            withIntermediateDirectories: true
        )
        try write("ignored", named: "notsurfaces.txt", to: shell)

        let bundle = try #require(SurfaceDefinitionLoader.load(from: shell))
        #expect(bundle.sourceFileNames == ["surfaces-extra.txt"])

        let parsed = SerikoParser.parseSurfaces(bundle.content)
        #expect(parsed[7]?.animations[3]?.interval == .talk)
    }
}
