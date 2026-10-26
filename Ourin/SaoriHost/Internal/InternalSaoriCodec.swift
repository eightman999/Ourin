import Foundation

/// 内蔵モジュールが共通で使う、バイト列の入出力形式（UKADOC「内蔵モジュールの共通規約」）。
enum InternalSaoriCodec {
    /// デコードした後のデータは 1 つの引数あたり 8MB まで。
    static let maximumBytes = 8 * 1024 * 1024

    // MARK: - 文字コード

    /// `--charset=` の文字コード（既定は UTF-8）。知らない名前・UTF-16 は invalid parameter。
    static func encoding(named name: String?) throws -> String.Encoding {
        guard let name, !name.isEmpty else { return .utf8 }
        let normalized = name.lowercased().replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("utf-16") || normalized.hasPrefix("utf16") { throw InternalSaoriError.invalidParameter }
        if let encoding = SaoriProtocol.stringEncoding(for: normalized) { return encoding }
        switch normalized {
        case "latin1", "iso-8859-1": return .isoLatin1
        case "ascii", "us-ascii": return .ascii
        case "windows-1252", "cp1252": return .windowsCP1252
        default: throw InternalSaoriError.invalidParameter
        }
    }

    // MARK: - 入力

    /// `--名前-in=` の形式で値をバイト列に読む。形式が無ければ `defaultFormat`。
    static func decode(_ value: String, format: String?, defaultFormat: String, charset: String?) throws -> Data {
        let name = (format?.isEmpty == false ? format! : defaultFormat).lowercased()
        let data: Data
        switch name {
        case "text":
            guard let bytes = value.data(using: try encoding(named: charset), allowLossyConversion: false) else {
                throw InternalSaoriError.invalidEncoding
            }
            data = bytes
        case "hex": data = try decodeHex(value)
        case "base64", "base64url": data = try decodeBase64(value)
        case "base32": data = try decodeBase32(value)
        case "url": data = try decodePercent(value)
        case "bech32": data = try Bech32.decodeData(value)
        default: throw InternalSaoriError.invalidParameter
        }
        guard data.count <= maximumBytes else { throw InternalSaoriError.tooLarge }
        return data
    }

    // MARK: - 出力

    /// `--out=` の形式でバイト列を文字列にする。
    static func encode(_ data: Data, format: String?, defaultFormat: String, charset: String?, hrp: String? = nil) throws -> String {
        let requested = format?.isEmpty == false ? format! : defaultFormat
        switch requested {
        case "HEX": return data.map { String(format: "%02X", $0) }.joined()
        default: break
        }
        switch requested.lowercased() {
        case "hex": return data.map { String(format: "%02x", $0) }.joined()
        case "base64": return data.base64EncodedString()
        case "base64url":
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        case "base32": return encodeBase32(data)
        case "url": return encodePercent(data)
        case "bech32":
            guard let hrp else { throw InternalSaoriError.invalidParameter }
            return try Bech32.encode(hrp: hrp, data: data)
        case "text":
            guard let text = String(data: data, encoding: try encoding(named: charset)) else { throw InternalSaoriError.notText }
            // NUL と改行は SAORI のヘッダに書けない。
            guard !text.contains("\u{0}"), !text.contains("\n"), !text.contains("\r") else { throw InternalSaoriError.notText }
            return text
        default:
            throw InternalSaoriError.invalidParameter
        }
    }

    // MARK: - 形式ごと

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 65...70: return c - 55
        case 97...102: return c - 87
        default: return nil
        }
    }

    static func decodeHex(_ text: String) throws -> Data {
        let characters = Array(text.utf8)
        guard characters.count % 2 == 0 else { throw InternalSaoriError.invalidEncoding }
        var bytes = Data(capacity: characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = hexValue(characters[index]), let low = hexValue(characters[index + 1]) else {
                throw InternalSaoriError.invalidEncoding
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    /// base64 と base64url の両方の文字を読む。パディングはあってもなくてもよい。
    static func decodeBase64(_ text: String) throws -> Data {
        var body = text
        // パディングは末尾にだけ置ける。
        var padding = 0
        while body.hasSuffix("=") { body.removeLast(); padding += 1 }
        guard padding <= 2 else { throw InternalSaoriError.invalidEncoding }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/-_")
        guard body.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw InternalSaoriError.invalidEncoding }
        // 1 文字だけ余る長さは不正。パディングがあるなら、文字数と合っていること。
        guard body.count % 4 != 1 else { throw InternalSaoriError.invalidEncoding }
        if padding > 0, (body.count + padding) % 4 != 0 { throw InternalSaoriError.invalidEncoding }
        var standard = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard += "=" }
        guard let data = Data(base64Encoded: standard) else { throw InternalSaoriError.invalidEncoding }
        return data
    }

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func encodeBase32(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                output.append(base32Alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { output.append(base32Alphabet[(buffer << (5 - bits)) & 31]) }
        while output.count % 8 != 0 { output.append("=") }
        return output
    }

    /// RFC 4648。大文字小文字・パディングの有無は問わない。
    static func decodeBase32(_ text: String) throws -> Data {
        var body = text.uppercased()
        while body.hasSuffix("=") { body.removeLast() }
        var bytes = Data()
        var buffer = 0
        var bits = 0
        for character in body {
            guard let value = base32Alphabet.firstIndex(of: character) else { throw InternalSaoriError.invalidEncoding }
            buffer = (buffer << 5) | value
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> (bits - 8)) & 0xff))
                bits -= 8
            }
            buffer &= (1 << bits) - 1
        }
        // 余った端数のビットは 0 であること。
        guard buffer == 0, bits < 5 else { throw InternalSaoriError.invalidEncoding }
        return bytes
    }

    /// パーセントエンコードを戻す。`+` は空白に戻さない。
    static func decodePercent(_ text: String) throws -> Data {
        let characters = Array(text.utf8)
        var bytes = Data()
        var index = 0
        while index < characters.count {
            if characters[index] == 37 { // %
                // % の後ろに 16 進 2 桁が続くこと。
                guard index + 2 < characters.count,
                      let high = hexValue(characters[index + 1]), let low = hexValue(characters[index + 2]) else {
                    throw InternalSaoriError.invalidEncoding
                }
                bytes.append(high << 4 | low)
                index += 3
            } else {
                bytes.append(characters[index])
                index += 1
            }
        }
        return bytes
    }

    /// RFC 3986 の非予約文字（A-Z a-z 0-9 - . _ ~）以外をすべて %XX（大文字）にする。
    static func encodePercent(_ data: Data) -> String {
        var output = ""
        for byte in data {
            switch byte {
            case 48...57, 65...90, 97...122, 45, 46, 95, 126: output.append(Character(UnicodeScalar(byte)))
            default: output += String(format: "%%%02X", byte)
            }
        }
        return output
    }
}

/// BIP-173 の bech32（bech32m は読めない）。
enum Bech32 {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generators: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var checksum: UInt32 = 1
        for value in values {
            let top = checksum >> 25
            checksum = (checksum & 0x1ffffff) << 5 ^ UInt32(value)
            for index in 0..<5 where (top >> UInt32(index)) & 1 == 1 { checksum ^= generators[index] }
        }
        return checksum
    }

    private static func expand(hrp: String) -> [UInt8] {
        let bytes = Array(hrp.utf8)
        return bytes.map { $0 >> 5 } + [0] + bytes.map { $0 & 31 }
    }

    private static func convertBits(_ data: [UInt8], from: Int, to: Int, pad: Bool) -> [UInt8]? {
        var accumulator = 0
        var bits = 0
        var result: [UInt8] = []
        let maxValue = (1 << to) - 1
        for value in data {
            if Int(value) >> from != 0 { return nil }
            accumulator = (accumulator << from) | Int(value)
            bits += from
            while bits >= to {
                bits -= to
                result.append(UInt8((accumulator >> bits) & maxValue))
            }
            accumulator &= (1 << bits) - 1
        }
        if pad {
            if bits > 0 { result.append(UInt8((accumulator << (to - bits)) & maxValue)) }
        } else if bits >= from || (accumulator << (to - bits)) & maxValue != 0 {
            return nil
        }
        return result
    }

    /// hrp（1〜83 文字）とデータから bech32 の文字列を作る。
    static func encode(hrp: String, data: Data) throws -> String {
        guard (1...83).contains(hrp.count), hrp.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
            throw InternalSaoriError.invalidParameter
        }
        let lowered = hrp.lowercased()
        guard let five = convertBits(Array(data), from: 8, to: 5, pad: true) else { throw InternalSaoriError.invalidEncoding }
        let checksumInput = expand(hrp: lowered) + five + [0, 0, 0, 0, 0, 0]
        let mod = polymod(checksumInput) ^ 1
        let checksum = (0..<6).map { UInt8((mod >> UInt32(5 * (5 - $0))) & 31) }
        return lowered + "1" + String((five + checksum).map { charset[Int($0)] })
    }

    /// データの部分をバイト列にする。hrp は見ない。大文字だけ・小文字だけのどちらでもよい。
    static func decodeData(_ text: String) throws -> Data {
        guard text.lowercased() == text || text.uppercased() == text else { throw InternalSaoriError.invalidEncoding }
        let lowered = text.lowercased()
        guard let separator = lowered.lastIndex(of: "1") else { throw InternalSaoriError.invalidEncoding }
        let hrp = String(lowered[..<separator])
        let dataPart = lowered[lowered.index(after: separator)...]
        guard !hrp.isEmpty, dataPart.count >= 6, hrp.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
            throw InternalSaoriError.invalidEncoding
        }
        var values: [UInt8] = []
        for character in dataPart {
            guard let index = charset.firstIndex(of: character) else { throw InternalSaoriError.invalidEncoding }
            values.append(UInt8(index))
        }
        // チェックサム（bech32。bech32m の定数は受け付けない）。
        guard polymod(expand(hrp: hrp) + values) == 1 else { throw InternalSaoriError.invalidEncoding }
        guard let bytes = convertBits(Array(values.dropLast(6)), from: 5, to: 8, pad: false) else {
            throw InternalSaoriError.invalidEncoding
        }
        return Data(bytes)
    }
}
