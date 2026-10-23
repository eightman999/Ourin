import CryptoKit
import Foundation

/// JWT（RFC 7519）の作成と検証（UKADOC 2.9.13 internal_jwt）。形式は JWS のコンパクト形式だけ。
///
/// HS256 / HS384 / HS512、RS256 / PS256、ES256、EdDSA（Ed25519）。none や知らない名前は `unsupported algorithm`。
struct InternalJWTModule: InternalSaoriModule {
    let name = "internal_jwt"

    typealias Support = InternalCryptoSupport

    var functions: [InternalSaoriFunction] { [sign, verify] }

    private enum Algorithm {
        case hmac(Support.HashAlgorithm, name: String)
        case es256, eddsa
        case rsa(InternalRSA.Scheme, name: String)

        /// 大文字小文字は区別しない。
        init(_ text: String) throws {
            switch text.uppercased() {
            case "HS256": self = .hmac(.sha256, name: "HS256")
            case "HS384": self = .hmac(.sha384, name: "HS384")
            case "HS512": self = .hmac(.sha512, name: "HS512")
            case "ES256": self = .es256
            case "EDDSA": self = .eddsa
            case "RS256": self = .rsa(.pkcs1v15, name: "RS256")
            case "PS256": self = .rsa(.pss, name: "PS256")
            default: throw InternalSaoriError.unsupportedAlgorithm
            }
        }

        /// ヘッダの alg に書く正式な名前。
        var name: String {
            switch self {
            case .hmac(_, let name), .rsa(_, let name): return name
            case .es256: return "ES256"
            case .eddsa: return "EdDSA"
            }
        }
    }

    // MARK: - Sign

    private var sign: InternalSaoriFunction {
        InternalSaoriFunction("Sign", positionals: 3, options: ["header", "key-in"]) { call, _ in
            let algorithm = try Algorithm(call.positionals[0])
            let payload = call.positionals[2]
            guard Self.isJSONObject(Data(payload.utf8)) else { throw InternalSaoriError.invalidParameter }
            let header = try Self.header(algorithm: algorithm, extra: call.option("header"))
            let signingInput = Self.base64url(Data(header.utf8)) + "." + Self.base64url(Data(payload.utf8))
            let message = Data(signingInput.utf8)

            let signature: Data
            switch algorithm {
            case .hmac(let hash, _):
                let key = try Self.hmacKey(call.positionals[1], call: call, hash: hash)
                signature = Support.hmac(hash, key: key, data: message)
            case .es256:
                guard call.option("key-in") == nil else { throw InternalSaoriError.invalidParameter }
                signature = try InternalKeyCodec.p256PrivateKey(call.positionals[1]).signature(for: message).rawRepresentation
            case .eddsa:
                guard call.option("key-in") == nil else { throw InternalSaoriError.invalidParameter }
                signature = InternalEd25519.sign(seed: try InternalKeyCodec.ed25519PrivateKey(call.positionals[1]).rawRepresentation, message: message)
            case .rsa(let scheme, _):
                guard call.option("key-in") == nil else { throw InternalSaoriError.invalidParameter }
                signature = try InternalRSA.sign(message, with: try InternalRSA.privateKey(call.positionals[1]), scheme: scheme)
            }
            return InternalSaoriResult(signingInput + "." + Self.base64url(signature))
        }
    }

    /// `{"alg":…,"typ":"JWT"}` に `--header=` の項目を足す。typ は指定が優先。alg は引数と同じ値だけ書ける。
    private static func header(algorithm: Algorithm, extra: String?) throws -> String {
        var typ = "\"JWT\""
        var rest: [String: Any] = [:]
        if let extra {
            guard let object = try? JSONSerialization.jsonObject(with: Data(extra.utf8)) as? [String: Any] else {
                throw InternalSaoriError.invalidParameter
            }
            rest = object
            if let alg = rest.removeValue(forKey: "alg") {
                // 大文字小文字まで引数の alg と同じ（正式な名前）でなければならない。
                guard let text = alg as? String, text.uppercased() == algorithm.name.uppercased() else { throw InternalSaoriError.invalidParameter }
            }
            if let value = rest.removeValue(forKey: "typ") { typ = try fragment(value) }
        }
        var header = "{\"alg\":\"\(algorithm.name)\",\"typ\":\(typ)"
        for key in rest.keys.sorted() {
            header += ",\(try fragment(key)):\(try fragment(rest[key]!))"
        }
        return header + "}"
    }

    // MARK: - Verify

    private var verify: InternalSaoriFunction {
        InternalSaoriFunction("Verify", positionals: 2, options: ["alg", "leeway", "time", "key-in"]) { call, _ in
            guard let algText = call.option("alg"), !algText.isEmpty else { throw InternalSaoriError.invalidParameter }
            let algorithm = try Algorithm(algText)
            var leeway = 0.0
            if let text = call.option("leeway") {
                guard let value = Int(text), (0...86_400).contains(value) else { throw InternalSaoriError.invalidParameter }
                leeway = Double(value)
            }
            let now: Double
            if let text = call.option("time") {
                now = Double(try InternalTimeModule.parseDateTime(text, zone: .current))
            } else {
                now = Date().timeIntervalSince1970
            }

            // 鍵は、トークンを読む前に確かめる（読めない・種類が違う・短いは invalid key）。
            enum Key { case hmac(Data), p256(P256.Signing.PublicKey), ed25519(Curve25519.Signing.PublicKey), rsa(SecKey) }
            let key: Key
            switch algorithm {
            case .hmac(let hash, _): key = .hmac(try Self.hmacKey(call.positionals[1], call: call, hash: hash))
            case .es256:
                guard call.option("key-in") == nil else { throw InternalSaoriError.invalidParameter }
                key = .p256(try InternalKeyCodec.p256PublicKey(call.positionals[1]))
            case .eddsa:
                guard call.option("key-in") == nil else { throw InternalSaoriError.invalidParameter }
                key = .ed25519(try InternalKeyCodec.ed25519PublicKey(call.positionals[1]))
            case .rsa:
                guard call.option("key-in") == nil else { throw InternalSaoriError.invalidParameter }
                key = .rsa(try InternalRSA.publicKey(call.positionals[1]))
            }

            let failure = InternalSaoriError.failed("authentication failed")
            let parts = call.positionals[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3,
                  let headerBytes = Self.decodeBase64url(parts[0]),
                  let payloadBytes = Self.decodeBase64url(parts[1]),
                  let signature = Self.decodeBase64url(parts[2]),
                  let headerObject = Self.jsonObject(headerBytes),
                  let payloadObject = Self.jsonObject(payloadBytes),
                  let payloadText = String(data: payloadBytes, encoding: .utf8) else { throw failure }
            // トークンの alg は信用しない。--alg= と（大文字小文字まで）同じでなければ失敗。none も同じ扱い。
            guard let tokenAlg = headerObject["alg"] as? String, tokenAlg == algorithm.name, headerObject["crit"] == nil else { throw failure }

            let message = Data((parts[0] + "." + parts[1]).utf8)
            let valid: Bool
            switch (algorithm, key) {
            case (.hmac(let hash, _), .hmac(let secret)):
                valid = Support.constantTimeEqual(Support.hmac(hash, key: secret, data: message), signature)
            case (_, .p256(let publicKey)):
                valid = (try? P256.Signing.ECDSASignature(rawRepresentation: signature)).map { publicKey.isValidSignature($0, for: message) } ?? false
            case (_, .ed25519(let publicKey)):
                valid = publicKey.isValidSignature(signature, for: message)
            case (.rsa(let scheme, _), .rsa(let publicKey)):
                valid = InternalRSA.verify(signature, for: message, with: publicKey, scheme: scheme)
            default:
                valid = false
            }
            guard valid else { throw failure }

            // exp / nbf は、あれば数値でなければならない（署名が正しいと分かってから見る）。
            let exp = try Self.numericClaim("exp", in: payloadObject, failure: failure)
            let nbf = try Self.numericClaim("nbf", in: payloadObject, failure: failure)
            if let exp, now >= exp + leeway { throw InternalSaoriError.failed("expired") }
            if let nbf, now + leeway < nbf { throw InternalSaoriError.failed("not yet valid") }

            let flattened = String(String.UnicodeScalarView(payloadText.unicodeScalars.map { $0 == "\r" || $0 == "\n" ? " " : $0 }))
            return InternalSaoriResult(flattened)
        }
    }

    // MARK: - 部品

    private static func hmacKey(_ value: String, call: InternalSaoriCall, hash: Support.HashAlgorithm) throws -> Data {
        guard let key = try? InternalSaoriCodec.decode(value, format: call.option("key-in"), defaultFormat: "text", charset: nil) else {
            throw InternalSaoriError.badRequest("invalid key")
        }
        // RFC 7518: 鍵はハッシュの長さ以上。
        guard key.count >= hash.digestLength else { throw InternalSaoriError.badRequest("invalid key") }
        return key
    }

    private static func numericClaim(_ name: String, in object: [String: Any], failure: InternalSaoriError) throws -> Double? {
        guard let value = object[name] else { return nil }
        // JSON の true / false も NSNumber で来るので、数値かどうかを型で確かめる。
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw failure }
        return number.doubleValue
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func isJSONObject(_ data: Data) -> Bool { jsonObject(data) != nil }

    /// JSON の値 1 つを文字列にする（スラッシュはエスケープしない）。
    private static func fragment(_ value: Any) throws -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { throw InternalSaoriError.invalidParameter }
        return String(text.dropFirst().dropLast())
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// パディング無しの base64url だけ読む（パディング・標準の記号・空白は不正）。
    private static func decodeBase64url(_ text: String) -> Data? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }), text.count % 4 != 1 else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while standard.count % 4 != 0 { standard += "=" }
        return Data(base64Encoded: standard)
    }
}
