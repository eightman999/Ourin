import Foundation
import Security

/// RSA の鍵の読み込み・生成と署名（RS256 = RSASSA-PKCS1-v1_5 + SHA-256、PS256 = RSASSA-PSS + SHA-256、ソルト 32 バイト）。
/// 鍵は 2048〜4096 ビット。秘密鍵は PKCS#8 か PKCS#1、公開鍵は SubjectPublicKeyInfo か PKCS#1。
enum InternalRSA {
    static let invalidKey = InternalKeyCodec.invalidKey
    static let sizes = 2048...4096

    enum Scheme {
        case pkcs1v15, pss

        var algorithm: SecKeyAlgorithm {
            switch self {
            case .pkcs1v15: return .rsaSignatureMessagePKCS1v15SHA256
            case .pss: return .rsaSignatureMessagePSSSHA256
            }
        }
    }

    // MARK: - 鍵の読み込み

    static func privateKey(_ text: String) throws -> SecKey {
        let (der, label) = try InternalKeyCodec.derBytes(text)
        var candidates: [Data] = []
        if label != "PRIVATE KEY", let inner = pkcs1Private(der) { candidates.append(inner) } // PKCS#1
        if label != "RSA PRIVATE KEY", let inner = unwrapPKCS8(der) { candidates.append(inner) }
        for pkcs1 in candidates {
            if let key = makeKey(pkcs1, kind: kSecAttrKeyClassPrivate) { return key }
        }
        throw invalidKey
    }

    /// 公開鍵。公開鍵の代わりに秘密鍵を渡してもよい。
    static func publicKey(_ text: String) throws -> SecKey {
        let (der, _) = try InternalKeyCodec.derBytes(text)
        for pkcs1 in [unwrapSPKI(der), pkcs1Public(der)].compactMap({ $0 }) {
            if let key = makeKey(pkcs1, kind: kSecAttrKeyClassPublic) { return key }
        }
        if let key = try? privateKey(text), let publicKey = SecKeyCopyPublicKey(key) { return publicKey }
        throw invalidKey
    }

    private static func makeKey(_ pkcs1: Data, kind: CFString) -> SecKey? {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kind]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil),
              let info = SecKeyCopyAttributes(key) as? [CFString: Any],
              let bits = info[kSecAttrKeySizeInBits] as? Int, sizes.contains(bits) else { return nil }
        return key
    }

    // MARK: - 署名

    static func sign(_ message: Data, with key: SecKey, scheme: Scheme) throws -> Data {
        guard SecKeyIsAlgorithmSupported(key, .sign, scheme.algorithm) else { throw invalidKey }
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, scheme.algorithm, message as CFData, &error) else { throw InternalSaoriError.internalError }
        return signature as Data
    }

    /// 署名が合わない・長さが違うときは false。
    static func verify(_ signature: Data, for message: Data, with key: SecKey, scheme: Scheme) -> Bool {
        guard SecKeyIsAlgorithmSupported(key, .verify, scheme.algorithm) else { return false }
        return SecKeyVerifySignature(key, scheme.algorithm, message as CFData, signature as CFData, nil)
    }

    // MARK: - 鍵の生成

    /// 秘密鍵は PKCS#8、公開鍵は SubjectPublicKeyInfo の DER。
    static func generate(bits: Int) throws -> (privateKey: Data, publicKey: Data) {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: bits]
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil), let publicKey = SecKeyCopyPublicKey(key),
              let privatePKCS1 = SecKeyCopyExternalRepresentation(key, nil) as Data?,
              let publicPKCS1 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw InternalSaoriError.internalError }
        let algorithm = DER.sequence([DER.oidRSAEncryption, DER.null])
        let pkcs8 = DER.sequence([DER.integer(0), algorithm, DER.tlv(0x04, privatePKCS1)])
        let spki = DER.sequence([algorithm, DER.tlv(0x03, Data([0]) + publicPKCS1)])
        return (pkcs8, spki)
    }

    // MARK: - DER の取り出し

    private static let rsaEncryptionOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])

    /// PKCS#8（SEQUENCE { INTEGER 0, SEQUENCE { OID rsaEncryption, NULL }, OCTET STRING { PKCS#1 } }）の中の PKCS#1。
    private static func unwrapPKCS8(_ der: Data) -> Data? {
        guard var outer = DER.reader(der, tag: 0x30), DER.read(&outer, tag: 0x02) != nil,
              var algorithm = DER.reader(&outer, tag: 0x30), DER.read(&algorithm, tag: 0x06) == rsaEncryptionOID,
              let inner = DER.read(&outer, tag: 0x04) else { return nil }
        return pkcs1Private(inner)
    }

    /// SubjectPublicKeyInfo の中の PKCS#1。
    private static func unwrapSPKI(_ der: Data) -> Data? {
        guard var outer = DER.reader(der, tag: 0x30), var algorithm = DER.reader(&outer, tag: 0x30),
              DER.read(&algorithm, tag: 0x06) == rsaEncryptionOID,
              let bits = DER.read(&outer, tag: 0x03), bits.first == 0 else { return nil }
        return pkcs1Public(Data(bits.dropFirst()))
    }

    /// RSAPrivateKey: SEQUENCE { INTEGER 0, INTEGER n, … } の形か。
    private static func pkcs1Private(_ der: Data) -> Data? {
        guard var body = DER.reader(der, tag: 0x30), DER.read(&body, tag: 0x02) == Data([0]), DER.read(&body, tag: 0x02) != nil else { return nil }
        return der
    }

    /// RSAPublicKey: SEQUENCE { INTEGER n, INTEGER e }。
    private static func pkcs1Public(_ der: Data) -> Data? {
        guard var body = DER.reader(der, tag: 0x30), DER.read(&body, tag: 0x02) != nil, DER.read(&body, tag: 0x02) != nil, body.isEmpty else { return nil }
        return der
    }
}

/// 最小限の DER の読み書き。
enum DER {
    static let null = Data([0x05, 0x00])
    static let oidRSAEncryption = tlv(0x06, Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]))

    static func tlv(_ tag: UInt8, _ value: Data) -> Data {
        var data = Data([tag])
        if value.count < 0x80 {
            data.append(UInt8(value.count))
        } else {
            var length = value.count
            var bytes: [UInt8] = []
            while length > 0 { bytes.insert(UInt8(length & 0xff), at: 0); length >>= 8 }
            data.append(0x80 | UInt8(bytes.count))
            data.append(contentsOf: bytes)
        }
        return data + value
    }

    static func sequence(_ items: [Data]) -> Data { tlv(0x30, items.reduce(Data(), +)) }

    static func integer(_ value: UInt8) -> Data { tlv(0x02, Data([value])) }

    /// `data` が `tag` の要素 1 つだけで終わっていれば、その中身を読むリーダーを返す。
    static func reader(_ data: Data, tag: UInt8) -> Data? {
        var cursor = data
        guard let value = read(&cursor, tag: tag), cursor.isEmpty else { return nil }
        return value
    }

    /// 入れ子の要素の中身を読むリーダー。
    static func reader(_ data: inout Data, tag: UInt8) -> Data? { read(&data, tag: tag) }

    /// 先頭の要素を読み、`data` をその後ろへ進める。
    static func read(_ data: inout Data, tag: UInt8) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == tag else { return nil }
        var length = Int(bytes[1])
        var cursor = 2
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, bytes.count >= cursor + count else { return nil }
            length = (0..<count).reduce(0) { $0 << 8 | Int(bytes[cursor + $1]) }
            cursor += count
        }
        guard bytes.count >= cursor + length else { return nil }
        data = Data(bytes[(cursor + length)...])
        return Data(bytes[cursor..<(cursor + length)])
    }
}
