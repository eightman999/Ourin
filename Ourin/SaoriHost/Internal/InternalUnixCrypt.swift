import Foundation

/// MD5-crypt（`$1$`・`$apr1$`）と SHA-crypt（`$5$`・`$6$`。Drepper の仕様）。
/// どちらもハッシュ部分の文字列だけを返す。
enum InternalUnixCrypt {
    typealias Hasher = InternalCryptoSupport.Hasher

    private static let alphabet = InternalDES.alphabet

    private static func hash(_ algorithm: InternalCryptoSupport.HashAlgorithm, _ parts: [Data]) -> Data {
        let hasher = Hasher(algorithm)
        for part in parts { hasher.update(part) }
        return hasher.finalize()
    }

    /// 24 ビットを `count` 文字にする（下位 6 ビットから）。
    private static func to64(_ value: UInt32, _ count: Int, into output: inout [UInt8]) {
        var v = value
        for _ in 0..<count {
            output.append(alphabet[Int(v & 0x3f)])
            v >>= 6
        }
    }

    // MARK: - MD5-crypt

    /// `magic` は `$1$` か `$apr1$`。salt は 8 バイトまで（呼び出し側で切る）。
    static func md5(password: Data, salt: Data, magic: String) -> String {
        let magicData = Data(magic.utf8)
        let alternate = hash(.md5, [password, salt, password])
        let context = Hasher(.md5)
        context.update(password); context.update(magicData); context.update(salt)
        var remaining = password.count
        while remaining > 0 {
            context.update(alternate.prefix(min(16, remaining)))
            remaining -= 16
        }
        var bits = password.count
        while bits != 0 {
            context.update(bits & 1 != 0 ? Data([0]) : password.prefix(1))
            bits >>= 1
        }
        var result = context.finalize()
        for round in 0..<1000 {
            let next = Hasher(.md5)
            next.update(round & 1 != 0 ? password : result)
            if round % 3 != 0 { next.update(salt) }
            if round % 7 != 0 { next.update(password) }
            next.update(round & 1 != 0 ? result : password)
            result = next.finalize()
        }
        let f = [UInt8](result)
        var output: [UInt8] = []
        let groups: [(Int, Int, Int)] = [(0, 6, 12), (1, 7, 13), (2, 8, 14), (3, 9, 15), (4, 10, 5)]
        for (a, b, c) in groups { to64(UInt32(f[a]) << 16 | UInt32(f[b]) << 8 | UInt32(f[c]), 4, into: &output) }
        to64(UInt32(f[11]), 2, into: &output)
        return String(decoding: output, as: UTF8.self)
    }

    // MARK: - SHA-crypt

    enum SHAVariant {
        case sha256, sha512

        var algorithm: InternalCryptoSupport.HashAlgorithm { self == .sha256 ? .sha256 : .sha512 }
        /// ハッシュ部分の文字数。
        var encodedLength: Int { self == .sha256 ? 43 : 86 }
    }

    /// salt は 16 バイトまで（呼び出し側で切る）。rounds は 1000 以上（呼び出し側で丸める）。
    static func sha(password: Data, salt: Data, rounds: Int, variant: SHAVariant) -> String {
        let algorithm = variant.algorithm
        let length = algorithm.digestLength
        let b = hash(algorithm, [password, salt, password])

        let a = Hasher(algorithm)
        a.update(password); a.update(salt)
        var count = password.count
        while count > length {
            a.update(b)
            count -= length
        }
        a.update(b.prefix(count))
        count = password.count
        while count > 0 {
            a.update(count & 1 != 0 ? b : password)
            count >>= 1
        }
        var digest = a.finalize()

        let dp = Hasher(algorithm)
        for _ in 0..<password.count { dp.update(password) }
        let p = repeated(dp.finalize(), to: password.count)
        let ds = Hasher(algorithm)
        for _ in 0..<(16 + Int(digest[digest.startIndex])) { ds.update(salt) }
        let s = repeated(ds.finalize(), to: salt.count)

        for round in 0..<rounds {
            let c = Hasher(algorithm)
            c.update(round & 1 != 0 ? p : digest)
            if round % 3 != 0 { c.update(s) }
            if round % 7 != 0 { c.update(p) }
            c.update(round & 1 != 0 ? digest : p)
            digest = c.finalize()
        }

        let f = [UInt8](digest)
        var output: [UInt8] = []
        func group(_ a: Int, _ b: Int, _ c: Int, _ count: Int) {
            to64(UInt32(f[a]) << 16 | UInt32(f[b]) << 8 | UInt32(f[c]), count, into: &output)
        }
        switch variant {
        case .sha512:
            let order: [(Int, Int, Int)] = [
                (0, 21, 42), (22, 43, 1), (44, 2, 23), (3, 24, 45), (25, 46, 4), (47, 5, 26), (6, 27, 48), (28, 49, 7),
                (50, 8, 29), (9, 30, 51), (31, 52, 10), (53, 11, 32), (12, 33, 54), (34, 55, 13), (56, 14, 35),
                (15, 36, 57), (37, 58, 16), (59, 17, 38), (18, 39, 60), (40, 61, 19), (62, 20, 41),
            ]
            for (x, y, z) in order { group(x, y, z, 4) }
            to64(UInt32(f[63]), 2, into: &output)
        case .sha256:
            let order: [(Int, Int, Int)] = [
                (0, 10, 20), (21, 1, 11), (12, 22, 2), (3, 13, 23), (24, 4, 14), (15, 25, 5), (6, 16, 26),
                (27, 7, 17), (18, 28, 8), (9, 19, 29),
            ]
            for (x, y, z) in order { group(x, y, z, 4) }
            to64(UInt32(f[31]) << 8 | UInt32(f[30]), 3, into: &output)
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// `data` を繰り返して `count` バイトにする。
    private static func repeated(_ data: Data, to count: Int) -> Data {
        var output = Data(capacity: count)
        while output.count + data.count <= count { output.append(data) }
        output.append(data.prefix(count - output.count))
        return output
    }
}
