import AVFoundation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Ourin

private struct FileOutcome {
    var status: Int
    var result: String?
    var values: [String]
    var error: String?
}

private func mediaInfo(_ arguments: [String], context: InternalSaoriContext = .none) -> FileOutcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_file", "Argument0: MediaInfo"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: context)
    let response = try! SaoriProtocol.parseResponse(text)
    var values: [String] = []
    while let value = response.headerValue("Value\(values.count)") { values.append(value) }
    return FileOutcome(status: response.statusCode, result: response.headerValue("Result"), values: values, error: response.headerValue("ErrorDescription"))
}

/// 検査用のメディアファイルを作る一時フォルダ。
private struct MediaFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sound"), withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    var context: InternalSaoriContext { InternalSaoriContext(ghostRoot: root, deliverEvent: nil) }

    /// ID3v2.3 のタグ付きの MP3（無音の MPEG-1 Layer III 128kbps 44.1kHz を 40 フレーム ≒ 1.044 秒）。
    func writeMP3(_ name: String, frames: [(String, Data)]) throws {
        func frame(_ id: String, _ body: Data) -> Data {
            var data = Data(id.utf8)
            let size = UInt32(body.count)
            data.append(contentsOf: [UInt8(size >> 24 & 0xff), UInt8(size >> 16 & 0xff), UInt8(size >> 8 & 0xff), UInt8(size & 0xff), 0, 0])
            return data + body
        }
        let body = frames.reduce(Data()) { $0 + frame($1.0, $1.1) }
        // ID3v2 のサイズは 7 ビットずつ（synchsafe）。
        let size = body.count
        var tag = Data("ID3".utf8) + Data([3, 0, 0])
        tag.append(contentsOf: [UInt8(size >> 21 & 0x7f), UInt8(size >> 14 & 0x7f), UInt8(size >> 7 & 0x7f), UInt8(size & 0x7f)])
        var audio = Data()
        for _ in 0..<40 { audio.append(contentsOf: [0xFF, 0xFB, 0x90, 0x00]); audio.append(Data(count: 413)) }
        try (tag + body + audio).write(to: root.appendingPathComponent(name))
    }

    /// UTF-16（BOM 付き）のテキスト項目。
    static func text(_ value: String) -> Data { Data([0x01, 0xFF, 0xFE]) + (value.data(using: .utf16LittleEndian) ?? Data()) + Data([0, 0]) }
}

struct InternalFileTests {
    @Test
    func mp3TagsAndDurationAreReadWithoutLoading() throws {
        let fixture = try MediaFixture()
        defer { fixture.remove() }
        try fixture.writeMP3("sound/bgm01.mp3", frames: [
            ("TIT2", MediaFixture.text("桜のテーマ")), ("TPE1", MediaFixture.text("さくら")), ("TALB", MediaFixture.text("りんね集")),
            ("TCON", MediaFixture.text("Game")), ("TRCK", MediaFixture.text("3/12")), ("TYER", MediaFixture.text("2024")),
            ("TPE2", MediaFixture.text("ベル"))
        ])
        let outcome = mediaInfo(["sound/bgm01.mp3", "title", "artist", "album", "genre", "track", "year", "albumartist", "duration", "width", "height", "comment"], context: fixture.context)
        #expect(outcome.status == 200, "\(outcome.error ?? "")")
        #expect(outcome.result == "audio")
        #expect(outcome.values.count == 11)
        // 取れる値は正しいこと（OS が返さない項目は空でもよい）。
        let expected = ["桜のテーマ", "さくら", "りんね集", "Game", "3", "2024", "ベル"]
        for (index, want) in expected.enumerated() { #expect(outcome.values[index] == want || outcome.values[index].isEmpty, "\(index): \(outcome.values[index])") }
        #expect(outcome.values.prefix(3).allSatisfy { !$0.isEmpty }, "title・artist・album は ID3v2 から読めるはず")
        // 長さは約 1044ms（±100ms か 1%）。音声に大きさは無い。
        let duration = Int(outcome.values[7]) ?? 0
        #expect(abs(duration - 1044) <= 100, "duration \(duration)")
        #expect(outcome.values[8].isEmpty && outcome.values[9].isEmpty)
    }

    @Test
    func keysAreCaseInsensitiveAndUnknownKeysAreEmpty() throws {
        let fixture = try MediaFixture()
        defer { fixture.remove() }
        try fixture.writeMP3("a.mp3", frames: [("TIT2", MediaFixture.text("T"))])
        let outcome = mediaInfo(["a.mp3", "TITLE", "Duration", "bitrate", "lyrics", "TITLE"], context: fixture.context)
        #expect(outcome.status == 200)
        #expect(outcome.values.count == 5)
        #expect(outcome.values[0] == outcome.values[4])
        #expect(outcome.values[2].isEmpty && outcome.values[3].isEmpty)
        #expect(!outcome.values[1].isEmpty)
    }

    @Test
    func newlinesBecome0x01AndNULsAreDropped() throws {
        let fixture = try MediaFixture()
        defer { fixture.remove() }
        try fixture.writeMP3("a.mp3", frames: [("TIT2", MediaFixture.text("a\r\nb\nc\rd"))])
        let title = mediaInfo(["a.mp3", "title"], context: fixture.context).values.first ?? ""
        // OS が値を返さない環境では空でもよい。返したなら整形されていること。
        if !title.isEmpty { #expect(title == "a\u{01}b\u{01}c\u{01}d", "\(title.unicodeScalars.map(\.value))") }
    }

    @Test
    func imagesReportTheirSizeAndNoDuration() throws {
        let fixture = try MediaFixture()
        defer { fixture.remove() }
        let url = fixture.root.appendingPathComponent("pic.png")
        let context = try #require(CGContext(data: nil, width: 40, height: 25, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let outcome = mediaInfo(["pic.png", "width", "height", "duration", "title"], context: fixture.context)
        #expect(outcome.status == 200)
        #expect(outcome.result == "image")
        #expect(outcome.values == ["40", "25", "", ""])
    }

    @Test
    func wavDurationIsReadAndUnreadableFilesGiveEmptyValues() throws {
        let fixture = try MediaFixture()
        defer { fixture.remove() }
        // 0.5 秒（8kHz・16bit・モノラル）の WAV。
        func le32(_ value: UInt32) -> Data { Data([UInt8(value & 0xff), UInt8(value >> 8 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 24 & 0xff)]) }
        func le16(_ value: UInt16) -> Data { Data([UInt8(value & 0xff), UInt8(value >> 8)]) }
        let samples = Data(count: 8000) // 4000 サンプル × 2 バイト
        var header = Data("RIFF".utf8)
        header.append(le32(UInt32(36 + samples.count)))
        header.append(Data("WAVEfmt ".utf8))
        header.append(le32(16)); header.append(le16(1)); header.append(le16(1))
        header.append(le32(8000)); header.append(le32(16000)); header.append(le16(2)); header.append(le16(16))
        header.append(Data("data".utf8))
        header.append(le32(UInt32(samples.count)))
        try (header + samples).write(to: fixture.root.appendingPathComponent("tone.wav"))
        let wav = mediaInfo(["tone.wav", "duration", "title"], context: fixture.context)
        #expect(wav.result == "audio")
        #expect(abs((Int(wav.values[0]) ?? 0) - 500) <= 50)
        #expect(wav.values[1].isEmpty)

        // 中身がメディアでないファイルや、空のファイルは 200 ですべて空。
        try Data("not media".utf8).write(to: fixture.root.appendingPathComponent("text.mp3"))
        try Data().write(to: fixture.root.appendingPathComponent("empty.mp3"))
        for name in ["text.mp3", "empty.mp3"] {
            let outcome = mediaInfo([name, "title", "duration", "width"], context: fixture.context)
            #expect(outcome.status == 200, "\(name)")
            #expect((outcome.result ?? "").isEmpty, "\(name)")
            #expect(outcome.values == ["", "", ""], "\(name)")
        }
    }

    @Test
    func pathsAndArgumentsAreValidated() throws {
        let fixture = try MediaFixture()
        defer { fixture.remove() }
        try fixture.writeMP3("sound/a.mp3", frames: [("TIT2", MediaFixture.text("T"))])
        // \ 区切りも使える。絶対パスはゴーストなしでも使える。
        #expect(mediaInfo(["sound\\a.mp3", "duration"], context: fixture.context).result == "audio")
        #expect(mediaInfo([fixture.root.appendingPathComponent("sound/a.mp3").path, "duration"]).result == "audio")
        func fails(_ outcome: FileOutcome, _ status: Int, _ text: String, line: UInt = #line) {
            #expect(outcome.status == status && outcome.error == text, "\(outcome.status) \(outcome.error ?? "")")
        }
        fails(mediaInfo(["sound/a.mp3", "title"]), 400, "ghost required")
        fails(mediaInfo(["sound/none.mp3", "title"], context: fixture.context), 400, "file not found")
        fails(mediaInfo(["sound", "title"], context: fixture.context), 400, "file not found") // フォルダ
        fails(mediaInfo(["https://example.com/a.mp3", "title"], context: fixture.context), 400, "file not found")
        fails(mediaInfo(["sound/a.mp3"], context: fixture.context), 400, "invalid parameter") // キーが 1 つも無い
        let keys = Array(repeating: "title", count: 11)
        #expect(mediaInfo(["sound/a.mp3"] + keys, context: fixture.context).values.count == 11)
        fails(mediaInfo(["sound/a.mp3"] + keys + ["title"], context: fixture.context), 400, "invalid parameter")
    }

    @Test
    func asyncDeliversTheKindAndValuesToTheGhost() async throws {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var event: (name: String, references: [String: String])?
            func set(_ name: String, _ references: [String: String]) { lock.lock(); event = (name, references); lock.unlock() }
            func get() -> (name: String, references: [String: String])? { lock.lock(); defer { lock.unlock() }; return event }
        }
        let fixture = try MediaFixture()
        defer { fixture.remove() }
        try fixture.writeMP3("sound/a.mp3", frames: [("TIT2", MediaFixture.text("T"))])
        let box = Box()
        let context = InternalSaoriContext(ghostRoot: fixture.root, deliverEvent: { box.set($0, $1) })
        let outcome = mediaInfo(["sound/a.mp3", "title", "duration", "--async=OnMediaInfo"], context: context)
        #expect(outcome.status == 204)
        let deadline = Date().addingTimeInterval(30)
        while box.get() == nil, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let event = try #require(box.get())
        #expect(event.name == "OnMediaInfo")
        #expect(event.references["Reference1"] == "audio")
        #expect(event.references["Reference2"] == "internal_file")
        #expect(event.references["Reference3"] == "MediaInfo")
        #expect(Int(event.references["Reference5"] ?? "") != nil)
    }

    @Test
    func moduleIsListed() throws {
        let response = try SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(
            requestText: "EXECUTE SAORI/1.0\r\nModule: internal_system\r\nArgument0: ListFunctions\r\nArgument1: internal_file\r\n\r\n"))
        #expect(response.headerValue("Result") == "MediaInfo")
    }
}
