import Compression
import Foundation

/// データの形式の変換と、圧縮・展開。
struct InternalDataModule: InternalSaoriModule {
    let name = "internal_data"

    var functions: [InternalSaoriFunction] {
        [
            // データを別の形式で書き直す（base64 ⇔ 16進 ⇔ パーセントエンコード ⇔ 文字列 ⇔ bech32 など）。
            InternalSaoriFunction("Convert", positionals: 1, options: ["data-in", "out", "charset", "hrp"]) { call, _ in
                let data = try InternalSaoriCodec.decode(call.positionals[0], format: call.option("data-in"), defaultFormat: "text", charset: call.option("charset"))
                return InternalSaoriResult(try InternalSaoriCodec.encode(
                    data, format: call.option("out"), defaultFormat: "text", charset: call.option("charset"), hrp: call.option("hrp")
                ))
            },
            // 圧縮（gzip / zlib / deflate）。--level は 0〜9 を受け付けるが、圧縮の強さは OS の既定になる。
            InternalSaoriFunction("Compress", positionals: 2, options: ["data-in", "level", "out", "charset"]) { call, _ in
                let method = call.positionals[0].lowercased()
                guard ["gzip", "zlib", "deflate"].contains(method) else { throw InternalSaoriError.unsupportedAlgorithm }
                if let level = call.option("level") {
                    guard let value = Int(level), (0...9).contains(value) else { throw InternalSaoriError.invalidParameter }
                }
                let data = try InternalSaoriCodec.decode(call.positionals[1], format: call.option("data-in"), defaultFormat: "text", charset: call.option("charset"))
                let compressed = try InternalCompression.compress(data, method: method)
                return InternalSaoriResult(try InternalSaoriCodec.encode(compressed, format: call.option("out"), defaultFormat: "base64", charset: call.option("charset")))
            },
            // 展開（gzip / zlib / deflate / brotli）。展開後も 8MB まで。
            InternalSaoriFunction("Decompress", positionals: 2, options: ["data-in", "out", "charset"]) { call, _ in
                let method = call.positionals[0].lowercased()
                guard ["gzip", "zlib", "deflate", "brotli", "zstd"].contains(method) else { throw InternalSaoriError.unsupportedAlgorithm }
                let data = try InternalSaoriCodec.decode(call.positionals[1], format: call.option("data-in"), defaultFormat: "base64", charset: call.option("charset"))
                let expanded = try InternalCompression.decompress(data, method: method)
                return InternalSaoriResult(try InternalSaoriCodec.encode(expanded, format: call.option("out"), defaultFormat: "text", charset: call.option("charset")))
            }
        ]
    }
}

enum InternalCompression {
    // MARK: - 圧縮

    static func compress(_ data: Data, method: String) throws -> Data {
        let raw = try deflate(data)
        switch method {
        case "deflate":
            return raw
        case "zlib":
            // CMF=0x78（deflate、32K 窓）、FLG=0x9C（既定の圧縮レベル。(CMF*256+FLG) が 31 の倍数）。
            var output = Data([0x78, 0x9C])
            output.append(raw)
            output.append(bigEndian: adler32(data))
            return output
        default:
            var output = Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xFF])
            output.append(raw)
            output.append(littleEndian: crc32(data))
            output.append(littleEndian: UInt32(truncatingIfNeeded: data.count))
            return output
        }
    }

    /// 生の deflate。Compression フレームワークの COMPRESSION_ZLIB はヘッダの無い deflate。
    private static func deflate(_ data: Data) throws -> Data {
        if data.isEmpty { return Data([0x03, 0x00]) } // 空データの deflate（固定ハフマンの終端ブロック）
        guard let compressed = try? (data as NSData).compressed(using: .zlib) else { throw InternalSaoriError.internalError }
        return compressed as Data
    }

    // MARK: - 展開

    static func decompress(_ data: Data, method: String) throws -> Data {
        switch method {
        case "deflate":
            let (output, consumed) = try inflate(data, from: 0)
            guard consumed == data.count else { throw InternalSaoriError.invalidEncoding }
            return output
        case "zlib":
            return try decompressZlib(data)
        case "gzip":
            return try decompressGzip(data)
        case "brotli":
            return try decompressBrotli(data)
        default:
            // OS の圧縮フレームワークに zstd が無い。
            throw InternalSaoriError.unsupportedAlgorithm
        }
    }

    private static func decompressZlib(_ data: Data) throws -> Data {
        guard data.count >= 6 else { throw InternalSaoriError.invalidEncoding }
        let cmf = data[data.startIndex], flg = data[data.startIndex + 1]
        // 圧縮方式は deflate（8）、ヘッダの検査値、プリセット辞書（FDICT）は扱わない。
        guard cmf & 0x0F == 8, (Int(cmf) * 256 + Int(flg)) % 31 == 0, flg & 0x20 == 0 else { throw InternalSaoriError.invalidEncoding }
        let (output, consumed) = try inflate(data, from: 2)
        guard data.count - consumed == 4 else { throw InternalSaoriError.invalidEncoding }
        let expected = data.suffix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard adler32(output) == expected else { throw InternalSaoriError.invalidEncoding }
        return output
    }

    /// 複数のメンバーをつないだ gzip も読む。壊れている・途中で切れている・後ろに余計なデータがあるときは invalid encoding。
    private static func decompressGzip(_ data: Data) throws -> Data {
        var output = Data()
        var offset = 0
        let bytes = [UInt8](data)
        repeat {
            guard bytes.count - offset >= 18, bytes[offset] == 0x1F, bytes[offset + 1] == 0x8B, bytes[offset + 2] == 8 else {
                throw InternalSaoriError.invalidEncoding
            }
            let flags = bytes[offset + 3]
            var position = offset + 10
            if flags & 0x04 != 0 { // FEXTRA
                guard position + 2 <= bytes.count else { throw InternalSaoriError.invalidEncoding }
                position += 2 + Int(bytes[position]) + Int(bytes[position + 1]) << 8
            }
            for flag in [UInt8(0x08), 0x10] where flags & flag != 0 { // FNAME / FCOMMENT（0 で終わる文字列）
                guard let end = bytes[min(position, bytes.count)...].firstIndex(of: 0) else { throw InternalSaoriError.invalidEncoding }
                position = end + 1
            }
            if flags & 0x02 != 0 { position += 2 } // FHCRC
            guard position < bytes.count else { throw InternalSaoriError.invalidEncoding }
            let (member, consumed) = try inflate(data, from: position)
            let trailer = consumed
            guard trailer + 8 <= bytes.count else { throw InternalSaoriError.invalidEncoding }
            let crc = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[trailer + $1]) << UInt32(8 * $1) }
            let size = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[trailer + 4 + $1]) << UInt32(8 * $1) }
            guard crc32(member) == crc, size == UInt32(truncatingIfNeeded: member.count) else { throw InternalSaoriError.invalidEncoding }
            output.append(member)
            guard output.count <= InternalSaoriCodec.maximumBytes else { throw InternalSaoriError.tooLarge }
            offset = trailer + 8
        } while offset < bytes.count
        return output
    }

    /// 生の deflate を `offset` から展開する。戻り値は展開結果と、入力のどこまで使ったか（先頭からの位置）。
    /// 終端まで読めない（途中で切れている）・壊れているときは invalid encoding、8MB を超えると too large。
    static func inflate(_ data: Data, from offset: Int) throws -> (Data, Int) {
        let source = [UInt8](data)
        guard offset <= source.count else { throw InternalSaoriError.invalidEncoding }
        var inflater = RawInflate(input: source, start: offset, limit: InternalSaoriCodec.maximumBytes)
        let consumed = try inflater.run()
        return (Data(inflater.output), consumed)
    }

    /// brotli は OS の圧縮フレームワークで展開する（入力全体を使い切ること）。
    static func decompressBrotli(_ data: Data) throws -> Data {
        let source = [UInt8](data)
        let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { scratch.deallocate() }
        var stream = compression_stream(dst_ptr: scratch, dst_size: 0, src_ptr: scratch, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_BROTLI) == COMPRESSION_STATUS_OK else {
            throw InternalSaoriError.unsupportedAlgorithm
        }
        defer { compression_stream_destroy(&stream) }
        let chunk = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { buffer.deallocate() }
        var output = Data()
        var finished = false
        try source.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { throw InternalSaoriError.invalidEncoding }
            stream.src_ptr = base
            stream.src_size = source.count
            while !finished {
                stream.dst_ptr = buffer
                stream.dst_size = chunk
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                output.append(buffer, count: chunk - stream.dst_size)
                if output.count > InternalSaoriCodec.maximumBytes { throw InternalSaoriError.tooLarge }
                switch status {
                case COMPRESSION_STATUS_END: finished = true
                case COMPRESSION_STATUS_OK:
                    // 出力の領域を使い切っていなくて入力も尽きたなら、途中で切れている。
                    if stream.src_size == 0 && stream.dst_size != 0 { throw InternalSaoriError.invalidEncoding }
                default: throw InternalSaoriError.invalidEncoding
                }
            }
        }
        return output
    }

    // MARK: - チェックサム

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? crc >> 1 ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return b << 16 | a
    }
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        append(contentsOf: [UInt8(value >> 24 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)])
    }

    mutating func append(littleEndian value: UInt32) {
        append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 24 & 0xff)])
    }
}
