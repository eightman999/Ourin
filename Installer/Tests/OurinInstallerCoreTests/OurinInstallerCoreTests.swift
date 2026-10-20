import XCTest
@testable import OurinInstallerCore

final class OurinInstallerCoreTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("OurinInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    // MARK: - helpers

    private func write(_ text: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(text.data(using: encoding)).write(to: url)
    }

    /// SSP 形式のフォルダを作る。
    private func makeSSP(at root: URL) throws {
        try write("", to: root.appendingPathComponent("ssp.exe"))
        try write("charset,Shift_JIS\nname,さくら\nshiori,yaya.dll\n",
                  to: root.appendingPathComponent("ghost/sakura/ghost/master/descript.txt"),
                  encoding: DescriptReader.cp932)
        try write("name,里々ゴースト\nshiori,satori.dll\n",
                  to: root.appendingPathComponent("ghost/satorighost/ghost/master/descript.txt"))
        try write("name,華和梨\nshiori,shiori.dll\n",
                  to: root.appendingPathComponent("ghost/kawari/ghost/master/descript.txt"))
        try write("name,既定\n", to: root.appendingPathComponent("ghost/noshiori/ghost/master/descript.txt"))
        try write("name,バルーン\n", to: root.appendingPathComponent("balloon/simple/descript.txt"))
        // descript.txt の無いフォルダは移行対象に出さない。
        try fm.createDirectory(at: root.appendingPathComponent("ghost/broken"), withIntermediateDirectories: true)
    }

    private func makeApp(at url: URL, version: String) throws {
        try write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>\(version)</string></dict></plist>
        """, to: url.appendingPathComponent("Contents/Info.plist"))
    }

    // MARK: - DescriptReader

    func testDescriptReaderDecodesDeclaredShiftJIS() throws {
        let data = try XCTUnwrap("charset,Shift_JIS\r\nname,さくら\r\n".data(using: DescriptReader.cp932))
        XCTAssertEqual(DescriptReader.parse(data)["name"], "さくら")
    }

    func testDescriptReaderFallsBackToShiftJISWithoutDeclaration() throws {
        let data = try XCTUnwrap("name,まゆら\n".data(using: DescriptReader.cp932))
        XCTAssertEqual(DescriptReader.parse(data)["name"], "まゆら")
    }

    func testDescriptReaderKeepsFirstValueAndSkipsComments() {
        let parsed = DescriptReader.parse(Data("// comment\nName,a\nname,b\n".utf8))
        XCTAssertEqual(parsed["name"], "a")
    }

    // MARK: - SSPScanner

    func testScannerListsGhostsAndBalloonsWithCompatibility() throws {
        let root = tmp.appendingPathComponent("SSP")
        try makeSSP(at: root)
        let items = SSPScanner.scan(root: root)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        XCTAssertEqual(Set(byID.keys), ["ghost/sakura", "ghost/satorighost", "ghost/kawari", "ghost/noshiori", "balloon/simple"])
        XCTAssertEqual(byID["ghost/sakura"]?.name, "さくら")
        XCTAssertEqual(byID["ghost/sakura"]?.compatibility, .supported("YAYA"))
        XCTAssertEqual(byID["ghost/satorighost"]?.compatibility, .supported("里々"))
        XCTAssertEqual(byID["ghost/kawari"]?.compatibility, .windowsShiori("shiori.dll"))
        // shiori 未指定は本体と同じく yaya.dll 扱い。
        XCTAssertEqual(byID["ghost/noshiori"]?.compatibility, .supported("YAYA"))
        XCTAssertEqual(byID["balloon/simple"]?.compatibility, .notApplicable)
    }

    // MARK: - SSPLocator

    func testLocatorFindsSSPInWineAndCrossOverBottles() throws {
        let home = tmp.appendingPathComponent("home")
        try makeSSP(at: home.appendingPathComponent(".wine/drive_c/Program Files/SSP"))
        try makeSSP(at: home.appendingPathComponent("Library/Application Support/CrossOver/Bottles/ukagaka/drive_c/users/me/Desktop/ssp"))
        // ssp.exe の無い ghost フォルダは SSP とみなさない。
        try fm.createDirectory(at: home.appendingPathComponent(".wine/drive_c/other/ghost"), withIntermediateDirectories: true)

        let found = SSPLocator(home: home).locate()
        XCTAssertEqual(found.map(\.root.lastPathComponent), ["SSP", "ssp"])
        XCTAssertEqual(found.map(\.source), ["Wine", "CrossOver（ukagaka）"])
    }

    func testLocatorDoesNotFollowSymlinks() throws {
        let home = tmp.appendingPathComponent("home")
        let drive = home.appendingPathComponent(".wine/drive_c")
        try fm.createDirectory(at: drive, withIntermediateDirectories: true)
        try makeSSP(at: tmp.appendingPathComponent("outside/SSP"))
        try fm.createSymbolicLink(at: drive.appendingPathComponent("link"), withDestinationURL: tmp.appendingPathComponent("outside"))
        XCTAssertTrue(SSPLocator(home: home).locate().isEmpty)
    }

    // MARK: - DataMigrator

    func testMigratorCopiesAndSkipsExistingWithoutTouchingSource() throws {
        let root = tmp.appendingPathComponent("SSP")
        try makeSSP(at: root)
        let location = OurinDataLocation(base: tmp.appendingPathComponent("Ourin"))
        try write("name,既存\n", to: location.ghostDirectory.appendingPathComponent("sakura/ghost/master/descript.txt"))

        let items = SSPScanner.scan(root: root).filter { ["ghost/sakura", "ghost/kawari", "balloon/simple"].contains($0.id) }
        let results = DataMigrator(location: location).migrate(items)
        let outcomes = Dictionary(uniqueKeysWithValues: results.map { ($0.item.id, $0.outcome) })

        XCTAssertEqual(outcomes["ghost/sakura"], .skippedExisting(location.ghostDirectory.appendingPathComponent("sakura", isDirectory: true)))
        XCTAssertEqual(outcomes["ghost/kawari"], .copied(location.ghostDirectory.appendingPathComponent("kawari", isDirectory: true)))
        XCTAssertEqual(outcomes["balloon/simple"], .copied(location.balloonDirectory.appendingPathComponent("simple", isDirectory: true)))

        // 既存は上書きしない。元データは残る。
        let existing = DescriptReader.read(location.ghostDirectory.appendingPathComponent("sakura/ghost/master/descript.txt"))
        XCTAssertEqual(existing?["name"], "既存")
        XCTAssertTrue(fm.fileExists(atPath: root.appendingPathComponent("ghost/kawari/ghost/master/descript.txt").path))
        XCTAssertEqual(location.installedGhostDirectories(), ["kawari", "sakura"])
        // 一時フォルダを残さない。
        let leftovers = try fm.contentsOfDirectory(atPath: location.ghostDirectory.path).filter { $0.contains("ourin-migrating") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    // MARK: - AppInstaller

    func testInstallerPlacesAppAndReplacesExisting() throws {
        let payload = tmp.appendingPathComponent("payload/Ourin.app")
        try makeApp(at: payload, version: "2.0")
        let apps = tmp.appendingPathComponent("Applications")
        try makeApp(at: apps.appendingPathComponent("Ourin.app"), version: "1.0")
        try write("old", to: apps.appendingPathComponent("Ourin.app/Contents/old.txt"))

        let installer = AppInstaller(payload: payload)
        XCTAssertEqual(installer.installedVersion(in: apps), "1.0")
        XCTAssertEqual(installer.payloadVersion, "2.0")

        let target = try installer.install(into: apps)
        XCTAssertEqual(AppInstaller.bundleVersion(at: target), "2.0")
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("Contents/old.txt").path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: apps.path), ["Ourin.app"])
        // 同梱元は残る。
        XCTAssertTrue(fm.fileExists(atPath: payload.path))
    }

    func testInstallerRejectsMissingPayload() {
        let installer = AppInstaller(payload: tmp.appendingPathComponent("none/Ourin.app"))
        XCTAssertThrowsError(try installer.install(into: tmp)) { error in
            XCTAssertEqual(error as? AppInstaller.InstallError, .payloadMissing(tmp.appendingPathComponent("none/Ourin.app").path))
        }
    }

    func testInstallerReportsUnwritableDirectory() throws {
        let payload = tmp.appendingPathComponent("payload/Ourin.app")
        try makeApp(at: payload, version: "2.0")
        let locked = tmp.appendingPathComponent("locked")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let installer = AppInstaller(payload: payload)
        XCTAssertFalse(installer.canWrite(to: locked))
        XCTAssertThrowsError(try installer.install(into: locked)) { error in
            XCTAssertEqual(error as? AppInstaller.InstallError, .notWritable(locked.path))
        }
    }

    func testPrivilegedScriptQuotesPathsAndInstalls() throws {
        let payload = tmp.appendingPathComponent("pay'load/Ourin.app")
        try makeApp(at: payload, version: "3.0")
        let apps = tmp.appendingPathComponent("Apps with space")
        try makeApp(at: apps.appendingPathComponent("Ourin.app"), version: "1.0")

        // 権限昇格せずに同じスクリプトを実行し、引用と差し替え手順を確認する。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", AppInstaller(payload: payload).privilegedInstallScript(into: apps)]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(AppInstaller.bundleVersion(at: apps.appendingPathComponent("Ourin.app")), "3.0")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: apps.path), ["Ourin.app"])
    }

    // MARK: - OurinPreferences

    func testPreferencesWriteStartupGhost() throws {
        let suite = "jp.ourin.installer.tests.\(UUID().uuidString)"
        let prefs = try XCTUnwrap(OurinPreferences(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        prefs.setStartupGhost("sakura")
        XCTAssertEqual(UserDefaults(suiteName: suite)?.string(forKey: OurinPreferences.startupGhostKey), "sakura")
        prefs.setStartupGhost(nil)
        XCTAssertNil(prefs.startupGhost)
    }
}
