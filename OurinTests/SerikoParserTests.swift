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
    func parseParameterizedAndCombinedIntervals() async throws {
        let text = """
        surface4
        {
          animation1.interval,talk,2
          animation2.interval,bind+runonce
          animation3.interval,bind+runonce+random,5
        }
        """

        let animations = try #require(SerikoParser.parseSurfaces(text)[4]?.animations)
        #expect(animations[1]?.interval == .talkCharacters(2))
        #expect(animations[2]?.interval == .combined([.bind, .runonce]))
        #expect(animations[3]?.interval == .combined([.bind, .runonce, .random(5)]))
    }

    @Test
    func parseStartTalkAndEndTalkIntervals() async throws {
        #expect(SerikoInterval.parse("starttalk") == .startTalk)
        #expect(SerikoInterval.parse("ENDTALK") == .endTalk)
        #expect(SerikoInterval.parse("starttalk+runonce") == .combined([.startTalk, .runonce]))
    }

    @Test
    func rejectMultipleParameterizedIntervals() async throws {
        let text = """
        surface4
        {
          animation1.interval,random,5+periodic,2
          animation2.interval,random,5+bind
        }
        """

        let animations = try #require(SerikoParser.parseSurfaces(text)[4]?.animations)
        #expect(animations[1]?.interval == .unknown("random,5+periodic,2"))
        #expect(animations[2]?.interval == .unknown("random,5+bind"))
    }

    @Test
    func parseControlPatternsKeepsCandidateListsTogether() async throws {
        let text = """
        surface0
        {
          animation10.interval,always
          animation10.pattern0,alternativestart,(11,12.13)
          animation10.pattern1,alternativestop,[14,15]
          animation10.pattern2,parallelstart,(16,17)
          animation10.pattern3,parallelstop,[18.19]
        }
        """

        let patterns = try #require(SerikoParser.parseSurfaces(text)[0]?.animations[10]?.patterns)
        #expect(patterns[0].method == .alternativeStart)
        #expect(patterns[0].referencedAnimationIDs == [11, 12, 13])
        #expect(patterns[1].method == .alternativeStop)
        #expect(patterns[1].referencedAnimationIDs == [14, 15])
        #expect(patterns[2].method == .parallelStart)
        #expect(patterns[2].referencedAnimationIDs == [16, 17])
        #expect(patterns[3].method == .parallelStop)
        #expect(patterns[3].referencedAnimationIDs == [18, 19])
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
    func parseScalingPatternPreservesFractionalFactors() async throws {
        let text = """
        surface0
        {
          animation7.interval,never
          animation7.pattern0,scaling,0,100,92.5,87.25
        }
        """

        let pattern = try #require(SerikoParser.parseSurfaces(text)[0]?.animations[7]?.patterns.first)
        #expect(pattern.method == .scaling)
        #expect(pattern.xValue == 92.5)
        #expect(pattern.yValue == 87.25)
    }

    @Test
    func parseImportPatternKeepsFilenameAndTimingArguments() async throws {
        let text = """
        surface0
        {
          animation8.interval,never
          animation8.pattern0,import,media/anim.gif,250,3,4
        }
        """

        let pattern = try #require(SerikoParser.parseSurfaces(text)[0]?.animations[8]?.patterns.first)
        #expect(pattern.method == .import)
        #expect(pattern.rawArguments == ["import", "media/anim.gif", "250", "3", "4"])
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
