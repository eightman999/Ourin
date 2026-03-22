import Testing
import Foundation
@testable import Ourin

struct NarInstallTests {
    @Test
    func parseInstallTxt() throws {
        let raw = "type,ghost\ndirectory,foo"
        let manifest = try InstallTxtParser.parse(raw)
        #expect(manifest.type == "ghost")
        #expect(manifest.directory == "foo")
    }

    @Test
    func installUtf8Nar() throws {
        let nar = try makeSampleNar(encoding: .utf8, dirName: "sample1_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        let target = try installer.install(fromNar: nar)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func installSjisNar() throws {
        let sjisEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        let nar = try makeSampleNar(encoding: sjisEnc, dirName: "sample_sjis_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        let target = try installer.install(fromNar: nar)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func updateDescriptorParsesRelativeAndAbsoluteEntries() throws {
        let text = """
        ; comment
        patch1.nar,2026-01-01
        https://example.com/ghost/patch2.nar\u{0001}meta
        """
        let base = URL(string: "https://example.com/ghost/")!
        let urls = UpdateDescriptorParser.parse(text, baseURL: base)
        #expect(urls.contains(URL(string: "https://example.com/ghost/patch1.nar")!))
        #expect(urls.contains(URL(string: "https://example.com/ghost/patch2.nar")!))
    }

    @Test
    func deleteTxtRemovesLegacyFiles() throws {
        let nar = try makeSampleNar(encoding: .utf8, dirName: "sample_delete_\(UUID().uuidString)", withDeleteInstruction: true)
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        let target = try installer.install(fromNar: nar)
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("legacy.txt").path))
    }

    private func makeSampleNar(encoding: String.Encoding, dirName: String, withDeleteInstruction: Bool = false) throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let installText = "type,ghost\ndirectory,\(dirName)"
        let installURL = base.appendingPathComponent("install.txt")
        try installText.data(using: encoding)!.write(to: installURL)
        let readmeURL = base.appendingPathComponent("README.txt")
        try "sample".data(using: encoding)!.write(to: readmeURL)
        if withDeleteInstruction {
            let legacyURL = base.appendingPathComponent("legacy.txt")
            try "legacy".data(using: encoding)!.write(to: legacyURL)
            let deleteURL = base.appendingPathComponent("delete.txt")
            try "legacy.txt".data(using: encoding)!.write(to: deleteURL)
        }
        let nar = base.appendingPathComponent("sample.nar")
        let proc = Process()
        proc.currentDirectoryURL = base
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        var files = ["install.txt", "README.txt"]
        if withDeleteInstruction {
            files.append(contentsOf: ["legacy.txt", "delete.txt"])
        }
        proc.arguments = ["-q", nar.path] + files
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw NSError(domain: "zip", code: Int(proc.terminationStatus), userInfo: nil) }
        return nar
    }
}
