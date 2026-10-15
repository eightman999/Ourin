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

        // SSP 座標: 自窓の左下を基準に、窓の左下を右へ 50・下へ 20 動かす（+Y は下向き）
        let f = window.frame
        #expect(Int(f.origin.x) == 150)
        #expect(Int(f.origin.y) == 180)
    }

    @Test
    func moveOriginUsesTopLeftScreenCoordinatesWithDownwardY() {
        // 1728x1117 の画面、300x400 の窓
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let current = CGRect(x: 10, y: 10, width: 300, height: 400)
        // --X=100,--Y=50（既定 left.top 同士）→ 窓の左上が画面左上から (100, 50)
        let o = GhostManager.moveTargetOrigin(current: current, base: screen, baseOffset: nil, moveOffset: nil, x: 100, y: 50)
        #expect(o == CGPoint(x: 100, y: 1117 - 50 - 400))
        // UKADOC の例: 画面左下を基準に窓の左上を Y=-400（上方向）へ
        let up = GhostManager.moveTargetOrigin(current: current, base: screen, baseOffset: "left.bottom", moveOffset: "left.top", x: 80, y: -400)
        #expect(up == CGPoint(x: 80, y: 0))
        // 右下揃え: 窓の right.bottom を画面の right.bottom へ
        let corner = GhostManager.moveTargetOrigin(current: current, base: screen, baseOffset: "right.bottom", moveOffset: "right.bottom", x: 0, y: 0)
        #expect(corner == CGPoint(x: 1428, y: 0))
    }

    @Test
    func moveOriginKeepsFixedAxis() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let current = CGRect(x: 640, y: 120, width: 300, height: 400)
        let o = GhostManager.moveTargetOrigin(current: current, base: screen, baseOffset: nil, moveOffset: nil, x: nil, y: 0)
        #expect(o == CGPoint(x: 640, y: 1117 - 400))
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
