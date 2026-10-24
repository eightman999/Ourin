import Foundation
import Testing
@testable import Ourin

/// 日本語以外の文字コード（#163）。
struct ForeignCharsetTests {
    private let samples: [(charset: String, text: String)] = [
        ("Big5", "繁體中文的偽春菜"),
        ("GB2312", "简体中文的伪春菜"),
        ("GBK", "简体中文的伪春菜"),
        ("GB18030", "简体中文𠀀"),
        ("EUC-KR", "한국어 고스트"),
        ("CP949", "한국어 고스트"),
        ("windows-1252", "Café déjà vu"),
        ("ISO-8859-1", "Café"),
        ("windows-1251", "Привет"),
        ("KOI8-R", "Привет"),
        ("Shift_JIS", "さくら①"), // CP932 の拡張文字も読める
        ("EUC-JP", "さくら"),
        ("UTF-16LE", "さくら")
    ]

    @Test
    func charsetNamesResolveIncludingAliases() {
        for (name, expected) in [
            ("UTF-8", String.Encoding.utf8), ("utf8", .utf8), ("Shift_JIS", .shiftJIS), ("x-sjis", .shiftJIS),
            ("windows-31j", .shiftJIS), ("cp932", .shiftJIS), ("EUC-JP", .japaneseEUC), ("ISO-2022-JP", .iso2022JP),
            ("ISO-8859-1", .isoLatin1), ("windows-1252", .windowsCP1252), ("cp1252", .windowsCP1252), ("1252", .windowsCP1252),
            ("UTF-16LE", .utf16LittleEndian)
        ] {
            #expect(EncodingAdapter.knownEncoding(for: name) == expected, "\(name)")
        }
        // 中国語・韓国語は Windows のコードページ（上位互換）で読む。
        #expect(EncodingAdapter.knownEncoding(for: "Big5") == EncodingAdapter.knownEncoding(for: "cp950"))
        #expect(EncodingAdapter.knownEncoding(for: "GB2312") == EncodingAdapter.knownEncoding(for: "GBK"))
        #expect(EncodingAdapter.knownEncoding(for: "EUC-KR") == EncodingAdapter.knownEncoding(for: "ks_c_5601-1987"))
        #expect(EncodingAdapter.knownEncoding(for: "UHC") == EncodingAdapter.knownEncoding(for: "CP949"))
        #expect(EncodingAdapter.knownEncoding(for: "nothing") == nil)
        #expect(EncodingAdapter.knownEncoding(for: "") == nil)
        // 知らない名前は UTF-8。
        #expect(EncodingAdapter.encoding(for: "nothing") == .utf8)
    }

    @Test
    func eachCharsetRoundTrips() throws {
        for sample in samples {
            let encoding = try #require(EncodingAdapter.knownEncoding(for: sample.charset), "\(sample.charset)")
            let bytes = try #require(sample.text.data(using: encoding), "\(sample.charset)")
            #expect(EncodingAdapter.decode(bytes, charset: sample.charset) == sample.text, "\(sample.charset)")
            #expect(EncodingAdapter.encode(sample.text, charset: sample.charset) == bytes, "\(sample.charset)")
        }
    }

    @Test
    func charsetNamesAreWrittenBack() {
        #expect(EncodingAdapter.charsetName(for: .utf8) == "UTF-8")
        #expect(EncodingAdapter.charsetName(for: .shiftJIS) == "Shift_JIS")
        #expect(EncodingAdapter.charsetName(for: .japaneseEUC) == "EUC-JP")
        #expect(EncodingAdapter.charsetName(for: .windowsCP1252).lowercased() == "windows-1252")
        let big5 = EncodingAdapter.encoding(for: "Big5")
        #expect(EncodingAdapter.knownEncoding(for: EncodingAdapter.charsetName(for: big5)) == big5)
    }

    @Test
    func textDefinitionFilesFollowTheirCharsetDeclaration() throws {
        for sample in samples where !sample.charset.hasPrefix("UTF-16") {
            let encoding = try #require(EncodingAdapter.knownEncoding(for: sample.charset))
            let text = "charset,\(sample.charset)\r\nname,\(sample.text)\r\n"
            let data = try #require(text.data(using: encoding), "\(sample.charset)")
            let decoded = EncodingAdapter.decodeTextDefinition(data)
            #expect(LegacyDescriptor.parseDictionary(decoded ?? "")["name"] == sample.text, "\(sample.charset)")
        }
        // charset: の表記、前の空行・コメント、BOM。
        let colon = try #require("// comment\n\ncharset: EUC-KR\nname,한국어\n".data(using: EncodingAdapter.encoding(for: "EUC-KR")))
        #expect(EncodingAdapter.decodeTextDefinition(colon)?.contains("한국어") == true)
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("name,さくら\n".utf8)
        #expect(EncodingAdapter.decodeTextDefinition(bom) == "name,さくら\n")
        let utf16 = try #require("name,さくら\n".data(using: .utf16)) // BOM 付き
        #expect(EncodingAdapter.decodeTextDefinition(utf16) == "name,さくら\n")
        // 宣言が無ければ UTF-8 → Shift_JIS。
        #expect(EncodingAdapter.decodeTextDefinition(Data("name,さくら".utf8)) == "name,さくら")
        #expect(EncodingAdapter.decodeTextDefinition("name,さくら".data(using: .shiftJIS)!) == "name,さくら")
        // 知らない宣言は無視して UTF-8 → Shift_JIS。
        #expect(EncodingAdapter.decodeTextDefinition(Data("charset,nothing\nname,x".utf8))?.hasSuffix("name,x") == true)
    }

    @Test
    func descriptFilesAreReadThroughEveryLoader() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-charset-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let big5 = EncodingAdapter.encoding(for: "Big5")
        try #require("charset,Big5\r\nname,繁體氣球\r\n".data(using: big5)).write(to: root.appendingPathComponent("descript.txt"))
        #expect(try DescriptorLoader.load(from: root)["name"] == "繁體氣球")
        #expect(LegacyDescriptor.readDictionary(from: root.appendingPathComponent("descript.txt"))?["name"] == "繁體氣球")
        let korean = EncodingAdapter.encoding(for: "EUC-KR")
        try #require("charset,EUC-KR\r\nname,한국어\r\n".data(using: korean)).write(to: root.appendingPathComponent("install.txt"))
        let install = try Data(contentsOf: root.appendingPathComponent("install.txt"))
        #expect(TextEncodingDetector.declaredCharset(in: install) == korean)
    }

    @Test
    func saoriAndHeadlineCharsetsUseTheSameTable() throws {
        #expect(SaoriProtocol.stringEncoding(for: "Big5") == EncodingAdapter.encoding(for: "Big5"))
        #expect(SaoriProtocol.stringEncoding(for: "nothing") == nil)
        let data = try SaoriProtocol.encode("中文", charset: "GBK")
        #expect(try SaoriProtocol.decode(data, charset: "GB2312") == "中文")
        #expect(HeadlineWireEngine.parseCharset("HEADLINE/2.0M 200 OK\r\nCharset: EUC-KR\r\n\r\n") == EncodingAdapter.encoding(for: "EUC-KR"))
        #expect(HeadlineWireEngine.parseRequestCharset("HEADLINE/2.0M 200 OK\r\nRequestCharset: Big5\r\n\r\n") == EncodingAdapter.encoding(for: "Big5"))
        #expect(HeadlineWireEngine.buildRequest(path: "/x", charset: EncodingAdapter.encoding(for: "Big5")).contains("Charset: Big5"))
    }
}
