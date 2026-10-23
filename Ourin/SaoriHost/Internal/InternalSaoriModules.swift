import Foundation
import Security

extension InternalSaoriRegistry {
    /// Ourin が実装している内蔵モジュール。
    static func standardModules() -> [InternalSaoriModule] {
        [InternalSystemModule(), InternalRandomModule(), InternalTimeModule(), InternalTextModule(), InternalDataModule()]
    }
}

// MARK: - internal_system

/// 内蔵モジュールの一覧（結果は Result にカンマ区切り、Value0 以降に 1 つずつ）。
struct InternalSystemModule: InternalSaoriModule {
    let name = "internal_system"

    var functions: [InternalSaoriFunction] {
        [
            InternalSaoriFunction("ListModules", positionals: 0) { _, _ in
                let names = InternalSaoriRegistry.shared.moduleNames
                return InternalSaoriResult(names.joined(separator: ","), values: names)
            },
            InternalSaoriFunction("ListFunctions", positionals: 1) { call, _ in
                guard let module = InternalSaoriRegistry.shared.module(named: call.positionals[0]) else {
                    throw InternalSaoriError.unknownModule
                }
                let names = module.functions.map(\.name)
                return InternalSaoriResult(names.joined(separator: ","), values: names)
            }
        ]
    }
}

// MARK: - internal_random

/// 暗号論的に安全な乱数（`SecRandomCopyBytes`）。
struct InternalRandomModule: InternalSaoriModule {
    let name = "internal_random"

    static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw InternalSaoriError.internalError }
        return Data(bytes)
    }

    static func randomUInt64() throws -> UInt64 {
        try randomBytes(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// `[0, bound)` の一様な乱数（偏りを避けるため棄却法）。
    static func uniform(below bound: UInt64) throws -> UInt64 {
        guard bound > 1 else { return 0 }
        let limit = UInt64.max - UInt64.max % bound
        while true {
            let value = try randomUInt64()
            if value < limit { return value % bound }
        }
    }

    var functions: [InternalSaoriFunction] {
        [
            // 1〜1024 バイト。範囲外は out of range。
            InternalSaoriFunction("Bytes", positionals: 1, options: ["out"]) { call, _ in
                guard let count = Int(call.positionals[0]) else { throw InternalSaoriError.invalidParameter }
                guard (1...1024).contains(count) else { throw InternalSaoriError.outOfRange }
                let data = try Self.randomBytes(count)
                return InternalSaoriResult(try InternalSaoriCodec.encode(data, format: call.option("out"), defaultFormat: "hex", charset: nil))
            },
            // 最小以上・最大以下の整数を、偏りなく 1 つ選ぶ（64 ビット符号付き整数の範囲）。
            InternalSaoriFunction("Number", positionals: 2) { call, _ in
                guard let minimum = Int64(call.positionals[0]), let maximum = Int64(call.positionals[1]), minimum <= maximum else {
                    throw InternalSaoriError.invalidParameter
                }
                let span = UInt64(bitPattern: maximum &- minimum)
                let offset = span == UInt64.max ? try Self.randomUInt64() : try Self.uniform(below: span + 1)
                return InternalSaoriResult(String(minimum &+ Int64(bitPattern: offset)))
            },
            // UUID（RFC 9562）。バージョン 4 は全体がランダム、7 は先頭 48 ビットが UNIX 時刻（ミリ秒）。
            InternalSaoriFunction("UUID", positionals: 0, options: ["version"]) { call, _ in
                let version = call.option("version") ?? "4"
                guard version == "4" || version == "7" else { throw InternalSaoriError.invalidParameter }
                var bytes = [UInt8](try Self.randomBytes(16))
                if version == "7" {
                    let milliseconds = UInt64(Date().timeIntervalSince1970 * 1000)
                    for index in 0..<6 { bytes[index] = UInt8((milliseconds >> UInt64(8 * (5 - index))) & 0xff) }
                }
                bytes[6] = bytes[6] & 0x0f | (version == "7" ? 0x70 : 0x40)
                bytes[8] = bytes[8] & 0x3f | 0x80
                let hex = bytes.map { String(format: "%02x", $0) }.joined()
                // 8-4-4-4-12 の正規の表記。
                let boundaries = [0, 8, 12, 16, 20, 32]
                let parts = zip(boundaries, boundaries.dropFirst()).map { start, end in
                    String(hex.dropFirst(start).prefix(end - start))
                }
                return InternalSaoriResult(parts.joined(separator: "-"))
            }
        ]
    }
}

// MARK: - internal_text

struct InternalTextModule: InternalSaoriModule {
    let name = "internal_text"

    var functions: [InternalSaoriFunction] {
        [
            // Unicode の正規化（NFC / NFD / NFKC / NFKD）。
            InternalSaoriFunction("Normalize", positionals: 2) { call, _ in
                let text = call.positionals[1]
                switch call.positionals[0].uppercased() {
                case "NFC": return InternalSaoriResult(text.precomposedStringWithCanonicalMapping)
                case "NFD": return InternalSaoriResult(text.decomposedStringWithCanonicalMapping)
                case "NFKC": return InternalSaoriResult(text.precomposedStringWithCompatibilityMapping)
                case "NFKD": return InternalSaoriResult(text.decomposedStringWithCompatibilityMapping)
                default: throw InternalSaoriError.unsupportedAlgorithm
                }
            }
        ]
    }
}
