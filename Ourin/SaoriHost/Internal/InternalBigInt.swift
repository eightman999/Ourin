import Foundation

/// 256 ビットの符号なし整数（64 ビットのリンブ 4 つ、下位が先）。楕円曲線の計算（secp256k1・Ed25519）のための最小限の実装。
struct U256: Equatable {
    var limbs: [UInt64]

    static let zero = U256(limbs: [0, 0, 0, 0])
    static let one = U256(1)

    init(limbs: [UInt64]) { self.limbs = limbs }
    init(_ value: UInt64) { limbs = [value, 0, 0, 0] }

    /// ビッグエンディアンのバイト列（32 バイトまで）。
    init(bytes: Data) {
        var result = [UInt64](repeating: 0, count: 4)
        for (index, byte) in Array(bytes).reversed().enumerated() where index < 32 {
            result[index / 8] |= UInt64(byte) << UInt64(8 * (index % 8))
        }
        limbs = result
    }

    init(littleEndian bytes: Data) { self.init(bytes: Data(bytes.reversed())) }

    init(hex: String) {
        var data = Data()
        var high: UInt8?
        for character in hex where !character.isWhitespace {
            let nibble = UInt8(character.hexDigitValue ?? 0)
            if let value = high { data.append(value << 4 | nibble); high = nil } else { high = nibble }
        }
        self.init(bytes: data)
    }

    var bigEndianBytes: Data {
        var data = Data()
        for limb in limbs.reversed() { for shift in stride(from: 56, through: 0, by: -8) { data.append(UInt8(truncatingIfNeeded: limb >> UInt64(shift))) } }
        return data
    }

    var littleEndianBytes: Data { Data(bigEndianBytes.reversed()) }

    var isZero: Bool { limbs.allSatisfy { $0 == 0 } }
    var isOdd: Bool { limbs[0] & 1 == 1 }

    func bit(_ index: Int) -> Bool { (limbs[index / 64] >> UInt64(index % 64)) & 1 == 1 }

    /// 最上位のビットの位置 + 1（0 なら 0）。
    var bitLength: Int {
        for index in (0..<4).reversed() where limbs[index] != 0 { return index * 64 + (64 - limbs[index].leadingZeroBitCount) }
        return 0
    }

    func compare(_ other: U256) -> Int {
        for index in (0..<4).reversed() {
            if limbs[index] != other.limbs[index] { return limbs[index] < other.limbs[index] ? -1 : 1 }
        }
        return 0
    }

    static func < (lhs: U256, rhs: U256) -> Bool { lhs.compare(rhs) < 0 }
    static func >= (lhs: U256, rhs: U256) -> Bool { lhs.compare(rhs) >= 0 }

    func adding(_ other: U256) -> (value: U256, carry: Bool) {
        var result = [UInt64](repeating: 0, count: 4)
        var carry = false
        for index in 0..<4 {
            let (s1, o1) = limbs[index].addingReportingOverflow(other.limbs[index])
            let (s2, o2) = s1.addingReportingOverflow(carry ? 1 : 0)
            result[index] = s2
            carry = o1 || o2
        }
        return (U256(limbs: result), carry)
    }

    func subtracting(_ other: U256) -> (value: U256, borrow: Bool) {
        var result = [UInt64](repeating: 0, count: 4)
        var borrow = false
        for index in 0..<4 {
            let (s1, o1) = limbs[index].subtractingReportingOverflow(other.limbs[index])
            let (s2, o2) = s1.subtractingReportingOverflow(borrow ? 1 : 0)
            result[index] = s2
            borrow = o1 || o2
        }
        return (U256(limbs: result), borrow)
    }

    func shiftedRight(_ count: Int) -> U256 {
        var result = [UInt64](repeating: 0, count: 4)
        let words = count / 64, bits = count % 64
        for index in 0..<4 where index + words < 4 {
            result[index] = limbs[index + words] >> UInt64(bits)
            if bits > 0, index + words + 1 < 4 { result[index] |= limbs[index + words + 1] << UInt64(64 - bits) }
        }
        return U256(limbs: result)
    }

    /// 512 ビットの積（8 リンブ）。
    func wideMultiplied(by other: U256) -> [UInt64] {
        var result = [UInt64](repeating: 0, count: 8)
        for row in 0..<4 {
            var carry: UInt64 = 0
            for column in 0..<4 {
                let (high, low) = limbs[row].multipliedFullWidth(by: other.limbs[column])
                let (s1, o1) = result[row + column].addingReportingOverflow(low)
                let (s2, o2) = s1.addingReportingOverflow(carry)
                result[row + column] = s2
                carry = high &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            result[row + 4] = carry
        }
        return result
    }

    /// 512 ビット（ビッグエンディアン 64 バイトまで）を 8 リンブにする。
    static func wide(bigEndian bytes: Data) -> [UInt64] {
        var result = [UInt64](repeating: 0, count: 8)
        for (index, byte) in Array(bytes).reversed().enumerated() where index < 64 {
            result[index / 8] |= UInt64(byte) << UInt64(8 * (index % 8))
        }
        return result
    }
}

/// 法 m での演算（m は素数）。`foldBits` / `foldC` を与えると m = 2^foldBits − foldC として素早く剰余を取る。無ければ一般の（遅い）剰余。
final class Modulus {
    let m: U256
    private let foldBits: Int
    private let foldC: UInt64

    init(_ m: U256, foldBits: Int = 0, foldC: UInt64 = 0) {
        self.m = m
        self.foldBits = foldBits
        self.foldC = foldC
    }

    /// 512 ビットの値を m で割った余り。
    func reduce(_ wide: [UInt64]) -> U256 {
        if foldBits == 0 { return slowReduce(wide) }
        var x = wide
        while true {
            let high = Self.shiftRight(x, foldBits)
            if high.allSatisfy({ $0 == 0 }) { break }
            var next = Self.lowBits(x, foldBits)
            var carry: UInt64 = 0
            for index in 0..<8 {
                let (h, l) = high[index].multipliedFullWidth(by: foldC)
                let (s1, o1) = next[index].addingReportingOverflow(l)
                let (s2, o2) = s1.addingReportingOverflow(carry)
                next[index] = s2
                carry = h &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0)
            }
            x = next
        }
        var result = U256(limbs: Array(x[0..<4]))
        while result >= m { result = result.subtracting(m).value }
        return result
    }

    func reduce(_ value: U256) -> U256 { reduce(value.limbs + [0, 0, 0, 0]) }

    /// 1 ビットずつ取り込んで引く素朴な剰余（スカラーの計算でだけ使うので遅くてよい）。
    private func slowReduce(_ wide: [UInt64]) -> U256 {
        var r = U256.zero
        for index in stride(from: 511, through: 0, by: -1) {
            let top = r.limbs[3] >> 63
            var carry = (wide[index / 64] >> UInt64(index % 64)) & 1
            for limb in 0..<4 {
                let next = r.limbs[limb] >> 63
                r.limbs[limb] = r.limbs[limb] << 1 | carry
                carry = next
            }
            if top == 1 || r >= m { r = r.subtracting(m).value }
        }
        return r
    }

    private static func shiftRight(_ x: [UInt64], _ count: Int) -> [UInt64] {
        var result = [UInt64](repeating: 0, count: 8)
        let words = count / 64, bits = count % 64
        for index in 0..<8 where index + words < 8 {
            result[index] = x[index + words] >> UInt64(bits)
            if bits > 0, index + words + 1 < 8 { result[index] |= x[index + words + 1] << UInt64(64 - bits) }
        }
        return result
    }

    private static func lowBits(_ x: [UInt64], _ count: Int) -> [UInt64] {
        var result = x
        let words = count / 64, bits = count % 64
        for index in 0..<8 {
            if index > words || (index == words && bits == 0) { result[index] = 0 }
            else if index == words { result[index] &= (UInt64(1) << UInt64(bits)) - 1 }
        }
        return result
    }

    func add(_ a: U256, _ b: U256) -> U256 {
        let (sum, carry) = a.adding(b)
        return carry || sum >= m ? sum.subtracting(m).value : sum
    }

    func sub(_ a: U256, _ b: U256) -> U256 {
        let (difference, borrow) = a.subtracting(b)
        return borrow ? difference.adding(m).value : difference
    }

    func neg(_ a: U256) -> U256 { a.isZero ? a : m.subtracting(a).value }
    func mul(_ a: U256, _ b: U256) -> U256 { reduce(a.wideMultiplied(by: b)) }
    func sqr(_ a: U256) -> U256 { mul(a, a) }

    func pow(_ base: U256, _ exponent: U256) -> U256 {
        var result = U256.one
        for index in stride(from: exponent.bitLength - 1, through: 0, by: -1) {
            result = sqr(result)
            if exponent.bit(index) { result = mul(result, base) }
        }
        return result
    }

    /// フェルマーの小定理による逆元（m が素数のとき）。
    func inv(_ a: U256) -> U256 { pow(a, m.subtracting(U256(2)).value) }
}
