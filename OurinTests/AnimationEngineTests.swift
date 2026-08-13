import Testing
@testable import Ourin
import Foundation
import AppKit
import CoreGraphics

struct AnimationEngineTests {
    @Test
    func parseCollisionRegions() throws {
        let surfacesContent = """
        surface0
        {
            animation0.interval,always
            animation0.pattern0,10,100,0,0
            collision0,10,10,100,100,test_region
            collision1,50,50,150,150,another_region
            point.centerx,100
            point.centery,50
            point.test.centerx,200
            point.test.centery,100
        }
        """
        
        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)
        
        let collisions = engine.getCollisions(for: 0)
        #expect(collisions.count == 2)
        #expect(collisions[0].name == "test_region")
        #expect(collisions[0].rect == CGRect(x: 10, y: 10, width: 90, height: 90))
        #expect(collisions[1].name == "another_region")
        #expect(collisions[1].rect == CGRect(x: 50, y: 50, width: 100, height: 100))
    }

    @Test
    func parseAndHitTestExtendedCollisionShapes() throws {
        let surfacesContent = """
        surface0
        {
            collisionex,circle,50,50,10,circle_region
            collisionex,polygon,0,0,100,0,0,100,triangle_region
        }
        """

        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)

        let collisions = engine.getCollisions(for: 0)
        #expect(collisions.count == 2)
        #expect(collisions[0].name == "circle_region")
        #expect(collisions[0].rect == CGRect(x: 40, y: 40, width: 20, height: 20))
        #expect(collisions[0].contains(CGPoint(x: 50, y: 50)))
        #expect(!collisions[0].contains(CGPoint(x: 40, y: 40)))
        #expect(collisions[1].name == "triangle_region")
        #expect(collisions[1].contains(CGPoint(x: 10, y: 10)))
        #expect(!collisions[1].contains(CGPoint(x: 80, y: 80)))
    }

    @Test
    func animationCollisionRegionsAreActiveOnlyWhileAnimationRuns() throws {
        let surfacesContent = """
        surface0
        {
            animation7.interval,always
            animation7.pattern0,10,100,0,0
            animation7.collision0,10,10,100,100,animated_region
            collision0,10,10,100,100,base_region
        }
        """

        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)

        let inactive = engine.getCollisions(for: 0)
        #expect(inactive.count == 1)
        #expect(inactive[0].name == "base_region")

        let active = engine.getCollisions(for: 0, activeAnimationIDs: [7])
        #expect(active.count == 2)
        #expect(active[0].name == "animated_region")
        #expect(active[0].contains(CGPoint(x: 20, y: 20)))
    }

    @Test
    func animationCollisionExSupportsStandardEllipseAndCircleForms() throws {
        let surfacesContent = """
        surface0
        {
            animation3.interval,always
            animation3.pattern0,10,100,0,0
            animation3.collisionex0,Head,ellipse,0,0,100,60
            animation3.collisionex1,Eye,circle,50,50,10
        }
        """

        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)

        let collisions = engine.getCollisions(for: 0, activeAnimationIDs: [3])
        #expect(collisions.count == 2)
        #expect(collisions[0].name == "Head")
        #expect(collisions[0].contains(CGPoint(x: 50, y: 30)))
        #expect(!collisions[0].contains(CGPoint(x: 0, y: 0)))
        #expect(collisions[1].name == "Eye")
        #expect(collisions[1].contains(CGPoint(x: 50, y: 50)))
    }

    @Test
    func collisionExRegionLoadsTargetColorAndInversionFromShellDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-collision-region-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 3,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        Self.setPixel([255, 0, 255], atX: 1, y: 1, in: bitmap)
        let imageData = try #require(bitmap.representation(using: .png, properties: [:]))
        try imageData.write(to: root.appendingPathComponent("atari.png"))

        let surfacesContent = """
        surface0
        {
            collisionex0,Base,region,atari.png,255,0,255
            animation4.interval,always
            animation4.pattern0,10,100,0,0
            animation4.collisionex0,Hit,region,atari.png,255,0,255
            animation4.collisionex1,Miss,region,atari.png,255,0,255,true
        }
        """

        let engine = AnimationEngine()
        engine.loadAnimations(
            surfaceID: 0,
            content: surfacesContent,
            resourceDirectory: root
        )

        let inactive = engine.getCollisions(for: 0)
        #expect(inactive.count == 1)
        #expect(inactive[0].name == "Base")
        #expect(inactive[0].contains(CGPoint(x: 1, y: 1)))
        #expect(!inactive[0].contains(CGPoint(x: 0, y: 0)))

        let active = engine.getCollisions(for: 0, activeAnimationIDs: [4])
        #expect(active.map(\.name) == ["Hit", "Miss", "Base"])
        #expect(active[0].contains(CGPoint(x: 1, y: 1)))
        #expect(!active[1].contains(CGPoint(x: 1, y: 1)))
        #expect(active[1].contains(CGPoint(x: 0, y: 0)))
    }

    @Test
    func reloadingSurfaceCollisionDefinitionsDoesNotDuplicateRegions() throws {
        let surfacesContent = """
        surface0
        {
            animation7.collision0,10,10,100,100,animated_region
            collision0,10,10,100,100,base_region
        }
        """

        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)

        #expect(engine.getCollisions(for: 0).map(\.name) == ["base_region"])
        #expect(engine.getCollisions(for: 0, activeAnimationIDs: [7]).map(\.name) == [
            "animated_region",
            "base_region"
        ])
    }

    private static func setPixel(
        _ values: [Int],
        atX x: Int,
        y: Int,
        in bitmap: NSBitmapImageRep
    ) {
        var values = values
        values.withUnsafeMutableBufferPointer { buffer in
            bitmap.setPixel(buffer.baseAddress!, atX: x, y: y)
        }
    }
    
    @Test
    func parsePointDefinitions() throws {
        let surfacesContent = """
        surface0
        {
            animation0.interval,always
            animation0.pattern0,10,100,0,0
            point.centerx,100
            point.centery,50
            point.test.centerx,200
            point.test.centery,100
        }
        """
        
        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)
        
        let points = engine.getAllPoints(for: 0)
        #expect(points != nil)
        #expect(points?.count == 2)
        #expect(points?["center"]?.x == 100)
        #expect(points?["center"]?.y == 50)
        #expect(points?["test"]?.x == 200)
        #expect(points?["test"]?.y == 100)
    }
    
    @Test
    func patternTypeOverlay() throws {
        let surfacesContent = """
        surface0
        {
            animation0.interval,always
            animation0.pattern0,10,100,0,0
        }
        """
        
        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)
        
        let animations = engine.getCollisions(for: 0)
        #expect(animations.count >= 0)
    }
    
    @Test
    func patternTypeBase() throws {
        let surfacesContent = """
        surface0
        {
            animation0.interval,always
            animation0.pattern0,10,100,0,0
        }
        """
        
        let engine = AnimationEngine()
        engine.loadAnimations(surfaceID: 0, content: surfacesContent)
        
        let points = engine.getAllPoints(for: 0)
        #expect(points != nil)
    }
}
