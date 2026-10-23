import CryptoKit
import Foundation

/// RFC 8032 の Ed25519 署名（決定的）。CryptoKit の署名は毎回変わるので、署名だけ自前で計算する（検証は CryptoKit）。
enum InternalEd25519 {
    private static let field = Modulus(U256(hex: "7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED"), foldBits: 255, foldC: 19)
    private static let order = Modulus(U256(hex: "1000000000000000000000000000000014DEF9DEA2F79CD65812631A5CF5D3ED"))

    private struct Point { var x: U256; var y: U256; var z: U256; var t: U256 }

    private static let identity = Point(x: .zero, y: .one, z: .one, t: .zero)

    /// d = −121665 / 121666
    private static let curveD: U256 = field.neg(field.mul(U256(121_665), field.inv(U256(121_666))))
    private static let twoD: U256 = field.add(curveD, curveD)

    private static let basePoint: Point = {
        let f = field
        let y = f.mul(U256(4), f.inv(U256(5)))
        let y2 = f.sqr(y)
        let x2 = f.mul(f.sub(y2, .one), f.inv(f.add(f.mul(curveD, y2), .one)))
        var x = f.pow(x2, f.m.adding(U256(3)).value.shiftedRight(3))
        if f.sqr(x) != x2 {
            let sqrtMinusOne = f.pow(U256(2), f.m.subtracting(.one).value.shiftedRight(2))
            x = f.mul(x, sqrtMinusOne)
        }
        if x.isOdd { x = f.neg(x) }
        return Point(x: x, y: y, z: .one, t: f.mul(x, y))
    }()

    private static func add(_ p: Point, _ q: Point) -> Point {
        let f = field
        let a = f.mul(f.sub(p.y, p.x), f.sub(q.y, q.x))
        let b = f.mul(f.add(p.y, p.x), f.add(q.y, q.x))
        let c = f.mul(f.mul(p.t, twoD), q.t)
        let d = f.mul(f.add(p.z, p.z), q.z)
        let e = f.sub(b, a), ff = f.sub(d, c), g = f.add(d, c), h = f.add(b, a)
        return Point(x: f.mul(e, ff), y: f.mul(g, h), z: f.mul(ff, g), t: f.mul(e, h))
    }

    private static func multiply(_ k: U256, _ p: Point) -> Point {
        var result = identity
        for index in stride(from: k.bitLength - 1, through: 0, by: -1) {
            result = add(result, result)
            if k.bit(index) { result = add(result, p) }
        }
        return result
    }

    private static func encode(_ p: Point) -> Data {
        let zInverse = field.inv(p.z)
        let x = field.mul(p.x, zInverse), y = field.mul(p.y, zInverse)
        var bytes = y.littleEndianBytes
        if x.isOdd { bytes[bytes.count - 1] |= 0x80 }
        return bytes
    }

    private static func hash(_ parts: Data...) -> U256 {
        var hasher = SHA512()
        for part in parts { hasher.update(data: part) }
        // ダイジェストはリトルエンディアンの整数として読む。
        return order.reduce(U256.wide(bigEndian: Data(Data(hasher.finalize()).reversed())))
    }

    /// 署名（64 バイト）。`seed` は 32 バイトの秘密鍵。
    static func sign(seed: Data, message: Data) -> Data {
        let digest = Data(SHA512.hash(data: seed))
        var scalarBytes = Array(digest.prefix(32))
        scalarBytes[0] &= 248
        scalarBytes[31] &= 127
        scalarBytes[31] |= 64
        let a = U256(littleEndian: Data(scalarBytes))
        let prefix = Data(digest.suffix(32))
        let publicKey = encode(multiply(a, basePoint))
        let r = hash(prefix, message)
        let encodedR = encode(multiply(r, basePoint))
        let k = hash(encodedR, publicKey, message)
        let s = order.add(r, order.mul(k, order.reduce(a)))
        return encodedR + s.littleEndianBytes
    }

    static func publicKey(seed: Data) -> Data {
        var scalarBytes = Array(Data(SHA512.hash(data: seed)).prefix(32))
        scalarBytes[0] &= 248
        scalarBytes[31] &= 127
        scalarBytes[31] |= 64
        return encode(multiply(U256(littleEndian: Data(scalarBytes)), basePoint))
    }
}
