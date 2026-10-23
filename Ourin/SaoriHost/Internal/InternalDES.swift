import Foundation

/// DES と、それを使う crypt(3) の 2 方式（伝統的な DES と BSDi の拡張 DES）。
enum InternalDES {
    // MARK: - FIPS 46-3 の表（番号は 1 始まり、先頭ビットが 1）

    private static let ip: [UInt8] = [
        58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4,
        62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8,
        57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
        61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7,
    ]
    private static let fp: [UInt8] = [
        40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31,
        38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29,
        36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27,
        34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25,
    ]
    private static let permutation: [UInt8] = [
        16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10,
        2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25,
    ]
    private static let pc1: [UInt8] = [
        57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18,
        10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36,
        63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22,
        14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4,
    ]
    private static let pc2: [UInt8] = [
        14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10,
        23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2,
        41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48,
        44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32,
    ]
    private static let shifts: [Int] = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]
    private static let sBoxes: [[UInt8]] = [
        [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, 0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
         4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, 15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
        [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, 3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5,
         0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, 13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
        [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, 13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
         13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, 1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
        [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, 13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
         10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, 3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
        [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, 14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
         4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, 11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
        [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, 10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
         9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, 4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
        [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, 13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
         1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, 6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
        [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, 1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
         7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, 2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
    ]

    /// S ボックスの出力に P 置換まで掛けたもの（8 個 × 64 通り）。
    private static let sp: [[UInt32]] = (0..<8).map { box in
        (0..<64).map { input -> UInt32 in
            let row = (input & 0x20) >> 4 | (input & 1)
            let column = (input >> 1) & 0xf
            let nibble = UInt64(sBoxes[box][row * 16 + column])
            return UInt32(permute(nibble << UInt64(28 - 4 * box), permutation, inBits: 32))
        }
    }

    /// `value` の下位 `inBits` ビットを `table`（1 始まり、先頭ビットが 1）で並べ替える。
    private static func permute(_ value: UInt64, _ table: [UInt8], inBits: Int) -> UInt64 {
        var output: UInt64 = 0
        for entry in table { output = output << 1 | (value >> UInt64(inBits - Int(entry))) & 1 }
        return output
    }

    // MARK: - DES 本体

    /// 16 個の 48 ビット副鍵。
    static func subkeys(key: UInt64) -> [UInt64] {
        let permuted = permute(key, pc1, inBits: 64)
        var c = UInt32(permuted >> 28), d = UInt32(permuted & 0xfff_ffff)
        var keys: [UInt64] = []
        for shift in shifts {
            let s = UInt32(shift)
            c = (c << s | c >> (28 - s)) & 0xfff_ffff
            d = (d << s | d >> (28 - s)) & 0xfff_ffff
            keys.append(permute(UInt64(c) << 28 | UInt64(d), pc2, inBits: 56))
        }
        return keys
    }

    /// 0 のブロックではなく `block` から始めて `count` 回 DES をかける。
    /// `saltMask`（24 ビット）の立っているビット i について、E 拡張の出力の i 番目と i+24 番目を入れ替える（crypt(3) のソルト）。
    static func cipher(block: UInt64, keys: [UInt64], saltMask: UInt32 = 0, count: Int = 1) -> UInt64 {
        var state = permute(block, ip, inBits: 64)
        var l = UInt32(state >> 32), r = UInt32(state & 0xffff_ffff)
        for _ in 0..<count {
            for key in keys {
                let extended = UInt64(r & 1) << 33 | UInt64(r) << 1 | UInt64(r >> 31)
                var expanded: UInt64 = 0
                for group in 0..<8 { expanded = expanded << 6 | (extended >> UInt64(28 - 4 * group)) & 0x3f }
                if saltMask != 0 {
                    var high = UInt32(expanded >> 24), low = UInt32(expanded & 0xff_ffff)
                    let f = (high ^ low) & saltMask
                    high ^= f; low ^= f
                    expanded = UInt64(high) << 24 | UInt64(low)
                }
                expanded ^= key
                var f: UInt32 = 0
                for group in 0..<8 { f |= sp[group][Int((expanded >> UInt64(42 - 6 * group)) & 0x3f)] }
                (l, r) = (r, l ^ f)
            }
            (l, r) = (r, l)
        }
        state = UInt64(l) << 32 | UInt64(r)
        return permute(state, fp, inBits: 64)
    }

    /// 通常の DES（ECB の 1 ブロック）。
    static func encrypt(block: UInt64, key: UInt64) -> UInt64 {
        cipher(block: block, keys: subkeys(key: key))
    }

    // MARK: - crypt(3)

    static let alphabet = Array("./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)

    static func value(of character: UInt8) -> UInt32? {
        alphabet.firstIndex(of: character).map { UInt32($0) }
    }

    private static func keyBlock(_ bytes: [UInt8]) -> UInt64 {
        var key: UInt64 = 0
        for index in 0..<8 { key = key << 8 | UInt64(index < bytes.count ? bytes[index] << 1 : 0) }
        return key
    }

    /// 64 ビットを 11 文字にする（末尾は 2 ビットの 0 で埋める）。
    private static func encode(_ block: UInt64) -> String {
        var output: [UInt8] = []
        for index in 0..<10 { output.append(alphabet[Int((block >> UInt64(58 - 6 * index)) & 0x3f)]) }
        output.append(alphabet[Int((block & 0xf) << 2)])
        return String(decoding: output, as: UTF8.self)
    }

    /// 伝統的な DES の crypt(3)。パスワードは先頭の 8 バイトだけ使う。salt は 2 文字（呼び出し側で検査済み）。
    /// 戻り値は 11 文字のハッシュ部分。
    static func traditional(password: [UInt8], salt: [UInt8]) -> String {
        let key = keyBlock(password)
        let saltValue = value(of: salt[1])! << 6 | value(of: salt[0])!
        let block = cipher(block: 0, keys: subkeys(key: key), saltMask: saltMask(saltValue), count: 25)
        return encode(block)
    }

    /// BSDi の拡張 DES。パスワードの長さに制限が無い。count は反復回数、salt は 24 ビット。
    static func extended(password: [UInt8], count: Int, salt: UInt32) -> String {
        var key = keyBlock(password)
        var keys = subkeys(key: key)
        var offset = 8
        while offset < password.count {
            // 鍵自身で鍵を暗号化し、次の 8 バイトを XOR する。
            key = cipher(block: key, keys: keys)
            var mix: UInt64 = 0
            for index in 0..<8 {
                let position = offset + index
                mix = mix << 8 | UInt64(position < password.count ? password[position] << 1 : 0)
            }
            key ^= mix
            keys = subkeys(key: key)
            offset += 8
        }
        return encode(cipher(block: 0, keys: keys, saltMask: saltMask(salt), count: count))
    }

    /// ソルトの下位ビット i を、E 拡張の i 番目（24 ビットの上位から数える）へ。
    private static func saltMask(_ salt: UInt32) -> UInt32 {
        var mask: UInt32 = 0
        for index in 0..<24 where salt & (1 << UInt32(index)) != 0 { mask |= 0x80_0000 >> UInt32(index) }
        return mask
    }
}
