import Foundation
import Testing
@testable import Ourin

struct BalloonTests {
    @Test func descriptorOverlay() async throws {
        let dir = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let desc = try DescriptorLoader.load(from: dir)
        #expect(desc["foo"] == "baz")
    }

    @Test func descriptorCharsetTwoPassShiftJIS() async throws {
        // charset,Shift_JIS 宣言付きの descript.txt を Shift_JIS で書き出し、
        // 宣言エンコーディングで正しく再デコードされることを検証する（二段読み）。
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = "charset,Shift_JIS\nname,テストバルーン\n"
        let sjisEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        let sjisData = body.data(using: sjisEncoding) ?? Data()
        try sjisData.write(to: dir.appendingPathComponent("descript.txt"))
        let desc = try DescriptorLoader.load(from: dir)
        #expect(desc["name"] == "テストバルーン")
    }

    @Test func icoDecode() async throws {
        // 1x1px の最小 ICO ファイルをバイト列として埋め込む
        let bytes: [UInt8] = [
            0x00,0x00,0x01,0x00,0x01,0x00,0x01,0x01,0x00,0x00,0x01,0x00,0x20,0x00,0x30,0x00,
            0x00,0x00,0x16,0x00,0x00,0x00,0x28,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x02,0x00,
            0x00,0x00,0x01,0x00,0x20,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0xff,0xff,0x00,0x00,0x00,0x00
        ]
        let data = Data(bytes)
        // 一時ファイルに書き出して ImageLoader をテスト
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.ico")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let img = try ImageLoader.load(url: tmp)
        #expect(img.width == 1)
        #expect(img.height == 1)
    }
}
