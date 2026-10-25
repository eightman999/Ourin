import CryptoKit
import Foundation

/// 公開鍵暗号の鍵の読み込み。1 行の DER の base64 か、PEM（改行を空白にしたものも可）で渡される。
/// 秘密鍵は PKCS#8（Ed25519 / P-256）、P-256 は SEC1（`EC PRIVATE KEY`）も読める。公開鍵は SubjectPublicKeyInfo。
enum InternalKeyCodec {
    static let invalidKey = InternalSaoriError.badRequest("invalid key")

    /// Ed25519 の PKCS#8（秘密鍵 32 バイトの前）と SubjectPublicKeyInfo（公開鍵 32 バイトの前）の固定の前置き。
    static let ed25519PKCS8 = Data([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20])
    static let ed25519SPKI = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])

    /// PEM（`-----BEGIN ...-----` から `-----END` まで）か、DER の base64（標準・URL セーフのどちらも可）。
    static func derBytes(_ text: String) throws -> (der: Data, label: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("-----BEGIN") {
            guard let labelStart = trimmed.range(of: "-----BEGIN "),
                  let labelEnd = trimmed.range(of: "-----", range: labelStart.upperBound..<trimmed.endIndex),
                  let footer = trimmed.range(of: "-----END", range: labelEnd.upperBound..<trimmed.endIndex) else { throw invalidKey }
            let label = String(trimmed[labelStart.upperBound..<labelEnd.lowerBound])
            let body = trimmed[labelEnd.upperBound..<footer.lowerBound].filter { !$0.isWhitespace }
            guard let der = try? InternalSaoriCodec.decodeBase64(String(body)) else { throw invalidKey }
            return (der, label)
        }
        guard let der = try? InternalSaoriCodec.decodeBase64(trimmed.filter { !$0.isWhitespace }) else { throw invalidKey }
        return (der, nil)
    }

    // MARK: - Ed25519

    static func ed25519PrivateKey(_ text: String) throws -> Curve25519.Signing.PrivateKey {
        let der = try derBytes(text).der
        guard der.count == ed25519PKCS8.count + 32, der.prefix(ed25519PKCS8.count) == ed25519PKCS8,
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: der.suffix(32)) else { throw invalidKey }
        return key
    }

    /// 公開鍵。公開鍵の代わりに秘密鍵を渡してもよい。
    static func ed25519PublicKey(_ text: String) throws -> Curve25519.Signing.PublicKey {
        let der = try derBytes(text).der
        if der.count == ed25519SPKI.count + 32, der.prefix(ed25519SPKI.count) == ed25519SPKI,
           let key = try? Curve25519.Signing.PublicKey(rawRepresentation: der.suffix(32)) {
            return key
        }
        return try ed25519PrivateKey(text).publicKey
    }

    // MARK: - P-256

    static func p256PrivateKey(_ text: String) throws -> P256.Signing.PrivateKey {
        let (der, label) = try derBytes(text)
        if label == "EC PRIVATE KEY" || label == nil {
            if let scalar = sec1Scalar(der), let key = try? P256.Signing.PrivateKey(rawRepresentation: scalar) { return key }
        }
        if let key = try? P256.Signing.PrivateKey(derRepresentation: der) { return key }
        throw invalidKey
    }

    static func p256PublicKey(_ text: String) throws -> P256.Signing.PublicKey {
        let der = try derBytes(text).der
        if let key = try? P256.Signing.PublicKey(derRepresentation: der) { return key }
        return try p256PrivateKey(text).publicKey
    }

    /// SEC1 の ECPrivateKey（SEQUENCE { INTEGER 1, OCTET STRING 秘密鍵, ... }）から 32 バイトの秘密鍵を取り出す。
    private static func sec1Scalar(_ der: Data) -> Data? {
        var reader = DERReader(der)
        guard let sequence = reader.read(tag: 0x30) else { return nil }
        var inner = DERReader(sequence)
        guard let version = inner.read(tag: 0x02), version == Data([0x01]), let scalar = inner.read(tag: 0x04), scalar.count == 32 else { return nil }
        return scalar
    }

    /// 最小限の DER の読み取り（タグ・長さ・値）。
    private struct DERReader {
        private let data: Data
        private var position: Int

        init(_ data: Data) {
            self.data = data
            self.position = data.startIndex
        }

        mutating func read(tag: UInt8) -> Data? {
            guard position < data.endIndex, data[position] == tag else { return nil }
            var cursor = position + 1
            guard cursor < data.endIndex else { return nil }
            var length = Int(data[cursor])
            cursor += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count > 0, count <= 4, cursor + count <= data.endIndex else { return nil }
                length = (0..<count).reduce(0) { $0 << 8 | Int(data[cursor + $1]) }
                cursor += count
            }
            guard cursor + length <= data.endIndex else { return nil }
            position = cursor + length
            return data.subdata(in: cursor..<(cursor + length))
        }
    }
}
