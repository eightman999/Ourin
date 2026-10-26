import CryptoKit
import Foundation
import Testing
@testable import Ourin

struct AppUpdaterTests {
    @Test
    func versionsCompareNumerically() {
        #expect(AppVersion.compare("0.0.1.21", "0.0.1.9") == .orderedDescending)
        #expect(AppVersion.compare("0.0.2", "0.0.1.99") == .orderedDescending)
        #expect(AppVersion.compare("0.1", "0.1.0.0") == .orderedSame)
        #expect(AppVersion.compare("1.0.0", "1.0.1") == .orderedAscending)
    }

    @Test
    func githubReleaseSelectsAppArchiveAndChecksum() throws {
        let json = """
        {"tag_name":"v0.1.0-beta.1","draft":false,"prerelease":false,"body":"notes","html_url":"https://example.com/r",
         "assets":[
           {"name":"Ourin-Installer-0.1.0.zip","browser_download_url":"https://example.com/installer.zip"},
           {"name":"Ourin-0.1.0.zip","browser_download_url":"https://example.com/app.zip"},
           {"name":"Ourin-0.1.0.zip.sha256","browser_download_url":"https://example.com/app.zip.sha256"}]}
        """
        let release = try #require(AppUpdateRelease.parseGitHubRelease(Data(json.utf8)))
        #expect(release.version == "0.1.0")
        #expect(release.archiveURL.absoluteString == "https://example.com/app.zip")
        #expect(release.checksumURL?.absoluteString == "https://example.com/app.zip.sha256")
        #expect(release.notes == "notes")
    }

    @Test
    func prereleaseAndReleasesWithoutAppArchiveAreIgnored() {
        let pre = #"{"tag_name":"v9","prerelease":true,"assets":[{"name":"Ourin-9.zip","browser_download_url":"https://e/a"}]}"#
        #expect(AppUpdateRelease.parseGitHubRelease(Data(pre.utf8)) == nil)
        let noApp = #"{"tag_name":"v9","assets":[{"name":"Ourin-Installer-9.zip","browser_download_url":"https://e/a"}]}"#
        #expect(AppUpdateRelease.parseGitHubRelease(Data(noApp.utf8)) == nil)
    }

    @Test
    func checksumMustMatchShasumOutput() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-update-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("payload".utf8).write(to: file)
        let hex = SHA256.hash(data: Data("payload".utf8)).map { String(format: "%02x", $0) }.joined()
        try AppUpdateVerifier.verifyChecksum(fileURL: file, checksumText: "\(hex)  Ourin-1.zip\n")
        #expect(throws: (any Error).self) {
            try AppUpdateVerifier.verifyChecksum(fileURL: file, checksumText: String(repeating: "0", count: 64))
        }
    }

    @Test
    func unsignedBundleHasNoTeamAndFailsVerification() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-update-\(UUID().uuidString)", isDirectory: true)
        let app = dir.appendingPathComponent("Ourin.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let info: [String: Any] = ["CFBundleIdentifier": "furin-lab.Ourin", "CFBundleShortVersionString": "9.9"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Info.plist"))

        #expect(AppUpdateVerifier.teamIdentifier(of: dir.appendingPathComponent("Ourin.app")) == nil)
        #expect(throws: (any Error).self) {
            _ = try AppUpdateVerifier.verifiedApp(in: dir, expectedVersion: "9.9",
                                                  bundleIdentifier: "furin-lab.Ourin", teamIdentifier: "ST983BCMDG")
        }
        #expect(throws: (any Error).self) {
            _ = try AppUpdateVerifier.verifiedApp(in: dir, expectedVersion: "9.9",
                                                  bundleIdentifier: "other.app", teamIdentifier: "ST983BCMDG")
        }
    }
}
