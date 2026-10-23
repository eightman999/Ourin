import CommonCrypto
import CryptoKit
import Foundation

/// ハッシュ・MAC・共通鍵暗号・鍵の導出・ワンタイムパスワード・公開鍵署名（UKADOC 2.9.13〜）。
///
/// OS の部品（CryptoKit・CommonCrypto）で賄える範囲を実装している。未実装の方式（sha512-256・sha3・blake2、
/// scrypt・argon2id、bip340・HashPassword / VerifyPassword、Protect / Unprotect）は `unsupported algorithm`
/// か、関数が無い（`unknown function`）として扱い、`ListFunctions` にも出さない。
struct InternalCryptoModule: InternalSaoriModule {
    let name = "internal_crypto"

    typealias Support = InternalCryptoSupport

    var functions: [InternalSaoriFunction] {
        [digest, hmac, compare, encrypt, decrypt, deriveKey, totp, generateKeyPair, sign, verify]
            + InternalCryptoKeyAgreement.functions + InternalCryptoPasswords.functions + InternalCryptoProtect.functions
    }

    // MARK: - Digest / HMAC / Compare

    private var digest: InternalSaoriFunction {
        InternalSaoriFunction("Digest", positionals: 2, options: ["data-in", "out", "charset"]) { call, context in
            let algorithm = try Support.hashAlgorithm(call.positionals[0])
            let hasher = Support.Hasher(algorithm)
            try Self.feed(call.positionals[1], call: call, context: context) { hasher.update($0) }
            return InternalSaoriResult(try Self.output(hasher.finalize(), call, defaultFormat: "hex"))
        }
    }

    private var hmac: InternalSaoriFunction {
        InternalSaoriFunction("HMAC", positionals: 3, options: ["key-in", "data-in", "out", "charset"]) { call, context in
            let algorithm = try Support.hashAlgorithm(call.positionals[0])
            let key = try Self.bytes(call.positionals[1], call, option: "key-in", defaultFormat: "text")
            let mac = Support.MAC(algorithm, key: key)
            try Self.feed(call.positionals[2], call: call, context: context) { mac.update($0) }
            return InternalSaoriResult(try Self.output(mac.finalize(), call, defaultFormat: "hex"))
        }
    }

    /// 2 つのバイト列を、内容によらず同じ時間で比べる。等しければ 1、違えば 0。
    private var compare: InternalSaoriFunction {
        InternalSaoriFunction("Compare", positionals: 2, options: ["a-in", "b-in", "charset"]) { call, _ in
            let first = try Self.bytes(call.positionals[0], call, option: "a-in", defaultFormat: "text")
            let second = try Self.bytes(call.positionals[1], call, option: "b-in", defaultFormat: "text")
            return InternalSaoriResult(Support.constantTimeEqual(first, second) ? "1" : "0")
        }
    }

    // MARK: - 共通鍵暗号

    private enum Cipher {
        case aesGCM(keyLength: Int), chaChaPoly, aesCBC(keyLength: Int), aesCTR(keyLength: Int), chaCha20

        init(_ name: String) throws {
            switch name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
            case "aes256gcm": self = .aesGCM(keyLength: 32)
            case "aes128gcm": self = .aesGCM(keyLength: 16)
            case "chacha20poly1305": self = .chaChaPoly
            case "aes256cbc": self = .aesCBC(keyLength: 32)
            case "aes128cbc": self = .aesCBC(keyLength: 16)
            case "aes256ctr": self = .aesCTR(keyLength: 32)
            case "chacha20": self = .chaCha20
            default: throw InternalSaoriError.unsupportedAlgorithm
            }
        }

        var keyLength: Int {
            switch self {
            case .aesGCM(let length), .aesCBC(let length), .aesCTR(let length): return length
            case .chaChaPoly, .chaCha20: return 32
            }
        }

        /// nonce / IV の長さ。
        var nonceLength: Int {
            switch self {
            case .aesGCM, .chaChaPoly, .chaCha20: return 12
            case .aesCBC, .aesCTR: return 16
            }
        }

        var isAuthenticated: Bool {
            switch self {
            case .aesGCM, .chaChaPoly: return true
            default: return false
            }
        }
    }

    private static let encryptionOptions: Set<String> = ["key-in", "aad", "aad-in", "iv", "iv-in", "pack", "out", "charset"]

    private var encrypt: InternalSaoriFunction {
        InternalSaoriFunction("Encrypt", positionals: 3, options: Self.encryptionOptions.union(["data-in"])) { call, _ in
            let cipher = try Cipher(call.positionals[0])
            let key = try Self.cipherKey(call.positionals[1], call, cipher: cipher)
            let plaintext = try Self.bytes(call.positionals[2], call, option: "data-in", defaultFormat: "text")
            let pack = try Self.packsNonce(call)
            let aad = try Self.associatedData(call, cipher: cipher)
            var nonce: Data
            if let iv = try Self.bytesIfPresent(call, option: "iv", inOption: "iv-in", defaultFormat: "hex") {
                guard iv.count == cipher.nonceLength else { throw InternalSaoriError.invalidParameter }
                nonce = iv
            } else {
                // nonce / IV を渡さない（暗号文の先頭にも付けない）使い方はできない。
                guard pack else { throw InternalSaoriError.invalidParameter }
                nonce = try InternalRandomModule.randomBytes(cipher.nonceLength)
            }
            let body = try Self.seal(cipher, key: key, nonce: nonce, plaintext: plaintext, aad: aad)
            return InternalSaoriResult(try Self.output(pack ? nonce + body : body, call, defaultFormat: "base64"))
        }
    }

    private var decrypt: InternalSaoriFunction {
        InternalSaoriFunction("Decrypt", positionals: 3, options: Self.encryptionOptions.union(["ciphertext-in"])) { call, _ in
            let cipher = try Cipher(call.positionals[0])
            let key = try Self.cipherKey(call.positionals[1], call, cipher: cipher)
            let data = try Self.bytes(call.positionals[2], call, option: "ciphertext-in", defaultFormat: "base64")
            let pack = try Self.packsNonce(call)
            let aad = try Self.associatedData(call, cipher: cipher)
            let givenIV = try Self.bytesIfPresent(call, option: "iv", inOption: "iv-in", defaultFormat: "hex")
            let nonce: Data
            let body: Data
            if pack {
                // nonce / IV が暗号文の先頭にあるときに --iv= を付けるのは不正。
                guard givenIV == nil else { throw InternalSaoriError.invalidParameter }
                guard data.count >= cipher.nonceLength else { throw InternalSaoriError.invalidEncoding }
                nonce = data.prefix(cipher.nonceLength)
                body = data.dropFirst(cipher.nonceLength)
            } else {
                guard let givenIV, givenIV.count == cipher.nonceLength else { throw InternalSaoriError.invalidParameter }
                nonce = givenIV
                body = data
            }
            let plaintext = try Self.open(cipher, key: key, nonce: nonce, body: Data(body), aad: aad)
            return InternalSaoriResult(try Self.output(plaintext, call, defaultFormat: "text"))
        }
    }

    private static func cipherKey(_ value: String, _ call: InternalSaoriCall, cipher: Cipher) throws -> Data {
        let key = try bytes(value, call, option: "key-in", defaultFormat: "text")
        guard key.count == cipher.keyLength else { throw InternalSaoriError.badRequest("invalid key") }
        return key
    }

    /// `--pack=none` なら nonce / IV を暗号文の先頭に付けない。
    private static func packsNonce(_ call: InternalSaoriCall) throws -> Bool {
        guard let pack = call.option("pack") else { return true }
        guard pack.lowercased() == "none" else { throw InternalSaoriError.invalidParameter }
        return false
    }

    /// 追加認証データ。認証付き暗号だけで使える。
    private static func associatedData(_ call: InternalSaoriCall, cipher: Cipher) throws -> Data {
        guard let aad = try bytesIfPresent(call, option: "aad", inOption: "aad-in", defaultFormat: "text") else { return Data() }
        guard cipher.isAuthenticated else { throw InternalSaoriError.invalidParameter }
        return aad
    }

    private static func seal(_ cipher: Cipher, key: Data, nonce: Data, plaintext: Data, aad: Data) throws -> Data {
        let symmetric = SymmetricKey(data: key)
        switch cipher {
        case .aesGCM:
            let box = try AES.GCM.seal(plaintext, using: symmetric, nonce: try AES.GCM.Nonce(data: nonce), authenticating: aad)
            return box.ciphertext + box.tag
        case .chaChaPoly:
            let box = try ChaChaPoly.seal(plaintext, using: symmetric, nonce: try ChaChaPoly.Nonce(data: nonce), authenticating: aad)
            return box.ciphertext + box.tag
        case .chaCha20:
            return Support.chaCha20(key: key, nonce: nonce, input: plaintext)
        case .aesCBC:
            return try crypt(kCCEncrypt, mode: kCCModeCBC, padding: CCPadding(ccPKCS7Padding), key: key, iv: nonce, input: plaintext)
        case .aesCTR:
            return try crypt(kCCEncrypt, mode: kCCModeCTR, padding: CCPadding(ccNoPadding), key: key, iv: nonce, input: plaintext)
        }
    }

    private static func open(_ cipher: Cipher, key: Data, nonce: Data, body: Data, aad: Data) throws -> Data {
        let symmetric = SymmetricKey(data: key)
        // 復号できなければ authentication failed。
        let failure = InternalSaoriError.failed("authentication failed")
        switch cipher {
        case .aesGCM:
            guard body.count >= 16 else { throw failure }
            do {
                let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonce), ciphertext: body.dropLast(16), tag: body.suffix(16))
                return try AES.GCM.open(box, using: symmetric, authenticating: aad)
            } catch { throw failure }
        case .chaChaPoly:
            guard body.count >= 16 else { throw failure }
            do {
                let box = try ChaChaPoly.SealedBox(nonce: try ChaChaPoly.Nonce(data: nonce), ciphertext: body.dropLast(16), tag: body.suffix(16))
                return try ChaChaPoly.open(box, using: symmetric, authenticating: aad)
            } catch { throw failure }
        case .chaCha20:
            return Support.chaCha20(key: key, nonce: nonce, input: body)
        case .aesCBC:
            guard !body.isEmpty, body.count % 16 == 0 else { throw failure }
            do { return try crypt(kCCDecrypt, mode: kCCModeCBC, padding: CCPadding(ccPKCS7Padding), key: key, iv: nonce, input: body) } catch { throw failure }
        case .aesCTR:
            return try crypt(kCCDecrypt, mode: kCCModeCTR, padding: CCPadding(ccNoPadding), key: key, iv: nonce, input: body)
        }
    }

    /// AES（CBC / CTR）。CTR は暗号化と復号が同じ処理。
    private static func crypt(_ operation: Int, mode: Int, padding: CCPadding, key: Data, iv: Data, input: Data) throws -> Data {
        var cryptor: CCCryptorRef?
        let created = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    CCOperation(operation), CCMode(mode), CCAlgorithm(kCCAlgorithmAES), padding,
                    ivBytes.baseAddress, keyBytes.baseAddress, key.count, nil, 0, 0,
                    CCModeOptions(kCCModeOptionCTR_BE), &cryptor
                )
            }
        }
        guard created == kCCSuccess, let cryptor else { throw InternalSaoriError.internalError }
        defer { CCCryptorRelease(cryptor) }
        var output = [UInt8](repeating: 0, count: CCCryptorGetOutputLength(cryptor, input.count, true))
        var written = 0
        let updated = input.withUnsafeBytes { CCCryptorUpdate(cryptor, $0.baseAddress, input.count, &output, output.count, &written) }
        guard updated == kCCSuccess else { throw InternalSaoriError.internalError }
        var tail = 0
        let finished = output.withUnsafeMutableBytes { CCCryptorFinal(cryptor, $0.baseAddress!.advanced(by: written), $0.count - written, &tail) }
        guard finished == kCCSuccess else { throw InternalSaoriError.failed("authentication failed") }
        return Data(output.prefix(written + tail))
    }

    // MARK: - 鍵の導出

    private var deriveKey: InternalSaoriFunction {
        InternalSaoriFunction("DeriveKey", positionals: 4,
                              options: ["password-in", "salt-in", "digest", "iterations", "info", "info-in", "out", "charset"]) { call, _ in
            let method = call.positionals[0].lowercased()
            let allowed: Set<String>
            switch method {
            case "pbkdf2": allowed = ["digest", "iterations"]
            case "hkdf", "hkdf-expand": allowed = ["digest", "info", "info-in"]
            case "hkdf-extract": allowed = ["digest"]
            case "scrypt", "argon2id": throw InternalSaoriError.unsupportedAlgorithm
            default: throw InternalSaoriError.unsupportedAlgorithm
            }
            // その方式で使わないオプションは不正。
            let common: Set<String> = ["password-in", "salt-in", "out", "charset", "async"]
            guard Set(call.options.keys).subtracting(common).isSubset(of: allowed) else { throw InternalSaoriError.invalidParameter }

            let password = try Self.bytes(call.positionals[1], call, option: "password-in", defaultFormat: "text")
            let salt = try Self.bytes(call.positionals[2], call, option: "salt-in", defaultFormat: "text")
            guard let length = Int(call.positionals[3].trimmingCharacters(in: .whitespaces)) else { throw InternalSaoriError.invalidParameter }
            guard (1...1024).contains(length) else { throw InternalSaoriError.outOfRange }
            let algorithm = try Support.hashAlgorithm(call.option("digest") ?? "sha256")
            let info = try Self.bytesIfPresent(call, option: "info", inOption: "info-in", defaultFormat: "text") ?? Data()
            let derived: Data
            switch method {
            case "pbkdf2":
                var iterations = 600_000
                if let text = call.option("iterations") {
                    guard let value = Int(text) else { throw InternalSaoriError.invalidParameter }
                    guard (1...10_000_000).contains(value) else { throw InternalSaoriError.outOfRange }
                    iterations = value
                }
                derived = try Self.pbkdf2(algorithm, password: password, salt: salt, iterations: iterations, length: length)
            case "hkdf":
                guard !password.isEmpty else { throw InternalSaoriError.invalidParameter }
                guard length <= 255 * algorithm.digestLength else { throw InternalSaoriError.outOfRange }
                derived = Self.hkdfExpand(algorithm, prk: Self.hkdfExtract(algorithm, salt: salt, ikm: password), info: info, length: length)
            case "hkdf-extract":
                guard !password.isEmpty else { throw InternalSaoriError.invalidParameter }
                // 結果は PRK で、長さはハッシュの長さちょうどでなければならない。
                guard length == algorithm.digestLength else { throw InternalSaoriError.outOfRange }
                derived = Self.hkdfExtract(algorithm, salt: salt, ikm: password)
            default: // hkdf-expand。password が PRK、salt は空にする。
                guard !password.isEmpty, salt.isEmpty else { throw InternalSaoriError.invalidParameter }
                guard length <= 255 * algorithm.digestLength else { throw InternalSaoriError.outOfRange }
                derived = Self.hkdfExpand(algorithm, prk: password, info: info, length: length)
            }
            return InternalSaoriResult(try Self.output(derived, call, defaultFormat: "hex"))
        }
    }

    private static func pbkdf2(_ algorithm: Support.HashAlgorithm, password: Data, salt: Data, iterations: Int, length: Int) throws -> Data {
        guard let prf = algorithm.pbkdf2PRF else { throw InternalSaoriError.unsupportedAlgorithm }
        var derived = [UInt8](repeating: 0, count: length)
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress, password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    prf, UInt32(iterations), &derived, length
                )
            }
        }
        guard status == kCCSuccess else { throw InternalSaoriError.internalError }
        return Data(derived)
    }

    /// RFC 5869 §2.2。salt が空なら、ハッシュの長さの 0 で埋めた salt を使う。
    private static func hkdfExtract(_ algorithm: Support.HashAlgorithm, salt: Data, ikm: Data) -> Data {
        Support.hmac(algorithm, key: salt.isEmpty ? Data(count: algorithm.digestLength) : salt, data: ikm)
    }

    /// RFC 5869 §2.3。
    private static func hkdfExpand(_ algorithm: Support.HashAlgorithm, prk: Data, info: Data, length: Int) -> Data {
        var output = Data()
        var previous = Data()
        var counter: UInt8 = 1
        while output.count < length {
            previous = Support.hmac(algorithm, key: prk, data: previous + info + Data([counter]))
            output.append(previous)
            counter &+= 1
        }
        return output.prefix(length)
    }

    // MARK: - TOTP

    /// 時刻ベースのワンタイムパスワード（RFC 6238）。桁数に満たなければ先頭を 0 で埋める。
    private var totp: InternalSaoriFunction {
        InternalSaoriFunction("TOTP", positionals: 1, options: ["key-in", "digits", "period", "digest", "time", "charset"]) { call, _ in
            let key = try Self.bytes(call.positionals[0], call, option: "key-in", defaultFormat: "base32")
            var digits = 6
            if let text = call.option("digits") {
                guard let value = Int(text), (6...10).contains(value) else { throw InternalSaoriError.invalidParameter }
                digits = value
            }
            var period = 30
            if let text = call.option("period") {
                guard let value = Int(text), (1...86_400).contains(value) else { throw InternalSaoriError.invalidParameter }
                period = value
            }
            let algorithm = try Support.hashAlgorithm(call.option("digest") ?? "sha1")
            // md5 は使えない。
            guard algorithm != .md5 else { throw InternalSaoriError.unsupportedAlgorithm }
            let epoch: Int64
            if let time = call.option("time") {
                epoch = try InternalTimeModule.parseDateTime(time, zone: .current)
            } else {
                epoch = Int64(Date().timeIntervalSince1970)
            }
            guard epoch >= 0 else { throw InternalSaoriError.outOfRange }

            var counter = UInt64(epoch) / UInt64(period)
            var message = Data(count: 8)
            for index in (0..<8).reversed() { message[index] = UInt8(counter & 0xff); counter >>= 8 }
            let mac = Support.hmac(algorithm, key: key, data: message)
            let offset = Int(mac[mac.count - 1] & 0x0f)
            let binary = (UInt32(mac[offset] & 0x7f) << 24) | UInt32(mac[offset + 1]) << 16 | UInt32(mac[offset + 2]) << 8 | UInt32(mac[offset + 3])
            var modulus: UInt64 = 1
            for _ in 0..<digits { modulus *= 10 }
            let code = String(UInt64(binary) % modulus)
            return InternalSaoriResult(String(repeating: "0", count: max(0, digits - code.count)) + code)
        }
    }

    // MARK: - 公開鍵署名（ed25519 / es256 / rs256 / ps256 / bip340）

    private enum SignatureAlgorithm {
        case ed25519, es256, rs256, ps256, bip340
        /// GenerateKeyPair だけの名前（rsa-2048 など。鍵は rs256 と ps256 のどちらにも使える）。
        case rsa(bits: Int)

        init(_ name: String) throws {
            switch name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
            case "ed25519": self = .ed25519
            case "es256": self = .es256
            case "rs256": self = .rs256
            case "ps256": self = .ps256
            case "bip340": self = .bip340
            case "rsa2048": self = .rsa(bits: 2048)
            case "rsa3072": self = .rsa(bits: 3072)
            case "rsa4096": self = .rsa(bits: 4096)
            default: throw InternalSaoriError.unsupportedAlgorithm
            }
        }
    }

    /// 秘密鍵は PKCS#8、公開鍵は SubjectPublicKeyInfo の DER を base64 にして返す。Result は秘密鍵。
    private var generateKeyPair: InternalSaoriFunction {
        InternalSaoriFunction("GenerateKeyPair", positionals: 1) { call, _ in
            switch try SignatureAlgorithm(call.positionals[0]) {
            case .ed25519:
                let key = Curve25519.Signing.PrivateKey()
                let privateKey = InternalKeyCodec.ed25519PKCS8 + key.rawRepresentation
                let publicKey = InternalKeyCodec.ed25519SPKI + key.publicKey.rawRepresentation
                return InternalSaoriResult(privateKey.base64EncodedString(), values: [privateKey.base64EncodedString(), publicKey.base64EncodedString()])
            case .es256:
                let key = P256.Signing.PrivateKey()
                let privateKey = key.derRepresentation
                return InternalSaoriResult(privateKey.base64EncodedString(), values: [privateKey.base64EncodedString(), key.publicKey.derRepresentation.base64EncodedString()])
            case .rsa(let bits):
                let pair = try InternalRSA.generate(bits: bits)
                return InternalSaoriResult(pair.privateKey.base64EncodedString(), values: [pair.privateKey.base64EncodedString(), pair.publicKey.base64EncodedString()])
            case .bip340:
                var secret = Data()
                repeat { secret = try InternalRandomModule.randomBytes(32) } while InternalSecp256k1.publicKey(secret: secret) == nil
                let publicKey = InternalSecp256k1.publicKey(secret: secret)!
                let secretHex = try InternalSaoriCodec.encode(secret, format: "hex", defaultFormat: "hex", charset: nil)
                let publicHex = try InternalSaoriCodec.encode(publicKey, format: "hex", defaultFormat: "hex", charset: nil)
                return InternalSaoriResult(secretHex, values: [secretHex, publicHex])
            case .rs256, .ps256:
                // 署名の方式の名前で鍵は作れない（rsa-2048 などを使う）。
                throw InternalSaoriError.unsupportedAlgorithm
            }
        }
    }

    private var sign: InternalSaoriFunction {
        InternalSaoriFunction("Sign", positionals: 3, options: ["data-in", "out", "charset", "key-in", "aux", "aux-in"]) { call, _ in
            let algorithm = try SignatureAlgorithm(call.positionals[0])
            // --key-in= / --aux= は bip340 だけのオプション。
            if case .bip340 = algorithm {} else {
                guard call.option("key-in") == nil, call.option("aux") == nil, call.option("aux-in") == nil else { throw InternalSaoriError.invalidParameter }
            }
            let data = try Self.bytes(call.positionals[2], call, option: "data-in", defaultFormat: "text")
            let signature: Data
            switch algorithm {
            case .bip340:
                let secret = try Self.bytes(call.positionals[1], call, option: "key-in", defaultFormat: "hex")
                guard InternalSecp256k1.scalar(secret) != nil else { throw InternalKeyCodec.invalidKey }
                let aux = try Self.bytesIfPresent(call, option: "aux", inOption: "aux-in", defaultFormat: "hex") ?? InternalRandomModule.randomBytes(32)
                guard aux.count == 32 else { throw InternalSaoriError.invalidParameter }
                guard let schnorr = InternalSecp256k1.schnorrSign(secret: secret, message: data, aux: aux) else { throw InternalSaoriError.internalError }
                return InternalSaoriResult(try Self.output(schnorr, call, defaultFormat: "hex"))
            case .ed25519:
                // RFC 8032 の決定的な署名（CryptoKit の署名は毎回変わる）。
                let seed = try InternalKeyCodec.ed25519PrivateKey(call.positionals[1]).rawRepresentation
                signature = InternalEd25519.sign(seed: seed, message: data)
            case .es256:
                // r‖s の 64 バイト（JWS と同じ形で、DER 形式ではない）。
                signature = try InternalKeyCodec.p256PrivateKey(call.positionals[1]).signature(for: data).rawRepresentation
            case .rs256:
                signature = try InternalRSA.sign(data, with: try InternalRSA.privateKey(call.positionals[1]), scheme: .pkcs1v15)
            case .ps256:
                signature = try InternalRSA.sign(data, with: try InternalRSA.privateKey(call.positionals[1]), scheme: .pss)
            case .rsa, .bip340:
                throw InternalSaoriError.unsupportedAlgorithm
            }
            return InternalSaoriResult(try Self.output(signature, call, defaultFormat: "base64url"))
        }
    }

    /// 署名を公開鍵で検証する。正しければ 1、正しくなければ 0（署名の長さが違うときも 0）。公開鍵の代わりに秘密鍵も渡せる。
    private var verify: InternalSaoriFunction {
        InternalSaoriFunction("Verify", positionals: 4, options: ["data-in", "signature-in", "charset", "key-in"]) { call, _ in
            let algorithm = try SignatureAlgorithm(call.positionals[0])
            if case .bip340 = algorithm {} else {
                guard call.option("key-in") == nil else { throw InternalSaoriError.invalidParameter }
            }
            let data = try Self.bytes(call.positionals[2], call, option: "data-in", defaultFormat: "text")
            if case .bip340 = algorithm {
                // 公開鍵は x 座標だけの 32 バイト（秘密鍵は受け付けない）。署名の長さが違うときは 0。
                let key = try Self.bytes(call.positionals[1], call, option: "key-in", defaultFormat: "hex")
                guard key.count == 32 else { throw InternalKeyCodec.invalidKey }
                let signature = try Self.bytes(call.positionals[3], call, option: "signature-in", defaultFormat: "hex")
                return InternalSaoriResult(InternalSecp256k1.schnorrVerify(publicKey: key, message: data, signature: signature) ? "1" : "0")
            }
            let signature = try Self.bytes(call.positionals[3], call, option: "signature-in", defaultFormat: "base64url")
            let valid: Bool
            switch algorithm {
            case .ed25519:
                valid = try InternalKeyCodec.ed25519PublicKey(call.positionals[1]).isValidSignature(signature, for: data)
            case .es256:
                let key = try InternalKeyCodec.p256PublicKey(call.positionals[1])
                valid = (try? P256.Signing.ECDSASignature(rawRepresentation: signature)).map { key.isValidSignature($0, for: data) } ?? false
            case .rs256:
                valid = InternalRSA.verify(signature, for: data, with: try InternalRSA.publicKey(call.positionals[1]), scheme: .pkcs1v15)
            case .ps256:
                valid = InternalRSA.verify(signature, for: data, with: try InternalRSA.publicKey(call.positionals[1]), scheme: .pss)
            case .rsa, .bip340:
                throw InternalSaoriError.unsupportedAlgorithm
            }
            return InternalSaoriResult(valid ? "1" : "0")
        }
    }

    // MARK: - 入出力

    private static func bytes(_ value: String, _ call: InternalSaoriCall, option: String, defaultFormat: String) throws -> Data {
        try InternalSaoriCodec.decode(value, format: call.option(option), defaultFormat: defaultFormat, charset: call.option("charset"))
    }

    /// `--名前=値`（`--名前-in=` で形式を変えられる）。指定が無ければ nil。
    private static func bytesIfPresent(_ call: InternalSaoriCall, option: String, inOption: String, defaultFormat: String) throws -> Data? {
        guard let value = call.option(option) else { return nil }
        return try InternalSaoriCodec.decode(value, format: call.option(inOption), defaultFormat: defaultFormat, charset: call.option("charset"))
    }

    private static func output(_ data: Data, _ call: InternalSaoriCall, defaultFormat: String) throws -> String {
        try InternalSaoriCodec.encode(data, format: call.option("out"), defaultFormat: defaultFormat, charset: call.option("charset"))
    }

    /// Digest / HMAC の data。`--data-in=file` ならファイルの中身を少しずつ読む（相対パスはゴーストのフォルダが基準）。
    private static func feed(_ value: String, call: InternalSaoriCall, context: InternalSaoriContext, consume: (Data) -> Void) throws {
        guard call.option("data-in")?.lowercased() == "file" else {
            consume(try bytes(value, call, option: "data-in", defaultFormat: "text"))
            return
        }
        let url: URL
        if value.hasPrefix("/") {
            url = URL(fileURLWithPath: value)
        } else if let root = context.ghostRoot {
            url = root.appendingPathComponent(value)
        } else {
            throw InternalSaoriError.ghostRequired
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let handle = try? FileHandle(forReadingFrom: url) else {
            throw InternalSaoriError.badRequest("file not found")
        }
        defer { try? handle.close() }
        while true {
            let chunk: Data
            do {
                guard let next = try handle.read(upToCount: 1 << 20) else { break }
                chunk = next
            } catch {
                throw InternalSaoriError.failed("file read failed")
            }
            if chunk.isEmpty { break }
            consume(chunk)
        }
    }
}
