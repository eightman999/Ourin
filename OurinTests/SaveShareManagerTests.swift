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

    // MARK: - 圧縮部の形式 (zlib = RFC 1950)

    /// SSP の SSGHeader (magic + FILETIME + 計算機名長 + 計算機名 + 非圧縮サイズ) に圧縮部をつなげる。
    private func makeSSG(body: String, computerName: String = "mac", payload: Data) -> Data {
        func le32(_ value: UInt32) -> [UInt8] {
            [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
        }
        var raw = Data(SaveShareManager.magic)
        raw.append(contentsOf: le32(0) + le32(0))
        raw.append(contentsOf: le32(UInt32(computerName.utf8.count)))
        raw.append(Data(computerName.utf8))
        raw.append(contentsOf: le32(UInt32(body.utf8.count)))
        raw.append(payload)
        return raw
    }

    /// 検算用の Adler-32 (RFC 1950)。本体の実装 (InternalCompression.adler32) とは別に持つ。
    private func referenceAdler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }

    private let sampleBody =
        "===SSP_SAVESHARE:1.0===\r\n" +
        "[TIMESTAMP:2023-11-14T22:13:20Z]\r\n" +
        "[GHOSTNAME:g]\r\n" +
        "[COMPUTERNAME:mac]\r\n" +
        "[FILE:save.dat]\r\n[SIZE:5]\r\n[TYPE:TEXT]\r\n" +
        "12345\r\n" +
        "[ENDFILE]\r\n" +
        "===SSP_SAVESHARE_END===\r\n"

    @Test func exportedPayloadIsZlibWithAdler32() throws {
        // 検算用の Adler-32 自体の確認 (Wikipedia の例)。
        #expect(referenceAdler32(Data("Wikipedia".utf8)) == 0x11E60398)

        let profile = try makeTempDir("profile")
        let outDir = try makeTempDir("out")
        try Data("12345".utf8).write(to: profile.appendingPathComponent("save.dat"))

        let ssg = outDir.appendingPathComponent("zlib.ssg")
        try SaveShareManager.exportSSG(
            ghostName: "g",
            computerName: "my-mac",
            profileURL: profile,
            to: ssg,
            includeFiles: ["save.dat"]
        )

        let raw = try Data(contentsOf: ssg)
        // 圧縮部は offset 0x14 + 計算機名の長さ (6) から。
        let payload = Data(raw.dropFirst(0x14 + 6))
        #expect(payload.count > 6)

        // zlib ヘッダ: CMF の下位 4bit が 8 (deflate)、(CMF*256+FLG) が 31 の倍数。SSP の compress2 level -1 は 78 9C。
        #expect(payload[0] == 0x78)
        #expect(payload[1] == 0x9C)
        #expect(payload[0] & 0x0F == 8)
        #expect((Int(payload[0]) * 256 + Int(payload[1])) % 31 == 0)

        // ヘッダと末尾 4 バイト (Adler-32、ビッグエンディアン) を外すと生 deflate になり、展開結果の Adler-32 が末尾と合う。
        let deflated = Data(payload.dropFirst(2).dropLast(4))
        let inflated = try (deflated as NSData).decompressed(using: .zlib) as Data
        let trailer = payload.suffix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        #expect(trailer == referenceAdler32(inflated))
        #expect(trailer == InternalCompression.adler32(inflated))

        // 展開結果は本文で、ヘッダの非圧縮サイズとも一致する。
        let body = String(decoding: inflated, as: UTF8.self)
        #expect(body.hasPrefix(SaveShareManager.textHeader))
        let header = try SaveShareManager.readHeader(raw)
        let sizeOffset = 0x10 + header.nameByteLength
        var storedSize = 0
        for i in 0..<4 { storedSize |= Int(raw[sizeOffset + i]) << (8 * i) }
        #expect(storedSize == inflated.count)
    }

    @Test func zlibStreamFromReferenceImplementationIsImportable() throws {
        // Python の zlib.compress(body, -1) (= compress2 level -1 と同じ zlib 形式) で作った実データ。
        let zlibPayload = Data([
            0x78, 0x9C, 0x5D, 0xCE, 0xC1, 0x0A, 0xC2, 0x30, 0x0C, 0x06, 0xE0, 0xBB, 0xE0, 0xA3, 0x6C, 0xAC,
            0xED, 0x76, 0x09, 0xE4, 0x50, 0x34, 0xBA, 0x82, 0xDD, 0xCA, 0x12, 0xC5, 0x4D, 0x64, 0x14, 0x15,
            0x4F, 0x9E, 0x14, 0x9F, 0xDF, 0x76, 0x47, 0x6F, 0xF9, 0xBF, 0x24, 0xF0, 0x23, 0x22, 0x73, 0x98,
            0xD9, 0x9E, 0x88, 0x5B, 0x3B, 0x10, 0xA8, 0xB2, 0x42, 0xC4, 0xF5, 0xEA, 0x22, 0xCE, 0x13, 0x8B,
            0xF5, 0x01, 0x74, 0xA5, 0x4D, 0xA1, 0x54, 0xA1, 0x6A, 0xD1, 0x1A, 0x94, 0x49, 0x30, 0x5D, 0xD3,
            0xC5, 0xBE, 0xED, 0x59, 0x3A, 0xEB, 0x09, 0x9E, 0x39, 0x6E, 0x7A, 0x1F, 0x8E, 0x42, 0xC3, 0x22,
            0xAF, 0x78, 0xCB, 0xB6, 0x73, 0x07, 0x82, 0x77, 0xFC, 0x3E, 0xCA, 0x7B, 0xFC, 0x64, 0x60, 0x37,
            0x11, 0x34, 0x79, 0x92, 0x31, 0x10, 0x08, 0x9D, 0x25, 0x05, 0xA5, 0x4D, 0xDD, 0x24, 0xA3, 0x6E,
            0x9B, 0x3F, 0x92, 0xE0, 0x5F, 0xAF, 0x39, 0xAD, 0x96, 0x5E, 0x3F, 0xFC, 0xEF, 0x2D, 0xED,
        ])
        // 末尾 4 バイトは本文の Adler-32 (0xFCEF2DED)。
        #expect(referenceAdler32(Data(sampleBody.utf8)) == 0xFCEF_2DED)

        let outDir = try makeTempDir("out")
        let restore = try makeTempDir("restore")
        let ssg = outDir.appendingPathComponent("ssp-like.ssg")
        try makeSSG(body: sampleBody, payload: zlibPayload).write(to: ssg)

        let restored = try SaveShareManager.importSSG(from: ssg, to: restore)
        #expect(restored == ["save.dat"])
        let save = try String(contentsOf: restore.appendingPathComponent("save.dat"), encoding: .utf8)
        #expect(save == "12345")
    }

    @Test func legacyRawDeflatePayloadIsStillImportable() throws {
        // 旧 Ourin は COMPRESSION_ZLIB の出力 (ヘッダも Adler-32 も無い生 deflate) をそのまま書いていた。
        let rawDeflate = try (Data(sampleBody.utf8) as NSData).compressed(using: .zlib) as Data

        let outDir = try makeTempDir("out")
        let restore = try makeTempDir("restore")
        let ssg = outDir.appendingPathComponent("legacy.ssg")
        try makeSSG(body: sampleBody, payload: rawDeflate).write(to: ssg)

        let restored = try SaveShareManager.importSSG(from: ssg, to: restore)
        #expect(restored == ["save.dat"])
        let save = try String(contentsOf: restore.appendingPathComponent("save.dat"), encoding: .utf8)
        #expect(save == "12345")
    }

    @Test func corruptedAdler32IsRejected() throws {
        let profile = try makeTempDir("profile")
        let outDir = try makeTempDir("out")
        try Data("12345".utf8).write(to: profile.appendingPathComponent("save.dat"))
        let ssg = outDir.appendingPathComponent("corrupt.ssg")
        try SaveShareManager.exportSSG(
            ghostName: "g",
            computerName: "mac",
            profileURL: profile,
            to: ssg,
            includeFiles: ["save.dat"]
        )

        // 末尾 (Adler-32 の最終バイト) を壊す。
        var raw = try Data(contentsOf: ssg)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: ssg)

        let restore = try makeTempDir("restore")
        #expect(throws: SaveShareManager.SaveShareError.self) {
            try SaveShareManager.importSSG(from: ssg, to: restore)
        }
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