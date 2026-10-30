import AppKit
import Testing
@testable import Ourin

struct InputMonitorRoutingTests {
    @Test func mouseEventsOutsideGhostWindowsAreNotDispatched() {
        for type: NSEvent.EventType in [.mouseMoved, .scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDragged] {
            for identifier: String? in [nil, "settings", "GhostCharacterWindow", "OtherApp"] {
                #expect(!InputMonitor.shouldDispatchLocalEvent(type, windowIdentifier: identifier))
            }
        }
    }
    @Test func ghostAndBalloonMouseEventsKeepTheirRouting() {
        for type: NSEvent.EventType in [.mouseMoved, .scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDragged] {
            for identifier in ["GhostCharacterWindow_0", "GhostCharacterWindow_1", "GhostBalloonWindow_0"] {
                #expect(InputMonitor.shouldDispatchLocalEvent(type, windowIdentifier: identifier))
            }
        }
    }
    @Test func localKeyboardAndModifierEventsKeepTheirRouting() {
        for type: NSEvent.EventType in [.keyDown, .keyUp, .flagsChanged] {
            #expect(InputMonitor.shouldDispatchLocalEvent(type, windowIdentifier: nil))
            #expect(InputMonitor.shouldDispatchLocalEvent(type, windowIdentifier: "settings"))
        }
    }
}
