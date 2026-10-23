import CommonCrypto
import CryptoKit
import Foundation

/// `internal_crypto` が使うアルゴリズムの名前と、ハッシュ・HMAC・ChaCha20 の実装。
enum InternalCryptoSupport {
    // MARK: - ハッシュ・HMAC のアルゴリズム

    enum HashAlgorithm: String {
        case md5, sha1, sha224, sha256, sha384, sha512

        var digestLength: Int {
            switch self {
            case .md5: return Int(CC_MD5_DIGEST_LENGTH)
            case .sha1: return Int(CC_SHA1_DIGEST_LENGTH)
            case .sha224: return Int(CC_SHA224_DIGEST_LENGTH)
            case .sha256: return Int(CC_SHA256_DIGEST_LENGTH)
            case .sha384: return Int(CC_SHA384_DIGEST_LENGTH)
            case .sha512: return Int(CC_SHA512_DIGEST_LENGTH)
            }
        }

        var hmacAlgorithm: CCHmacAlgorithm {
            switch self {
            case .md5: return CCHmacAlgorithm(kCCHmacAlgMD5)
            case .sha1: return CCHmacAlgorithm(kCCHmacAlgSHA1)
            case .sha224: return CCHmacAlgorithm(kCCHmacAlgSHA224)
            case .sha256: return CCHmacAlgorithm(kCCHmacAlgSHA256)
            case .sha384: return CCHmacAlgorithm(kCCHmacAlgSHA384)
            case .sha512: return CCHmacAlgorithm(kCCHmacAlgSHA512)
            }
        }

        /// PBKDF2 の疑似乱数関数。MD5 は OS が対応していない。
        var pbkdf2PRF: CCPseudoRandomAlgorithm? {
            switch self {
            case .md5: return nil
            case .sha1: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1)
            case .sha224: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA224)
            case .sha256: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
            case .sha384: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA384)
            case .sha512: return CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512)
            }
        }
    }

    /// アルゴリズム名。ハイフン・アンダースコアの有無と大文字小文字は区別しない（SHA-256 も sha_256 も sha256 と同じ）。
    /// OS の部品で賄えない名前（sha512-256・sha3-*・blake2*）は、知らない名前と同じ unsupported algorithm。
    static func hashAlgorithm(_ name: String) throws -> HashAlgorithm {
        let normalized = name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        guard let algorithm = HashAlgorithm(rawValue: normalized) else { throw InternalSaoriError.unsupportedAlgorithm }
        return algorithm
    }

    // MARK: - ハッシュ

    /// ハッシュの途中経過。大きなファイルを少しずつ読んで流し込める。
    final class Hasher {
        private enum State {
            case md5(Insecure.MD5), sha1(Insecure.SHA1), sha224(CC_SHA256_CTX), sha256(SHA256), sha384(SHA384), sha512(SHA512)
        }

        private var state: State

        init(_ algorithm: HashAlgorithm) {
            switch algorithm {
            case .md5: state = .md5(Insecure.MD5())
            case .sha1: state = .sha1(Insecure.SHA1())
            case .sha224:
                var context = CC_SHA256_CTX()
                CC_SHA224_Init(&context)
                state = .sha224(context)
            case .sha256: state = .sha256(SHA256())
            case .sha384: state = .sha384(SHA384())
            case .sha512: state = .sha512(SHA512())
            }
        }

        func update(_ data: Data) {
            switch state {
            case .md5(var hash): hash.update(data: data); state = .md5(hash)
            case .sha1(var hash): hash.update(data: data); state = .sha1(hash)
            case .sha224(var context):
                data.withUnsafeBytes { _ = CC_SHA224_Update(&context, $0.baseAddress, CC_LONG($0.count)) }
                state = .sha224(context)
            case .sha256(var hash): hash.update(data: data); state = .sha256(hash)
            case .sha384(var hash): hash.update(data: data); state = .sha384(hash)
            case .sha512(var hash): hash.update(data: data); state = .sha512(hash)
            }
        }

        func finalize() -> Data {
            switch state {
            case .md5(let hash): return Data(hash.finalize())
            case .sha1(let hash): return Data(hash.finalize())
            case .sha224(var context):
                var digest = [UInt8](repeating: 0, count: Int(CC_SHA224_DIGEST_LENGTH))
                CC_SHA224_Final(&digest, &context)
                return Data(digest)
            case .sha256(let hash): return Data(hash.finalize())
            case .sha384(let hash): return Data(hash.finalize())
            case .sha512(let hash): return Data(hash.finalize())
            }
        }
    }

    // MARK: - HMAC

    final class MAC {
        private var context = CCHmacContext()
        private let algorithm: HashAlgorithm

        init(_ algorithm: HashAlgorithm, key: Data) {
            self.algorithm = algorithm
            key.withUnsafeBytes { CCHmacInit(&context, algorithm.hmacAlgorithm, $0.baseAddress, $0.count) }
        }

        func update(_ data: Data) {
            data.withUnsafeBytes { CCHmacUpdate(&context, $0.baseAddress, $0.count) }
        }

        func finalize() -> Data {
            var output = [UInt8](repeating: 0, count: algorithm.digestLength)
            CCHmacFinal(&context, &output)
            return Data(output)
        }
    }

    static func hmac(_ algorithm: HashAlgorithm, key: Data, data: Data) -> Data {
        let mac = MAC(algorithm, key: key)
        mac.update(data)
        return mac.finalize()
    }

    /// 内容によらず同じ時間で比べる（長さが違えば false）。
    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    // MARK: - ChaCha20（RFC 8439。認証なし）

    /// ブロックカウンタは 0 から。nonce は 12 バイト。
    static func chaCha20(key: Data, nonce: Data, input: Data) -> Data {
        precondition(key.count == 32 && nonce.count == 12)
        func rotate(_ value: UInt32, _ bits: UInt32) -> UInt32 { value << bits | value >> (32 - bits) }
        func word(_ data: Data, _ index: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[data.startIndex + index * 4 + $1]) << UInt32(8 * $1) }
        }
        var state = [UInt32](repeating: 0, count: 16)
        state[0] = 0x6170_7865; state[1] = 0x3320_646e; state[2] = 0x7962_2d32; state[3] = 0x6b20_6574
        for index in 0..<8 { state[4 + index] = word(key, index) }
        for index in 0..<3 { state[13 + index] = word(nonce, index) }

        var output = Data(capacity: input.count)
        var counter: UInt32 = 0
        var offset = 0
        while offset < input.count {
            state[12] = counter
            var working = state
            func quarter(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
                working[a] = working[a] &+ working[b]; working[d] = rotate(working[d] ^ working[a], 16)
                working[c] = working[c] &+ working[d]; working[b] = rotate(working[b] ^ working[c], 12)
                working[a] = working[a] &+ working[b]; working[d] = rotate(working[d] ^ working[a], 8)
                working[c] = working[c] &+ working[d]; working[b] = rotate(working[b] ^ working[c], 7)
            }
            for _ in 0..<10 {
                quarter(0, 4, 8, 12); quarter(1, 5, 9, 13); quarter(2, 6, 10, 14); quarter(3, 7, 11, 15)
                quarter(0, 5, 10, 15); quarter(1, 6, 11, 12); quarter(2, 7, 8, 13); quarter(3, 4, 9, 14)
            }
            var block = [UInt8](repeating: 0, count: 64)
            for index in 0..<16 {
                let value = working[index] &+ state[index]
                for byte in 0..<4 { block[index * 4 + byte] = UInt8((value >> UInt32(8 * byte)) & 0xff) }
            }
            let count = min(64, input.count - offset)
            for index in 0..<count { output.append(input[input.startIndex + offset + index] ^ block[index]) }
            offset += count
            counter &+= 1
        }
        return output
    }
}
