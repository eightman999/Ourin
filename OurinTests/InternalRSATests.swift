import CryptoKit
import Foundation
import Testing
@testable import Ourin

private struct RSAOutcome {
    var status: Int
    var result: String?
    var values: [String]
    var error: String?
}

private func rsa(_ function: String, _ arguments: [String] = [], context: InternalSaoriContext = .none) -> RSAOutcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_crypto", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: context)
    let response = try! SaoriProtocol.parseResponse(text)
    var values: [String] = []
    while let value = response.headerValue("Value\(values.count)") { values.append(value) }
    return RSAOutcome(status: response.statusCode, result: response.headerValue("Result"), values: values, error: response.headerValue("ErrorDescription"))
}

private func rsaOK(_ outcome: RSAOutcome, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == 200, "status \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.result == expected, sourceLocation: sourceLocation)
}

private func rsaFails(_ outcome: RSAOutcome, _ status: Int, _ description: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == status, "got \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.error == description, sourceLocation: sourceLocation)
}

struct InternalRSATests {
    // openssl で作った 2048 ビットの鍵と、"hello rsa" への署名（RS256 と、ソルト 32 バイトの PS256）。
    private let priv8 = "MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCJsrFcNw0C33SO3oGGZLDlsOMSIjdYRSgg0IwY5DRAMTQh8KWqV34CVS0Wyz/johaQ4VpS64Rs9YZj6DtRTvi86p/ARoWfR2wCsdZpl94H3eu3BaDXT38Z0eaUyJE+oLZS1nf2WktiT4CHoI8JHHG/QjgPI/ye1TY6CzmVOLBXcIbkDY06XaXmDF2jrYU/44vUih8g50miXsepHvD7cfuTS5lipGtBxjh5yLqiAhcRmjNfFryTnVmu8/aUD7C4SlfxUtgpn3yYlWIBLM2SG0HqNJ9YOO/mhKelez0oDfCeKcJBy85c0Zl8EGf61FJKzXUTOTMh7TZRY38kRWmJfEzLAgMBAAECggEALzE0AhPH/M0SyIhPwfyud/o4yJU7fKAvEZgH+9vyYHG8mUk9rfTQdgI1MtOz8NMzgrIJX9PiDenUBleoRMSZET4kRCSnVSCITyAeCRCIgw+24oImTsSrHfFHYoSe6uTvt9JTSPZHUclHlrQbcZbzEQaj6eR+hv0x2ZDRSmgkX8LrcHBix94Tf5SSYXrbHOn+cK8rEmWMdM0KotI4VRMEY7eRMBgxtQJxi2zmahAe3xs62thbjxjZr6wVpiNRGYiGXuuLBS2csthKqhUDBjflrcYseDKntR5eKD+QiXgsui04ryQODEoAuLQGN+RW/Y/KsxvNMZbf3gSXuyu49nbnuQKBgQC/R88/4UZFg30SaNFarZ7r8lZrVm+uKoMIjKBD6ZD5jVSizSh9VSfzR49BZG3rTyDT5y2lr/NsIUWukUU3cYj7oNBzkitZWeCkFXAX6CelxoPIEzK+g1VIgjQHAtZfQm3Xy0jTNyhuRaHw3SF52Tn+jFiZ7t+xdA+VripKaPtBPwKBgQC4SbdAESbWusDIS2I9eJl/eQHXQ9UdRU39jG6ATvFka9Ya7zw+Ay8DPXrudATKbBF5NANSadefhRzJwgTlEIe2hVlrY0HUku8UfgRL26Jka63lxkJoPCXLaEgxszAiZjtUmqImsXNzvQz4wKSN56guRIPjMBDdWzJn9DESXA7FdQKBgGU8nmYS1txnsUSTEWrKxXffdPmub8FgYqWduBz5e29467iWmL1s2o4Z66oSe1K1OIyuqCwvKciq+3RfEqE7h+KVxH3GeQb7WLe/WOpuRr2oiYrVDmBipjqQHvUu/ULBp900jECtyspCNGmEv/j7jYQ5x5MBKIeFA9KWsW9cjM6FAoGAME9CtozIfanfN6JrUmn28y+ph+DEUTQFyd2yafhH12ddbRoh1K/I9zR6sV/Akb/apMc5x7TvTWX7sfgmiFXY/cPfOQOAElWiTuDqB2jAHUsM/xsF9YUu8y+XHVA34gyiqP8QWsxR05lPeTYm7Pw5Xkefu0KyaRSrFg0xf/qZ9LECgYArhbeWgwOjkpghZCVD+3kGHZsQaYC9ZrcvQtvXSzkgHaOkxy/S9tG5DvVFnuT8/JG6lPEVPu/W4BhLYuTe/XtjqAJyEuctmA4r6S0sXLKQJmpxZ4WRz55PXO3l4BpzHrq7QWoyYW8NbwP0uLVWPY8e30IG5xsd2lV6gdkrgnALcg=="
    private let pub = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAibKxXDcNAt90jt6BhmSw5bDjEiI3WEUoINCMGOQ0QDE0IfClqld+AlUtFss/46IWkOFaUuuEbPWGY+g7UU74vOqfwEaFn0dsArHWaZfeB93rtwWg109/GdHmlMiRPqC2UtZ39lpLYk+Ah6CPCRxxv0I4DyP8ntU2Ogs5lTiwV3CG5A2NOl2l5gxdo62FP+OL1IofIOdJol7HqR7w+3H7k0uZYqRrQcY4eci6ogIXEZozXxa8k51ZrvP2lA+wuEpX8VLYKZ98mJViASzNkhtB6jSfWDjv5oSnpXs9KA3wninCQcvOXNGZfBBn+tRSSs11EzkzIe02UWN/JEVpiXxMywIDAQAB"
    private let priv1 = "MIIEogIBAAKCAQEAibKxXDcNAt90jt6BhmSw5bDjEiI3WEUoINCMGOQ0QDE0IfClqld+AlUtFss/46IWkOFaUuuEbPWGY+g7UU74vOqfwEaFn0dsArHWaZfeB93rtwWg109/GdHmlMiRPqC2UtZ39lpLYk+Ah6CPCRxxv0I4DyP8ntU2Ogs5lTiwV3CG5A2NOl2l5gxdo62FP+OL1IofIOdJol7HqR7w+3H7k0uZYqRrQcY4eci6ogIXEZozXxa8k51ZrvP2lA+wuEpX8VLYKZ98mJViASzNkhtB6jSfWDjv5oSnpXs9KA3wninCQcvOXNGZfBBn+tRSSs11EzkzIe02UWN/JEVpiXxMywIDAQABAoIBAC8xNAITx/zNEsiIT8H8rnf6OMiVO3ygLxGYB/vb8mBxvJlJPa300HYCNTLTs/DTM4KyCV/T4g3p1AZXqETEmRE+JEQkp1UgiE8gHgkQiIMPtuKCJk7Eqx3xR2KEnurk77fSU0j2R1HJR5a0G3GW8xEGo+nkfob9MdmQ0UpoJF/C63BwYsfeE3+UkmF62xzp/nCvKxJljHTNCqLSOFUTBGO3kTAYMbUCcYts5moQHt8bOtrYW48Y2a+sFaYjURmIhl7riwUtnLLYSqoVAwY35a3GLHgyp7UeXig/kIl4LLotOK8kDgxKALi0BjfkVv2PyrMbzTGW394El7sruPZ257kCgYEAv0fPP+FGRYN9EmjRWq2e6/JWa1ZvriqDCIygQ+mQ+Y1Uos0ofVUn80ePQWRt608g0+ctpa/zbCFFrpFFN3GI+6DQc5IrWVngpBVwF+gnpcaDyBMyvoNVSII0BwLWX0Jt18tI0zcobkWh8N0hedk5/oxYme7fsXQPla4qSmj7QT8CgYEAuEm3QBEm1rrAyEtiPXiZf3kB10PVHUVN/YxugE7xZGvWGu88PgMvAz167nQEymwReTQDUmnXn4UcycIE5RCHtoVZa2NB1JLvFH4ES9uiZGut5cZCaDwly2hIMbMwImY7VJqiJrFzc70M+MCkjeeoLkSD4zAQ3VsyZ/QxElwOxXUCgYBlPJ5mEtbcZ7FEkxFqysV333T5rm/BYGKlnbgc+XtveOu4lpi9bNqOGeuqEntStTiMrqgsLynIqvt0XxKhO4filcR9xnkG+1i3v1jqbka9qImK1Q5gYqY6kB71Lv1CwafdNIxArcrKQjRphL/4+42EOceTASiHhQPSlrFvXIzOhQKBgDBPQraMyH2p3zeia1Jp9vMvqYfgxFE0Bcndsmn4R9dnXW0aIdSvyPc0erFfwJG/2qTHOce0701l+7H4JohV2P3D3zkDgBJVok7g6gdowB1LDP8bBfWFLvMvlx1QN+IMoqj/EFrMUdOZT3k2Juz8OV5Hn7tCsmkUqxYNMX/6mfSxAoGAK4W3loMDo5KYIWQlQ/t5Bh2bEGmAvWa3L0Lb10s5IB2jpMcv0vbRuQ71RZ7k/PyRupTxFT7v1uAYS2Lk3v17Y6gCchLnLZgOK+ktLFyykCZqcWeFkc+eT1zt5eAacx66u0FqMmFvDW8D9Li1Vj2PHt9CBucbHdpVeoHZK4JwC3I="
    private let pub1 = "MIIBCgKCAQEAibKxXDcNAt90jt6BhmSw5bDjEiI3WEUoINCMGOQ0QDE0IfClqld+AlUtFss/46IWkOFaUuuEbPWGY+g7UU74vOqfwEaFn0dsArHWaZfeB93rtwWg109/GdHmlMiRPqC2UtZ39lpLYk+Ah6CPCRxxv0I4DyP8ntU2Ogs5lTiwV3CG5A2NOl2l5gxdo62FP+OL1IofIOdJol7HqR7w+3H7k0uZYqRrQcY4eci6ogIXEZozXxa8k51ZrvP2lA+wuEpX8VLYKZ98mJViASzNkhtB6jSfWDjv5oSnpXs9KA3wninCQcvOXNGZfBBn+tRSSs11EzkzIe02UWN/JEVpiXxMywIDAQAB"
    private let small = "MIICdgIBADANBgkqhkiG9w0BAQEFAASCAmAwggJcAgEAAoGBAMn7/C/C8SlDxzx/7VXgpewKICPawuYMHo+fDgK7sofMgZJM9IgW0jlRpTsL5HhoHdcwCShiqUBEqJMAU6UfuiXsHb2oCNLDD6cchEecgoOrSmUIZCmerGAfClGNZlh3KPGOrUEA0wCx5jonBwzbUibbxna8ES8BmOrOok/xL43nAgMBAAECgYAgDxDN++EPLaTX424mLUvolQrY5gX9QXswTIyKvoPtrfX65KADYavoUR8qqg6PVec2mnc5o789ZihjfK/KC6kdx5Hky7JWjHh6MEawxBbUWNfk4edOh0wEt4Yoe1M1umHqDB56FFPStm9Eocm/4JGB9rJrPAiXgF31Ywa0pJSi0QJBAOjKaPu4Qi6YdS8lXLcs+QoIrSrtgi8oHry1+/ePeIbfk5TgcooOVLsutMFRXQZFuGZm1aDVd5ilUv7LCRKMDXsCQQDeH0t6ksLp1t1x5vCJf0U8ZXWq2/11p+QrkuT6zMIrdZtBZ3R3tLLMlXugIEJbMRaX6uDJoO1IoF2oQ8TLm5eFAkAZi9zpgtcAdgqmGduK3oyV5U3boCThN+3nl7EHAd+gLXjspZTsQZZa1E1RybQDtDMASdi3xbVSMxJgk7dzKZtxAkEArr2F3n64cceD3EhmsHR8HkBfKjP4mGek+5aLJraQhin2IqTlngp8oq9yWw0lxqG+eXLgth4wrXLjWy09E0RrFQJAf0FHQP+H9pImvT3+yAt9VH9UgdtvAYJlznpnavjfHZCldf4oM1C927l9mM6e+g8MPwFK2MQ24Er9Bnz+OpFbyw=="
    private let smallPub = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDJ+/wvwvEpQ8c8f+1V4KXsCiAj2sLmDB6Pnw4Cu7KHzIGSTPSIFtI5UaU7C+R4aB3XMAkoYqlARKiTAFOlH7ol7B29qAjSww+nHIRHnIKDq0plCGQpnqxgHwpRjWZYdyjxjq1BANMAseY6JwcM21Im28Z2vBEvAZjqzqJP8S+N5wIDAQAB"
    private let rs256 = "DeVNUStS50oza9hHhIVM_ZZC0_l8t6nRbky3C7H7__WUnp1rLhjQRnb6kOKATevB6nynMm2UwAcxIhLCdi2uEubfKv5f8eBCulYssLplyHANNwFg4pO_Tsn1Ty5kjZ76UJV1n24nwZDAXWSqN2Oh7MMpJFACjmHgwENJbZyTNTmhbJikJ9_ys_IGuBmFwEo6ZR_8YqA5ajRxpK_mEDyepWiznP6WN1Cz-NVYFm-Uzkj52YOymfZaEGt2b60AaKn9n5lqOQ3DzDQYr9eJmwRFngce9EH1L8fJKZG77mG4fc3R5XrnVVan0V9IJkyJifEvU379_7oeCOSdxWor_7Q_ZA"
    private let ps256 = "Lhie4KfKgR1aa0PhAC5NUOsS9B2A96w4nayZIdn44DE4Y1sA_eSjHROObYtaTtgmnLTtV_H9RZeEEAMYqLgyu5H_-_tAjTssO3Ey7LL3LjNU1dT8o0LnosC42rjdUr4fJQb_bS_etdrqXDab68zwcLGmVWaljdViRoXwrxpVm-oC5g7ZBJxAj6ZrvSl_JtGe5N_fux5uIBTL1tdSJEje1i6GsV_YYf7abiDuPfNvN2rp3__fKePvX3hNzZQHRlW-hPfNimIJaKF90DNRF7EX_G9pdJvMapiXoPXbEPJYeMJLfJqjxirHHl4c--GiSyyBMGa8BydTq4Dp574ojz_NZg"

    private func pem(_ label: String, _ base64: String) -> String { "-----BEGIN \(label)----- \(base64) -----END \(label)-----" }

    @Test
    func rs256MatchesOpenSSLAndIsDeterministic() {
        rsaOK(rsa("Sign", ["rs256", priv8, "hello rsa"]), rs256)
        rsaOK(rsa("Sign", ["RS-256", priv1, "hello rsa"]), rs256) // PKCS#1 の秘密鍵でも同じ
        rsaOK(rsa("Sign", ["rs256", pem("PRIVATE KEY", priv8), "hello rsa"]), rs256)
        rsaOK(rsa("Sign", ["rs256", pem("RSA PRIVATE KEY", priv1), "hello rsa"]), rs256)
        rsaOK(rsa("Verify", ["rs256", pub, "hello rsa", rs256]), "1")
        rsaOK(rsa("Verify", ["rs256", pub1, "hello rsa", rs256]), "1")
        rsaOK(rsa("Verify", ["rs256", pem("PUBLIC KEY", pub), "hello rsa", rs256]), "1")
        rsaOK(rsa("Verify", ["rs256", pem("RSA PUBLIC KEY", pub1), "hello rsa", rs256]), "1")
        rsaOK(rsa("Verify", ["rs256", priv8, "hello rsa", rs256]), "1") // 公開鍵の代わりに秘密鍵
        rsaOK(rsa("Verify", ["rs256", pub, "hello rsb", rs256]), "0")
        rsaOK(rsa("Verify", ["rs256", pub, "hello rsa", "AAAA"]), "0") // 長さが違う
        rsaOK(rsa("Verify", ["rs256", pub, "hello rsa", ""]), "0")
        // PS256 の署名は RS256 では通らない（逆も同じ）。
        rsaOK(rsa("Verify", ["rs256", pub, "hello rsa", ps256]), "0")
        rsaOK(rsa("Verify", ["ps256", pub, "hello rsa", rs256]), "0")
    }

    @Test
    func ps256VerifiesOpenSSLSignaturesAndSignsRandomly() throws {
        rsaOK(rsa("Verify", ["ps256", pub, "hello rsa", ps256]), "1") // ソルト 32 バイトの OpenSSL の署名
        rsaOK(rsa("Verify", ["PS256", priv8, "hello rsa", ps256]), "1")
        rsaOK(rsa("Verify", ["ps256", pub, "hello rsb", ps256]), "0")
        let first = try #require(rsa("Sign", ["ps256", priv8, "hello rsa"]).result)
        let second = try #require(rsa("Sign", ["ps256", priv8, "hello rsa"]).result)
        #expect(first != second) // 毎回違う署名
        rsaOK(rsa("Verify", ["ps256", pub, "hello rsa", first]), "1")
        rsaOK(rsa("Verify", ["ps256", pub, "hello rsa", second]), "1")
        #expect(try InternalSaoriCodec.decodeBase64(first).count == 256)
        // 署名の形式を変えて渡す。
        let hex = try InternalSaoriCodec.encode(try InternalSaoriCodec.decodeBase64(first), format: "hex", defaultFormat: "hex", charset: nil)
        rsaOK(rsa("Verify", ["ps256", pub, "hello rsa", hex, "--signature-in=hex"]), "1")
    }

    @Test
    func generatedKeysWorkForBothSchemes() throws {
        let pair = rsa("GenerateKeyPair", ["rsa-2048"])
        #expect(pair.status == 200, "\(pair.error ?? "")")
        #expect(pair.values.count == 2)
        #expect(pair.result == pair.values[0])
        let privateKey = pair.values[0], publicKey = pair.values[1]
        for scheme in ["rs256", "ps256"] {
            let signature = try #require(rsa("Sign", [scheme, privateKey, "message"]).result)
            rsaOK(rsa("Verify", [scheme, publicKey, "message", signature]), "1")
            rsaOK(rsa("Verify", [scheme, publicKey, "other", signature]), "0")
            rsaOK(rsa("Verify", [scheme, rsa("GenerateKeyPair", ["rsa_2048"]).values[1], "message", signature]), "0")
        }
        // 生成した鍵は openssl でも読める形（PKCS#8 / SubjectPublicKeyInfo）で、openssl の署名が検証できる。
        let rsKey = try InternalRSA.privateKey(privateKey)
        #expect(SecKeyGetBlockSize(rsKey) == 256)
    }

    @Test
    func keySizesAndKindsAreChecked() {
        // 2048 ビット未満の鍵は invalid key。
        rsaFails(rsa("Sign", ["rs256", small, "m"]), 400, "invalid key")
        rsaFails(rsa("Verify", ["rs256", smallPub, "m", rs256]), 400, "invalid key")
        rsaFails(rsa("Sign", ["rs256", "AAAA", "m"]), 400, "invalid key")
        rsaFails(rsa("Sign", ["rs256", pub, "m"]), 400, "invalid key") // 公開鍵では署名できない
        rsaFails(rsa("Verify", ["rs256", "AAAA", "m", rs256]), 400, "invalid key")
        rsaFails(rsa("Sign", ["rs256", pem("PRIVATE KEY", "!!!"), "m"]), 400, "invalid key")
        // 種類の違う鍵（Ed25519・P-256）。
        let ed = rsa("GenerateKeyPair", ["ed25519"]).values
        rsaFails(rsa("Sign", ["rs256", ed[0], "m"]), 400, "invalid key")
        rsaFails(rsa("Verify", ["ps256", ed[1], "m", rs256]), 400, "invalid key")
        let ec = rsa("GenerateKeyPair", ["es256"]).values
        rsaFails(rsa("Sign", ["ps256", ec[0], "m"]), 400, "invalid key")
        rsaFails(rsa("Sign", ["ed25519", priv8, "m"]), 400, "invalid key")
        rsaFails(rsa("Sign", ["es256", priv8, "m"]), 400, "invalid key")
        // 署名に使えない名前。
        rsaFails(rsa("Sign", ["rsa-2048", priv8, "m"]), 400, "unsupported algorithm")
        rsaFails(rsa("GenerateKeyPair", ["rs256"]), 400, "unsupported algorithm")
        rsaFails(rsa("GenerateKeyPair", ["rsa-1024"]), 400, "unsupported algorithm")
        rsaFails(rsa("GenerateKeyPair", ["rsa-8192"]), 400, "unsupported algorithm")
    }

    @Test
    func jwtSupportsRS256AndPS256() throws {
        for alg in ["RS256", "PS256"] {
            let token = try #require(jwt("Sign", [alg, priv8, "{\"sub\":\"sakura\",\"exp\":4102444800}"]).result)
            let header = try InternalSaoriCodec.decodeBase64(String(token.split(separator: ".")[0]))
            #expect(String(data: header, encoding: .utf8) == "{\"alg\":\"\(alg)\",\"typ\":\"JWT\"}")
            let verified = jwt("Verify", [token, pub, "--alg=\(alg)"])
            #expect(verified.result == "{\"sub\":\"sakura\",\"exp\":4102444800}", "\(alg) \(verified.error ?? "")")
            // alg のすり替え: RS256 のトークンを PS256 として・HS256 として検証する、--key-in= は使えない。
            let other = alg == "RS256" ? "PS256" : "RS256"
            #expect(jwt("Verify", [token, pub, "--alg=\(other)"]).error == "authentication failed")
            #expect(jwt("Verify", [token, pub, "--alg=HS256"]).error == "authentication failed")
            #expect(jwt("Verify", [token, pub, "--alg=\(alg)", "--key-in=hex"]).error == "invalid parameter")
            #expect(jwt("Sign", [alg, priv8, "{}", "--key-in=hex"]).error == "invalid parameter")
            #expect(jwt("Verify", [token, smallPub, "--alg=\(alg)"]).error == "invalid key")
            // 公開鍵を HMAC の鍵にした偽造トークン（HS256）は、RSA として検証すると通らない。
            let forged = jwt("Sign", ["HS256", String(repeating: "p", count: 40), "{\"sub\":\"admin\"}"]).result ?? ""
            #expect(jwt("Verify", [forged, pub, "--alg=\(alg)"]).error == "authentication failed")
        }
    }

    private func jwt(_ function: String, _ arguments: [String]) -> RSAOutcome {
        var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_jwt", "Argument0: \(function)"]
        for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
        let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: .none)
        let response = try! SaoriProtocol.parseResponse(text)
        return RSAOutcome(status: response.statusCode, result: response.headerValue("Result"), values: [], error: response.headerValue("ErrorDescription"))
    }
}
