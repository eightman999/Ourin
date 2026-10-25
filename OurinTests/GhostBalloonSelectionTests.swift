import Foundation
import Testing
@testable import Ourin

/// ゴーストの descript.txt の標準バルーン（UKADOC: balloon・default.balloon.path・recommended.*）（#184）。
struct GhostBalloonSelectionTests {
    private func makeBase() throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("Ourin-Balloon-\(UUID().uuidString)", isDirectory: true)
        for (directory, name) in [("wiz", "wiz"), ("other", "Other Balloon")] {
            let folder = base.appendingPathComponent("balloon/\(directory)", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try "charset,UTF-8\r\nname,\(name)\r\n".write(to: folder.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: base.appendingPathComponent("ghost/sample/ghost/master"), withIntermediateDirectories: true)
        return base
    }

    @Test
    func descriptBalloonSettingsChooseAnInstalledBalloon() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        let ghost = base.appendingPathComponent("ghost/sample", isDirectory: true)
        func resolve(_ configure: (inout GhostConfiguration) -> Void) -> String? {
            var config = GhostConfiguration(name: "sample", shiori: "yaya.dll")
            configure(&config)
            return GhostManager.configuredBalloonDirectory(for: config, ghostURL: ghost, baseDirectory: base)?.lastPathComponent
        }
        // balloon はバルーン名。Taromati2 のようにフォルダ名と同じものも、descript の name でも探せる。
        #expect(resolve { $0.balloon = "wiz" } == "wiz")
        #expect(resolve { $0.balloon = "Other Balloon" } == "other")
        // default.balloon.path は相対パス（基準フォルダからでも balloon/ からでもよい）。
        #expect(resolve { $0.defaultBalloonPath = "balloon\\other" } == "other")
        #expect(resolve { $0.defaultBalloonPath = "wiz" } == "wiz")
        // 推奨（recommended.*）を標準より優先する。
        #expect(resolve { $0.balloon = "wiz"; $0.recommendedBalloon = "Other Balloon" } == "other")
        #expect(resolve { $0.balloon = "wiz"; $0.recommendedBalloonPath = "balloon/other" } == "other")
        // 見つからないもの・基準フォルダの外を指すものは使わない（従来のゴーストのフォルダの balloon/ に任せる）。
        #expect(resolve { $0.balloon = "missing" } == nil)
        #expect(resolve { $0.defaultBalloonPath = "../../etc" } == nil)
        #expect(resolve { _ in } == nil)
    }

    @MainActor
    @Test
    func switchingByNameFindsInstalledBalloons() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }
        OurinPaths.testBaseOverride = base
        defer { OurinPaths.testBaseOverride = nil }

        let manager = GhostManager(ghostURL: base.appendingPathComponent("ghost/sample", isDirectory: true))
        // \![change,balloon,名前] とメニューの切り替えは、インストール済みのバルーンも探す。
        #expect(manager.switchBalloon(named: "wiz", scope: 0))
        #expect(manager.balloonConfig?.name == "wiz")
        #expect(manager.switchBalloon(named: "Other Balloon", scope: 0))
        #expect(manager.balloonConfig?.name == "Other Balloon")
        #expect(!manager.switchBalloon(named: "missing", scope: 0))
    }
}
