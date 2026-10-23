import CryptoKit
import Foundation
import IOKit

/// Protect / Unprotect。データを「この Mac のこのユーザー」（`--scope=machine` ならこの Mac の全ユーザー）だけが戻せる形に包む。
///
/// Windows の DPAPI に当たる OS の機能が macOS には無いので、Mac のハードウェア UUID（とユーザー ID）から導いた鍵で
/// AES-256-GCM にかける。ほかの Mac・ほかのユーザーにコピーしても戻せない。同じユーザーで動くほかのプログラムからは戻せる。
/// 包んだデータの形: 版（1）‖ 範囲（1 = user、2 = machine）‖ nonce（12）‖ 暗号文 ‖ 認証タグ（16）。範囲と版は認証される。
enum InternalCryptoProtect {
    private static let version: UInt8 = 1

    static var functions: [InternalSaoriFunction] {
        [
            InternalSaoriFunction("Protect", positionals: 1, options: ["data-in", "scope", "out", "charset"]) { call, _ in
                let scope: UInt8
                switch call.option("scope")?.lowercased() {
                case nil, "user": scope = 1
                case "machine": scope = 2
                default: throw InternalSaoriError.invalidParameter
                }
                let data = try InternalSaoriCodec.decode(call.positionals[0], format: call.option("data-in"), defaultFormat: "text", charset: call.option("charset"))
                let header = Data([version, scope])
                let sealed = try AES.GCM.seal(data, using: try key(scope: scope), authenticating: header)
                guard let combined = sealed.combined else { throw InternalSaoriError.internalError }
                return InternalSaoriResult(try InternalSaoriCodec.encode(header + combined, format: call.option("out"), defaultFormat: "base64", charset: call.option("charset")))
            },
            InternalSaoriFunction("Unprotect", positionals: 1, options: ["data-in", "out", "charset"]) { call, _ in
                let failure = InternalSaoriError.failed("authentication failed")
                let blob = try InternalSaoriCodec.decode(call.positionals[0], format: call.option("data-in"), defaultFormat: "base64", charset: call.option("charset"))
                guard blob.count >= 2 + 12 + 16, blob[blob.startIndex] == version, blob[blob.startIndex + 1] == 1 || blob[blob.startIndex + 1] == 2 else { throw failure }
                let scope = blob[blob.startIndex + 1]
                guard let box = try? AES.GCM.SealedBox(combined: blob.dropFirst(2)),
                      let plain = try? AES.GCM.open(box, using: try key(scope: scope), authenticating: blob.prefix(2)) else { throw failure }
                return InternalSaoriResult(try InternalSaoriCodec.encode(plain, format: call.option("out"), defaultFormat: "text", charset: call.option("charset")))
            }
        ]
    }

    /// 鍵: HKDF-SHA256(この Mac のハードウェア UUID、info = 用途 ＋ 範囲（user ならユーザー ID）)。
    private static func key(scope: UInt8) throws -> SymmetricKey {
        var info = "ourin.internal_crypto.protect.v1"
        info += scope == 1 ? ".user.\(getuid())" : ".machine"
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(try hardwareUUID().utf8)), salt: Data(), info: Data(info.utf8), outputByteCount: 32)
    }

    private static func hardwareUUID() throws -> String {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { throw InternalSaoriError.internalError }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
              !value.isEmpty else { throw InternalSaoriError.internalError }
        return value
    }
}
