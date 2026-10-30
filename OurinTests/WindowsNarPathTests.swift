import Foundation
import CryptoKit
import Testing
@testable import Ourin

struct WindowsNarPathTests {
    @Test(arguments: ["traversal", "collision"])
    func invalidWindowsPathsDoNotOverwriteExistingFiles(mode: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-InvalidWindowsNar-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"), output = root.appendingPathComponent("extract")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinel = root.appendingPathComponent("outside.txt")
        try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
        if mode == "traversal" {
            try "replace".write(to: source.appendingPathComponent("..\\outside.txt"), atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.createDirectory(at: source.appendingPathComponent("ghost"), withIntermediateDirectories: true)
            try "keep".write(to: source.appendingPathComponent("ghost/value.txt"), atomically: true, encoding: .utf8)
            try "replace".write(to: source.appendingPathComponent("ghost\\value.txt"), atomically: true, encoding: .utf8)
        }
        let archive = root.appendingPathComponent("invalid.nar")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", source.path, archive.path]; try zip.run(); zip.waitUntilExit()
        try #require(zip.terminationStatus == 0)
        #expect(throws: (any Error).self) { try ZipUtil.extractZip(archive, to: output) }
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        if mode == "collision" {
            #expect(try String(contentsOf: output.appendingPathComponent("ghost/value.txt"), encoding: .utf8) == "keep")
        }
    }

    @Test(arguments: [false, true]) func emptyWindowsRootMarkerDoesNotRemoveExtractedFiles(asFile: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-WindowsNar-\(UUID().uuidString)")
        let source = root.appendingPathComponent("source"), extract = root.appendingPathComponent("extract")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        if asFile { try Data().write(to: source.appendingPathComponent("\\")) }
        else { try FileManager.default.createDirectory(at: source.appendingPathComponent("\\"), withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        try "type,ghost\ndirectory,windows-path-test\n".write(to: source.appendingPathComponent("install.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("ghost\\master\\"), withIntermediateDirectories: true)
        try "name,original\n".write(to: source.appendingPathComponent("ghost\\master\\descript.txt"), atomically: true, encoding: .utf8)
        let nar = root.appendingPathComponent("sample.nar")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", source.path, nar.path]; try zip.run(); zip.waitUntilExit()
        try #require(zip.terminationStatus == 0)
        try ZipUtil.extractZip(nar, to: extract)
        #expect(try String(contentsOf: extract.appendingPathComponent("ghost/master/descript.txt"), encoding: .utf8) == "name,original\n")
        #expect(FileManager.default.fileExists(atPath: extract.appendingPathComponent("install.txt").path))
        #expect(!FileManager.default.fileExists(atPath: extract.appendingPathComponent("\\").path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OURIN_EMO_NAR"] != nil,
                   "Set TEST_RUNNER_OURIN_EMO_NAR to the pinned original emo-gs NAR"))
    func originalDistributionUsesProductionExtractAndManifestInspection() throws {
        let archive = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OURIN_EMO_NAR"]))
        let hash = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        try #require(hash == "9048182947acbdb917baf5a389bfd75118a7e587deecaca5863956757904b3d9")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-RealWindowsNar-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: output) }
        try ZipUtil.extractZip(archive, to: output)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("ghost/master/emo/shiori/init.lua").path))
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("emo-kakukaku/install.txt").path))
        let manifest = try NarInstaller().inspectManifest(fromNar: archive)
        #expect(manifest.type == "ghost")
        #expect(manifest.directory == "emo")
    }
}
