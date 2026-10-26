import Foundation

/// 大きさの違うハッシュを同じ形で流し込むための口（SHA-3・SHA-512/256・BLAKE2 用）。
protocol InternalStreamingHash: AnyObject {
    func update(_ data: Data)
    func finalize() -> Data
}

/// SHA-3（FIPS 202）。Keccak-f[1600] のスポンジ。
final class SHA3Hash: InternalStreamingHash {
    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808a, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808b, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008a, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000a,
        0x0000_0000_8000_808b, 0x8000_0000_0000_008b, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800a, 0x8000_0000_8000_000a,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]
    private static let rotations: [UInt64] = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44]
    private static let lanes: [Int] = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1]

    private var state = [UInt64](repeating: 0, count: 25)
    private let rate: Int
    private let outputLength: Int
    private var buffer = [UInt8]()

    /// - Parameter outputBits: 224 / 256 / 384 / 512。
    init(outputBits: Int) {
        outputLength = outputBits / 8
        rate = 200 - 2 * outputLength
        buffer.reserveCapacity(rate)
    }

    private static func permute(_ a: inout [UInt64]) {
        var c = [UInt64](repeating: 0, count: 5)
        for round in 0..<24 {
            for x in 0..<5 { c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ (c[(x + 1) % 5] << 1 | c[(x + 1) % 5] >> 63)
                for y in stride(from: 0, to: 25, by: 5) { a[y + x] ^= d }
            }
            var current = a[1]
            for index in 0..<24 {
                let lane = lanes[index]
                let saved = a[lane]
                let r = rotations[index]
                a[lane] = current << r | current >> (64 - r)
                current = saved
            }
            for y in stride(from: 0, to: 25, by: 5) {
                for x in 0..<5 { c[x] = a[y + x] }
                for x in 0..<5 { a[y + x] = c[x] ^ (~c[(x + 1) % 5] & c[(x + 2) % 5]) }
            }
            a[0] ^= roundConstants[round]
        }
    }

    private func absorb(_ block: ArraySlice<UInt8>) {
        var index = block.startIndex
        for lane in 0..<(rate / 8) {
            var word: UInt64 = 0
            for byte in 0..<8 { word |= UInt64(block[index + byte]) << UInt64(8 * byte) }
            state[lane] ^= word
            index += 8
        }
        Self.permute(&state)
    }

    func update(_ data: Data) {
        buffer.append(contentsOf: data)
        var offset = 0
        while buffer.count - offset >= rate {
            absorb(buffer[offset..<(offset + rate)])
            offset += rate
        }
        if offset > 0 { buffer.removeFirst(offset) }
    }

    func finalize() -> Data {
        var last = buffer + [UInt8](repeating: 0, count: rate - buffer.count)
        last[buffer.count] ^= 0x06
        last[rate - 1] ^= 0x80
        absorb(last[...])
        var output = Data()
        for lane in 0..<(outputLength + 7) / 8 {
            for byte in 0..<8 { output.append(UInt8((state[lane] >> UInt64(8 * byte)) & 0xff)) }
        }
        return output.prefix(outputLength)
    }
}

/// SHA-512/256（FIPS 180-4 §5.3.6.2）。SHA-512 の計算に別の初期値を使い、先頭 32 バイトを取る。
final class SHA512_256Hash: InternalStreamingHash {
    private static let k: [UInt64] = [
        0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538,
        0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe,
        0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235,
        0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
        0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab,
        0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
        0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed,
        0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
        0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218,
        0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
        0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373,
        0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
        0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c,
        0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6,
        0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc,
        0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
    ]
    private var h: [UInt64] = [
        0x22312194FC2BF72C, 0x9F555FA3C84C64C2, 0x2393B86B6F53B151, 0x963877195940EABD,
        0x96283EE2A88EFFE3, 0xBE5E1E2553863992, 0x2B0199FC2C85B8AA, 0x0EB72DDC81C52CA2,
    ]
    private var buffer = [UInt8]()
    private var total: UInt64 = 0

    private func compress(_ block: ArraySlice<UInt8>) {
        var w = [UInt64](repeating: 0, count: 80)
        let base = block.startIndex
        for t in 0..<16 {
            var word: UInt64 = 0
            for byte in 0..<8 { word = word << 8 | UInt64(block[base + t * 8 + byte]) }
            w[t] = word
        }
        func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { x >> n | x << (64 - n) }
        for t in 16..<80 {
            let s0 = rotr(w[t - 15], 1) ^ rotr(w[t - 15], 8) ^ (w[t - 15] >> 7)
            let s1 = rotr(w[t - 2], 19) ^ rotr(w[t - 2], 61) ^ (w[t - 2] >> 6)
            w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
        }
        var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
        for t in 0..<80 {
            let t1 = hh &+ (rotr(e, 14) ^ rotr(e, 18) ^ rotr(e, 41)) &+ ((e & f) ^ (~e & g)) &+ Self.k[t] &+ w[t]
            let t2 = (rotr(a, 28) ^ rotr(a, 34) ^ rotr(a, 39)) &+ ((a & b) ^ (a & c) ^ (b & c))
            hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
        }
        h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
        h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
    }

    func update(_ data: Data) {
        total &+= UInt64(data.count)
        buffer.append(contentsOf: data)
        var offset = 0
        while buffer.count - offset >= 128 {
            compress(buffer[offset..<(offset + 128)])
            offset += 128
        }
        if offset > 0 { buffer.removeFirst(offset) }
    }

    func finalize() -> Data {
        var tail = buffer
        tail.append(0x80)
        while tail.count % 128 != 112 { tail.append(0) }
        tail.append(contentsOf: [UInt8](repeating: 0, count: 8))
        let bits = total &* 8
        for shift in stride(from: 56, through: 0, by: -8) { tail.append(UInt8((bits >> UInt64(shift)) & 0xff)) }
        for offset in stride(from: 0, to: tail.count, by: 128) { compress(tail[offset..<(offset + 128)]) }
        var output = Data()
        for word in h.prefix(4) {
            for shift in stride(from: 56, through: 0, by: -8) { output.append(UInt8((word >> UInt64(shift)) & 0xff)) }
        }
        return output
    }
}
