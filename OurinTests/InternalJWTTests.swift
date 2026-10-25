import CryptoKit
import Foundation
import Testing
@testable import Ourin

private struct JWTOutcome {
    var status: Int
    var result: String?
    var values: [String]
    var error: String?
}

private func jwt(_ function: String, _ arguments: [String] = [], context: InternalSaoriContext = .none) -> JWTOutcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_jwt", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: context)
    let response = try! SaoriProtocol.parseResponse(text)
    var values: [String] = []
    while let value = response.headerValue("Value\(values.count)") { values.append(value) }
    return JWTOutcome(status: response.statusCode, result: response.headerValue("Result"), values: values, error: response.headerValue("ErrorDescription"))
}

private func jwtOK(_ outcome: JWTOutcome, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == 200, "status \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.result == expected, sourceLocation: sourceLocation)
}

private func jwtFails(_ outcome: JWTOutcome, _ status: Int, _ description: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == status, "got \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.error == description, sourceLocation: sourceLocation)
}

struct InternalJWTTests {
    private let secret = "0123456789abcdef0123456789abcdef"
    private let documented = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzYWt1cmEiLCJleHAiOjQxMDI0NDQ4MDB9.eJKcQzLKm4FjTltXWvPqonVpfwhVaBgpvf9nZw0szuM"

    @Test
    func documentedExampleSignsAndVerifies() {
        jwtOK(jwt("Sign", ["HS256", secret, "{\"sub\":\"sakura\",\"exp\":4102444800}"]), documented)
        jwtOK(jwt("Sign", ["hs256", secret, "{\"sub\":\"sakura\",\"exp\":4102444800}"]), documented) // alg は大文字小文字を区別しない
        jwtOK(jwt("Verify", [documented, secret, "--alg=HS256"]), "{\"sub\":\"sakura\",\"exp\":4102444800}")
        jwtOK(jwt("Verify", [documented, secret, "--alg=hs256"]), "{\"sub\":\"sakura\",\"exp\":4102444800}")
    }

    @Test
    func rfc7515HS256VectorVerifiesAndFlattensNewlines() {
        // RFC 7515 A.1。ヘッダ・ペイロードに CRLF を含む。鍵は JWK の base64url。
        let token = "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let key = "AyM1SysPpbyDfgZld3umj1qzKObwVMkoqQ-EstJQLr_T-1qS0gZH75aKtMN3Yj0iPS4hcgUuTwjAzZr1Z9CAow"
        let outcome = jwt("Verify", [token, key, "--alg=HS256", "--key-in=base64url", "--time=1300819379"])
        jwtOK(outcome, "{\"iss\":\"joe\",   \"exp\":1300819380,   \"http://example.com/is_root\":true}")
        // exp の時刻ちょうどで失効する。leeway で延ばせる。
        jwtFails(jwt("Verify", [token, key, "--alg=HS256", "--key-in=base64url", "--time=1300819380"]), 500, "expired")
        jwtOK(jwt("Verify", [token, key, "--alg=HS256", "--key-in=base64url", "--time=1300819380", "--leeway=1"]),
              "{\"iss\":\"joe\",   \"exp\":1300819380,   \"http://example.com/is_root\":true}")
    }

    @Test
    func headerOptionAddsItemsButCannotChangeTheAlgorithm() throws {
        func header(_ token: String?) throws -> String {
            let part = try #require(token?.split(separator: ".").first)
            return String(data: try InternalSaoriCodec.decodeBase64(String(part)), encoding: .utf8) ?? ""
        }
        let withKid = jwt("Sign", ["HS256", secret, "{\"a\":1}", "--header={\"kid\":\"k/1\"}"])
        #expect(try header(withKid.result) == "{\"alg\":\"HS256\",\"typ\":\"JWT\",\"kid\":\"k/1\"}")
        #expect(try header(jwt("Sign", ["HS256", secret, "{}", "--header={\"typ\":\"at+jwt\"}"]).result) == "{\"alg\":\"HS256\",\"typ\":\"at+jwt\"}")
        // alg を書くなら引数と同じ値だけ。
        #expect(jwt("Sign", ["HS256", secret, "{}", "--header={\"alg\":\"HS256\"}"]).status == 200)
        jwtFails(jwt("Sign", ["HS256", secret, "{}", "--header={\"alg\":\"HS512\"}"]), 400, "invalid parameter")
        jwtFails(jwt("Sign", ["HS256", secret, "{}", "--header={\"alg\":\"none\"}"]), 400, "invalid parameter")
        jwtFails(jwt("Sign", ["HS256", secret, "{}", "--header=[1]"]), 400, "invalid parameter")
        jwtFails(jwt("Sign", ["HS256", secret, "{}", "--header=nonsense"]), 400, "invalid parameter")
    }

    @Test
    func payloadMustBeASingleJSONObject() {
        for payload in ["", "[1]", "\"text\"", "1", "null", "{\"a\":1} {\"b\":2}", "{\"a\":", "plain"] {
            jwtFails(jwt("Sign", ["HS256", secret, payload]), 400, "invalid parameter")
        }
        // 書かれた文字列のまま使う（空白も順序もそのまま）。
        let token = jwt("Sign", ["HS256", secret, "{ \"b\" : 2,\"a\":1 }"]).result ?? ""
        jwtOK(jwt("Verify", [token, secret, "--alg=HS256"]), "{ \"b\" : 2,\"a\":1 }")
    }

    @Test
    func hmacKeysMustBeAsLongAsTheHash() {
        jwtFails(jwt("Sign", ["HS256", String(repeating: "k", count: 31), "{}"]), 400, "invalid key")
        #expect(jwt("Sign", ["HS256", String(repeating: "k", count: 32), "{}"]).status == 200)
        jwtFails(jwt("Sign", ["HS384", String(repeating: "k", count: 47), "{}"]), 400, "invalid key")
        #expect(jwt("Sign", ["HS384", String(repeating: "k", count: 48), "{}"]).status == 200)
        jwtFails(jwt("Sign", ["HS512", String(repeating: "k", count: 63), "{}"]), 400, "invalid key")
        #expect(jwt("Sign", ["HS512", String(repeating: "k", count: 64), "{}"]).status == 200)
        // 16 進で渡した 16 バイトは短い。32 バイトなら通る。
        jwtFails(jwt("Sign", ["HS256", String(repeating: "ab", count: 16), "{}", "--key-in=hex"]), 400, "invalid key")
        #expect(jwt("Sign", ["HS256", String(repeating: "ab", count: 32), "{}", "--key-in=hex"]).status == 200)
        jwtFails(jwt("Verify", [documented, "short", "--alg=HS256"]), 400, "invalid key")
        jwtFails(jwt("Sign", ["HS256", "zz", "{}", "--key-in=hex"]), 400, "invalid key")
    }

    @Test
    func everyHMACAlgorithmRoundTrips() {
        for (alg, length) in [("HS256", 32), ("HS384", 48), ("HS512", 64)] {
            let key = String(repeating: "s", count: length)
            let token = jwt("Sign", [alg, key, "{\"n\":1}"]).result ?? ""
            jwtOK(jwt("Verify", [token, key, "--alg=\(alg)"]), "{\"n\":1}")
            jwtFails(jwt("Verify", [token, String(repeating: "t", count: length), "--alg=\(alg)"]), 500, "authentication failed")
        }
    }

    @Test
    func algorithmSubstitutionIsRejected() throws {
        // --alg= が無い・知らない名前（none を含む）・RSA 系（未実装）。
        jwtFails(jwt("Verify", [documented, secret]), 400, "invalid parameter")
        jwtFails(jwt("Verify", [documented, secret, "--alg="]), 400, "invalid parameter")
        for alg in ["none", "RS384", "PS512", "HS1", "ES384"] {
            jwtFails(jwt("Verify", [documented, secret, "--alg=\(alg)"]), 400, "unsupported algorithm")
            jwtFails(jwt("Sign", [alg, secret, "{}"]), 400, "unsupported algorithm")
        }
        // トークンの alg と --alg= が違う。
        jwtFails(jwt("Verify", [documented, String(repeating: "k", count: 48), "--alg=HS384"]), 500, "authentication failed")
        // alg が none の署名なしトークン。
        func b64(_ text: String) -> String { Data(text.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") }
        let none = b64("{\"alg\":\"none\"}") + "." + b64("{\"sub\":\"x\"}") + "."
        jwtFails(jwt("Verify", [none, secret, "--alg=HS256"]), 500, "authentication failed")
        // ヘッダの alg を書き換えただけ（署名はそのまま）、alg の大文字小文字違い。
        let forged = b64("{\"alg\":\"hs256\",\"typ\":\"JWT\"}") + "." + documented.split(separator: ".")[1] + "." + documented.split(separator: ".")[2]
        jwtFails(jwt("Verify", [forged, secret, "--alg=HS256"]), 500, "authentication failed")
        // HS256 の公開鍵を HMAC の鍵にする攻撃: ES256 で指定した検証に HS256 のトークンは通らない。
        let pair = jwt("Sign", ["ES256", "x", "{}"]) // 鍵が読めない
        jwtFails(pair, 400, "invalid key")
        let keys = InternalSaoriRegistry.shared.handle(requestText: "EXECUTE SAORI/1.0\r\nModule: internal_crypto\r\nArgument0: GenerateKeyPair\r\nArgument1: es256\r\n\r\n")
        let response = try SaoriProtocol.parseResponse(keys)
        let publicKey = try #require(response.headerValue("Value1"))
        let hs = jwt("Sign", ["HS256", String(repeating: "p", count: 40), "{}"]).result ?? ""
        jwtFails(jwt("Verify", [hs, publicKey, "--alg=ES256"]), 500, "authentication failed")
    }

    @Test
    func malformedTokensFailAuthentication() {
        let failure = "authentication failed"
        func b64(_ text: String) -> String { Data(text.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") }
        let payload = documented.split(separator: ".")[1]
        let signature = documented.split(separator: ".")[2]
        let header = documented.split(separator: ".")[0]
        let cases = [
            "", "abc", "a.b", "a.b.c.d", "\(header).\(payload)", "\(header).\(payload).\(signature).x",
            "\(header)=.\(payload).\(signature)", "\(header).\(payload)=.\(signature)", "\(header).\(payload).\(signature)=",
            "\(header)+.\(payload).\(signature)",
            "\(b64("[1]")).\(payload).\(signature)", "\(b64("not json")).\(payload).\(signature)",
            "\(header).\(b64("[1]")).\(signature)", "\(header).\(b64("\"s\"")).\(signature)",
            "\(header).\(payload).", "\(header).\(payload).AAAA"
        ]
        for token in cases { jwtFails(jwt("Verify", [token, secret, "--alg=HS256"]), 500, failure) }
        // 署名を 1 文字変える・ペイロードを書き換える。
        // 末尾の文字は下位ビットが余るので、読み取り結果の変わる先頭の文字を変える。
        let tampered = String(documented.prefix(documented.count - signature.count)) + (signature.first == "e" ? "f" : "e") + String(signature.dropFirst())
        jwtFails(jwt("Verify", [tampered, secret, "--alg=HS256"]), 500, failure)
        let swapped = "\(header).\(b64("{\"sub\":\"admin\",\"exp\":4102444800}")).\(signature)"
        jwtFails(jwt("Verify", [swapped, secret, "--alg=HS256"]), 500, failure)
        // UTF-8 として正しくないペイロード（署名は正しく付ける）。
        let badBytes = Data([0x7B, 0x22, 0x61, 0x22, 0x3A, 0x22, 0xFF, 0x22, 0x7D]) // {"a":"\xFF"}
        let input = "\(header)." + badBytes.base64EncodedString().replacingOccurrences(of: "=", with: "")
        let mac = InternalCryptoSupport.hmac(.sha256, key: Data(secret.utf8), data: Data(input.utf8))
        let sig = mac.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        jwtFails(jwt("Verify", ["\(input).\(sig)", secret, "--alg=HS256"]), 500, failure)
    }

    @Test
    func criticalHeadersAndNonNumericClaimsFail() {
        func token(_ header: String, _ payload: String) -> String {
            func b64(_ text: String) -> String { Data(text.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") }
            let input = b64(header) + "." + b64(payload)
            let mac = InternalCryptoSupport.hmac(.sha256, key: Data(secret.utf8), data: Data(input.utf8))
            return input + "." + mac.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let plain = "{\"alg\":\"HS256\"}"
        jwtOK(jwt("Verify", [token(plain, "{\"a\":1}"), secret, "--alg=HS256"]), "{\"a\":1}")
        jwtFails(jwt("Verify", [token("{\"alg\":\"HS256\",\"crit\":[\"exp\"]}", "{\"a\":1}"), secret, "--alg=HS256"]), 500, "authentication failed")
        for claim in ["\"exp\":\"100\"", "\"exp\":true", "\"exp\":null", "\"nbf\":\"1\"", "\"nbf\":[1]"] {
            jwtFails(jwt("Verify", [token(plain, "{\(claim)}"), secret, "--alg=HS256"]), 500, "authentication failed")
        }
        // exp・nbf が無ければ時刻は見ない。小数も使える。
        jwtOK(jwt("Verify", [token(plain, "{\"exp\":100.5}"), secret, "--alg=HS256", "--time=100"]), "{\"exp\":100.5}")
    }

    @Test
    func expirationAndNotBeforeUseTimeAndLeeway() {
        func token(_ payload: String) -> String { jwt("Sign", ["HS256", secret, payload]).result ?? "" }
        let both = token("{\"nbf\":1000,\"exp\":2000}")
        jwtOK(jwt("Verify", [both, secret, "--alg=HS256", "--time=1000"]), "{\"nbf\":1000,\"exp\":2000}")
        jwtOK(jwt("Verify", [both, secret, "--alg=HS256", "--time=1999"]), "{\"nbf\":1000,\"exp\":2000}")
        jwtFails(jwt("Verify", [both, secret, "--alg=HS256", "--time=2000"]), 500, "expired")
        jwtFails(jwt("Verify", [both, secret, "--alg=HS256", "--time=999"]), 500, "not yet valid")
        // 時計のずれの許容。
        jwtOK(jwt("Verify", [both, secret, "--alg=HS256", "--time=2009", "--leeway=10"]), "{\"nbf\":1000,\"exp\":2000}")
        jwtFails(jwt("Verify", [both, secret, "--alg=HS256", "--time=2010", "--leeway=10"]), 500, "expired")
        jwtOK(jwt("Verify", [both, secret, "--alg=HS256", "--time=990", "--leeway=10"]), "{\"nbf\":1000,\"exp\":2000}")
        jwtFails(jwt("Verify", [both, secret, "--alg=HS256", "--time=989", "--leeway=10"]), 500, "not yet valid")
        // 既定の現在時刻: 過去の exp は失効、遠い未来の exp は有効。
        jwtFails(jwt("Verify", [token("{\"exp\":1}"), secret, "--alg=HS256"]), 500, "expired")
        jwtOK(jwt("Verify", [token("{\"exp\":4102444800}"), secret, "--alg=HS256"]), "{\"exp\":4102444800}")
        jwtFails(jwt("Verify", [token("{\"nbf\":4102444800}"), secret, "--alg=HS256"]), 500, "not yet valid")
        // 署名が合わないトークンは、期限切れより先に authentication failed。
        jwtFails(jwt("Verify", [token("{\"exp\":1}"), String(repeating: "x", count: 32), "--alg=HS256"]), 500, "authentication failed")
        // 範囲外・数値でない leeway と、日時でない --time=。
        for leeway in ["-1", "86401", "x", ""] {
            jwtFails(jwt("Verify", [both, secret, "--alg=HS256", "--leeway=\(leeway)"]), 400, "invalid parameter")
        }
        #expect(jwt("Verify", [both, secret, "--alg=HS256", "--time=nonsense"]).status == 400)
    }

    @Test
    func publicKeyAlgorithmsRoundTrip() throws {
        for (jwtAlg, keyAlg) in [("ES256", "es256"), ("EdDSA", "ed25519")] {
            let response = try SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(
                requestText: "EXECUTE SAORI/1.0\r\nModule: internal_crypto\r\nArgument0: GenerateKeyPair\r\nArgument1: \(keyAlg)\r\n\r\n"))
            let privateKey = try #require(response.headerValue("Value0")), publicKey = try #require(response.headerValue("Value1"))
            let token = try #require(jwt("Sign", [jwtAlg, privateKey, "{\"sub\":\"桜\",\"exp\":4102444800}"]).result)
            #expect(token.split(separator: ".").count == 3)
            let signatureBytes = try InternalSaoriCodec.decodeBase64(String(token.split(separator: ".")[2]))
            #expect(signatureBytes.count == 64) // ES256 は r‖s の 64 バイト
            jwtOK(jwt("Verify", [token, publicKey, "--alg=\(jwtAlg)"]), "{\"sub\":\"桜\",\"exp\":4102444800}")
            jwtOK(jwt("Verify", [token, privateKey, "--alg=\(jwtAlg.lowercased())"]), "{\"sub\":\"桜\",\"exp\":4102444800}")
            // 別の鍵・書き換えは認証失敗。
            let other = try SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(
                requestText: "EXECUTE SAORI/1.0\r\nModule: internal_crypto\r\nArgument0: GenerateKeyPair\r\nArgument1: \(keyAlg)\r\n\r\n")).headerValue("Value1") ?? ""
            jwtFails(jwt("Verify", [token, other, "--alg=\(jwtAlg)"]), 500, "authentication failed")
            // --key-in= は HS* だけ。鍵が読めない・種類が違う。
            jwtFails(jwt("Sign", [jwtAlg, privateKey, "{}", "--key-in=base64"]), 400, "invalid parameter")
            jwtFails(jwt("Verify", [token, publicKey, "--alg=\(jwtAlg)", "--key-in=base64"]), 400, "invalid parameter")
            jwtFails(jwt("Sign", [jwtAlg, "AAAA", "{}"]), 400, "invalid key")
            jwtFails(jwt("Verify", [token, "AAAA", "--alg=\(jwtAlg)"]), 400, "invalid key")
        }
    }

    @Test
    func moduleIsListedWithItsFunctions() throws {
        let response = try SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(
            requestText: "EXECUTE SAORI/1.0\r\nModule: internal_system\r\nArgument0: ListFunctions\r\nArgument1: internal_jwt\r\n\r\n"))
        #expect(response.headerValue("Result") == "Sign,Verify")
        jwtFails(jwt("Decode", ["x"]), 400, "unknown function")
    }
}
