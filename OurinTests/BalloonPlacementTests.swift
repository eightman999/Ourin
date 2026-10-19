import AppKit
import Testing
@testable import Ourin

struct BalloonPlacementTests {
    private let screen = CGRect(x: 0, y: 64, width: 1728, height: 1020)
    private let balloon = CGSize(width: 335, height: 169)

    private func offsets(_ table: [String: CGFloat]) -> (String) -> CGFloat? { { table[$0] } }

    @Test
    func autoPlacesLeftOfShellOnRightHalfUsingOffsets() {
        // emily4: sakura.balloon.offsetx=7, offsety=-40。シェルは画面右側
        let shell = CGRect(x: 1408, y: 83, width: 300, height: 400)
        let o = GhostManager.shellBalloonOrigin(character: shell, balloonSize: balloon, screen: screen, alignment: "none",
                                                offset: offsets(["offsetx": 7, "offsety": -40]))
        // 左に置き、シェル側へ 7 寄せる。上端はシェル上端より 40 上
        #expect(o.x == CGFloat(1408 - 335 + 7))
        #expect(o.y + balloon.height == shell.maxY + CGFloat(40))
    }

    @Test
    func autoPlacesRightOfShellOnLeftHalf() {
        let shell = CGRect(x: 100, y: 83, width: 300, height: 400)
        let o = GhostManager.shellBalloonOrigin(character: shell, balloonSize: balloon, screen: screen, alignment: nil,
                                                offset: offsets(["offsetx": 10, "offsety": 10]))
        #expect(o.x == CGFloat(400 - 10))
        #expect(o.y + balloon.height == shell.maxY - CGFloat(10))
    }

    @Test
    func explicitSideUsesDirectionalOffsets() {
        let shell = CGRect(x: 1408, y: 83, width: 300, height: 400)
        let o = GhostManager.shellBalloonOrigin(character: shell, balloonSize: balloon, screen: screen, alignment: "right",
                                                offset: offsets(["offsetx": 7, "offsetxr": 20, "offsety": 0]))
        #expect(o.x == shell.maxX - 20)
        #expect(o.y + balloon.height == shell.maxY)
    }

    @Test
    func autoFlipsWhenPreferredSideOverflows() {
        let small = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let shell = CGRect(x: 300, y: 100, width: 150, height: 300)
        let wide = CGSize(width: 600, height: 150)
        // 左半分なので右が優先だが、右は 450+600 > 1000 ではみ出すので左へ回す
        let o = GhostManager.shellBalloonOrigin(character: shell, balloonSize: wide, screen: small, alignment: "none", offset: { _ in nil })
        #expect(o.x == CGFloat(300 - 600))
    }
}
