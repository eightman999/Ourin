// OurinTests/SaveShareManagerTests.swift
import Foundation
import Testing
@testable import Ourin

struct SaveShareManagerTests {

    private func makeTempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinSaveShareTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func exportImportRoundTrip() throws {
        let profile = try makeTempDir("profile")
        let outDir = try makeTempDir("out")

        // プロファイルに yaya_variable.cfg と save.dat を置く
        try Data("Yaya=value\r\nSecond=line\r\n".utf8).write(to: profile.appendingPathComponent("yaya_variable.cfg"))
        try Data("12345".utf8).write(to: profile.appendingPathComponent("save.dat"))

        let ssg = outDir.appendingPathComponent("ghost.ssg")
        let exported = try SaveShareManager.exportSSG(
            ghostName: "testghost",
            computerName: "my-mac",
            profileURL: profile,
            to: ssg
        )
        #expect(exported.contains("yaya_variable.cfg"))
        #expect(exported.contains("save.dat"))

        // 別ディレクトリへインポート
        let restore = try makeTempDir("restore")
        let restored = try SaveShareManager.importSSG(from: ssg, to: restore)
        #expect(restored.contains("yaya_variable.cfg"))
        #expect(restored.contains("save.dat"))

        let yaya = try String(contentsOf: restore.appendingPathComponent("yaya_variable.cfg"), encoding: .utf8)
        #expect(yaya == "Yaya=value\r\nSecond=line\r\n")
        let save = try String(contentsOf: restore.appendingPathComponent("save.dat"), encoding: .utf8)
        #expect(save == "12345")
    }

    @Test func binaryFileIsBase64Encoded() throws {
        let profile = try makeTempDir("profile")
        let outDir = try makeTempDir("out")

        // savedata.adb は BINARY。バイナリデータを置く。
        let binary = Data([0x00, 0x01, 0x02, 0xFF, 0xFE])
        try binary.write(to: profile.appendingPathComponent("savedata.adb"))

        let ssg = outDir.appendingPathComponent("bin.ssg")
        try SaveShareManager.exportSSG(
            ghostName: "g",
            computerName: "mac",
            profileURL: profile,
            to: ssg,
            includeFiles: ["savedata.adb"]
        )

        let raw = try Data(contentsOf: ssg)
        // ヘッダ + 圧縮データ。インポートすれば元のバイナリが復元される。
        #expect(raw.count > 0)

        let restore = try makeTempDir("restore")
        try SaveShareManager.importSSG(from: ssg, to: restore)
        let restored = try Data(contentsOf: restore.appendingPathComponent("savedata.adb"))
        #expect(restored == binary)
    }

    @Test func headerLayoutMatchesSSP() throws {
        let profile = try makeTempDir("profile")
        let outDir = try makeTempDir("out")
        try Data("x".utf8).write(to: profile.appendingPathComponent("save.dat"))

        let ssg = outDir.appendingPathComponent("hdr.ssg")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try SaveShareManager.exportSSG(
            ghostName: "g",
            computerName: "my-mac",
            profileURL: profile,
            to: ssg,
            includeFiles: ["save.dat"],
            timestamp: timestamp
        )

        let raw = try Data(contentsOf: ssg)
        // magic "SSZ\0"
        #expect(Array(raw[0..<4]) == [0x53, 0x53, 0x5A, 0x00])

        // FILETIME (1700000000 sec = 11644473600 + 1700000000 sec after 1601)
        let ft = SaveShareManager.fileTime(from: timestamp)
        #expect(raw[4] == UInt8(ft.low & 0xFF))
        #expect(raw[8] == UInt8(ft.high & 0xFF))

        // computerNameLen-1 = 6 ("my-mac")
        #expect(raw[12] == 6)

        // computerName
        #expect(String(decoding: raw[16..<22], as: UTF8.self) == "my-mac")

        // uncompressedSize (LE32 at 0x10 + 6 = 22)
        let s0 = UInt32(raw[22])
        let s1 = UInt32(raw[23]) << 8
        let s2 = UInt32(raw[24]) << 16
        let s3 = UInt32(raw[25]) << 24
        let sizeVal = s0 | s1 | s2 | s3
        // 本文は textHeader + ヘッダ行 + [FILE..] + footer。少なくとも textHeader 分はある。
        #expect(sizeVal > SaveShareManager.textHeader.utf8.count)

        // zlib データは offset 0x14 + 6 = 26 から
        #expect(raw.count > 26)
    }

    @Test func plainTextFallbackWhenNoMagic() throws {
        let outDir = try makeTempDir("out")
        let restore = try makeTempDir("restore")
        // magic なしのプレーンテキスト .ssg (SSP のフォールバック動作)
        let plain =
            "===SSP_SAVESHARE:1.0===\r\n" +
            "[TIMESTAMP:2023-11-14T22:13:20Z]\r\n" +
            "[GHOSTNAME:g]\r\n" +
            "[COMPUTERNAME:mac]\r\n" +
            "[FILE:save.dat]\r\n[SIZE:5]\r\n[TYPE:TEXT]\r\n" +
            "12345\r\n" +
            "[ENDFILE]\r\n" +
            "===SSP_SAVESHARE_END===\r\n"
        let ssg = outDir.appendingPathComponent("plain.ssg")
        try Data(plain.utf8).write(to: ssg)

        let restored = try SaveShareManager.importSSG(from: ssg, to: restore)
        #expect(restored == ["save.dat"])
        let save = try String(contentsOf: restore.appendingPathComponent("save.dat"), encoding: .utf8)
        #expect(save == "12345")
    }

    @Test func pathTraversalRejected() throws {
        let outDir = try makeTempDir("out")
        let restore = try makeTempDir("restore")
        let evil =
            "===SSP_SAVESHARE:1.0===\r\n" +
            "[FILE:../evil.dat]\r\n[SIZE:3]\r\n[TYPE:TEXT]\r\n" +
            "abc\r\n" +
            "[ENDFILE]\r\n" +
            "===SSP_SAVESHARE_END===\r\n"
        let ssg = outDir.appendingPathComponent("evil.ssg")
        try Data(evil.utf8).write(to: ssg)

        #expect(throws: SaveShareManager.SaveShareError.self) {
            try SaveShareManager.importSSG(from: ssg, to: restore)
        }
    }

    @Test func missingFilesAreSkipped() throws {
        let profile = try makeTempDir("profile")
        let outDir = try makeTempDir("out")
        // どのファイルも存在しない
        let ssg = outDir.appendingPathComponent("none.ssg")
        let exported = try SaveShareManager.exportSSG(
            ghostName: "g",
            computerName: "mac",
            profileURL: profile,
            to: ssg,
            includeFiles: ["yaya_variable.cfg", "save.dat"]
        )
        #expect(exported.isEmpty)

        // 空の .ssg でもヘッダは magic 付きで生成される
        let raw = try Data(contentsOf: ssg)
        #expect(Array(raw[0..<4]) == [0x53, 0x53, 0x5A, 0x00])

        // 往復 (空 → 復元も空)
        let restore = try makeTempDir("restore")
        let restored = try SaveShareManager.importSSG(from: ssg, to: restore)
        #expect(restored.isEmpty)
    }

    @Test func readHeaderParsesComputerName() throws {
        let profile = try makeTempDir("profile")
        let outDir = try makeTempDir("out")
        try Data("x".utf8).write(to: profile.appendingPathComponent("save.dat"))
        let ssg = outDir.appendingPathComponent("hdr2.ssg")
        try SaveShareManager.exportSSG(
            ghostName: "g",
            computerName: "MacBook-Pro.local",
            profileURL: profile,
            to: ssg
        )
        let raw = try Data(contentsOf: ssg)
        let header = try SaveShareManager.readHeader(raw)
        #expect(header.computerName == "MacBook-Pro.local")
    }
}