import Foundation

/// Argon2id（RFC 9106）。`HashPassword` / `VerifyPassword` は PHC 文字列の読み書きと範囲の検査だけを行い、計算は `InternalArgon2Core` に任せる。
enum InternalArgon2 {
    /// 定義済みのバージョン。0x13（v=19）が現行、0x10（v=16。PHC 文字列に v= が無いものも同じ）は旧版。
    /// 旧版は 2 周目以降のブロックの書き込みが「上書き」ではなく「XOR」になる点だけが違う。
    static func deriveID(password: Data, salt: Data, iterations: Int, memoryKiB: Int, lanes: Int, length: Int,
                         version: Int) throws -> Data {
        InternalArgon2Core.deriveID(password: password, salt: salt, iterations: iterations, memoryKiB: memoryKiB, lanes: lanes,
                                    length: length, version: version)
    }

    /// バージョン 1.3（0x13）。
    static func deriveID(password: Data, salt: Data, iterations: Int, memoryKiB: Int, lanes: Int, length: Int) throws -> Data {
        try deriveID(password: password, salt: salt, iterations: iterations, memoryKiB: memoryKiB, lanes: lanes,
                     length: length, version: 0x13)
    }
}
