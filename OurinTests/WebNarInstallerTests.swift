import Foundation
import Testing
@testable import Ourin

/// Web 経由（x-ukagaka-link:type=install）の NAR は、ユーザーが承認するまで設置しない。
struct WebNarInstallerTests {
    private func makeNar() throws -> (nar: URL, work: URL) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = work.appendingPathComponent("pkg", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("ghost/master"), withIntermediateDirectories: true)
        try "charset,UTF-8\r\ntype,ghost\r\nname,WebEvil\r\ndirectory,webevil_\(UUID().uuidString.prefix(8))\r\n"
            .write(to: root.appendingPathComponent("install.txt"), atomically: true, encoding: .utf8)
        try "charset,UTF-8\r\nname,WebEvil\r\n"
            .write(to: root.appendingPathComponent("ghost/master/descript.txt"), atomically: true, encoding: .utf8)

        let nar = work.appendingPathComponent("evil.nar")
        let zip = Process()
        zip.currentDirectoryURL = root
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", nar.path, "install.txt", "ghost"]
        try zip.run()
        zip.waitUntilExit()
        try #require(zip.terminationStatus == 0)
        return (nar, work)
    }

    @Test
    func declinedConfirmationDoesNotInstall() throws {
        let (nar, work) = try makeNar()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = try #require(URL(string: "https://mallory.example/evil.nar"))

        var shown: [WebNarInstaller.InstallConfirmation] = []
        var installed: [URL] = []
        let approved = try WebNarInstaller.installAfterConfirmation(
            archiveURL: nar,
            sourceURL: source,
            confirm: { shown.append($0); return false },
            install: { installed.append($0) }
        )

        #expect(!approved)
        #expect(installed.isEmpty)
        #expect(shown == [WebNarInstaller.InstallConfirmation(
            host: "mallory.example",
            name: "WebEvil",
            type: "ghost",
            url: "https://mallory.example/evil.nar"
        )])
    }

    @Test
    func approvedConfirmationInstallsOnce() throws {
        let (nar, work) = try makeNar()
        defer { try? FileManager.default.removeItem(at: work) }
        let source = try #require(URL(string: "https://example.com/good.nar"))

        var installed: [URL] = []
        let approved = try WebNarInstaller.installAfterConfirmation(
            archiveURL: nar,
            sourceURL: source,
            confirm: { _ in true },
            install: { installed.append($0) }
        )

        #expect(approved)
        #expect(installed == [nar])
    }

    @Test
    func invalidArchiveIsRejectedBeforeConfirmation() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let bogus = work.appendingPathComponent("bogus.nar")
        try Data("not a zip".utf8).write(to: bogus)

        var confirmed = false
        var installed = false
        #expect(throws: (any Error).self) {
            try WebNarInstaller.installAfterConfirmation(
                archiveURL: bogus,
                sourceURL: URL(string: "https://example.com/bogus.nar")!,
                confirm: { _ in confirmed = true; return true },
                install: { _ in installed = true }
            )
        }
        #expect(!confirmed)
        #expect(!installed)
    }
}
