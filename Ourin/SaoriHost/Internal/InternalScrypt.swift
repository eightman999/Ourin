import CommonCrypto
import Foundation

/// scrypt（RFC 7914）。PBKDF2-HMAC-SHA256 は CommonCrypto、Salsa20/8 と ROMix は自前。
enum InternalScrypt {
    /// N × r × 128 バイトの上限（12MiB）。
    static let memoryLimit = 12 * 1024 * 1024

    /// - n: 2 以上の 2 の累乗でなければ invalid parameter（2 未満は out of range）。
    /// - r: 1 以上、p: 1〜16、length: 1〜1024。N × r × 128 が 12MiB を超えると out of range。
    static func derive(password: Data, salt: Data, n: Int, r: Int, p: Int, length: Int) throws -> Data {
        guard n >= 2 else { throw InternalSaoriError.outOfRange }
        guard n & (n - 1) == 0 else { throw InternalSaoriError.invalidParameter }
        guard (1...(memoryLimit / 128)).contains(r), (1...16).contains(p), (1...1024).contains(length) else {
            throw InternalSaoriError.outOfRange
        }
        guard n <= memoryLimit / (128 * r) else { throw InternalSaoriError.outOfRange }

        let blockWords = 32 * r
        var block = try pbkdf2(prf: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), password: password, salt: salt,
                               iterations: 1, length: p * 128 * r)
        var words = [UInt32](repeating: 0, count: p * blockWords)
        for index in 0..<words.count {
            let offset = index * 4
            words[index] = UInt32(block[offset]) | UInt32(block[offset + 1]) << 8
                | UInt32(block[offset + 2]) << 16 | UInt32(block[offset + 3]) << 24
        }

        let table = UnsafeMutablePointer<UInt32>.allocate(capacity: n * blockWords)
        let scratch = UnsafeMutablePointer<UInt32>.allocate(capacity: blockWords)
        let temp = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        let work = UnsafeMutablePointer<UInt32>.allocate(capacity: 16)
        defer { table.deallocate(); scratch.deallocate(); temp.deallocate(); work.deallocate() }

        words.withUnsafeMutableBufferPointer { buffer in
            for lane in 0..<p {
                let x = buffer.baseAddress! + lane * blockWords
                for i in 0..<n {
                    (table + i * blockWords).update(from: x, count: blockWords)
                    blockMix(x, scratch, temp, work, r)
                }
                for _ in 0..<n {
                    let j = Int(x[(2 * r - 1) * 16]) & (n - 1)
                    let v = table + j * blockWords
                    for k in 0..<blockWords { x[k] ^= v[k] }
                    blockMix(x, scratch, temp, work, r)
                }
            }
        }

        for (index, word) in words.enumerated() {
            let offset = index * 4
            block[offset] = UInt8(word & 0xff); block[offset + 1] = UInt8(word >> 8 & 0xff)
            block[offset + 2] = UInt8(word >> 16 & 0xff); block[offset + 3] = UInt8(word >> 24)
        }
        return try pbkdf2(prf: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), password: password, salt: block, iterations: 1, length: length)
    }

    // MARK: - ブロック

    @inline(__always) private static func rotate(_ value: UInt32, _ bits: UInt32) -> UInt32 { value << bits | value >> (32 - bits) }

    private static func blockMix(_ b: UnsafeMutablePointer<UInt32>, _ y: UnsafeMutablePointer<UInt32>,
                                 _ t: UnsafeMutablePointer<UInt32>, _ w: UnsafeMutablePointer<UInt32>, _ r: Int) {
        t.update(from: b + (2 * r - 1) * 16, count: 16)
        for i in 0..<(2 * r) {
            let source = b + i * 16
            for k in 0..<16 { t[k] ^= source[k] }
            salsa20_8(t, w)
            let destination = y + (i % 2 == 0 ? i / 2 : r + i / 2) * 16
            destination.update(from: t, count: 16)
        }
        b.update(from: y, count: 32 * r)
    }

    private static func salsa20_8(_ t: UnsafeMutablePointer<UInt32>, _ w: UnsafeMutablePointer<UInt32>) {
        w.update(from: t, count: 16)
        for _ in 0..<4 {
            w[4] ^= rotate(w[0] &+ w[12], 7); w[8] ^= rotate(w[4] &+ w[0], 9)
            w[12] ^= rotate(w[8] &+ w[4], 13); w[0] ^= rotate(w[12] &+ w[8], 18)
            w[9] ^= rotate(w[5] &+ w[1], 7); w[13] ^= rotate(w[9] &+ w[5], 9)
            w[1] ^= rotate(w[13] &+ w[9], 13); w[5] ^= rotate(w[1] &+ w[13], 18)
            w[14] ^= rotate(w[10] &+ w[6], 7); w[2] ^= rotate(w[14] &+ w[10], 9)
            w[6] ^= rotate(w[2] &+ w[14], 13); w[10] ^= rotate(w[6] &+ w[2], 18)
            w[3] ^= rotate(w[15] &+ w[11], 7); w[7] ^= rotate(w[3] &+ w[15], 9)
            w[11] ^= rotate(w[7] &+ w[3], 13); w[15] ^= rotate(w[11] &+ w[7], 18)
            w[1] ^= rotate(w[0] &+ w[3], 7); w[2] ^= rotate(w[1] &+ w[0], 9)
            w[3] ^= rotate(w[2] &+ w[1], 13); w[0] ^= rotate(w[3] &+ w[2], 18)
            w[6] ^= rotate(w[5] &+ w[4], 7); w[7] ^= rotate(w[6] &+ w[5], 9)
            w[4] ^= rotate(w[7] &+ w[6], 13); w[5] ^= rotate(w[4] &+ w[7], 18)
            w[11] ^= rotate(w[10] &+ w[9], 7); w[8] ^= rotate(w[11] &+ w[10], 9)
            w[9] ^= rotate(w[8] &+ w[11], 13); w[10] ^= rotate(w[9] &+ w[8], 18)
            w[12] ^= rotate(w[15] &+ w[14], 7); w[13] ^= rotate(w[12] &+ w[15], 9)
            w[14] ^= rotate(w[13] &+ w[12], 13); w[15] ^= rotate(w[14] &+ w[13], 18)
        }
        for k in 0..<16 { t[k] = t[k] &+ w[k] }
    }

    // MARK: - PBKDF2

    /// CommonCrypto の PBKDF2。空のパスワード・ソルトも渡せる。
    static func pbkdf2(prf: CCPseudoRandomAlgorithm, password: Data, salt: Data, iterations: Int, length: Int) throws -> Data {
        var derived = [UInt8](repeating: 0, count: length)
        let passwordBytes = [UInt8](password) + [0]
        let saltBytes = [UInt8](salt) + [0]
        let status = passwordBytes.withUnsafeBufferPointer { passwordPointer in
            saltBytes.withUnsafeBufferPointer { saltPointer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    UnsafeRawPointer(passwordPointer.baseAddress!).assumingMemoryBound(to: Int8.self), password.count,
                    saltPointer.baseAddress!, salt.count,
                    prf, UInt32(iterations), &derived, length
                )
            }
        }
        guard status == kCCSuccess else { throw InternalSaoriError.internalError }
        return Data(derived)
    }
}
