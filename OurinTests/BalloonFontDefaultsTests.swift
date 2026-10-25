import AppKit
import Foundation
import Testing
@testable import Ourin

/// バルーンの descript.txt の本文の既定スタイル（font.color・font.height）を、表示の最初から使う。
@MainActor
struct BalloonFontDefaultsTests {
    /// ghost/balloon/<フォルダ>/descript.txt を持つ一時ゴーストを作る。
    private func makeGhost(balloons: [String: String]) throws -> URL {
        let fm = FileManager.default
        let ghost = fm.temporaryDirectory.appendingPathComponent("ourin-balloon-font-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: ghost.appendingPathComponent("ghost/master", isDirectory: true), withIntermediateDirectories: true)
        for (directory, descript) in balloons {
            let folder = ghost.appendingPathComponent("balloon/\(directory)", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try descript.write(to: folder.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        }
        return ghost
    }

    private func rgb(_ color: NSColor) -> [Int] {
        guard let converted = color.usingColorSpace(.sRGB) else { return [] }
        return [converted.redComponent, converted.greenComponent, converted.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    private func apply(_ manager: GhostManager, _ args: [String]) {
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .command(name: "f", args: args))
        manager.processNextUnit()
    }

    private static let wiz = "charset,UTF-8\r\nname,wiz\r\nfont.color.r,255\r\nfont.color.g,255\r\nfont.color.b,255\r\nfont.height,14\r\n"
    private static let other = "charset,UTF-8\r\nname,other\r\nfont.color.r,10\r\nfont.color.g,20\r\nfont.color.b,30\r\nfont.height,10\r\n"
    private static let plain = "charset,UTF-8\r\nname,plain\r\n"

    @Test func newBalloonUsesDescriptFontDefaults() throws {
        let ghost = try makeGhost(balloons: ["wiz": Self.wiz])
        defer { try? FileManager.default.removeItem(at: ghost) }
        let manager = GhostManager(ghostURL: ghost)
        defer { _ = manager.shutdown() }

        #expect(manager.switchBalloon(named: "wiz", scope: 0))
        let vm = manager.getBalloonVM(for: 0)

        // Taromati2 の wiz（黒地）: 本文は白で、黒字にならない。
        #expect(rgb(vm.fontColor) == [255, 255, 255])
        #expect(vm.fontSize == 14)
    }

    @Test func balloonWithoutFontColorUsesUkadocDefault() throws {
        let ghost = try makeGhost(balloons: ["plain": Self.plain])
        defer { try? FileManager.default.removeItem(at: ghost) }
        let manager = GhostManager(ghostURL: ghost)
        defer { _ = manager.shutdown() }

        #expect(manager.switchBalloon(named: "plain", scope: 0))
        let vm = manager.getBalloonVM(for: 0)

        // UKADOC: font.color の既定値は 0,0,0、font.height は 12。
        #expect(rgb(vm.fontColor) == [0, 0, 0])
        #expect(vm.fontSize == 12)
    }

    @Test func noBalloonConfigKeepsSystemTextColor() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-balloon-font-none"))
        defer { _ = manager.shutdown() }
        let vm = manager.getBalloonVM(for: 0)

        #expect(manager.balloonConfig == nil)
        #expect(vm.fontColor == .textColor)
        #expect(vm.fontSize == 12)
    }

    @Test func switchingBalloonUpdatesExistingBalloons() throws {
        let ghost = try makeGhost(balloons: ["wiz": Self.wiz, "other": Self.other])
        defer { try? FileManager.default.removeItem(at: ghost) }
        let manager = GhostManager(ghostURL: ghost)
        defer { _ = manager.shutdown() }

        #expect(manager.switchBalloon(named: "wiz", scope: 0))
        let sakura = manager.getBalloonVM(for: 0)
        let kero = manager.getBalloonVM(for: 1)
        #expect(rgb(sakura.fontColor) == [255, 255, 255])

        #expect(manager.switchBalloon(named: "other", scope: 0))
        for vm in [sakura, kero] {
            #expect(rgb(vm.fontColor) == [10, 20, 30])
            #expect(vm.fontSize == 10)
        }
    }

    @Test func fontDefaultCommandsRestoreDescriptFontDefaults() throws {
        let ghost = try makeGhost(balloons: ["wiz": Self.wiz])
        defer { try? FileManager.default.removeItem(at: ghost) }
        let manager = GhostManager(ghostURL: ghost)
        defer { _ = manager.shutdown() }

        #expect(manager.switchBalloon(named: "wiz", scope: 0))
        let vm = manager.getBalloonVM(for: 0)

        apply(manager, ["color", "255", "0", "0"])
        apply(manager, ["height", "20"])
        #expect(rgb(vm.fontColor) == [255, 0, 0])
        apply(manager, ["default"])
        #expect(rgb(vm.fontColor) == [255, 255, 255])
        #expect(vm.fontSize == 14)

        apply(manager, ["color", "255", "0", "0"])
        apply(manager, ["color", "default"])
        #expect(rgb(vm.fontColor) == [255, 255, 255])
    }
}
