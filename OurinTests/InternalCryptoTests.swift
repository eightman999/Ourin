import CryptoKit
import Foundation
import Testing
@testable import Ourin

private struct Outcome {
    var status: Int
    var result: String?
    var values: [String]
    var error: String?
}

private func call(_ function: String, _ arguments: [String] = [], context: InternalSaoriContext = .none) -> Outcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_crypto", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: context)
    let response = try! SaoriProtocol.parseResponse(text)
    var values: [String] = []
    while let value = response.headerValue("Value\(values.count)") { values.append(value) }
    return Outcome(status: response.statusCode, result: response.headerValue("Result"), values: values, error: response.headerValue("ErrorDescription"))
}

private func ok(_ outcome: Outcome, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == 200, "status \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.result == expected, sourceLocation: sourceLocation)
}

private func fails(_ outcome: Outcome, _ status: Int, _ description: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == status, "got \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.error == description, sourceLocation: sourceLocation)
}

// MARK: - Digest / HMAC / Compare

struct InternalCryptoHashTests {
    @Test
    func digestMatchesPublishedVectors() {
        // 記述例と、FIPS 180 / RFC 1321 / RFC 3174 の "abc"。
        ok(call("Digest", ["sha256", "abc"]), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        ok(call("Digest", ["md5", "abc"]), "900150983cd24fb0d6963f7d28e17f72")
        ok(call("Digest", ["sha1", "abc"]), "a9993e364706816aba3e25717850c26c9cd0d89d")
        ok(call("Digest", ["sha224", "abc"]), "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7")
        ok(call("Digest", ["sha384", "abc"]), "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
        ok(call("Digest", ["sha512", "abc"]), "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        // 空のデータ。
        ok(call("Digest", ["sha256", ""]), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test
    func algorithmNamesIgnoreHyphensUnderscoresAndCase() {
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        for name in ["SHA256", "SHA-256", "sha_256", "Sha-256"] { ok(call("Digest", [name, "abc"]), expected) }
        for name in ["sha512-256", "SHA3_256", "sha3-512", "Blake2b512", "blake2s-256"] {
            #expect(call("Digest", [name, "abc"]).status == 200, "\(name)")
        }
        // 知らない名前は unsupported algorithm。
        for name in ["crc32", "nothing", "sha3", "blake2b"] {
            fails(call("Digest", [name, "abc"]), 400, "unsupported algorithm")
        }
    }

    @Test
    func inputAndOutputFormatsAndCharset() {
        // 文字列は既定で UTF-8 のバイト列としてハッシュする。--charset= で別の文字コードに。
        let utf8 = call("Digest", ["sha256", "あ"]).result
        let utf8Hex = call("Digest", ["sha256", "e38182", "--data-in=hex"]).result
        #expect(utf8 == utf8Hex)
        #expect(call("Digest", ["sha256", "あ", "--charset=Shift_JIS"]).result == call("Digest", ["sha256", "82a0", "--data-in=hex"]).result)
        #expect(utf8 != call("Digest", ["sha256", "あ", "--charset=Shift_JIS"]).result)
        ok(call("Digest", ["md5", "abc", "--out=HEX"]), "900150983CD24FB0D6963F7D28E17F72")
        ok(call("Digest", ["md5", "abc", "--out=base64"]), "kAFQmDzST7DWlj99KOF/cg==")
        ok(call("Digest", ["md5", "YWJj", "--data-in=base64"]), "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test
    func digestAndHMACReadFilesRelativeToTheGhostFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-crypto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("abc".utf8).write(to: root.appendingPathComponent("sub/data.bin"))
        let large = Data(repeating: 0x61, count: 3 * 1024 * 1024 + 17) // 読み込みの単位（1MiB）をまたぐ
        try large.write(to: root.appendingPathComponent("large.bin"))
        let ghost = InternalSaoriContext(ghostRoot: root, deliverEvent: nil)

        ok(call("Digest", ["sha256", "sub/data.bin", "--data-in=file"], context: ghost), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // 絶対パスは、ゴーストなしでも読める。
        ok(call("Digest", ["sha256", root.appendingPathComponent("sub/data.bin").path, "--data-in=file"]), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let expectedLarge = SHA256.hash(data: large).map { String(format: "%02x", $0) }.joined()
        ok(call("Digest", ["sha256", "large.bin", "--data-in=file"], context: ghost), expectedLarge)
        ok(call("HMAC", ["sha256", "key", "sub/data.bin", "--data-in=file"], context: ghost),
           call("HMAC", ["sha256", "key", "abc"]).result ?? "")
        // 相対パスはゴーストなしでは使えない。無いファイルとフォルダは file not found。
        fails(call("Digest", ["sha256", "sub/data.bin", "--data-in=file"]), 400, "ghost required")
        fails(call("Digest", ["sha256", "missing.bin", "--data-in=file"], context: ghost), 400, "file not found")
        fails(call("Digest", ["sha256", "sub", "--data-in=file"], context: ghost), 400, "file not found")
    }

    @Test
    func hmacMatchesRFCVectors() {
        let data = "what do ya want for nothing?"
        // RFC 4231 テストケース 2、RFC 2202 テストケース 2。
        ok(call("HMAC", ["sha256", "Jefe", data]), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        ok(call("HMAC", ["sha512", "Jefe", data]), "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737")
        ok(call("HMAC", ["md5", "Jefe", data]), "750c783e6ab0b503eaa86e310a5db738")
        ok(call("HMAC", ["sha1", "Jefe", data]), "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79")
        ok(call("HMAC", ["sha224", "Jefe", data]), "a30e01098bc6dbbf45690f3a7e9e6d0f8bbea2a39e6148008fd05e44")
        // 鍵を 16 進で渡す。
        ok(call("HMAC", ["sha256", "4a656665", data, "--key-in=hex"]), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        fails(call("HMAC", ["crc32", "k", "d"]), 400, "unsupported algorithm")
    }

    @Test
    func compareIsEqualityOverBytes() {
        ok(call("Compare", ["abc", "abc"]), "1")
        ok(call("Compare", ["abc", "abd"]), "0")
        ok(call("Compare", ["abc", "abcd"]), "0") // 長さが違えば 0
        // 16 進の署名どうしは、大文字小文字の違いを気にしなくてよい。
        ok(call("Compare", ["ABCD", "abcd", "--a-in=hex", "--b-in=hex"]), "1")
        ok(call("Compare", ["AB", "abcd", "--a-in=hex", "--b-in=hex"]), "0")
        #expect(InternalCryptoSupport.constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!InternalCryptoSupport.constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 4])))
    }
}

// MARK: - 共通鍵暗号

struct InternalCryptoCipherTests {
    private let key32 = "0123456789abcdef0123456789abcdef"
    private let key16 = "0123456789abcdef"

    @Test
    func everyCipherRoundTripsAndUsesAFreshNonceEachTime() {
        let cases: [(algorithm: String, key: String)] = [
            ("aes-256-gcm", key32), ("aes-128-gcm", key16), ("chacha20-poly1305", key32),
            ("aes-256-cbc", key32), ("aes-128-cbc", key16), ("aes-256-ctr", key32), ("chacha20", key32)
        ]
        for item in cases {
            let first = call("Encrypt", [item.algorithm, item.key, "secret message 桜鈴"])
            #expect(first.status == 200, "\(item.algorithm)")
            let second = call("Encrypt", [item.algorithm, item.key, "secret message 桜鈴"])
            // nonce / IV は暗号化のたびに乱数で作るので、同じ入力でも暗号文が変わる。
            #expect(first.result != second.result, "\(item.algorithm)")
            ok(call("Decrypt", [item.algorithm, item.key, first.result ?? ""]), "secret message 桜鈴")
        }
        // 名前のハイフン・アンダースコアと大文字小文字は区別しない。
        let packed = call("Encrypt", ["AES_256_GCM", key32, "x"]).result ?? ""
        ok(call("Decrypt", ["aes256gcm", key32, packed]), "x")
    }

    @Test
    func ciphertextLayoutFollowsTheDocumentedShapes() throws {
        func size(_ algorithm: String, _ key: String, _ plaintext: String) throws -> Int {
            try InternalSaoriCodec.decodeBase64(call("Encrypt", [algorithm, key, plaintext]).result ?? "").count
        }
        // nonce（12）＋ 暗号文 ＋ 認証タグ（16）。
        #expect(try size("aes-256-gcm", key32, "hello") == 12 + 5 + 16)
        #expect(try size("chacha20-poly1305", key32, "hello") == 12 + 5 + 16)
        // IV（16）＋ 暗号文（PKCS#7 で 16 の倍数）。
        #expect(try size("aes-256-cbc", key32, "hello") == 16 + 16)
        #expect(try size("aes-256-cbc", key32, String(repeating: "x", count: 16)) == 16 + 32)
        // IV（16）＋ 暗号文（同じ長さ）。nonce（12）＋ 暗号文。
        #expect(try size("aes-256-ctr", key32, "hello") == 16 + 5)
        #expect(try size("chacha20", key32, "hello") == 12 + 5)
    }

    @Test
    func aesGCMMatchesTheNISTTestCase() {
        // NIST GCM テストケース 16（AES-256、追加認証データあり）。
        let key = "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"
        let iv = "cafebabefacedbaddecaf888"
        let aad = "feedfacedeadbeeffeedfacedeadbeefabaddad2"
        let plaintext = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"
        let ciphertext = "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662"
        let tag = "76fc6ece0f4e1768cddf8853bb2d551b"
        let encrypted = call("Encrypt", ["aes-256-gcm", key, plaintext, "--key-in=hex", "--data-in=hex", "--iv=\(iv)", "--pack=none", "--aad=\(aad)", "--aad-in=hex", "--out=hex"])
        ok(encrypted, ciphertext + tag)
        ok(call("Decrypt", ["aes-256-gcm", key, ciphertext + tag, "--key-in=hex", "--ciphertext-in=hex", "--iv=\(iv)", "--pack=none", "--aad=\(aad)", "--aad-in=hex", "--out=hex"]), plaintext)
        // 追加認証データが違えば、復号できない。
        fails(call("Decrypt", ["aes-256-gcm", key, ciphertext + tag, "--key-in=hex", "--ciphertext-in=hex", "--iv=\(iv)", "--pack=none", "--out=hex"]), 500, "authentication failed")
    }

    @Test
    func chaCha20Poly1305MatchesRFC8439() {
        // RFC 8439 §2.8.2。
        let key = "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"
        let nonce = "070000004041424344454647"
        let aad = "50515253c0c1c2c3c4c5c6c7"
        let plaintext = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
        let expected = "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116" + "1ae10b594f09e26a7e902ecbd0600691"
        let encrypted = call("Encrypt", ["chacha20-poly1305", key, plaintext, "--key-in=hex", "--iv=\(nonce)", "--pack=none", "--aad=\(aad)", "--aad-in=hex", "--out=hex"])
        ok(encrypted, expected)
        ok(call("Decrypt", ["chacha20-poly1305", key, expected, "--key-in=hex", "--ciphertext-in=hex", "--iv=\(nonce)", "--pack=none", "--aad=\(aad)", "--aad-in=hex"]), plaintext)
    }

    @Test
    func rawChaCha20AndAESModesMatchPublishedVectors() {
        // RFC 8439 付録 A.1 テストベクタ #1: 鍵・nonce が 0 で、カウンタ 0 のキーストリーム。
        let keystream = "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586"
        ok(call("Encrypt", ["chacha20", String(repeating: "00", count: 32), String(repeating: "00", count: 64), "--key-in=hex", "--data-in=hex", "--iv=\(String(repeating: "00", count: 12))", "--pack=none", "--out=hex"]), keystream)
        // NIST SP 800-38A F.2.1（CBC-AES128）: 先頭のブロック。パディングで末尾に 1 ブロック付く。
        let cbc = call("Encrypt", ["aes-128-cbc", "2b7e151628aed2a6abf7158809cf4f3c", "6bc1bee22e409f96e93d7e117393172a", "--key-in=hex", "--data-in=hex", "--iv=000102030405060708090a0b0c0d0e0f", "--pack=none", "--out=hex"])
        #expect(cbc.result?.hasPrefix("7649abac8119b246cee98e9b12e9197d") == true)
        #expect(cbc.result?.count == 64)
        // NIST SP 800-38A F.5.5（CTR-AES256）。
        ok(call("Encrypt", ["aes-256-ctr", "603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4", "6bc1bee22e409f96e93d7e117393172a", "--key-in=hex", "--data-in=hex", "--iv=f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", "--pack=none", "--out=hex"]),
           "601ec313775789a5b7a7f504bbf3d228")
    }

    @Test
    func invalidKeysOptionsAndTamperedDataAreRejected() {
        fails(call("Encrypt", ["aes-256-gcm", "short", "x"]), 400, "invalid key")
        fails(call("Encrypt", ["aes-128-gcm", key32, "x"]), 400, "invalid key") // AES-128 に 32 バイトの鍵
        fails(call("Encrypt", ["nothing", key32, "x"]), 400, "unsupported algorithm")
        fails(call("Decrypt", ["aes-256-gcm", "short", "AAAA"]), 400, "invalid key")
        // --iv= は長さちょうど。--pack=none のときは --iv= が要る。
        fails(call("Encrypt", ["aes-256-gcm", key32, "x", "--iv=00", "--iv-in=hex"]), 400, "invalid parameter")
        fails(call("Encrypt", ["aes-256-gcm", key32, "x", "--pack=none"]), 400, "invalid parameter")
        fails(call("Encrypt", ["aes-256-gcm", key32, "x", "--pack=other"]), 400, "invalid parameter")
        // --aad= は認証付き暗号だけ。
        fails(call("Encrypt", ["aes-256-cbc", key32, "x", "--aad=a"]), 400, "invalid parameter")
        fails(call("Encrypt", ["chacha20", key32, "x", "--aad=a"]), 400, "invalid parameter")
        // 復号: nonce が先頭にあるときの --iv=、--pack=none で --iv= が無い、短すぎる暗号文。
        let packed = call("Encrypt", ["aes-256-gcm", key32, "x"]).result ?? ""
        fails(call("Decrypt", ["aes-256-gcm", key32, packed, "--iv=000000000000000000000000", "--iv-in=hex"]), 400, "invalid parameter")
        fails(call("Decrypt", ["aes-256-gcm", key32, packed, "--pack=none"]), 400, "invalid parameter")
        fails(call("Decrypt", ["aes-256-gcm", key32, "AAAA"]), 400, "invalid encoding")
        // 暗号文・認証タグを 1 バイト変えると復号できない。違う鍵でも同じ。
        var bytes = (try? InternalSaoriCodec.decodeBase64(packed)) ?? Data()
        bytes[bytes.count - 1] ^= 1
        fails(call("Decrypt", ["aes-256-gcm", key32, bytes.base64EncodedString()]), 500, "authentication failed")
        fails(call("Decrypt", ["aes-256-gcm", "fedcba9876543210fedcba9876543210", packed]), 500, "authentication failed")
        // CBC はパディングが合わないとき。
        let cbc = call("Encrypt", ["aes-256-cbc", key32, "hello"]).result ?? ""
        // パディングがたまたま合うこともあるので、失敗の種類までは問わない。
        #expect(call("Decrypt", ["aes-256-cbc", "fedcba9876543210fedcba9876543210", cbc]).status == 500)
        // 復号した結果が文字列にならない（--out=text で NUL を含む）ときは not text。
        let binary = call("Encrypt", ["aes-256-gcm", key32, "00ff", "--data-in=hex"]).result ?? ""
        fails(call("Decrypt", ["aes-256-gcm", key32, binary]), 500, "not text")
        ok(call("Decrypt", ["aes-256-gcm", key32, binary, "--out=hex"]), "00ff")
    }
}

// MARK: - DeriveKey / TOTP

struct InternalCryptoDerivationTests {
    @Test
    func pbkdf2MatchesPublishedVectors() {
        // 記述例（RFC 6070 の 4096 回）。
        ok(call("DeriveKey", ["pbkdf2", "password", "salt", "20", "--digest=sha1", "--iterations=4096"]), "4b007901b765489abead49d926f721d065a429c1")
        // RFC 7914 §11（PBKDF2-HMAC-SHA256）。
        ok(call("DeriveKey", ["pbkdf2", "passwd", "salt", "64", "--iterations=1"]),
           "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
        // 既定は sha256・600000 回。
        #expect(call("DeriveKey", ["pbkdf2", "password", "salt", "32"]).result?.count == 64)
        ok(call("DeriveKey", ["pbkdf2", "password", "salt", "8", "--iterations=1", "--out=base64"]), try! InternalSaoriCodec.encode(
            try! InternalSaoriCodec.decodeHex(call("DeriveKey", ["pbkdf2", "password", "salt", "8", "--iterations=1"]).result ?? ""),
            format: "base64", defaultFormat: "hex", charset: nil))
    }

    @Test
    func hkdfMatchesRFC5869() {
        // RFC 5869 テストケース 1（SHA-256）。
        let ikm = String(repeating: "0b", count: 22)
        let salt = "000102030405060708090a0b0c"
        let info = "f0f1f2f3f4f5f6f7f8f9"
        let okm = "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
        let prk = "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5"
        ok(call("DeriveKey", ["hkdf", ikm, salt, "42", "--password-in=hex", "--salt-in=hex", "--info=\(info)", "--info-in=hex"]), okm)
        ok(call("DeriveKey", ["hkdf-extract", ikm, salt, "32", "--password-in=hex", "--salt-in=hex"]), prk)
        ok(call("DeriveKey", ["hkdf-expand", prk, "", "42", "--password-in=hex", "--info=\(info)", "--info-in=hex"]), okm)
        // テストケース 3（salt・info が空）。
        ok(call("DeriveKey", ["hkdf", ikm, "", "42", "--password-in=hex"]),
           "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8")
    }

    @Test
    func derivationParametersAreValidatedPerMethod() {
        fails(call("DeriveKey", ["scrypt", "p", "s", "32"]), 400, "unsupported algorithm")
        fails(call("DeriveKey", ["argon2id", "p", "s", "32"]), 400, "unsupported algorithm")
        fails(call("DeriveKey", ["nothing", "p", "s", "32"]), 400, "unsupported algorithm")
        // その方式で使わないオプションは invalid parameter。
        fails(call("DeriveKey", ["hkdf", "p", "s", "32", "--iterations=10"]), 400, "invalid parameter")
        fails(call("DeriveKey", ["pbkdf2", "p", "s", "32", "--info=x"]), 400, "invalid parameter")
        fails(call("DeriveKey", ["hkdf-extract", "p", "s", "32", "--info=x"]), 400, "invalid parameter")
        // 長さ・回数の範囲。
        fails(call("DeriveKey", ["pbkdf2", "p", "s", "0"]), 400, "out of range")
        fails(call("DeriveKey", ["pbkdf2", "p", "s", "1025"]), 400, "out of range")
        fails(call("DeriveKey", ["pbkdf2", "p", "s", "x"]), 400, "invalid parameter")
        fails(call("DeriveKey", ["pbkdf2", "p", "s", "16", "--iterations=0"]), 400, "out of range")
        fails(call("DeriveKey", ["pbkdf2", "p", "s", "16", "--iterations=10000001"]), 400, "out of range")
        fails(call("DeriveKey", ["pbkdf2", "p", "s", "16", "--digest=md5", "--iterations=1"]), 400, "unsupported algorithm")
        // hkdf: IKM は空にできない。長さはハッシュの長さ × 255 まで。extract は長さがちょうど。expand は salt を空にする。
        fails(call("DeriveKey", ["hkdf", "", "s", "32"]), 400, "invalid parameter")
        fails(call("DeriveKey", ["hkdf", "p", "s", "\(255 * 32 + 1)"]), 400, "out of range")
        fails(call("DeriveKey", ["hkdf-extract", "p", "s", "31"]), 400, "out of range")
        fails(call("DeriveKey", ["hkdf-expand", "p", "s", "32"]), 400, "invalid parameter")
        #expect(call("DeriveKey", ["hkdf-extract", "p", "s", "20", "--digest=sha1"]).result?.count == 40)
    }

    @Test
    func totpMatchesRFC6238AndTheDocumentedExample() {
        // 記述例: 鍵は base32、--time=59、8 桁。
        ok(call("TOTP", ["GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "--time=59", "--digits=8"]), "94287082")
        // RFC 6238 付録 B（SHA-1・SHA-256・SHA-512）。鍵は ASCII の文字列。
        let sha1Key = "12345678901234567890"
        let sha256Key = "12345678901234567890123456789012"
        let sha512Key = "1234567890123456789012345678901234567890123456789012345678901234"
        ok(call("TOTP", [sha1Key, "--key-in=text", "--time=1111111109", "--digits=8"]), "07081804") // 先頭を 0 で埋める
        ok(call("TOTP", [sha1Key, "--key-in=text", "--time=20000000000", "--digits=8"]), "65353130")
        ok(call("TOTP", [sha256Key, "--key-in=text", "--time=59", "--digits=8", "--digest=sha256"]), "46119246")
        ok(call("TOTP", [sha512Key, "--key-in=text", "--time=59", "--digits=8", "--digest=sha512"]), "90693936")
        // 桁数・周期・日時の書き方。
        ok(call("TOTP", [sha1Key, "--key-in=text", "--time=59", "--digits=6"]), "287082")
        ok(call("TOTP", [sha1Key, "--key-in=text", "--time=1970-01-01T00:00:59Z", "--digits=6"]), "287082") // 59 秒と同じ 30 秒の枠
        ok(call("TOTP", [sha1Key, "--key-in=text", "--time=89", "--period=60", "--digits=6"]), call("TOTP", [sha1Key, "--key-in=text", "--time=60", "--period=60", "--digits=6"]).result ?? "")
        #expect(call("TOTP", [sha1Key, "--key-in=text", "--digits=10"]).result?.count == 10)
        // 既定の時刻は現在時刻。
        #expect(call("TOTP", ["GEZDGNBVGY3TQOJQ"]).result?.count == 6)
        fails(call("TOTP", [sha1Key, "--key-in=text", "--digest=md5"]), 400, "unsupported algorithm")
        fails(call("TOTP", [sha1Key, "--key-in=text", "--digits=5"]), 400, "invalid parameter")
        fails(call("TOTP", [sha1Key, "--key-in=text", "--digits=11"]), 400, "invalid parameter")
        fails(call("TOTP", [sha1Key, "--key-in=text", "--period=0"]), 400, "invalid parameter")
        fails(call("TOTP", [sha1Key, "--key-in=text", "--time=yesterday"]), 400, "invalid parameter")
        fails(call("TOTP", ["not base32!"]), 400, "invalid encoding")
    }
}

// MARK: - 公開鍵署名

struct InternalCryptoSignatureTests {
    @Test
    func ed25519SignatureMatchesTheDocumentedExample() throws {
        // 記述例（RFC 8037 の Ed25519）。署名は RFC 8037 のもの。
        let key = "MC4CAQAwBQYDK2VwBCIEIJ1hsZ3v/VpguoRK9JLsLMREScVpezJpGXA7rAMcrn9g"
        let data = "eyJhbGciOiJFZERTQSJ9.RXhhbXBsZSBvZiBFZDI1NTE5IHNpZ25pbmc"
        let signature = "hgyY0il_MGCjP0JzlnLWG1PPOt7-09PGcvMg3AIbQR6dWbhijcNR4ki4iylGjg5BhVsPt9g7sVvpAr_MuM0KAg"
        // CryptoKit の Ed25519 は署名が毎回変わる（どれも検証できる）ので、記述例の署名は検証側で確かめる。
        let signed = try #require(call("Sign", ["ed25519", key, data]).result)
        ok(call("Verify", ["ed25519", key, data, signed]), "1")
        ok(call("Verify", ["ed25519", key, data, signature]), "1")
        // 公開鍵の代わりに秘密鍵を渡してもよい。
        ok(call("Verify", ["ed25519", key, data, signature]), "1")
        ok(call("Verify", ["ed25519", key, data + "x", signature]), "0")
        ok(call("Verify", ["ed25519", key, data, "AAAA"]), "0") // 署名の長さが違うときも 0
        // 署名の形式を変える。
        let hex = call("Sign", ["ed25519", key, data, "--out=hex"]).result ?? ""
        #expect(hex.count == 128)
        ok(call("Verify", ["ed25519", key, data, hex, "--signature-in=hex"]), "1")
    }

    @Test
    func generatedKeyPairsSignAndVerifyForBothAlgorithms() throws {
        for algorithm in ["ed25519", "es256"] {
            let pair = call("GenerateKeyPair", [algorithm])
            #expect(pair.status == 200, "\(algorithm)")
            #expect(pair.values.count == 2)
            // Result は秘密鍵（Value0 と同じ）。公開鍵は Value1。
            #expect(pair.result == pair.values[0])
            let privateKey = pair.values[0], publicKey = pair.values[1]
            #expect(privateKey != publicKey)

            let signature = try #require(call("Sign", [algorithm, privateKey, "message"]).result)
            ok(call("Verify", [algorithm, publicKey, "message", signature]), "1")
            ok(call("Verify", [algorithm, privateKey, "message", signature]), "1")
            ok(call("Verify", [algorithm, publicKey, "tampered", signature]), "0")
            // 別の鍵ペアの公開鍵では検証できない。
            let other = call("GenerateKeyPair", [algorithm]).values[1]
            ok(call("Verify", [algorithm, other, "message", signature]), "0")
            // 鍵が読めない・種類が合わない。
            fails(call("Sign", [algorithm, "AAAA", "m"]), 400, "invalid key")
            fails(call("Verify", [algorithm, "AAAA", "m", signature]), 400, "invalid key")
        }
        // ES256 の署名は r‖s の 64 バイト（JWS と同じ形で、DER 形式ではない）。
        let es256 = call("GenerateKeyPair", ["es256"]).values[0]
        let raw = try InternalSaoriCodec.decodeBase64(call("Sign", ["es256", es256, "m"]).result ?? "")
        #expect(raw.count == 64)
        // ES256 は署名が毎回違うが、どれも検証できる。
        #expect(call("Sign", ["es256", es256, "m"]).result != call("Sign", ["es256", es256, "m"]).result)
        // 種類の違う鍵は invalid key。
        let ed = call("GenerateKeyPair", ["ed25519"]).values[0]
        fails(call("Sign", ["es256", ed, "m"]), 400, "invalid key")
        fails(call("Sign", ["ed25519", es256, "m"]), 400, "invalid key")
    }

    @Test
    func keysCanBePassedAsPEMWithSpacesInsteadOfNewlines() throws {
        func pem(_ label: String, _ base64: String) -> String {
            // 改行を空白にしたもの（SAORI のヘッダに改行は書けない）。
            "-----BEGIN \(label)----- \(base64) -----END \(label)-----"
        }
        let ed = call("GenerateKeyPair", ["ed25519"]).values
        let edSignature = try #require(call("Sign", ["ed25519", pem("PRIVATE KEY", ed[0]), "m"]).result)
        ok(call("Verify", ["ed25519", pem("PUBLIC KEY", ed[1]), "m", edSignature]), "1")

        let ec = call("GenerateKeyPair", ["es256"]).values
        let ecSignature = try #require(call("Sign", ["es256", pem("PRIVATE KEY", ec[0]), "m"]).result)
        ok(call("Verify", ["es256", pem("PUBLIC KEY", ec[1]), "m", ecSignature]), "1")

        // SEC1（EC PRIVATE KEY）の P-256 秘密鍵: SEQUENCE { INTEGER 1, OCTET STRING 秘密鍵 }。
        let scalar = P256.Signing.PrivateKey()
        let sec1 = Data([0x30, 0x25, 0x02, 0x01, 0x01, 0x04, 0x20]) + scalar.rawRepresentation
        let sec1Signature = try #require(call("Sign", ["es256", pem("EC PRIVATE KEY", sec1.base64EncodedString()), "m"]).result)
        ok(call("Verify", ["es256", scalar.publicKey.derRepresentation.base64EncodedString(), "m", sec1Signature]), "1")

        fails(call("Sign", ["ed25519", "-----BEGIN PRIVATE KEY----- !!! -----END PRIVATE KEY-----", "m"]), 400, "invalid key")
    }

    @Test
    func unimplementedSignatureAlgorithmsAreUnsupported() {
        for algorithm in ["bip340", "rsa-1024", "rsa-8192", "sha3"] {
            fails(call("GenerateKeyPair", [algorithm]), 400, "unsupported algorithm")
            fails(call("Sign", [algorithm, "key", "m"]), 400, "unsupported algorithm")
        }
        // --key-in= は bip340 だけのオプションなので、ほかの方式では受け付けない。
        fails(call("Sign", ["ed25519", "AAAA", "m", "--key-in=hex"]), 400, "invalid parameter")
    }

    @Test
    func listFunctionsShowsOnlyWhatIsImplemented() {
        let outcome = try! SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(
            requestText: "EXECUTE SAORI/1.0\r\nModule: internal_system\r\nArgument0: ListFunctions\r\nArgument1: internal_crypto\r\n\r\n"))
        let names = (outcome.headerValue("Result") ?? "").split(separator: ",").map(String.init)
        #expect(names == ["Digest", "HMAC", "Compare", "Encrypt", "Decrypt", "DeriveKey", "TOTP", "GenerateKeyPair", "Sign", "Verify"])
        fails(call("HashPassword", ["p"]), 400, "unknown function")
        fails(call("Protect", ["d"]), 400, "unknown function")
    }

    @Test
    func asyncDeliversTheKeyPairAsReference4And5() async throws {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var event: (name: String, references: [String: String])?
        }
        let box = Box()
        let context = InternalSaoriContext(ghostRoot: URL(fileURLWithPath: "/tmp/ghost"), deliverEvent: { name, params in
            box.lock.lock(); box.event = (name, params); box.lock.unlock()
        })
        #expect(call("GenerateKeyPair", ["es256", "--async=OnKeys"], context: context).status == 204)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            box.lock.lock(); let done = box.event != nil; box.lock.unlock()
            if done { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let event = try #require(box.event)
        #expect(event.name == "OnKeys")
        #expect(event.references["Reference3"] == "GenerateKeyPair")
        // 非同期の呼び出しでは、秘密鍵が Reference4、公開鍵が Reference5。
        #expect(event.references["Reference4"]?.isEmpty == false)
        #expect(event.references["Reference5"]?.isEmpty == false)
        #expect(event.references["Reference1"] == event.references["Reference4"])
    }
}
