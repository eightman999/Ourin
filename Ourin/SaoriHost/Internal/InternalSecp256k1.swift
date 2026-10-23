import CryptoKit
import Foundation

/// secp256k1 の BIP-340 Schnorr 署名と ECDH。OS の部品に無いので、自前の 256 ビット演算（InternalBigInt）で実装している。
/// 鍵を使う計算は定数時間ではない（ローカルのゴーストが呼ぶ用途を前提にしている）。
enum InternalSecp256k1 {
    static let field = Modulus(U256(hex: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F"), foldBits: 256, foldC: 0x1_0000_03D1)
    static let order = Modulus(U256(hex: "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141"))

    struct Affine { var x: U256; var y: U256 }
    private struct Jacobian { var x: U256; var y: U256; var z: U256 }

    static let generator = Affine(
        x: U256(hex: "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"),
        y: U256(hex: "483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"))

    // MARK: - 点の演算

    private static let infinity = Jacobian(x: .one, y: .one, z: .zero)

    private static func double(_ p: Jacobian) -> Jacobian {
        if p.z.isZero || p.y.isZero { return infinity }
        let f = field
        let a = f.sqr(p.x), b = f.sqr(p.y), c = f.sqr(b)
        let xb = f.add(p.x, b)
        var d = f.sub(f.sub(f.sqr(xb), a), c)
        d = f.add(d, d)
        let e = f.add(f.add(a, a), a)
        let x3 = f.sub(f.sqr(e), f.add(d, d))
        var c8 = f.add(c, c); c8 = f.add(c8, c8); c8 = f.add(c8, c8)
        let y3 = f.sub(f.mul(e, f.sub(d, x3)), c8)
        let yz = f.mul(p.y, p.z)
        return Jacobian(x: x3, y: y3, z: f.add(yz, yz))
    }

    private static func add(_ p: Jacobian, _ q: Jacobian) -> Jacobian {
        if p.z.isZero { return q }
        if q.z.isZero { return p }
        let f = field
        let z1z1 = f.sqr(p.z), z2z2 = f.sqr(q.z)
        let u1 = f.mul(p.x, z2z2), u2 = f.mul(q.x, z1z1)
        let s1 = f.mul(p.y, f.mul(q.z, z2z2)), s2 = f.mul(q.y, f.mul(p.z, z1z1))
        let h = f.sub(u2, u1), r = f.sub(s2, s1)
        if h.isZero { return r.isZero ? double(p) : infinity }
        let h2 = f.sqr(h), h3 = f.mul(h, h2)
        let v = f.mul(u1, h2)
        let x3 = f.sub(f.sub(f.sqr(r), h3), f.add(v, v))
        let y3 = f.sub(f.mul(r, f.sub(v, x3)), f.mul(s1, h3))
        return Jacobian(x: x3, y: y3, z: f.mul(h, f.mul(p.z, q.z)))
    }

    private static func multiply(_ k: U256, _ p: Affine) -> Jacobian {
        let base = Jacobian(x: p.x, y: p.y, z: .one)
        var result = infinity
        for index in stride(from: k.bitLength - 1, through: 0, by: -1) {
            result = double(result)
            if k.bit(index) { result = add(result, base) }
        }
        return result
    }

    private static func affine(_ p: Jacobian) -> Affine? {
        if p.z.isZero { return nil }
        let f = field
        let zInverse = f.inv(p.z)
        let z2 = f.sqr(zInverse)
        return Affine(x: f.mul(p.x, z2), y: f.mul(p.y, f.mul(z2, zInverse)))
    }

    private static func negate(_ p: Jacobian) -> Jacobian { Jacobian(x: p.x, y: field.neg(p.y), z: p.z) }

    static func isOnCurve(_ p: Affine) -> Bool {
        guard p.x < field.m, p.y < field.m else { return false }
        let right = field.add(field.mul(p.x, field.sqr(p.x)), U256(7))
        return field.sqr(p.y) == right
    }

    /// x 座標から、y の偶奇が指定どおりの点を求める。曲線上に無ければ nil。
    static func liftX(_ x: U256, oddY: Bool) -> Affine? {
        guard x < field.m else { return nil }
        let c = field.add(field.mul(x, field.sqr(x)), U256(7))
        let exponent = field.m.adding(.one).value.shiftedRight(2)
        var y = field.pow(c, exponent)
        guard field.sqr(y) == c else { return nil }
        if y.isOdd != oddY { y = field.neg(y) }
        return Affine(x: x, y: y)
    }

    // MARK: - BIP-340

    private static func taggedHash(_ tag: String, _ parts: Data...) -> Data {
        let tagHash = Data(SHA256.hash(data: Data(tag.utf8)))
        var hasher = SHA256()
        hasher.update(data: tagHash)
        hasher.update(data: tagHash)
        for part in parts { hasher.update(data: part) }
        return Data(hasher.finalize())
    }

    /// 秘密鍵（32 バイト、1 以上で位数未満）から x 座標だけの公開鍵（32 バイト）を求める。範囲外なら nil。
    static func publicKey(secret: Data) -> Data? {
        guard let d = scalar(secret), let point = affine(multiply(d, generator)) else { return nil }
        return point.x.bigEndianBytes
    }

    static func scalar(_ secret: Data) -> U256? {
        guard secret.count == 32 else { return nil }
        let d = U256(bytes: secret)
        return d.isZero || d >= order.m ? nil : d
    }

    /// 署名（64 バイト）。`message` はハッシュせずそのまま、`aux` は 32 バイト。鍵が不正なら nil。
    static func schnorrSign(secret: Data, message: Data, aux: Data) -> Data? {
        guard aux.count == 32, let secretScalar = scalar(secret), let p = affine(multiply(secretScalar, generator)) else { return nil }
        let d = p.y.isOdd ? order.neg(secretScalar) : secretScalar
        let auxHash = taggedHash("BIP0340/aux", aux)
        let t = Data(zip(d.bigEndianBytes, auxHash).map { $0 ^ $1 })
        let px = p.x.bigEndianBytes
        let nonceHash = taggedHash("BIP0340/nonce", t, px, message)
        let k0 = order.reduce(U256(bytes: nonceHash))
        guard !k0.isZero, let r = affine(multiply(k0, generator)) else { return nil }
        let k = r.y.isOdd ? order.neg(k0) : k0
        let rx = r.x.bigEndianBytes
        let e = order.reduce(U256(bytes: taggedHash("BIP0340/challenge", rx, px, message)))
        let s = order.add(k, order.mul(e, d))
        return rx + s.bigEndianBytes
    }

    /// 検証。公開鍵は x 座標だけの 32 バイト、署名は 64 バイト。形が違う・点でない・合わないときは false。
    static func schnorrVerify(publicKey: Data, message: Data, signature: Data) -> Bool {
        guard publicKey.count == 32, signature.count == 64,
              let p = liftX(U256(bytes: publicKey), oddY: false) else { return false }
        let r = U256(bytes: signature.prefix(32)), s = U256(bytes: signature.suffix(32))
        guard r < field.m, s < order.m else { return false }
        let e = order.reduce(U256(bytes: taggedHash("BIP0340/challenge", Data(signature.prefix(32)), Data(publicKey), message)))
        let sg = multiply(s, generator)
        let ep = negate(multiply(e, p))
        guard let point = affine(add(sg, ep)), !point.y.isOdd, point.x == r else { return false }
        return true
    }

    // MARK: - ECDH

    /// 共有の秘密（点の x 座標、32 バイト）。相手の公開鍵は 32 バイト（x のみ、y は偶数）・33 バイト（圧縮）・65 バイト（非圧縮）。不正なら nil。
    static func sharedSecret(secret: Data, peer: Data) -> Data? {
        guard let d = scalar(secret) else { return nil }
        let point: Affine?
        switch peer.count {
        case 32:
            point = liftX(U256(bytes: peer), oddY: false)
        case 33:
            let prefix = peer[peer.startIndex]
            point = prefix == 0x02 || prefix == 0x03 ? liftX(U256(bytes: peer.dropFirst()), oddY: prefix == 0x03) : nil
        case 65:
            let candidate = Affine(x: U256(bytes: peer.dropFirst().prefix(32)), y: U256(bytes: peer.suffix(32)))
            point = peer[peer.startIndex] == 0x04 && isOnCurve(candidate) ? candidate : nil
        default:
            point = nil
        }
        guard let point, let shared = affine(multiply(d, point)) else { return nil }
        return shared.x.bigEndianBytes
    }
}
