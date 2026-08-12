import AppKit
import Testing
@testable import Ourin

@MainActor
struct MoveCommandTests {
    private func makeGhostManager() -> GhostManager {
        let url = URL(fileURLWithPath: "/tmp/ghost-test")
        return GhostManager(ghostURL: url)
    }

    @Test
    func moveWaitAppendsPlaybackWait() async throws {
        let gm = makeGhostManager()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        gm.characterWindows[0] = window

        gm.executeMoveCommand(args: ["--x=120", "--y=150", "--time=200", "--wait=true"], async: false)

        let hasWait = gm.playbackQueue.contains { unit in
            if case .wait(let sec) = unit { return abs(sec - 0.2) < 0.001 }
            return false
        }
        #expect(hasWait)
    }

    @Test
    func moveTargetResolvesWithBaseAndOffsets() async throws {
        let gm = makeGhostManager()
        let startFrame = NSRect(x: 100, y: 200, width: 240, height: 160)
        let window = NSWindow(contentRect: startFrame, styleMask: .borderless, backing: .buffered, defer: false)
        gm.characterWindows[0] = window

        gm.executeMoveCommand(args: ["--x=50", "--y=20", "--base=window", "--base-offset=left.bottom", "--move-offset=left.bottom", "--time=0"], async: false)

        // Wait for the DispatchQueue.main.async block in moveWindow() to execute
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }

        let f = window.frame
        #expect(Int(f.origin.x) == 50)
        #expect(Int(f.origin.y) == 20)
    }

    @Test
    func stickyWindowUsesCapturedRelativeOriginInBothAxes() {
        let masterOrigin = CGPoint(x: 400, y: 220)
        let followerOrigin = CGPoint(x: 735, y: 518)
        let offset = GhostManager.stickyOffset(masterOrigin: masterOrigin, followerOrigin: followerOrigin)

        #expect(offset.x == 335)
        #expect(offset.y == 298)

        let movedMaster = CGPoint(x: 1000, y: 900)
        let movedFollower = GhostManager.stickyFollowerOrigin(masterOrigin: movedMaster, offset: offset)
        #expect(movedFollower.x == 1335)
        #expect(movedFollower.y == 1198)
    }
}
