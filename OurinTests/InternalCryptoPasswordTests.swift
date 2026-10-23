import CommonCrypto
import Foundation
import Testing
@testable import Ourin

private struct PasswordOutcome {
    var status: Int
    var result: String?
    var error: String?
}

private func pwCall(_ function: String, _ arguments: [String] = []) -> PasswordOutcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_crypto", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let text = InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: .none)
    let response = try! SaoriProtocol.parseResponse(text)
    return PasswordOutcome(status: response.statusCode, result: response.headerValue("Result"), error: response.headerValue("ErrorDescription"))
}

private func pwOk(_ outcome: PasswordOutcome, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == 200, "status \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.result == expected, "result \(outcome.result ?? "nil")", sourceLocation: sourceLocation)
}

private func pwFails(_ outcome: PasswordOutcome, _ status: Int, _ description: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == status, "got \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.error == description, sourceLocation: sourceLocation)
}

/// 正しいパスワードで 1、少し変えたパスワードで 0。
private func pwVerifies(_ password: String, _ hash: String, sourceLocation: SourceLocation = #_sourceLocation) {
    pwOk(pwCall("VerifyPassword", [password, hash]), "1", sourceLocation: sourceLocation)
    pwOk(pwCall("VerifyPassword", [password + "x", hash]), "0", sourceLocation: sourceLocation)
}

private func matches(_ text: String?, _ pattern: String) -> Bool {
    text?.range(of: "^" + pattern + "$", options: .regularExpression) != nil
}

private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

// MARK: - scrypt（純関数）

struct InternalScryptTests {
    @Test
    func matchesRFC7914Vectors() throws {
        #expect(hex(try InternalScrypt.derive(password: Data(), salt: Data(), n: 16, r: 1, p: 1, length: 64))
                == "77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906")
        #expect(hex(try InternalScrypt.derive(password: Data("password".utf8), salt: Data("NaCl".utf8), n: 1024, r: 8, p: 16, length: 64))
                == "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640")
    }

    @Test
    func rejectsParametersOutsideTheRange() {
        let password = Data("p".utf8), salt = Data("s".utf8)
        // RFC 7914 の 3 つ目（N=16384, r=8 は 16MiB）は 12MiB の上限を超える。
        #expect(throws: InternalSaoriError.outOfRange) {
            try InternalScrypt.derive(password: password, salt: salt, n: 16384, r: 8, p: 1, length: 64)
        }
        #expect(throws: InternalSaoriError.outOfRange) { try InternalScrypt.derive(password: password, salt: salt, n: 16, r: 1, p: 17, length: 8) }
        #expect(throws: InternalSaoriError.outOfRange) { try InternalScrypt.derive(password: password, salt: salt, n: 16, r: 1, p: 0, length: 8) }
        #expect(throws: InternalSaoriError.outOfRange) { try InternalScrypt.derive(password: password, salt: salt, n: 16, r: 0, p: 1, length: 8) }
        #expect(throws: InternalSaoriError.outOfRange) { try InternalScrypt.derive(password: password, salt: salt, n: 16, r: 1, p: 1, length: 0) }
        #expect(throws: InternalSaoriError.outOfRange) { try InternalScrypt.derive(password: password, salt: salt, n: 16, r: 1, p: 1, length: 1025) }
        #expect(throws: InternalSaoriError.outOfRange) { try InternalScrypt.derive(password: password, salt: salt, n: 1, r: 1, p: 1, length: 8) }
        #expect(throws: InternalSaoriError.invalidParameter) { try InternalScrypt.derive(password: password, salt: salt, n: 24, r: 1, p: 1, length: 8) }
        // ちょうど 12MiB（N=12288 は 2 の累乗でない / N=8192, r=12 = 12MiB）は通る。
        #expect((try? InternalScrypt.derive(password: password, salt: salt, n: 8192, r: 12, p: 1, length: 8))?.count == 8)
    }
}

// MARK: - DES

struct InternalDESTests {
    @Test
    func coreMatchesFIPSExampleAndCommonCrypto() {
        // 定番の例（key 133457799BBCDFF1, plain 0123456789ABCDEF）。
        #expect(InternalDES.encrypt(block: 0x0123_4567_89AB_CDEF, key: 0x1334_5779_9BBC_DFF1) == 0x85E8_1354_0F0A_B405)

        var generator = SystemRandomNumberGenerator()
        for _ in 0..<64 {
            let key = UInt64.random(in: 0...UInt64.max, using: &generator)
            let block = UInt64.random(in: 0...UInt64.max, using: &generator)
            var keyBytes = (0..<8).map { UInt8(truncatingIfNeeded: key >> UInt64(56 - 8 * $0)) }
            var blockBytes = (0..<8).map { UInt8(truncatingIfNeeded: block >> UInt64(56 - 8 * $0)) }
            var output = [UInt8](repeating: 0, count: 8)
            var written = 0
            let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmDES), CCOptions(kCCOptionECBMode),
                                 &keyBytes, 8, nil, &blockBytes, 8, &output, 8, &written)
            #expect(status == kCCSuccess)
            let expected = output.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            #expect(InternalDES.encrypt(block: block, key: key) == expected, "key \(key) block \(block)")
        }
    }

    // perl の crypt()（libc）と htpasswd -d で作ったもの。
    private static let vectors: [(password: String, hash: String)] = [
        ("", "abmF1QH4PEr.E"),
        ("", "xyw1.V0rbu5mQ"),
        ("password", "abJnggxhB/yWI"),
        ("password", "..UZoIyj/Hy/c"),
        ("password", "//TIk/siaNpyQ"),
        ("password", "ZziFATVXHo2.6"),
        ("pässwörd日本", "xyn1r77gvFX.M"),
        ("pässwörd日本", "abzp3RXJm5gNA"),
        // 8 文字を超える分は使われない。
        ("abcdefgh", "r5cYTC7sQ5Jgs"),
        ("abcdefghijkl", "r5cYTC7sQ5Jgs"),
    ]

    @Test
    func desCryptMatchesLibc() {
        for (password, hash) in Self.vectors { pwOk(pwCall("VerifyPassword", [password, hash]), "1") }
        pwOk(pwCall("VerifyPassword", ["passwore", "abJnggxhB/yWI"]), "0")
        // 9 文字目以降が違っても同じ（パスワードが長くても切り捨てるだけで、エラーにはならない）。
        pwOk(pwCall("VerifyPassword", ["abcdefghZZZ", "r5cYTC7sQ5Jgs"]), "1")
        pwOk(pwCall("VerifyPassword", ["abcdefgX", "r5cYTC7sQ5Jgs"]), "0")
    }

    // perl の crypt() で作った拡張 DES。"_J9.." の回数は 725、"_7C/." は 5001。
    private static let bsdiVectors: [(password: String, hash: String)] = [
        ("", "_J9..abcdoj0PMidvoVc"),
        ("password", "_J9..abcdIPPmXD22F8s"),
        ("pässwörd日本", "_J9..abcdP8RoUB28Qwc"),
        ("abcdefghijkl", "_J9..abcdUgKrUa.Zy3M"),
        ("password", "_7C/.abcdpsRgFoP9Jr2"),
        ("password", "_7C/.wxyzGP7JuHQr/3c"),
        ("abcdefghijkl", "_7C/.abcd1HbSGhkbJKc"),
        ("pässwörd日本", "_7C/.abcdccFDcglt33Y"),
        // 8 文字・9 文字・16 文字・17 文字の境目（鍵を 8 バイトずつ混ぜる）。
        (String(repeating: "a", count: 8), "_J9..abcdbYYUNpaCFAY"),
        (String(repeating: "a", count: 9), "_J9..abcd/3wpSCNuHO2"),
        (String(repeating: "a", count: 16), "_J9..abcdY4QJF9CJMu."),
        (String(repeating: "a", count: 17), "_J9..abcdWEuDaLL5v5."),
        (String(repeating: "a", count: 20), "_J9..abcd9c6BmGoOkU2"),
    ]

    @Test
    func bsdiCryptMatchesLibc() {
        for (password, hash) in Self.bsdiVectors { pwOk(pwCall("VerifyPassword", [password, hash]), "1") }
        pwOk(pwCall("VerifyPassword", ["passwore", "_J9..abcdIPPmXD22F8s"]), "0")
    }
}

// MARK: - MD5-crypt / apr1 / SHA-crypt

struct InternalUnixCryptTests {
    // openssl passwd と htpasswd で作ったもの。
    @Test
    func md5CryptAndApr1() {
        pwVerifies("", "$1$abcdefgh$M55TzYaaccxVGbptZWaxX/")
        pwVerifies("password", "$1$abcdefgh$G//4keteveJp0qb8z2DxG/")
        pwVerifies("pässwörd日本", "$1$abcdefgh$FSGm5abKv7m3Zc44E.gkg/")
        pwVerifies(String(repeating: "x", count: 40), "$1$$G53W039fA8pYNjBkvdsfQ.")
        pwVerifies("pässwörd日本", "$1$a$0hulaQSLyUvTBBdl8vJzJ0")
        pwVerifies("", "$apr1$abcdefgh$L.PT565ESX4Tp2bqNs7Ie.")
        pwVerifies("password", "$apr1$abcdefgh$FBwExRW4dCc8aL.OvjpIE1")
        pwVerifies("password", "$apr1$juD5oDzq$tVLLQm9dUaEFRI3xRZRgN/")
        pwVerifies(String(repeating: "x", count: 17), "$apr1$Zz$6aXzUrW.OqVm.7Lyl1lP21")
        // 8 文字より長いソルトは不正。ハッシュの長さが違うのも不正。
        pwFails(pwCall("VerifyPassword", ["password", "$1$abcdefghi$G//4keteveJp0qb8z2DxG/"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$1$abcdefgh$G//4keteveJp0qb8z2Dx"]), 400, "invalid parameter")
    }

    @Test
    func shaCryptMatchesDrepperVectors() {
        let sha256: [(String, String, String)] = [
            ("Hello world!", "$5$saltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc5", ""),
            ("Hello world!", "$5$rounds=10000$saltstringsaltst$3xv.VbSHBb41AL9AvLeujZkZRBAwqFMz2.opqey6IcA", ""),
            ("we have a short salt string but not a short password", "$5$rounds=77777$short$JiO1O3ZpDAxGJeaDIuqCoEFysAe1mZNJRs3pw0KQRd/", ""),
            ("a short string", "$5$rounds=123456$asaltof16chars..$gP3VQ/6X7UUEW3HkBn2w1/Ptq2jxPyzV/cZKmF/wJvD", ""),
            ("the minimum number is still observed", "$5$rounds=1000$roundstoolow$yfvwcWrQ8l/K0DAWyuPMDNHpIVlTQebY9l/gL972bIC", ""),
            ("password", "$5$saltsaltsaltsalt$WsFBeg1qQ90JL3VkUTuM7xVV/5njhLngIVm6ftSnBR2", ""),
            ("pässwörd日本", "$5$saltsaltsaltsalt$AaDysu0W6INPoitko5tAzv6UUuFBbhIec22WHeP7w31", ""),
            ("pässwörd日本", "$5$rounds=2000$saltsalt$i4J7zIqeUSxlAiRoMg2fVbcUC.q45TYlX2wCCt49mF0", ""),
            (String(repeating: "x", count: 33), "$5$rounds=1000$ab$JCooSwNM4idbaUAUPwI.eL4i/cyFWzXvlA52dn0EJr7", ""),
        ]
        for (password, hash, _) in sha256 { pwOk(pwCall("VerifyPassword", [password, hash]), "1") }
        let sha512: [(String, String)] = [
            ("Hello world!", "$6$saltstring$svn8UoSVapNtMuq1ukKS4tPQd8iKwSMHWjl/O817G3uBnIFNjnQJuesI68u4OTLiBFdcbYEdFCoEOfaS35inz1"),
            ("Hello world!", "$6$rounds=10000$saltstringsaltst$OW1/O6BYHV6BcXZu8QVeXbDWra3Oeqh0sbHbbMCVNSnCM/UrjmM0Dp8vOuZeHBy/YTBmSK6H9qs/y3RnOaw5v."),
            ("This is just a test", "$6$rounds=5000$toolongsaltstrin$lQ8jolhgVRVhY4b5pZKaysCLi0QBxGoNeKQzQ3glMhwllF7oGDZxUhx1yxdYcz/e1JSbq3y6JMxxl8audkUEm0"),
            ("a very much longer text to encrypt.  This one even stretches over morethan one line.",
             "$6$rounds=1400$anotherlongsalts$POfYwTEok97VWcjxIiSOjiykti.o/pQs.wPvMxQ6Fm7I6IoYN3CmLs66x9t0oSwbtEW7o7UmJEiDwGqd8p4ur1"),
            ("we have a short salt string but not a short password",
             "$6$rounds=77777$short$WuQyW2YR.hBNpjjRhpYD/ifIw05xdfeEyQoMxIXbkvr0gge1a1x3yRULJ5CCaUeOxFmtlcGZelFl5CxtgfiAc0"),
            ("a short string", "$6$rounds=123456$asaltof16chars..$BtCwjqMJGx5hrJhZywWvt0RLE8uZ4oPwcelCjmw2kSYu.Ec6ycULevoBK25fs2xXgMNrCzIMVcgEJAstJeonj1"),
            ("the minimum number is still observed",
             "$6$rounds=1000$roundstoolow$kUMsbe306n21p9R.FRkW3IGn.S9NPN0x50YhH1xhLsPuWGsUSklZt58jaTfF4ZEQpyUNGc0dqbpBYYBaHHrsX."),
            ("password", "$6$saltsaltsaltsalt$bcXJ8qxwY5sQ4v8MTl.0B1jeZ0z0JlA9jjmbUoCJZ.1wYXiLTU.q2ILyrDJLm890lyfuF7sWAeli0yjOyFPkf0"),
            ("pässwörd日本", "$6$saltsaltsaltsalt$mkGCepmO8e8KX2VgHfscswntQR9nfo7rbv3UHbEhnAS/8AFkDmsSKlFHt6qz/StuuaP3Cj7Lz4Rdjc19t./Bb1"),
            ("password", "$6$rounds=1000$saltsalt$Z/J9iYO1iE9xnr8JPQL57ZWsVRtVjrUv3CiWc/wKWseqXgSqn3HFYJ/Ng7YXa8XlLj.wpdAwHOJJzuGFqBBRa0"),
            (String(repeating: "x", count: 130), "$6$rounds=1000$ab$166./bH5A/EXX4smjIrTAQJJFl0BGROGsDnt4PG8n/pfI8/IVlNOQUorQpey3w9E06iweqwApSrdkRFy4UlNu."),
        ]
        for (password, hash) in sha512 { pwOk(pwCall("VerifyPassword", [password, hash]), "1") }
        pwOk(pwCall("VerifyPassword", ["Hello world?", sha512[0].1]), "0")
        pwOk(pwCall("VerifyPassword", ["Hello world?", sha256[0].1]), "0")
    }

    @Test
    func shaCryptRoundsHandling() {
        // rounds= が 1000 未満なら 1000 に切り上げる（openssl で rounds=100 と書いたものが rounds=1000 になる）。
        pwOk(pwCall("VerifyPassword", ["pw", "$5$rounds=100$saltsalt$eNI.02a9Kos9UxzxjTLpNZ6kYHkRe9Z8OsGkDDoW/X2"]), "1")
        pwOk(pwCall("VerifyPassword", ["pw", "$5$rounds=1000$saltsalt$eNI.02a9Kos9UxzxjTLpNZ6kYHkRe9Z8OsGkDDoW/X2"]), "1")
        let hash = "$5$saltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc5"
        pwFails(pwCall("VerifyPassword", ["Hello world!", "$5$rounds=10000001$saltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc5"]),
                400, "out of range")
        pwFails(pwCall("VerifyPassword", ["Hello world!", "$5$rounds=99999999999999999999$saltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc5"]),
                400, "out of range")
        pwFails(pwCall("VerifyPassword", ["Hello world!", "$5$rounds=abc$saltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc5"]),
                400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["Hello world!", "$5$saltstringsaltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc5"]),
                400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["Hello world!", "$5$saltstring$5B8vYYiY.CVt1RlTTf8KbXBH3hsxY/GNooZaBBGWEc"]), 400, "invalid parameter")
        pwOk(pwCall("VerifyPassword", ["Hello world!", hash]), "1")
    }
}

// MARK: - bcrypt

struct InternalBcryptTests {
    @Test
    func matchesReferenceVectors() {
        // crypt_blowfish の試験データ。
        pwVerifies("U*U", "$2a$05$CCCCCCCCCCCCCCCCCCCCC.E5YPO9kmyuRGyh0XouQYb4YMJKvyOeW")
        pwVerifies("U*U*", "$2a$05$CCCCCCCCCCCCCCCCCCCCC.VGOzA784oUp/Z0DY336zx7pLYAy0lwK")
        pwVerifies("U*U*U", "$2a$05$XXXXXXXXXXXXXXXXXXXXXOAcXxm9kjPGEMsLznoKqmqw7tc8WCx4a")
        pwVerifies("", "$2a$05$CCCCCCCCCCCCCCCCCCCCC.7uG0VCzI2bS7j6ymqJi9CdcdxiRTWNy")
        // 72 バイトより後ろは使われない。
        let long = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789chars after 72 are ignored"
        pwOk(pwCall("VerifyPassword", [long, "$2a$05$abcdefghijklmnopqrstuu5s2v8.iXieOjg/.AySBTTZIIVFJeBui"]), "1")
        pwOk(pwCall("VerifyPassword", [String(long.prefix(72)), "$2a$05$abcdefghijklmnopqrstuu5s2v8.iXieOjg/.AySBTTZIIVFJeBui"]), "1")
        pwOk(pwCall("VerifyPassword", [String(long.prefix(71)), "$2a$05$abcdefghijklmnopqrstuu5s2v8.iXieOjg/.AySBTTZIIVFJeBui"]), "0")
    }

    @Test
    func matchesHtpasswd() {
        // htpasswd -nbB -C 5（$2y$）。
        pwVerifies("", "$2y$05$lyHuhlUdihs6DF2ukva.HuZaqxKEgKYBM6lqGnFcF3953.ndEzNCq")
        pwVerifies("password", "$2y$05$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK")
        pwVerifies("pässwörd日本", "$2y$05$CKGtZZ/1C.48AhZ/NcRKteTLtQ5Nr4B/KS.bPphOCoAiqEgU2sXgG")
        pwOk(pwCall("VerifyPassword", [String(repeating: "a", count: 80), "$2y$05$yuLEzuH5q4sq8GFuY6RN/eJL.OjFpQ0JvdbJtc43IjAicGFwypzse"]), "1")
        pwOk(pwCall("VerifyPassword", [String(repeating: "a", count: 72), "$2y$05$yuLEzuH5q4sq8GFuY6RN/eJL.OjFpQ0JvdbJtc43IjAicGFwypzse"]), "1")
        // $2a$ $2b$ $2y$ は同じ扱い。
        for prefix in ["$2a$", "$2b$"] {
            pwOk(pwCall("VerifyPassword", ["password", prefix + "05$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK"]), "1")
        }
    }

    @Test
    func rejectsBadStrings() {
        let tail = "05$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK"
        pwFails(pwCall("VerifyPassword", ["password", "$2x$" + tail]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["password", "$2$" + tail]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["password", "$2b$17$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["password", "$2b$03$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["password", "$2b$5$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$2b$05$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdKa"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$2b$05$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRd!"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$2b$ab$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK"]), 400, "invalid parameter")
    }
}

// MARK: - PHC（scrypt・pbkdf2・argon2id）

struct InternalPHCTests {
    @Test
    func scryptStrings() {
        // python の hashlib.scrypt で作ったもの。
        pwVerifies("password", "$scrypt$ln=4,r=8,p=1$c2FsdHNhbHQ$xdm4IMyPApeWQ+5AiPVw2L3OCnA4OBnnwWGIV2OM5+o")
        pwVerifies("", "$scrypt$ln=4,r=1,p=2$$fgzgItQWEECDYdSHpJYtCw")
        pwVerifies("pässwörd日本", "$scrypt$ln=10,r=8,p=2$MDEyMzQ1Njc4OWFiY2RlZg$PSu6CHdFvMpjzdDmyD018Cl9XS1gKlUmJrjb8BKxTGo")
        // メモリが 12MiB を超えるもの（ln=14, r=8 は 16MiB）、p が範囲外のもの。
        pwFails(pwCall("VerifyPassword", ["password", "$scrypt$ln=14,r=8,p=1$c2FsdHNhbHQ$xdm4IMyPApeWQ+5AiPVw2L3OCnA4OBnnwWGIV2OM5+o"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["password", "$scrypt$ln=4,r=8,p=17$c2FsdHNhbHQ$xdm4IMyPApeWQ+5AiPVw2L3OCnA4OBnnwWGIV2OM5+o"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["password", "$scrypt$ln=4,r=8$c2FsdHNhbHQ$xdm4IMyPApeWQ+5AiPVw2L3OCnA4OBnnwWGIV2OM5+o"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$scrypt$ln=4,r=8,p=1,x=1$c2FsdHNhbHQ$xdm4IMyPApeWQ+5AiPVw2L3OCnA4OBnnwWGIV2OM5+o"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$scrypt$ln=4,r=8,p=1$c2FsdHNhbHQ=$xdm4IMyPApeWQ+5AiPVw2L3OCnA4OBnnwWGIV2OM5+o"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$scrypt$ln=4,r=8,p=1$c2FsdHNhbHQ"]), 400, "invalid parameter")
    }

    @Test
    func pbkdf2Strings() {
        // python の hashlib.pbkdf2_hmac で作ったもの。
        pwVerifies("password", "$pbkdf2-sha1$i=1000,l=20$MDEyMzQ1Njc4OWFiY2RlZg$DYW+LTZG5wxyiF/qvsh40/+/hXk")
        pwVerifies("password", "$pbkdf2-sha256$i=1000,l=32$MDEyMzQ1Njc4OWFiY2RlZg$hRRjgXWkW8ResfIvBP99J/T4vkgEmMRV/0tJTOjR59I")
        pwVerifies("password", "$pbkdf2-sha512$i=1000,l=64$MDEyMzQ1Njc4OWFiY2RlZg$38DzhdBT7fPaUGBlsh42VTuuKSFAIYGZJ7l6feCDLIl+K3hdPFgxxu7xuUi4gIuH6cEIoODn18xH9Ig2ryNgUw")
        // RFC 6070（l= の無いもの）と、空のパスワード・空のソルト。
        pwVerifies("password", "$pbkdf2-sha1$i=4096$c2FsdA$SwB5AbdlSJq+rUnZJvch0GWkKcE")
        pwVerifies("", "$pbkdf2-sha256$i=1,l=32$$984LZT0tcqQQjPWr6RL/3Xd2Ftu7J6cOggTzri0Pb60")
        // 反復回数の範囲外、l= と合わないもの、知らない方式。
        pwFails(pwCall("VerifyPassword", ["password", "$pbkdf2-sha1$i=0$c2FsdA$SwB5AbdlSJq+rUnZJvch0GWkKcE"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["password", "$pbkdf2-sha1$i=10000001$c2FsdA$SwB5AbdlSJq+rUnZJvch0GWkKcE"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["password", "$pbkdf2-sha1$i=4096,l=32$c2FsdA$SwB5AbdlSJq+rUnZJvch0GWkKcE"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$pbkdf2-sha1$l=20$c2FsdA$SwB5AbdlSJq+rUnZJvch0GWkKcE"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["password", "$pbkdf2-md5$i=1$c2FsdA$SwB5AbdlSJq+rUnZJvch0GWkKcE"]), 400, "unsupported algorithm")
    }

    // Argon2id 本体はまだ無い（InternalArgon2 は unsupported algorithm）。文字列の読み取りと範囲の検査は、その手前で行う。
    @Test
    func argon2idStringsAreCheckedBeforeDerivation() {
        let salt = "c29tZXNhbHRzYWx0", hash = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=65536,t=3,p=4$\(salt)$\(hash)"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=12288,t=0,p=1$\(salt)$\(hash)"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=12288,t=3,p=17$\(salt)$\(hash)"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=7,t=3,p=1$\(salt)$\(hash)"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=12288,t=3,p=1$c2hvcnQ$\(hash)"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=12288,t=3,p=1$\(salt)$AAA"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=18$m=12288,t=3,p=1$\(salt)$\(hash)"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=12288,t=3$\(salt)$\(hash)"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=12288,t=3,p=1,keyid=AA$\(salt)$\(hash)"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2id$v=19$m=12288,t=3,p=1$\(salt)"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2i$v=19$m=12288,t=3,p=1$\(salt)$\(hash)"]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["p", "$argon2d$v=19$m=12288,t=3,p=1$\(salt)$\(hash)"]), 400, "unsupported algorithm")
    }
}

// MARK: - 形の誤り・入力の検査

struct InternalPasswordInputTests {
    @Test
    func malformedHashStrings() {
        pwFails(pwCall("VerifyPassword", ["p", ""]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "$"]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["p", "$$"]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["p", "$7$whatever$hash"]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["p", "$sha1$whatever$hash"]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["p", "*0"]), 400, "unsupported algorithm")
        pwFails(pwCall("VerifyPassword", ["p", "short"]), 400, "unsupported algorithm")
        // 13 文字でも、DES の文字でなければ不正。
        pwFails(pwCall("VerifyPassword", ["p", "abJnggxhB/yW!"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "_J9..abcd"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "_J9..abcdIPPmXD22F8!"]), 400, "invalid parameter")
        pwFails(pwCall("VerifyPassword", ["p", "_J9..abcdIPPmXD22F8sX"]), 400, "invalid parameter")
        // 反復回数 0 は範囲外。
        pwFails(pwCall("VerifyPassword", ["p", "_....abcdIPPmXD22F8s"]), 400, "out of range")
        pwFails(pwCall("VerifyPassword", ["p"]), 400, "invalid parameter")
    }

    @Test
    func passwordRestrictionsForCryptFormats() {
        let formats = [
            "$2b$05$rYGTqoYINxIMiRgfRx56Oe0WmAhVLUVmVHB5YSuwnEFGEHbUcvRdK",
            "$6$saltsaltsaltsalt$bcXJ8qxwY5sQ4v8MTl.0B1jeZ0z0JlA9jjmbUoCJZ.1wYXiLTU.q2ILyrDJLm890lyfuF7sWAeli0yjOyFPkf0",
            "$5$saltsaltsaltsalt$WsFBeg1qQ90JL3VkUTuM7xVV/5njhLngIVm6ftSnBR2",
            "$1$abcdefgh$G//4keteveJp0qb8z2DxG/",
            "$apr1$abcdefgh$FBwExRW4dCc8aL.OvjpIE1",
            "_J9..abcdIPPmXD22F8s",
            "abJnggxhB/yWI",
        ]
        for hash in formats {
            // NUL を含むと invalid parameter。1024 バイトちょうどは通り、1025 バイトは out of range。
            pwFails(pwCall("VerifyPassword", ["6100", hash, "--password-in=hex"]), 400, "invalid parameter")
            pwFails(pwCall("VerifyPassword", [String(repeating: "a", count: 1025), hash]), 400, "out of range")
            if !hash.hasPrefix("$2b$") && !hash.hasPrefix("$6$") && !hash.hasPrefix("$5$") {
                #expect(pwCall("VerifyPassword", [String(repeating: "a", count: 1024), hash]).status == 200)
            }
        }
        // 文字コード指定（Shift_JIS のバイト列で照合する）。
        pwOk(pwCall("VerifyPassword", ["日本", "$1$abcdefgh$G//4keteveJp0qb8z2DxG/", "--charset=Shift_JIS"]), "0")
        pwFails(pwCall("VerifyPassword", ["pässwörd", "$1$abcdefgh$G//4keteveJp0qb8z2DxG/", "--charset=Shift_JIS"]), 400, "invalid encoding")
        pwFails(pwCall("HashPassword", ["6100", "--method=des-crypt", "--password-in=hex"]), 400, "invalid parameter")
        pwFails(pwCall("HashPassword", [String(repeating: "a", count: 1025), "--method=md5-crypt"]), 400, "out of range")
        pwFails(pwCall("HashPassword", ["p", "--method=nothing"]), 400, "unsupported algorithm")
        pwFails(pwCall("HashPassword", ["p", "--method=sha1-crypt"]), 400, "unsupported algorithm")
        pwFails(pwCall("HashPassword", ["p", "--unknown=1"]), 400, "invalid parameter")
    }

    @Test
    func listFunctionsIncludesPasswordFunctions() {
        let outcome = try! SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(
            requestText: "EXECUTE SAORI/1.0\r\nModule: internal_system\r\nArgument0: ListFunctions\r\nArgument1: internal_crypto\r\n\r\n"))
        let names = (outcome.headerValue("Result") ?? "").split(separator: ",").map(String.init)
        #expect(names.contains("HashPassword") && names.contains("VerifyPassword"))
    }
}

// MARK: - HashPassword → VerifyPassword

struct InternalPasswordRoundTripTests {
    /// `heavy` は計算の重い方式（デバッグビルドでは数秒かかる）。作って照合するのを 1 回ずつにする。
    private func roundTrip(_ method: String?, shape: String, password: String = "pässwörd日本!", heavy: Bool = false,
                           sourceLocation: SourceLocation = #_sourceLocation) -> String? {
        let options = method.map { ["--method=\($0)"] } ?? []
        let hashed = pwCall("HashPassword", [password] + options)
        #expect(hashed.status == 200, "status \(hashed.status) \(hashed.error ?? "")", sourceLocation: sourceLocation)
        #expect(matches(hashed.result, shape), "hash \(hashed.result ?? "nil")", sourceLocation: sourceLocation)
        guard let hash = hashed.result else { return nil }
        if heavy {
            pwOk(pwCall("VerifyPassword", [password, hash]), "1", sourceLocation: sourceLocation)
            return hash
        }
        pwVerifies(password, hash, sourceLocation: sourceLocation)
        // ソルトは毎回違う。
        #expect(pwCall("HashPassword", [password] + options).result != hash, sourceLocation: sourceLocation)
        return hash
    }

    private let b64 = "[A-Za-z0-9+/]"
    private let crypt64 = "[./0-9A-Za-z]"

    @Test
    func md5AndApr1AndDes() {
        _ = roundTrip("md5-crypt", shape: "\\$1\\$\(crypt64){8}\\$\(crypt64){22}")
        _ = roundTrip("MD5_CRYPT", shape: "\\$1\\$\(crypt64){8}\\$\(crypt64){22}", password: "")
        _ = roundTrip("apr1", shape: "\\$apr1\\$\(crypt64){8}\\$\(crypt64){22}")
        _ = roundTrip("des-crypt", shape: "\(crypt64){13}", password: "pä日")
        // DES は 8 文字まで。
        let hashed = pwCall("HashPassword", ["abcdefgh", "--method=des-crypt"])
        pwOk(pwCall("VerifyPassword", ["abcdefghij", hashed.result ?? ""]), "1")
        pwOk(pwCall("VerifyPassword", ["abcdefg", hashed.result ?? ""]), "0")
    }

    @Test
    func bsdi() {
        // 反復回数 5001 は "7C/." と書ける。
        if let hash = roundTrip("bsdi-crypt", shape: "_7C/\\.\(crypt64){4}\(crypt64){11}") {
            #expect(hash.count == 20)
        }
        _ = roundTrip("bsdi-crypt", shape: "_7C/\\.\(crypt64){15}", password: String(repeating: "long password ", count: 8))
    }

    @Test
    func pbkdf2() {
        _ = roundTrip("pbkdf2-sha256", shape: "\\$pbkdf2-sha256\\$i=600000,l=32\\$\(b64){22}\\$\(b64){43}", heavy: true)
    }

    @Test
    func scryptWithTheFixedParameters() {
        // 既定のパラメータ（8MiB・p=10）はデバッグビルドで 20 秒ほどかかる。照合の計算は RFC 7914 と PHC 文字列の試験で確かめている。
        let hashed = pwCall("HashPassword", ["pässwörd日本!", "--method=scrypt"])
        #expect(matches(hashed.result, "\\$scrypt\\$ln=13,r=8,p=10\\$\(b64){22}\\$\(b64){43}"), "hash \(hashed.result ?? "nil")")
    }

    @Test
    func shaCrypt() {
        _ = roundTrip("sha256-crypt", shape: "\\$5\\$rounds=535000\\$\(crypt64){16}\\$\(crypt64){43}", heavy: true)
        _ = roundTrip("sha512_crypt", shape: "\\$6\\$rounds=656000\\$\(crypt64){16}\\$\(crypt64){86}", heavy: true)
    }

    @Test
    func bcrypt() {
        _ = roundTrip("bcrypt", shape: "\\$2b\\$12\\$\(crypt64){53}", heavy: true)
    }
}
