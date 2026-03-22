import AppKit
import Testing
@testable import Ourin

struct MoveCommandTests {
    private func makeGhostManager() -> GhostManager {
        let url = URL(fileURLWithPath: "/tmp/ghost-test")
        return GhostManager(ghostURL: url)
    }

    @Test
    func moveWaitAppendsPlaybackWait() async throws {
        let gm = makeGhostManager()
        // Prepare a window for current scope (0)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        gm.characterWindows[0] = window

        // Execute a timed move with wait flag
        gm.executeMoveCommand(args: ["--x=120", "--y=150", "--time=200", "--wait=true"], async: false)

        // Expect a wait unit (about 0.2s) appended to playback queue
        // PlaybackUnit is internal; inspect via pattern matching
        let hasWait = gm.playbackQueue.contains { unit in
            if case .wait(let sec) = unit { return abs(sec - 0.2) < 0.001 }
            return false
        }
        #expect(hasWait)
    }

    @Test
    func moveTargetResolvesWithBaseAndOffsets() async throws {
        let gm = makeGhostManager()
        // Window starts at (100,200)
        let startFrame = NSRect(x: 100, y: 200, width: 240, height: 160)
        let window = NSWindow(contentRect: startFrame, styleMask: .borderless, backing: .buffered, defer: false)
        gm.characterWindows[0] = window

        // Resolve target from base=window with base/move anchors; time=0 (instant)
        gm.executeMoveCommand(args: ["--x=50", "--y=20", "--base=window", "--base-offset=left.bottom", "--move-offset=left.bottom", "--time=0"], async: false)

        // With the chosen offsets, target should be exactly (50,20)
        let f = window.frame
        #expect(Int(f.origin.x) == 50)
        #expect(Int(f.origin.y) == 20)
    }
}

