import Foundation
import Testing
@testable import Ourin

struct SerikoParserTests {
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
}

