import Foundation

/// bcrypt（EksBlowfish）。`$2a$` `$2b$` `$2y$` は同じ計算（72 バイトで打ち切る）。
enum InternalBcrypt {
    static let alphabet = Array("./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8)

    /// 先頭の 72 バイト（終端の NUL を含む）を鍵にして、ハッシュ 23 バイトを返す。
    static func hash(password: Data, cost: Int, salt: Data) -> Data {
        precondition(salt.count == 16 && (4...31).contains(cost))
        var key = [UInt8](password) + [0]
        if key.count > 72 { key = Array(key.prefix(72)) }
        let saltWords = (0..<4).map { word(salt, $0 * 4) }

        let state = Blowfish()
        state.expandKey(salt: saltWords, key: key)
        let saltBytes = [UInt8](salt)
        for _ in 0..<(1 << cost) {
            state.expandKey(salt: nil, key: key)
            state.expandKey(salt: nil, key: saltBytes)
        }

        var text = Array("OrpheanBeholderScryDoubt".utf8)
        var words = (0..<6).map { word(Data(text), $0 * 4) }
        for _ in 0..<64 {
            for pair in 0..<3 {
                var l = words[pair * 2], r = words[pair * 2 + 1]
                state.encrypt(&l, &r)
                words[pair * 2] = l; words[pair * 2 + 1] = r
            }
        }
        text.removeAll()
        for value in words { text += [UInt8(value >> 24), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)] }
        return Data(text.prefix(23))
    }

    private static func word(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base]) << 24 | UInt32(data[base + 1]) << 16 | UInt32(data[base + 2]) << 8 | UInt32(data[base + 3])
    }

    // MARK: - bcrypt 流の base64（パディングなし。文字の並びが違う）

    static func encode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            let c1 = bytes[index]; index += 1
            output.append(alphabet[Int(c1 >> 2)])
            var c = (c1 & 0x03) << 4
            if index >= bytes.count { output.append(alphabet[Int(c)]); break }
            let c2 = bytes[index]; index += 1
            c |= c2 >> 4
            output.append(alphabet[Int(c)])
            c = (c2 & 0x0f) << 2
            if index >= bytes.count { output.append(alphabet[Int(c)]); break }
            let c3 = bytes[index]; index += 1
            c |= c3 >> 6
            output.append(alphabet[Int(c)])
            output.append(alphabet[Int(c3 & 0x3f)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// `count` バイトぶんを読む。文字が足りない・範囲外の文字なら nil。
    static func decode(_ text: String, count: Int) -> Data? {
        var values: [UInt8] = []
        for byte in text.utf8 {
            guard let position = alphabet.firstIndex(of: byte) else { return nil }
            values.append(UInt8(position))
        }
        var output: [UInt8] = []
        var index = 0
        while output.count < count {
            guard index + 1 < values.count else { return nil }
            output.append(values[index] << 2 | (values[index + 1] & 0x30) >> 4)
            if output.count >= count { break }
            guard index + 2 < values.count else { return nil }
            output.append((values[index + 1] & 0x0f) << 4 | (values[index + 2] & 0x3c) >> 2)
            if output.count >= count { break }
            guard index + 3 < values.count else { return nil }
            output.append((values[index + 2] & 0x03) << 6 | values[index + 3])
            index += 4
        }
        return Data(output)
    }
}

/// Blowfish。初期値は円周率の 16 進展開（`BlowfishTables`）。
final class Blowfish {
    private let p = UnsafeMutablePointer<UInt32>.allocate(capacity: 18)
    private let s = UnsafeMutablePointer<UInt32>.allocate(capacity: 1024)

    init() {
        BlowfishTables.p.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: 18) }
        BlowfishTables.s.withUnsafeBufferPointer { s.update(from: $0.baseAddress!, count: 1024) }
    }

    deinit {
        p.deallocate()
        s.deallocate()
    }

    @inline(__always)
    func encrypt(_ left: inout UInt32, _ right: inout UInt32) {
        var l = left, r = right
        l ^= p[0]
        var i = 1
        while i <= 16 {
            r ^= (((s[Int(l >> 24)] &+ s[256 + Int(l >> 16 & 0xff)]) ^ s[512 + Int(l >> 8 & 0xff)]) &+ s[768 + Int(l & 0xff)]) ^ p[i]
            l ^= (((s[Int(r >> 24)] &+ s[256 + Int(r >> 16 & 0xff)]) ^ s[512 + Int(r >> 8 & 0xff)]) &+ s[768 + Int(r & 0xff)]) ^ p[i + 1]
            i += 2
        }
        left = r ^ p[17]
        right = l
    }

    /// bcrypt の ExpandKey。`salt` が nil なら 0 のソルト（ソルトを混ぜない）。
    func expandKey(salt: [UInt32]?, key: [UInt8]) {
        var position = 0
        for index in 0..<18 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                value = value << 8 | UInt32(key[position])
                position = (position + 1) % key.count
            }
            p[index] ^= value
        }
        var l: UInt32 = 0, r: UInt32 = 0
        var saltIndex = 0
        func step(_ target: UnsafeMutablePointer<UInt32>) {
            if let salt {
                l ^= salt[saltIndex]; r ^= salt[saltIndex + 1]
                saltIndex = (saltIndex + 2) % 4
            }
            encrypt(&l, &r)
            target[0] = l; target[1] = r
        }
        for index in stride(from: 0, to: 18, by: 2) { step(p + index) }
        for index in stride(from: 0, to: 1024, by: 2) { step(s + index) }
    }
}
