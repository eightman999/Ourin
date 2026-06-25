import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct OurinMigratorTests {
    // MARK: - LegacyAssetScanner

    @Test
    func classifiesPE32BinaryFromHeader() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigratorTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let dllURL = dir.appendingPathComponent("test.dll")
        try Self.minimalPE32DLL().write(to: dllURL)

        let kind = LegacyAssetScanner.classifyBinary(at: dllURL)
        #expect(kind == .pe32)
    }

    @Test
    func classifiesNonPEAsUnknown() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigratorTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("notpe.bin")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url)
        #expect(LegacyAssetScanner.classifyBinary(at: url) == .unknown)
    }

    @Test
    func scansPluginDirectoryAndReadsDescriptor() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigratorScan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let pluginDir = base.appendingPathComponent("plugin/shared_value", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        try """
        Charset,UTF-8
        name,共有変数プラグイン
        filename,shared_value.dll
        id,ABED14AF-F34B-4ff2-95B7-30ED37D5802D
        """.write(to: pluginDir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try Self.minimalPE32DLL().write(to: pluginDir.appendingPathComponent("shared_value.dll"))

        let roots: [(URL, LegacyAssetScanner.ScanRootKind)] = [
            (base.appendingPathComponent("plugin"), .plugin)
        ]
        let assets = LegacyAssetScanner.scan(roots: roots)

        #expect(assets.count == 1)
        let asset = try #require(assets.first)
        #expect(asset.kind == .plugin)
        #expect(asset.binaryKind == .pe32)
        #expect(asset.filename == "shared_value.dll")
        #expect(asset.sspID == "ABED14AF-F34B-4ff2-95B7-30ED37D5802D")
        #expect(asset.name == "共有変数プラグイン")
        #expect(asset.status == .metadataOnly)
    }

    @Test
    func scanRootsCoverAllTargets() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigratorRoots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let roots = LegacyAssetScanner.defaultScanRoots(baseDirectory: base)
        #expect(roots.count == 4)
        let names = roots.map { $0.1.subfolderName }
        #expect(names.contains("plugin"))
        #expect(names.contains("calendar/plugin"))
        #expect(names.contains("headline"))
        #expect(names.contains("data"))
    }

    // MARK: - OurinManifest

    @Test
    func knownBuiltinMappingResolvesSharedValue() {
        #expect(OurinManifest.builtinImplementation(for: "shared_value.dll") == "builtin:shared_value")
        #expect(OurinManifest.builtinImplementation(for: "SHARED_VALUE.DLL") == "builtin:shared_value")
        #expect(OurinManifest.isKnownBuiltin("SAKNIFE.DLL"))
        #expect(OurinManifest.builtinImplementation(for: "SSPH.exe") == "builtin:ssph_compat")
    }

    @Test
    func recommendedModeSuggestsNativeReplacementForKnownDLL() {
        let (mode, impl) = OurinManifest.recommendedMode(for: "shared_value.dll")
        #expect(mode == .nativeReplacement)
        #expect(impl == "builtin:shared_value")
    }

    @Test
    func recommendedModeSuggestsScaffoldForUnknownDLL() {
        let (mode, impl) = OurinManifest.recommendedMode(for: "mystery.dll")
        #expect(mode == .scaffold)
        #expect(impl == nil)
    }

    @Test
    func manifestRoundTripsThroughJSON() throws {
        let manifest = OurinManifest(
            source: OurinManifest.Source(filename: "x.dll", kind: "pe32-dll", sspPluginId: "GUID"),
            mode: .nativeReplacement,
            implementation: "builtin:shared_value",
            analysis: OurinManifest.AnalysisRef(
                decompiled: "ourin/analysis/decompiled.c",
                report: "ourin/analysis/report.md"
            )
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigratorJSON-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("ourin.json")
        try manifest.write(to: url)

        let read = try #require(OurinManifest.read(from: url))
        #expect(read.format == "ourin-migration-1")
        #expect(read.source.filename == "x.dll")
        #expect(read.source.kind == "pe32-dll")
        #expect(read.source.sspPluginId == "GUID")
        #expect(read.mode == .nativeReplacement)
        #expect(read.implementation == "builtin:shared_value")
        #expect(read.analysis?.report == "ourin/analysis/report.md")
    }

    @Test
    func manifestReadReturnsNilForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        #expect(OurinManifest.read(from: url) == nil)
    }

    // MARK: - PluginScaffolder

    @Test
    func scaffoldGeneratesPluginBundleStructure() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigratorScaffold-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        Charset,UTF-8
        name,Test Plugin
        filename,mystery.dll
        id,test-id
        """.write(to: dir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try "ReadMe for mystery".write(to: dir.appendingPathComponent("ReadMe.txt"), atomically: true, encoding: .utf8)

        let asset = LegacyAssetScanner.Asset(
            id: "test",
            name: "Test Plugin",
            kind: .plugin,
            binaryKind: .pe32,
            filename: "mystery.dll",
            binaryURL: dir.appendingPathComponent("mystery.dll"),
            directoryURL: dir,
            descriptor: ["name": "Test Plugin", "filename": "mystery.dll"],
            existingManifest: nil,
            status: .metadataOnly
        )

        let result = try #require(PluginScaffolder.scaffold(for: asset))
        #expect(result.overwritten == false)

        // *_mac/ 標準形の検証
        let pkg = result.packageURL
        #expect(pkg.lastPathComponent.hasSuffix("_mac"))
        #expect(FileManager.default.fileExists(atPath: pkg.appendingPathComponent("descript.txt").path))
        #expect(FileManager.default.fileExists(atPath: pkg.appendingPathComponent("install.txt").path))
        #expect(FileManager.default.fileExists(atPath: pkg.appendingPathComponent("README.md").path))
        // .plugin bundle
        #expect(FileManager.default.fileExists(atPath: result.pluginURL.appendingPathComponent("Contents/Info.plist").path))
        #expect(FileManager.default.fileExists(atPath: result.pluginURL.appendingPathComponent("Contents/Resources/ourin.json").path))
        #expect(FileManager.default.fileExists(atPath: result.pluginURL.appendingPathComponent("Contents/Resources/descript.txt").path))
        // Sources/
        #expect(FileManager.default.fileExists(atPath: pkg.appendingPathComponent("Sources").path))
        // OriginalDocs/ に ReadMe.txt がコピーされている
        #expect(FileManager.default.fileExists(atPath: pkg.appendingPathComponent("OriginalDocs/ReadMe.txt").path))

        let manifest = try #require(OurinManifest.read(from: result.manifestURL))
        #expect(manifest.mode == .scaffold)

        // 既存がある場合は force なしで nil を返す
        #expect(PluginScaffolder.scaffold(for: asset, force: false) == nil)
        // force ありで上書き
        let forced = try #require(PluginScaffolder.scaffold(for: asset, force: true))
        #expect(forced.overwritten == true)
    }

    // MARK: - MigrationReport

    @Test
    func reportRendersSummaryAndTODOs() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinMigratorReport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let asset = LegacyAssetScanner.Asset(
            id: "sv",
            name: "Shared Value",
            kind: .plugin,
            binaryKind: .pe32,
            filename: "shared_value.dll",
            binaryURL: nil,
            directoryURL: dir,
            descriptor: ["name": "Shared Value", "id": "GUID"],
            existingManifest: nil,
            status: .metadataOnly
        )

        let content = MigrationReport.render(asset: asset,
                                             analysisDirectory: dir,
                                             manifest: nil,
                                             ghidraDurationSeconds: 12.3)
        #expect(content.contains("# Migration Report: Shared Value"))
        #expect(content.contains("PE32"))
        #expect(content.contains("native-replacement"))
        #expect(content.contains("builtin:shared_value"))
        #expect(content.contains("## Implementation TODO"))
        #expect(content.contains("OnBoot"))
    }

    // MARK: - Helpers

    /// 最小の PE32 DLL バイナリを生成（MZ + e_lfanew + PE sig + COFF + Optional magic）。
    private static func minimalPE32DLL() -> Data {
        var data = Data(count: 0x200)
        // MZ header
        data[0] = 0x4D; data[1] = 0x5A
        // e_lfanew @ 0x3C -> points to 0x80
        let lfanew: UInt32 = 0x80
        data.replaceSubrange(0x3C..<0x40, with: withUnsafeBytes(of: lfanew.littleEndian) { Data($0) })
        // PE\0\0 @ 0x80
        data[0x80] = 0x50; data[0x81] = 0x45; data[0x82] = 0x00; data[0x83] = 0x00
        // COFF Machine = IMAGE_FILE_MACHINE_I386 (0x014C) @ 0x84
        let machine: UInt16 = 0x014C
        data.replaceSubrange(0x84..<0x86, with: withUnsafeBytes(of: machine.littleEndian) { Data($0) })
        // Optional Header Magic = 0x10B (PE32) @ lfanew+24 = 0x80+24 = 0x98
        let magic: UInt16 = 0x10B
        data.replaceSubrange(0x98..<0x9A, with: withUnsafeBytes(of: magic.littleEndian) { Data($0) })
        return data
    }
}
