import Foundation
import Testing
@testable import Ourin

private struct CurveOutcome {
    var status: Int
    var result: String?
    var values: [String]
    var error: String?
}

private func run(_ function: String, _ arguments: [String] = [], module: String = "internal_crypto") -> CurveOutcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: \(module)", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: .none)
    let response = try! SaoriProtocol.parseResponse(text)
    var values: [String] = []
    while let value = response.headerValue("Value\(values.count)") { values.append(value) }
    return CurveOutcome(status: response.statusCode, result: response.headerValue("Result"), values: values, error: response.headerValue("ErrorDescription"))
}

private func expectOK(_ outcome: CurveOutcome, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == 200, "status \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.result == expected, sourceLocation: sourceLocation)
}

private func expectFail(_ outcome: CurveOutcome, _ status: Int, _ description: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == status, "got \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.error == description, sourceLocation: sourceLocation)
}

private func hexBytes(_ hex: String) -> Data { try! InternalSaoriCodec.decodeHex(hex) }

private func patternBytes(_ count: Int, _ multiplier: Int, _ offset: Int) -> Data {
    Data((0..<count).map { UInt8(($0 * multiplier + offset) % 256) })
}

// MARK: - BIP-340

struct InternalBIP340Tests {
    private static let message = "243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89"
    private static let secret1 = "b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef"
    private static let public1 = "dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659"
    private static let aux1 = "0000000000000000000000000000000000000000000000000000000000000001"
    private static let signature1 = "6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de33418906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a"

    private func sign(_ secret: String, _ message: String, aux: String, extra: [String] = []) -> CurveOutcome {
        run("Sign", ["bip340", secret, message, "--data-in=hex", "--aux=\(aux)"] + extra)
    }

    @Test
    func officialSigningVectors() {
        // test-vectors.csv の 0〜3。
        expectOK(sign("0000000000000000000000000000000000000000000000000000000000000003", String(repeating: "00", count: 32), aux: String(repeating: "00", count: 32)),
                 "e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca821525f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0")
        expectOK(sign(Self.secret1, Self.message, aux: Self.aux1), Self.signature1)
        expectOK(sign("c90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b14e5c9", "7e2d58d8b3bcdf1abadec7829054f90dda9805aab56c77333024b9d0a508b75c",
                      aux: "c87aa53824b4d7ae2eb035a2b5bbbccc080e76cdc6d1692c4b0b62d798e6d906"),
                 "5831aaeed7b44bb74e5eab94ba9d4294c49bcf2a60728d8b4c200f50dd313c1bab745879a5ad954a72c45a91c3a51d3c7adea98d82f8481e0e1e03674a6f3fb7")
        expectOK(sign("0b432b2677937381aef05bb02a66ecd012773062cf3fa2549e44f58ed2401710", String(repeating: "ff", count: 32), aux: String(repeating: "ff", count: 32)),
                 "7eb0509757e246f19449885651611cb965ecc1a187dd51b64fda1edc9637d5ec97582b9cb13db3933705b32ba982af5af25fd78881ebb32771fc5922efc66ea3")
    }

    @Test
    func variableLengthMessagesMatchTheReferenceImplementation() {
        // 参照実装（BIP-340 の Python）で求めた値。メッセージはハッシュされず、長さは自由。
        let aux = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        let cases: [(count: Int, signature: String)] = [
            (0, "de00107613ebb2006e67c4604218fcb0fc5d011a2a9a1b0c8132b052d1dbcf5b800e48177e5c37972bd479dc3ec4b69063802678451c0113e0e29968e65ddce7"),
            (1, "e7ac2d294cd633c811462d59727284318bfd0639a555253fd1e406ba7076dcfefc8c8073286d0eabe51c3f4cc85d13a20103be8562d6ef2d1e86b2d94e8c73f8"),
            (17, "9b6afb760ce83cb649040f37e103444054e803c96e212192388eec04b5671a6bfc1a61e7b1edf0ab5a83e11049d6863d70e4d862b2b260ade1a855c7aed06687"),
            (100, "b720fbc8c4d2474c859d7060235d6212f0cb5c7f56d4fcbfdd4c1f2f961bd11e515d8dcf6fb90c5d4977bcce5bc247c6278c75d86628dc76a6fac4a225d39c06"),
        ]
        for item in cases {
            let message = patternBytes(item.count, 7, 3).map { String(format: "%02x", $0) }.joined()
            expectOK(sign(Self.secret1, message, aux: aux), item.signature)
            expectOK(run("Verify", ["bip340", Self.public1, message, item.signature, "--data-in=hex"]), "1")
        }
    }

    @Test
    func verifyAcceptsTheSigningVectorsAndRejectsTheOfficialFailureCases() {
        expectOK(run("Verify", ["bip340", Self.public1, Self.message, Self.signature1, "--data-in=hex"]), "1")
        // 公式ベクタ 4（有効）。
        expectOK(run("Verify", ["bip340", "d69c3509bb99e412e68b0fe8544e72837dfa30746d8be2aa65975f29d22dc7b9",
                                "4df3c3f68fcc83b27e9d42c90431a72499f17875c81a599b566c9889b9696703",
                                "00000000000000000000003b78ce563f89a0ed9414f5aa28ad0d96d6795f9c6376afb1548af603b3eb45c9f8207dee1060cb71c04e80f593060b07d28308d7f4",
                                "--data-in=hex"]), "1")
        // 公式ベクタ 6: R の y が奇数。
        expectOK(run("Verify", ["bip340", "dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659", Self.message,
                                "fff97bd5755eeea420453a14355235d382f6472f8568a18b2f057a14602975563cc27944640ac607cd107ae10923d9ef7a73c643e166be5ebeafa34b1ac553e2",
                                "--data-in=hex"]), "0")
        // R の y が奇数になる署名（k を反転しないで作ったもの）。
        expectOK(run("Verify", ["bip340", Self.public1, Self.message,
                                "f01d6b9018ab421dd410404cb869072065522bf85734008f105cf385a023a80f72eca73310bb9747ff6d8d4745edcadfad7ca5aa8a52fb80b7f97bac7860f727",
                                "--data-in=hex"]), "0")
        let good = Self.signature1
        // 公開鍵が曲線上の点でない（x = 5）。長さは 32 バイトなので 400 ではなく 0。
        expectOK(run("Verify", ["bip340", String(repeating: "00", count: 31) + "05", Self.message, good, "--data-in=hex"]), "0")
        // 公開鍵が p 以上。
        expectOK(run("Verify", ["bip340", "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f", Self.message, good, "--data-in=hex"]), "0")
        // r が p 以上。
        expectOK(run("Verify", ["bip340", Self.public1, Self.message, "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f" + good.suffix(64), "--data-in=hex"]), "0")
        // s が位数 n 以上。
        expectOK(run("Verify", ["bip340", Self.public1, Self.message, good.prefix(64) + "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141", "--data-in=hex"]), "0")
        // メッセージ・署名・公開鍵の改ざん。
        expectOK(run("Verify", ["bip340", Self.public1, String(Self.message.dropLast()) + "8", good, "--data-in=hex"]), "0")
        expectOK(run("Verify", ["bip340", Self.public1, Self.message, String(good.dropLast()) + "b", "--data-in=hex"]), "0")
        expectOK(run("Verify", ["bip340", "dd308afec5777e13121fa72b9cc1b7cc0139715309b086c960e18fd969774eb8", Self.message, good, "--data-in=hex"]), "0")
        // 署名の長さが違うときは 0。
        expectOK(run("Verify", ["bip340", Self.public1, Self.message, String(good.dropLast(2)), "--data-in=hex"]), "0")
        expectOK(run("Verify", ["bip340", Self.public1, Self.message, "", "--data-in=hex"]), "0")
    }

    @Test
    func keyHandling() {
        // 公開鍵の長さが違う・秘密鍵を公開鍵として渡す（bip340 では受け付けない）。
        expectFail(run("Verify", ["bip340", String(Self.public1.dropLast(2)), Self.message, Self.signature1, "--data-in=hex"]), 400, "invalid key")
        expectFail(run("Verify", ["bip340", Self.public1 + "00", Self.message, Self.signature1, "--data-in=hex"]), 400, "invalid key")
        // 範囲外の秘密鍵: 0・位数以上・長さ違い。
        for bad in [String(repeating: "00", count: 32), "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141",
                    String(repeating: "ff", count: 32), "01", Self.secret1 + "00"] {
            expectFail(run("Sign", ["bip340", bad, "m"]), 400, "invalid key")
        }
        // 位数 − 1 は有効。
        #expect(run("Sign", ["bip340", "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413f", "m"]).status == 200)
        // aux の長さが違う。
        expectFail(run("Sign", ["bip340", Self.secret1, "m", "--aux=0011"]), 400, "invalid parameter")
        // --key-in= / --aux= は bip340 だけ。
        expectFail(run("Verify", ["ed25519", "AAAA", "m", "AAAA", "--key-in=hex"]), 400, "invalid parameter")
        expectFail(run("Sign", ["es256", "AAAA", "m", "--aux=00"]), 400, "invalid parameter")
        expectFail(run("Sign", ["rs256", "AAAA", "m", "--key-in=hex"]), 400, "invalid parameter")
    }

    @Test
    func algorithmNameIsNormalisedAndOutputFormatsWork() {
        expectOK(run("Sign", ["BIP-340", Self.secret1, Self.message, "--data-in=hex", "--aux=\(Self.aux1)"]), Self.signature1)
        expectOK(run("Sign", ["bip_340", Self.secret1, Self.message, "--data-in=hex", "--aux=\(Self.aux1)"]), Self.signature1)
        let base64 = hexBytes(Self.signature1).base64EncodedString()
        expectOK(run("Sign", ["bip340", Self.secret1, Self.message, "--data-in=hex", "--aux=\(Self.aux1)", "--out=base64"]), base64)
        expectOK(run("Verify", ["bip340", Self.public1, Self.message, base64, "--data-in=hex", "--signature-in=base64"]), "1")
        // aux を別の形式で。
        let auxBase64 = hexBytes(Self.aux1).base64EncodedString()
        expectOK(run("Sign", ["bip340", Self.secret1, Self.message, "--data-in=hex", "--aux=\(auxBase64)", "--aux-in=base64"]), Self.signature1)
    }

    @Test
    func bech32KeysAreAccepted() throws {
        let nsec = try InternalSaoriCodec.encode(hexBytes(Self.secret1), format: "bech32", defaultFormat: "hex", charset: nil, hrp: "nsec")
        let npub = try InternalSaoriCodec.encode(hexBytes(Self.public1), format: "bech32", defaultFormat: "hex", charset: nil, hrp: "npub")
        #expect(nsec.hasPrefix("nsec1") && npub.hasPrefix("npub1"))
        expectOK(run("Sign", ["bip340", nsec, Self.message, "--key-in=bech32", "--data-in=hex", "--aux=\(Self.aux1)"]), Self.signature1)
        expectOK(run("Verify", ["bip340", npub, Self.message, Self.signature1, "--key-in=bech32", "--data-in=hex"]), "1")
    }

    @Test
    func randomAuxGivesDifferentButValidSignatures() throws {
        let first = try #require(run("Sign", ["bip340", Self.secret1, "hello"]).result)
        let second = try #require(run("Sign", ["bip340", Self.secret1, "hello"]).result)
        #expect(first.count == 128)
        #expect(first != second)
        expectOK(run("Verify", ["bip340", Self.public1, "hello", first]), "1")
        expectOK(run("Verify", ["bip340", Self.public1, "hello", second]), "1")
        expectOK(run("Verify", ["bip340", Self.public1, "hellO", second]), "0")
    }

    @Test
    func generatedKeyPairs() throws {
        let pair = run("GenerateKeyPair", ["bip340"])
        #expect(pair.status == 200)
        #expect(pair.values.count == 2)
        #expect(pair.result == pair.values[0])
        let secret = pair.values[0], publicKey = pair.values[1]
        #expect(secret.count == 64 && publicKey.count == 64)
        #expect(secret == secret.lowercased() && publicKey == publicKey.lowercased())
        // 公開鍵は秘密鍵から決まるもので、署名・ECDH にそのまま使える。
        let signature = try #require(run("Sign", ["bip340", secret, "message"]).result)
        expectOK(run("Verify", ["bip340", publicKey, "message", signature]), "1")
        let other = run("GenerateKeyPair", ["bip340"]).values
        expectOK(run("KeyAgreement", ["secp256k1", secret, other[1]]), try #require(run("KeyAgreement", ["secp256k1", other[0], publicKey]).result))
        #expect(run("Verify", ["bip340", other[1], "message", signature]).result == "0")
    }

    @Test
    func schnorrRoundTripsForManySecrets() {
        // 位数の近く・小さい値・偶奇が混じる鍵で往復する。
        let secrets = ["0000000000000000000000000000000000000000000000000000000000000001",
                       "0000000000000000000000000000000000000000000000000000000000000002",
                       "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd036413f",
                       Self.secret1]
        for secret in secrets {
            let publicKey = InternalSecp256k1.publicKey(secret: hexBytes(secret))
            #expect(publicKey != nil)
            for count in [0, 5, 32, 300] {
                let message = patternBytes(count, 13, 1)
                let signature = InternalSecp256k1.schnorrSign(secret: hexBytes(secret), message: message, aux: Data(repeating: 9, count: 32))
                #expect(signature != nil)
                #expect(InternalSecp256k1.schnorrVerify(publicKey: publicKey!, message: message, signature: signature!))
            }
        }
        // 秘密鍵 1 の公開鍵は生成元 G の x 座標。
        #expect(InternalSecp256k1.publicKey(secret: hexBytes(secrets[0])) == hexBytes("79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"))
    }
}

// MARK: - KeyAgreement

struct InternalKeyAgreementTests {
    private static let secret = "315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268"
    private static let peer = "c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133"
    private static let shared = "5ad01c0fc57ed5f92a0518b6440ca876eb1f247ddbb237ba1caaabbf4cebbdce"
    private static let uncompressed = "04c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133729f5b704652bf4ce3c878084ff3332d9742798fc098ed9ea908f4458b0889f0"

    @Test
    func documentedNIP44Example() {
        expectOK(run("KeyAgreement", ["secp256k1", Self.secret, Self.peer]), Self.shared)
        // 続きの記述例: hkdf-extract で NIP-44 の会話鍵になる。
        expectOK(run("DeriveKey", ["hkdf-extract", Self.shared, "nip44-v2", "32", "--password-in=hex"]),
                 "3dfef0ce2a4d80a25e7a328accf73448ef67096f65f79588e358d9a0eb9013f1")
    }

    @Test
    func peerKeyForms() {
        // 圧縮形式（y が偶数 02、奇数 03）。x だけの形は偶数の y として扱う。奇数の y の点でも x 座標は同じ。
        expectOK(run("KeyAgreement", ["secp256k1", Self.secret, "02" + Self.peer]), Self.shared)
        expectOK(run("KeyAgreement", ["secp256k1", Self.secret, "03" + Self.peer]), Self.shared)
        expectOK(run("KeyAgreement", ["secp256k1", Self.secret, Self.uncompressed]), Self.shared)
    }

    @Test
    func optionsAndFormats() throws {
        let secretBase64 = hexBytes(Self.secret).base64EncodedString()
        let peerBase64 = hexBytes(Self.peer).base64EncodedString()
        expectOK(run("KeyAgreement", ["secp256k1", secretBase64, Self.peer, "--key-in=base64"]), Self.shared)
        expectOK(run("KeyAgreement", ["secp256k1", Self.secret, peerBase64, "--peer-in=base64"]), Self.shared)
        expectOK(run("KeyAgreement", ["SECP-256K1", Self.secret, Self.peer, "--out=base64"]), hexBytes(Self.shared).base64EncodedString())
        let nsec = try InternalSaoriCodec.encode(hexBytes(Self.secret), format: "bech32", defaultFormat: "hex", charset: nil, hrp: "nsec")
        let npub = try InternalSaoriCodec.encode(hexBytes(Self.peer), format: "bech32", defaultFormat: "hex", charset: nil, hrp: "npub")
        expectOK(run("KeyAgreement", ["secp256k1", nsec, npub, "--key-in=bech32", "--peer-in=bech32"]), Self.shared)
    }

    @Test
    func rejectsBadInput() {
        let zero = String(repeating: "00", count: 32)
        // 秘密鍵: 0・位数以上・長さ違い。
        expectFail(run("KeyAgreement", ["secp256k1", zero, Self.peer]), 400, "invalid key")
        expectFail(run("KeyAgreement", ["secp256k1", "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141", Self.peer]), 400, "invalid key")
        expectFail(run("KeyAgreement", ["secp256k1", "0102", Self.peer]), 400, "invalid key")
        // 相手: 曲線上にない（x = 5）・点でない非圧縮・長さ違い・prefix 違い。
        expectFail(run("KeyAgreement", ["secp256k1", Self.secret, String(repeating: "00", count: 31) + "05"]), 400, "invalid key")
        expectFail(run("KeyAgreement", ["secp256k1", Self.secret, String(Self.uncompressed.dropLast()) + "1"]), 400, "invalid key")
        expectFail(run("KeyAgreement", ["secp256k1", Self.secret, String(Self.peer.dropLast(2))]), 400, "invalid key")
        expectFail(run("KeyAgreement", ["secp256k1", Self.secret, "05" + Self.peer]), 400, "invalid key")
        expectFail(run("KeyAgreement", ["secp256k1", Self.secret, "02" + Self.peer + "00"]), 400, "invalid key")
        // 方式。
        expectFail(run("KeyAgreement", ["x25519", Self.secret, Self.peer]), 400, "unsupported algorithm")
        expectFail(run("KeyAgreement", ["secp256r1", Self.secret, Self.peer]), 400, "unsupported algorithm")
    }

    @Test
    func bothSidesAgree() {
        let aliceSecret = "0000000000000000000000000000000000000000000000000000000000001234"
        let bobSecret = "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364100"
        let alicePublic = InternalSecp256k1.publicKey(secret: hexBytes(aliceSecret))!.map { String(format: "%02x", $0) }.joined()
        let bobPublic = InternalSecp256k1.publicKey(secret: hexBytes(bobSecret))!.map { String(format: "%02x", $0) }.joined()
        let a = run("KeyAgreement", ["secp256k1", aliceSecret, bobPublic]).result
        let b = run("KeyAgreement", ["secp256k1", bobSecret, alicePublic]).result
        #expect(a != nil && a == b)
    }
}

// MARK: - Ed25519（RFC 8032、決定的）

struct InternalEd25519Tests {
    private func signature(seed: String, message: Data) -> String {
        InternalEd25519.sign(seed: hexBytes(seed), message: message).map { String(format: "%02x", $0) }.joined()
    }

    private func publicKey(_ seed: String) -> String {
        InternalEd25519.publicKey(seed: hexBytes(seed)).map { String(format: "%02x", $0) }.joined()
    }

    @Test
    func rfc8032Vectors() {
        // TEST 1（空のメッセージ）。
        let seed1 = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
        #expect(publicKey(seed1) == "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        #expect(signature(seed: seed1, message: Data()) == "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        // TEST 2（1 バイト）。
        let seed2 = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
        #expect(publicKey(seed2) == "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c")
        #expect(signature(seed: seed2, message: Data([0x72])) == "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00")
    }

    @Test
    func matchesTheReferenceImplementation() {
        // 参照実装（RFC 8032 の Python）で求めた値（TEST 3・1024 バイト相当の長さを含む）。
        let seed3 = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
        #expect(publicKey(seed3) == "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025")
        #expect(signature(seed: seed3, message: Data([0x05])) == "eb7210c5db39d3bc9712e68098d60059c4724cf5b18366a239ee65f04671d37124de3072c4b0b27ce813a5e57101e7ff46ab763c86f99ad522bd9dab88a94605")
        let zero = String(repeating: "00", count: 32)
        #expect(signature(seed: zero, message: Data()) == "8f895b3cafe2c9506039d0e2a66382568004674fe8d237785092e40d6aaf483e4fc60168705f31f101596138ce21aa357c0d32a064f423dc3ee4aa3abf53f803")
        let ones = String(repeating: "ff", count: 32)
        #expect(publicKey(ones) == "76a1592044a6e4f511265bca73a604d90b0529d1df602be30a19a9257660d1f5")
        #expect(signature(seed: ones, message: patternBytes(1024, 31, 5)) == "5b9c4dbbe3406404308bc5487604902f1c471ad3deca31ff98062b4dadc26a2a0c724ef0bfee82a08a9ddc17e36e26808e98bcce5919b6b87119ed6cd1bba103")
        let counting = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"
        #expect(signature(seed: counting, message: patternBytes(100, 31, 5)) == "7de3441534541c53be16c85a2ffc96bf1d2af913b23a9f4b83191fc26110573118a21305a54d2ac8d22e590f7c79dc235e205f89dcc462936eda58d97bc51c04")
    }

    @Test
    func signaturesVerifyWithCryptoKitAndAreStable() throws {
        // 自前の署名が CryptoKit で検証でき、同じ入力なら同じ署名になる。
        for count in [0, 1, 63, 64, 65, 1000] {
            let message = patternBytes(count, 11, 2)
            let pair = run("GenerateKeyPair", ["ed25519"])
            let first = try #require(run("Sign", ["ed25519", pair.values[0], message.base64EncodedString(), "--data-in=base64"]).result)
            let second = try #require(run("Sign", ["ed25519", pair.values[0], message.base64EncodedString(), "--data-in=base64"]).result)
            #expect(first == second)
            expectOK(run("Verify", ["ed25519", pair.values[1], message.base64EncodedString(), first, "--data-in=base64"]), "1")
        }
    }

    @Test
    func jwtEdDSAIsDeterministic() throws {
        let key = "MC4CAQAwBQYDK2VwBCIEIJ1hsZ3v/VpguoRK9JLsLMREScVpezJpGXA7rAMcrn9g"
        let first = try #require(run("Sign", ["EdDSA", key, "{\"sub\":\"sakura\"}"], module: "internal_jwt").result)
        let second = try #require(run("Sign", ["EdDSA", key, "{\"sub\":\"sakura\"}"], module: "internal_jwt").result)
        #expect(first == second)
        #expect(first.split(separator: ".").count == 3)
        let verified = run("Verify", [first, key, "--alg=EdDSA"], module: "internal_jwt")
        #expect(verified.status == 200, "\(verified.error ?? "")")
    }
}
