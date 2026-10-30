import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import Ourin

@Suite(.serialized)
@MainActor
struct BalloonSelectionTests {
    @Test func rootAndUnrelatedPathsCannotBecomeSavedBalloonSelections() throws {
        try withFixture { manager, base in
            for directory in [URL(fileURLWithPath: "/", isDirectory: true),
                              base.appendingPathComponent("unrelated", isDirectory: true)] {
                manager.rememberBalloonSelection(directory)
                #expect(manager.balloonSelectionDefaults.data(forKey: manager.balloonSelectionPreferenceKey) == nil)
            }
        }
    }

    @Test func sharedDirectoryAndDisplayNameResolveWithoutUnknownFallback() throws {
        try withFixture { manager, base in
            let shared = try writeBalloon(name: "Shared Balloon", directory: base.appendingPathComponent("balloon/Shared"))
            #expect(manager.loadStartupBalloon())
            #expect(manager.balloonConfig?.name == "Local")
            #expect(manager.switchBalloon(named: "shared", scope: 0))
            #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == shared.resolvingSymlinksInPath().path)
            #expect(manager.resolveBalloonDirectory(named: "Shared Balloon")?.resolvingSymlinksInPath().path == shared.resolvingSymlinksInPath().path)
            #expect(manager.resolveBalloonDirectory(named: "balloon\\Shared")?.resolvingSymlinksInPath().path == shared.resolvingSymlinksInPath().path)
            #expect(!manager.switchBalloon(named: "nonexistent", scope: 0))
            #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == shared.resolvingSymlinksInPath().path)
            #expect(!manager.switchBalloon(named: "../outside", scope: 0))
        }
    }

    @Test func explicitSelectionSurvivesStartupDefaultsAndMenuDecodesNames() throws {
        try withFixture { manager, base in
            let standard = try writeBalloon(name: "Standard", directory: base.appendingPathComponent("balloon/standard"))
            let recommended = try writeBalloon(name: "Recommended", directory: base.appendingPathComponent("balloon/recommended"))
            let custom = try writeBalloon(name: "Shared 日本語", directory: base.appendingPathComponent("balloon/custom"))
            var config = GhostConfiguration(name: "fixture")
            config.defaultBalloonPath = "balloon\\standard"
            manager.ghostConfig = config
            #expect(manager.loadStartupBalloon())
            #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == standard.resolvingSymlinksInPath().path)
            config.recommendedBalloonPath = "recommended"
            manager.ghostConfig = config
            #expect(manager.loadStartupBalloon())
            #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == recommended.resolvingSymlinksInPath().path)
            let encoded = try #require("Shared 日本語".addingPercentEncoding(withAllowedCharacters: .alphanumerics))
            manager.handleMenuAction("switch_balloon:\(encoded)")
            #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == custom.resolvingSymlinksInPath().path)
            #expect(manager.loadStartupBalloon())
            #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == custom.resolvingSymlinksInPath().path)
        }
    }

    @Test(arguments: ["base", "ghost"])
    func startupPreservesPublishedRelativeBalloonPaths(root: String) throws {
        try withFixture { manager, base in
            let parent = root == "base" ? base : manager.ghostURL
            let legacy = try writeBalloon(name: "Legacy Relative", directory: parent.appendingPathComponent("legacy/style"))
            var config = GhostConfiguration(name: "fixture")
            config.recommendedBalloonPath = "legacy/style"
            manager.ghostConfig = config
            #expect(manager.loadStartupBalloon())
            #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == legacy.resolvingSymlinksInPath().path)
        }
    }

    @Test func explicitChoicePersistsAcrossManagersAndOverridesRecommendedDefaults() throws {
        try withFixture { manager, base in
            let custom = try writeBalloon(name: "My Balloon", directory: base.appendingPathComponent("balloon/custom"))
            _ = try writeBalloon(name: "Recommended", directory: base.appendingPathComponent("balloon/recommended"))
            #expect(manager.switchBalloon(named: "custom", scope: 0))
            let data = try #require(manager.balloonSelectionDefaults.data(forKey: manager.balloonSelectionPreferenceKey))
            let record = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(record["schemaVersion"] as? Int == 1)
            #expect(record["location"] as? String == "shared")
            #expect(record["relativePath"] as? String == "custom")
            #expect(record["name"] as? String == "My Balloon")
            let fresh = GhostManager(ghostURL: manager.ghostURL)
            fresh.balloonSelectionDefaults = manager.balloonSelectionDefaults
            defer { _ = fresh.shutdown() }
            var config = GhostConfiguration(name: "fixture")
            config.recommendedBalloonPath = "recommended"
            fresh.ghostConfig = config
            #expect(fresh.loadStartupBalloon())
            #expect(fresh.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == custom.resolvingSymlinksInPath().path)
        }
    }

    @Test func deletedAndInvalidSelectionsFallBackWithoutReadingOutsideBalloonRoots() throws {
        try withFixture { manager, base in
            let custom = try writeBalloon(name: "Deleted", directory: base.appendingPathComponent("balloon/custom"))
            #expect(manager.switchBalloon(named: "custom", scope: 0))
            let defaults = manager.balloonSelectionDefaults, key = manager.balloonSelectionPreferenceKey
            let saved = try #require(defaults.data(forKey: key))
            try FileManager.default.removeItem(at: custom)
            let unsafe = try JSONSerialization.data(withJSONObject: ["schemaVersion":1,"location":"shared","relativePath":"../outside","name":"Outside"])
            let future = try JSONSerialization.data(withJSONObject: ["schemaVersion":999,"location":"shared","relativePath":"custom","name":"Deleted"])
            for record in [saved, unsafe, future, Data("malformed JSON".utf8)] {
                defaults.set(record, forKey: key)
                let fresh = GhostManager(ghostURL: manager.ghostURL)
                fresh.balloonSelectionDefaults = defaults
                #expect(fresh.loadStartupBalloon())
                #expect(fresh.balloonConfig?.name == "Local")
                #expect(fresh.explicitlySelectedBalloonDirectoryURL == nil)
                _ = fresh.shutdown()
            }
        }
    }

    @Test func selectedBalloonSurvivesBaseRelocationAndDirectoryRename() throws {
        try withFixture { manager, base in
            _ = try writeBalloon(name: "Movable", directory: base.appendingPathComponent("balloon/custom"))
            #expect(manager.switchBalloon(named: "custom", scope: 0))
            let key = manager.balloonSelectionPreferenceKey
            let moved = base.deletingLastPathComponent().appendingPathComponent("Ourin-MovedBase-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: base, to: moved)
            OurinPaths.testBaseOverride = moved
            defer {
                OurinPaths.testBaseOverride = base
                try? FileManager.default.removeItem(at: moved)
            }
            let fresh = GhostManager(ghostURL: moved.appendingPathComponent("ghost/example"))
            fresh.balloonSelectionDefaults = manager.balloonSelectionDefaults
            defer { _ = fresh.shutdown() }
            #expect(fresh.balloonSelectionPreferenceKey == key)
            #expect(fresh.loadStartupBalloon())
            #expect(fresh.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == moved.appendingPathComponent("balloon/custom").resolvingSymlinksInPath().path)
            let renamed = moved.appendingPathComponent("balloon/renamed")
            try FileManager.default.moveItem(at: moved.appendingPathComponent("balloon/custom"), to: renamed)
            #expect(fresh.loadStartupBalloon())
            #expect(fresh.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == renamed.resolvingSymlinksInPath().path)
            let updated = try #require(fresh.balloonSelectionDefaults.data(forKey: key))
            let record = try #require(JSONSerialization.jsonObject(with: updated) as? [String: Any])
            #expect(record["relativePath"] as? String == "renamed")
        }
    }

    @Test func descriptorCharsetAndBOMPreserveJapaneseNames() throws {
        try withFixture { manager, base in
            let target = base.appendingPathComponent("balloon/japanese")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let descriptor = target.appendingPathComponent("descript.txt")
            for (declaration, encoding, bom) in [("UTF-8", String.Encoding.utf8, false), ("UTF-8", .utf8, true),
                                               ("Shift_JIS", .shiftJIS, false), ("UTF-8", .shiftJIS, false)] {
                var data = try #require("charset,\(declaration)\nname,バルーン\n".data(using: encoding))
                if bom { data = Data([0xEF,0xBB,0xBF]) + data }
                try data.write(to: descriptor)
                #expect(BalloonConfig.load(from: descriptor.path)?.name == "バルーン")
                #expect(manager.resolveBalloonDirectory(named: "バルーン")?.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path)
            }
        }
    }

    @Test func switchingRefreshesExistingHostingViewWithoutDiscardingContents() throws {
        try withFixture { manager, base in
            #expect(manager.loadStartupBalloon())
            let vm = manager.getBalloonVM(for: 0)
            vm.text = "Keep the current conversation"
            let window = try #require(manager.balloonWindows[0])
            let oldController = try #require(window.contentViewController as? NSHostingController<BalloonView>)
            #expect(oldController.rootView.config?.name == "Local")
            let target = try writeBalloon(name: "Replacement", directory: base.appendingPathComponent("balloon/replacement"))
            #expect(manager.switchBalloon(named: "replacement", scope: 0))
            #expect(manager.balloonWindows[0] === window)
            #expect(manager.balloonViewModels[0] === vm)
            #expect(vm.text == "Keep the current conversation")
            #expect(oldController.rootView.config?.name == "Replacement")
            #expect(oldController.rootView.imageLoader.map { URL(fileURLWithPath: $0.balloonPath).resolvingSymlinksInPath().path } == target.resolvingSymlinksInPath().path)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OURIN_BALLOON_NAR"] != nil,
                   "Set TEST_RUNNER_OURIN_BALLOON_NAR for an original bundled-balloon NAR"))
    func realNarInstallsAndSelectsSharedBalloonWithoutCopyingIntoGhost() throws {
        let archive = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OURIN_BALLOON_NAR"]))
        let expected = archive.lastPathComponent == "HiroShinosawa.nar"
            ? "eeff4e64cfc96dad292e090b4144c3c2251508f18907f9419e3c4c8e25f48bef"
            : "9048182947acbdb917baf5a389bfd75118a7e587deecaca5863956757904b3d9"
        try #require(hash(try Data(contentsOf: archive)) == expected)
        let persistentPath = ProcessInfo.processInfo.environment["OURIN_BALLOON_INSTALL_BASE"]
        let base = persistentPath.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-InstalledBalloon-\(UUID().uuidString)")
        try #require(!FileManager.default.fileExists(atPath: base.path))
        let oldBase = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = oldBase
            if persistentPath == nil { try? FileManager.default.removeItem(at: base) }
        }
        let source = base.appendingPathComponent("original-extract")
        try ZipUtil.extractZip(archive, to: source)
        let result = try NarInstaller().installWithResult(fromNar: archive)
        let directory = try #require(result.manifest.balloonDirectory)
        let shared = base.appendingPathComponent("balloon/\(directory)")
        #expect(FileManager.default.fileExists(atPath: shared.appendingPathComponent("descript.txt").path))
        #expect(!FileManager.default.fileExists(atPath: result.target.appendingPathComponent("balloon").path))
        let suiteName = "Ourin.BalloonSelectionTests.Nar.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = GhostManager(ghostURL: result.target)
        manager.balloonSelectionDefaults = defaults
        defer { _ = manager.shutdown() }
        let encoded = try #require(directory.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        manager.handleMenuAction("switch_balloon:\(encoded)")
        #expect(manager.activeBalloonDirectoryURL?.resolvingSymlinksInPath().path == shared.resolvingSymlinksInPath().path)
        #expect(manager.balloonImageLoader?.loadSurface(index: 0) != nil)
        if archive.lastPathComponent == "HiroShinosawa.nar" { #expect(manager.balloonConfig?.name == "篠澤バルーン") }
        let enumerator = try #require(FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]))
        var checked = 0
        for case let file as URL in enumerator {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let sourcePath = source.resolvingSymlinksInPath().path
            let filePath = file.resolvingSymlinksInPath().path
            try #require(filePath.hasPrefix(sourcePath + "/"))
            let relative = String(filePath.dropFirst(sourcePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if ZipUtil.pathContainsIgnoredDirectory(relative) || ZipUtil.shouldIgnore(fileName: file.lastPathComponent) { continue }
            #expect(hash(try Data(contentsOf: file)) == hash(try Data(contentsOf: result.target.appendingPathComponent(relative))))
            checked += 1
        }
        #expect(checked > 100)
        #expect(hash(try Data(contentsOf: archive)) == expected)
        print("OURIN_BALLOON_INSTALL_PASS \(result.target.path) shared=\(shared.path) original-files=\(checked)")
    }

    private func withFixture(_ run: (GhostManager, URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-BalloonSelection-\(UUID().uuidString)")
        let oldBase = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = base
        defer { OurinPaths.testBaseOverride = oldBase; try? FileManager.default.removeItem(at: base) }
        let ghost = base.appendingPathComponent("ghost/example")
        try writeBalloon(name: "Local", directory: ghost.appendingPathComponent("balloon"))
        let suiteName = "Ourin.BalloonSelectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = GhostManager(ghostURL: ghost)
        manager.balloonSelectionDefaults = defaults
        defer { _ = manager.shutdown() }
        try run(manager, base)
    }
    @discardableResult private func writeBalloon(name: String, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "charset,UTF-8\nname,\(name)\n".write(to: directory.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        return directory
    }
    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
