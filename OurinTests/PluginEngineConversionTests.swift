import Foundation
import Testing
@testable import Ourin

/// SSP 形式のプラグイン（descript.txt + Windows DLL）を `.plugin` へ変換し、内蔵エンジンで動かす経路。
@Suite(.serialized)
struct PluginEngineConversionTests {
    // MARK: - PE ヘッダ

    @Test
    func peParserReadsMachineExportsAndImports() throws {
        let info = try #require(PEImageInfo.parse(MinimalPE.build(exports: ["load", "request", "unload"], imports: ["KERNEL32.dll"])))
        #expect(info.machine == .x86)
        #expect(info.exports == ["load", "request", "unload"])
        #expect(info.imports == ["KERNEL32.dll"])
        #expect(info.exportsUkagakaModuleABI)
    }

    @Test
    func peParserRejectsNonPE() {
        #expect(PEImageInfo.parse(Data("not a dll".utf8)) == nil)
    }

    @Test
    func engineIsRecognizedFromModuleName() {
        #expect(PluginEngineKind.recognize(moduleName: "yaya.dll") == .yaya)
        #expect(PluginEngineKind.recognize(moduleName: "system\\AYA.DLL") == .yaya)
        #expect(PluginEngineKind.recognize(moduleName: "kagari.dll") == .kagari)
        #expect(PluginEngineKind.recognize(moduleName: "main.dll") == nil)
    }

    // MARK: - 変換

    @Test
    func engineDLLIsConvertedToPluginBundleNextToTheDLL() throws {
        let dir = try makeYayaPluginDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let bundleURL = dir.appendingPathComponent("yaya.plugin")
        func convertedPath() throws -> String? {
            guard case .converted(let url, .yaya) = try #require(DLLPluginConverter.convert(pluginDirectory: dir)).outcome else {
                return nil
            }
            return url.standardizedFileURL.resolvingSymlinksInPath().path
        }
        let expected = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        #expect(try convertedPath() == expected)
        #expect(DLLPluginConverter.engineKind(ofBundleAt: bundleURL) == .yaya)
        // 元の DLL は残す
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("yaya.dll").path))

        // 2 回目は作成済みの .plugin をそのまま使う
        #expect(try convertedPath() == expected)
    }

    @Test
    func nativeCodeDLLIsReportedAsUnsupportedWithItsImports() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "charset,UTF-8\r\nname,Native\r\nid,native-id\r\nfilename,main.dll\r\n"
            .write(to: dir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try MinimalPE.build(exports: ["load", "request", "unload"], imports: ["USER32.dll"])
            .write(to: dir.appendingPathComponent("main.dll"))

        let report = try #require(DLLPluginConverter.convert(pluginDirectory: dir))
        guard case .unsupported(let reason) = report.outcome else {
            Issue.record("expected unsupported, got \(report.outcome)")
            return
        }
        #expect(reason.contains("USER32.dll"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("main.plugin").path))
    }

    // MARK: - 内蔵 YAYA で実行

    @Test
    func convertedYayaPluginAnswersPluginRequestsThroughBuiltInEngine() throws {
        let dir = try makeYayaPluginDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard case .converted(let bundleURL, _) = try #require(DLLPluginConverter.convert(pluginDirectory: dir)).outcome else {
            Issue.record("conversion failed")
            return
        }

        let plugin = try Plugin(url: bundleURL)
        defer { plugin.unload() }
        #expect(plugin.engine?.kind == .yaya)
        #expect(plugin.load(directoryURL: dir))

        let menu = try PluginProtocolParser.parseResponse(
            plugin.send(PluginFrame(id: "OnMenuExec", references: ["", "さくら"], charset: "UTF-8").build(), charset: "UTF-8")
        )
        #expect(menu.statusCode == 200)
        #expect(menu.script == "\\0OnMenuExec:さくら\\e")

        // load には SSP と同じく DLL のフォルダ（末尾区切り付き）が渡る
        let path = try PluginProtocolParser.parseResponse(
            plugin.send(PluginFrame(id: "loadpath", charset: "UTF-8").build(), charset: "UTF-8")
        )
        #expect(path.value == dir.path + "/")
    }

    // MARK: - fixtures

    private func makeYayaPluginDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-yaya-plugin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "charset,UTF-8\r\nname,EngineFixture\r\nid,engine-fixture\r\nfilename,yaya.dll\r\nsecondchangeinterval,0\r\n"
            .write(to: dir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try MinimalPE.build(exports: ["load", "request", "unload"], imports: ["KERNEL32.dll"])
            .write(to: dir.appendingPathComponent("yaya.dll"))
        try "charset, UTF-8\r\ndic, plugin.dic\r\n"
            .write(to: dir.appendingPathComponent("yaya.txt"), atomically: true, encoding: .utf8)
        let dic = """
        load
        {
        \tLoadPath = _argv[0]
        }

        request
        {
        \t_lines = SPLIT(_argv[0], CHR(13) + CHR(10))
        \t_id = ''
        \t_ref1 = ''
        \tforeach _lines; _line {
        \t\tif SUBSTR(_line, 0, 4) == 'ID: ' { _id = ERASE(_line, 0, 4) }
        \t\tif SUBSTR(_line, 0, 12) == 'Reference1: ' { _ref1 = ERASE(_line, 0, 12) }
        \t}
        \t_crlf = CHR(13) + CHR(10)
        \tif _id == 'loadpath' {
        \t\t'PLUGIN/2.0 200 OK' + _crlf + 'Charset: UTF-8' + _crlf + 'Value: ' + LoadPath + _crlf + _crlf
        \t}
        \telse {
        \t\t'PLUGIN/2.0 200 OK' + _crlf + 'Charset: UTF-8' + _crlf + 'Script: \\0' + _id + ':' + _ref1 + '\\e' + _crlf + _crlf
        \t}
        }
        """
        try dic.write(to: dir.appendingPathComponent("plugin.dic"), atomically: true, encoding: .utf8)
        return dir
    }
}

/// エクスポート表とインポート表だけを持つ最小の PE32 (x86) イメージ。
enum MinimalPE {
    static func build(exports: [String], imports: [String]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 0x400)
        func put16(_ value: Int, at offset: Int) {
            bytes[offset] = UInt8(value & 0xFF); bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
        }
        func put32(_ value: Int, at offset: Int) {
            put16(value & 0xFFFF, at: offset); put16((value >> 16) & 0xFFFF, at: offset + 2)
        }
        func putString(_ text: String, at offset: Int) {
            for (i, byte) in text.utf8.enumerated() { bytes[offset + i] = byte }
        }
        bytes[0] = 0x4D; bytes[1] = 0x5A
        let pe = 0x80
        put32(pe, at: 0x3C)
        putString("PE", at: pe)
        put16(0x014C, at: pe + 4)          // Machine: x86
        put16(1, at: pe + 6)               // NumberOfSections
        put16(224, at: pe + 20)            // SizeOfOptionalHeader
        let optional = pe + 24
        put16(0x10B, at: optional)         // PE32
        let directories = optional + 96
        let sectionTable = optional + 224
        // 1 セクション: RVA 0x1000 → file 0x200
        let sectionRVA = 0x1000, sectionFile = 0x200, sectionSize = 0x200
        putString(".rdata", at: sectionTable)
        put32(sectionSize, at: sectionTable + 8)
        put32(sectionRVA, at: sectionTable + 12)
        put32(sectionSize, at: sectionTable + 16)
        put32(sectionFile, at: sectionTable + 20)
        func rva(_ fileOffset: Int) -> Int { fileOffset - sectionFile + sectionRVA }

        // export directory @0x200, names array @0x230, strings @0x260〜
        let exportDir = 0x200, namesArray = 0x230
        var cursor = 0x260
        put32(rva(exportDir), at: directories)
        put32(0x40, at: directories + 4)
        put32(exports.count, at: exportDir + 24)
        put32(rva(namesArray), at: exportDir + 32)
        for (i, name) in exports.enumerated() {
            put32(rva(cursor), at: namesArray + i * 4)
            putString(name, at: cursor)
            cursor += name.utf8.count + 1
        }
        // import descriptors @0x300（20 バイト × n + 終端）
        let importDir = 0x300
        cursor = 0x380
        put32(rva(importDir), at: directories + 8)
        put32(20 * (imports.count + 1), at: directories + 12)
        for (i, name) in imports.enumerated() {
            put32(rva(cursor), at: importDir + i * 20 + 12)
            putString(name, at: cursor)
            cursor += name.utf8.count + 1
        }
        return Data(bytes)
    }
}
