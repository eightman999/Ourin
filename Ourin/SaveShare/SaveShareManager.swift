// Ourin/SaveShare/SaveShareManager.swift
//
// SSP 互換のセーブデータ共有 (.ssg) エクスポート/インポートを提供する。
//
// ## .ssg バイナリ形式 (SSP 2.8.35f sp_saveshare より)
//
//   offset  0 : magic "SSZ\\0" (4 bytes)
//   offset  4 : FILETIME.dwLowDateTime (LE32)
//   offset  8 : FILETIME.dwHighDateTime (LE32)
//   offset 12 : computerNameLen-1 (LE32)   ※ GetComputerNameW の長さから 1 引いた値
//   offset 16 : computerName (computerNameLen-1 bytes、無ければ省略)
//   offset 16+len : uncompressedSize (LE32) ※ 圧縮前の本文バイト数
//   offset 20+len : zlib 圧縮データ (compress2 level -1)
//
//   本文テキスト (SSP 互換):
//     "===SSP_SAVESHARE:1.0===\\r\\n"
//     "[TIMESTAMP:yyyy-MM-ddTHH:mm:ssZ]\\r\\n"
//     "[GHOSTNAME:<ghost>]\\r\\n"
//     "[COMPUTERNAME:<computer>]\\r\\n"
//     "[FILE:<name>]\\r\\n[SIZE:<n>]\\r\\n[TYPE:TEXT]\\r\\n<text>\\r\\n[ENDFILE]\\r\\n"
//     "[FILE:<name>]\\r\\n[SIZE:<n>]\\r\\n[TYPE:BINARY]\\r\\n<base64>\\r\\n[ENDFILE]\\r\\n"
//     "===SSP_SAVESHARE_END===\\r\\n"
//
//   - TEXT: 生バイトをそのまま埋める。末尾に \\r\\n が付く。
//   - BINARY: Base64 エンコードした文字列を埋める。SIZE は Base64 文字列長。
//   - 読み込み時、先頭 4 バイトが magic と一致しなければプレーンテキストとして扱う
//     (ReadAndDecompressSSG のフォールバック動作)。
//
// SSP のプロファイルファイル定義 (data/profile/<ghost>/ 直下、15 件):
//   yaya_variable.cfg, aya_variable.cfg, satori_savedata.txt,
//   dict-save.txt, dict-save2.txt, dict-keeps-savedata.txt, Dict-KEEPSs.txt,
//   save.dat, savedata1.dat, savedata2.dat, savedata3.dat, savedata4.dat,
//   savedata5.dat, savedata.adb (BINARY), savedata.asv
import Foundation
import Compression

/// SSP 互換のセーブデータ共有 (.ssg) をエクスポート/インポートする。
enum SaveShareManager {

    enum SaveShareError: Error {
        case invalidSSG
        case unsupportedCompression
        case fileNotIncluded(String)
        case pathTraversal(String)
    }

    /// SSP の .ssg マジック "SSZ" (LE32 = 0x005A5353)。
    static let magic: [UInt8] = [0x53, 0x53, 0x5A, 0x00] // "SSZ\0"

    static let textHeader = "===SSP_SAVESHARE:1.0===\r\n"
    static let textFooter = "===SSP_SAVESHARE_END===\r\n"

    /// SSP が .ssg に含めるプロファイルファイル定義 (名前, バイナリか)。
    static let defaultProfileFiles: [(name: String, isBinary: Bool)] = [
        ("yaya_variable.cfg", false),
        ("aya_variable.cfg", false),
        ("satori_savedata.txt", false),
        ("dict-save.txt", false),
        ("dict-save2.txt", false),
        ("dict-keeps-savedata.txt", false),
        ("Dict-KEEPSs.txt", false),
        ("save.dat", false),
        ("savedata1.dat", false),
        ("savedata2.dat", false),
        ("savedata3.dat", false),
        ("savedata4.dat", false),
        ("savedata5.dat", false),
        ("savedata.adb", true),
        ("savedata.asv", false),
    ]

    /// SSP の SSGHeaderInfo レイアウト (timeLow, timeHigh, computerName)。
    struct SSGHeaderInfo {
        var timeLow: UInt32
        var timeHigh: UInt32
        var computerName: String
        var nameByteLength: Int
    }

    // MARK: - エクスポート

    /// 指定ゴーストのプロファイルディレクトリを .ssg に書き出す。
    ///
    /// - Parameters:
    ///   - ghostName: ゴースト名 (ヘッダの GHOSTNAME に使う)
    ///   - computerName: コンピュータ名 (ヘッダの COMPUTERNAME / バイナリヘッダに使う)
    ///   - profileURL: data/profile/<ghost>/ ディレクトリ
    ///   - url: 書き出し先 .ssg ファイル
    ///   - includeFiles: 含めるファイル名 (nil なら SSP のデフォルトプロファイルファイル)
    /// - Returns: 含めたファイル名のリスト
    @discardableResult
    static func exportSSG(
        ghostName: String,
        computerName: String,
        profileURL: URL,
        to url: URL,
        includeFiles: [String]? = nil,
        timestamp: Date = Date()
    ) throws -> [String] {
        let fm = FileManager.default
        let names = includeFiles ?? defaultProfileFiles.map(\.name)
        var body = textHeader

        body += "[TIMESTAMP:\(iso8601(timestamp))]\r\n"
        if !ghostName.isEmpty {
            body += "[GHOSTNAME:\(ghostName)]\r\n"
        }
        if !computerName.isEmpty {
            body += "[COMPUTERNAME:\(computerName)]\r\n"
        }

        var included: [String] = []
        for name in names {
            guard isValidProfileName(name) else { throw SaveShareError.pathTraversal(name) }
            let fileURL = profileURL.appendingPathComponent(name)
            guard fm.fileExists(atPath: fileURL.path) else { continue }

            let data = try Data(contentsOf: fileURL)
            let isBinary = defaultProfileFiles.first(where: { $0.name == name })?.isBinary ?? false
            if isBinary {
                let base64 = data.base64EncodedString()
                body += "[FILE:\(name)]\r\n[SIZE:\(base64.count)]\r\n[TYPE:BINARY]\r\n"
                body += base64
                body += "\r\n[ENDFILE]\r\n"
            } else {
                body += "[FILE:\(name)]\r\n[SIZE:\(data.count)]\r\n[TYPE:TEXT]\r\n"
                body += String(decoding: data, as: UTF8.self)
                body += "\r\n[ENDFILE]\r\n"
            }
            included.append(name)
        }

        body += textFooter

        let uncompressed = Data(body.utf8)
        let compressed = try zlibCompress(uncompressed)
        let nameByteLength = computerName.utf8.count

        var header = Data()
        header.append(contentsOf: magic)
        let ft = fileTime(from: timestamp)
        header.append(contentsOf: le32(ft.low))
        header.append(contentsOf: le32(ft.high))
        header.append(contentsOf: le32(UInt32(nameByteLength)))
        if nameByteLength > 0 {
            header.append(Data(computerName.utf8))
        }
        header.append(contentsOf: le32(UInt32(uncompressed.count)))
        header.append(compressed)

        try header.write(to: url, options: .atomic)
        return included
    }

    // MARK: - インポート

    /// .ssg ファイルを読み、指定ディレクトリへプロファイルファイルを復元する。
    ///
    /// - Parameters:
    ///   - url: .ssg ファイル
    ///   - profileURL: 復元先 data/profile/<ghost>/ ディレクトリ
    /// - Returns: 復元したファイル名のリスト
    @discardableResult
    static func importSSG(from url: URL, to profileURL: URL) throws -> [String] {
        let fm = FileManager.default
        let raw = try Data(contentsOf: url)

        let body: String
        if raw.starts(with: magic) {
            let header = try readHeader(raw)
            let (compressed, uncompressedSize) = try readCompressedPayload(raw, header: header)
            guard let decoded = try zlibDecompress(compressed, expectedSize: uncompressedSize) else {
                throw SaveShareError.unsupportedCompression
            }
            body = String(decoding: decoded, as: UTF8.self)
        } else {
            // 先頭が magic でない場合はプレーンテキストとして扱う (SSP のフォールバック)。
            body = String(decoding: raw, as: UTF8.self)
        }

        guard body.hasPrefix(textHeader) else { throw SaveShareError.invalidSSG }

        let entries = try parseBody(body)
        try fm.createDirectory(at: profileURL, withIntermediateDirectories: true)
        var restored: [String] = []
        for entry in entries {
            let fileURL = profileURL.appendingPathComponent(entry.name)
            let data: Data
            if entry.isBinary {
                guard let d = Data(base64Encoded: entry.content) else {
                    throw SaveShareError.invalidSSG
                }
                data = d
            } else {
                data = Data(entry.content.utf8)
            }
            try data.write(to: fileURL, options: .atomic)
            restored.append(entry.name)
        }
        return restored
    }

    /// .ssg ファイルからヘッダ情報のみを読み取る (SSP の ReadSSGHeader 相当)。
    static func readHeader(_ data: Data) throws -> SSGHeaderInfo {
        guard data.count >= 0x14, data.starts(with: magic) else {
            throw SaveShareError.invalidSSG
        }
        let timeLow = le32Value(data, offset: 4)
        let timeHigh = le32Value(data, offset: 8)
        let nameLen = Int(le32Value(data, offset: 12))
        guard data.count >= nameLen + 0x10 else { throw SaveShareError.invalidSSG }
        let name = String(decoding: data[16..<(16 + nameLen)], as: UTF8.self)
        return SSGHeaderInfo(timeLow: timeLow, timeHigh: timeHigh, computerName: name, nameByteLength: nameLen)
    }

    /// ヘッダに続く zlib データと圧縮前サイズを取り出す。
    private static func readCompressedPayload(_ data: Data, header: SSGHeaderInfo) throws -> (Data, Int) {
        let nameLen = header.nameByteLength
        // uncompressedSize は offset 0x10 + nameLen、データは offset 0x14 + nameLen から始まる。
        let sizeOffset = 0x10 + nameLen
        let payloadStart = 0x14 + nameLen
        guard sizeOffset + 4 <= data.count, payloadStart <= data.count else {
            throw SaveShareError.invalidSSG
        }
        let uncompressedSize = Int(le32Value(data, offset: sizeOffset))
        let compressed = data.dropFirst(payloadStart)
        return (Data(compressed), uncompressedSize)
    }

    // MARK: - 本文パース

    struct Entry {
        var name: String
        var isBinary: Bool
        var content: String
    }

    static func parseBody(_ body: String) throws -> [Entry] {
        guard body.hasPrefix(textHeader) else { throw SaveShareError.invalidSSG }
        var lines = body.components(separatedBy: "\r\n")
        // 先頭の ===SSP_SAVESHARE:1.0=== を除去
        lines.removeFirst()

        var entries: [Entry] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.hasPrefix(textFooter) { break }
            if line.hasPrefix("[FILE:") {
                guard let end = line.firstIndex(of: "]") else { throw SaveShareError.invalidSSG }
                let name = String(line[line.index(line.startIndex, offsetBy: 6)..<end])
                guard isValidProfileName(name) else { throw SaveShareError.pathTraversal(name) }

                // [SIZE:n]
                var size = 0
                while index < lines.count, !lines[index].hasPrefix("[SIZE:") {
                    index += 1
                }
                if index < lines.count, lines[index].hasPrefix("[SIZE:") {
                    let s = String(lines[index].dropFirst(6).dropLast())
                    size = Int(s) ?? 0
                    index += 1
                }

                // [TYPE:TEXT] or [TYPE:BINARY]
                var isBinary = false
                while index < lines.count, !lines[index].hasPrefix("[TYPE:") {
                    index += 1
                }
                if index < lines.count, lines[index].hasPrefix("[TYPE:") {
                    isBinary = lines[index].contains("BINARY")
                    index += 1
                }

                // 内容 (size バイト相当、\r\n 区切り) を [ENDFILE] まで収集
                var content = ""
                while index < lines.count, !lines[index].hasPrefix("[ENDFILE]") {
                    if !content.isEmpty { content += "\r\n" }
                    content += lines[index]
                    index += 1
                }
                // 末尾の [ENDFILE] を読み飛ばす
                if index < lines.count {
                    index += 1
                }
                entries.append(Entry(name: name, isBinary: isBinary, content: content))
            }
        }
        return entries
    }

    // MARK: - ヘルパー

    private static func isValidProfileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && !name.contains("..")
    }

    private static func iso8601(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return fmt.string(from: date)
    }

    private static func le32(_ value: UInt32) -> Data {
        var v = value
        return Data(bytes: &v, count: 4)
    }

    private static func le32Value(_ data: Data, offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            guard offset + i < data.count else { break }
            value |= UInt32(data[offset + i]) << (8 * i)
        }
        return value
    }

    /// Windows FILETIME (1601-01-01 からの 100ns 間隔)。
    static func fileTime(from date: Date) -> (low: UInt32, high: UInt32) {
        // 1601-01-01 00:00:00 UTC は Unix epoch より 11644473600 秒前。
        let unix = date.timeIntervalSince1970
        let intervals = UInt64((unix + 11644473600) * 10_000_000)
        return (UInt32(intervals & 0xFFFF_FFFF), UInt32(intervals >> 32))
    }

    static func zlibCompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let dstCap = data.count + (data.count / 2) + 64
        var dst = Data(count: dstCap)
        let written = dst.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!,
                    dstCap,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < dstCap else { throw SaveShareError.unsupportedCompression }
        return dst.prefix(written)
    }

    static func zlibDecompress(_ data: Data, expectedSize: Int) throws -> Data? {
        guard !data.isEmpty else { return Data() }
        let cap = expectedSize > 0 ? expectedSize : (data.count * 8 + 64)
        var dst = Data(count: cap)
        let written = dst.withUnsafeMutableBytes { (dstPtr: UnsafeMutableRawBufferPointer) -> Int in
            data.withUnsafeBytes { (srcPtr: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!,
                    cap,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return dst.prefix(written)
    }
}