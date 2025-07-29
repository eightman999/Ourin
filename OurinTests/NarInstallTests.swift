import Testing
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
        let nar = try makeSampleNar(encoding: .utf8, dirName: "sample1")
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        try installer.install(fromNar: nar)
    }

    @Test
    func installSjisNar() throws {
        let sjisEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        let nar = try makeSampleNar(encoding: sjisEnc, dirName: "sample_sjis")
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        try installer.install(fromNar: nar)
    }

    private func makeSampleNar(encoding: String.Encoding, dirName: String) throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let installText = "type,ghost\ndirectory,\(dirName)"
        let installURL = base.appendingPathComponent("install.txt")
        try installText.data(using: encoding)!.write(to: installURL)
        let readmeURL = base.appendingPathComponent("README.txt")
        try "sample".data(using: encoding)!.write(to: readmeURL)
        let nar = base.appendingPathComponent("sample.nar")
        let proc = Process()
        proc.currentDirectoryURL = base
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.arguments = ["-q", nar.path, "install.txt", "README.txt"]
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw NSError(domain: "zip", code: Int(proc.terminationStatus), userInfo: nil) }
        return nar
    }
}
