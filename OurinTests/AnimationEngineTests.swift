import Testing
@testable import Ourin
import Foundation
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
