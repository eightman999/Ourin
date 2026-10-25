import CommonCrypto
import Foundation
import Security

/// HashPassword / VerifyPassword。
///
/// PHC 文字列（argon2id・scrypt・pbkdf2-*）と crypt(3) の形式（bcrypt・SHA-crypt・MD5-crypt・apr1・BSDi・DES）を扱う。
/// パラメータの範囲は DeriveKey と同じ（メモリは 12MiB まで）。
enum InternalCryptoPasswords {
    typealias Support = InternalCryptoSupport

    static var functions: [InternalSaoriFunction] { [hashPassword, verifyPassword] }

    // MARK: - 固定のパラメータ（HashPassword）

    private static let argonIterations = 3, argonMemory = 12288, argonLanes = 1
    private static let scryptLog = 13, scryptR = 8, scryptP = 10
    private static let pbkdf2Iterations = 600_000
    private static let bcryptCost = 12
    private static let sha512Rounds = 656_000, sha256Rounds = 535_000
    private static let bsdiCount = 5001

    private static let maximumRounds = 10_000_000
    private static let maximumCryptPasswordBytes = 1024

    // MARK: - 関数

    private enum Method {
        case argon2id, scrypt, pbkdf2Sha256, bcrypt, sha512Crypt, sha256Crypt, md5Crypt, apr1, bsdiCrypt, desCrypt

        init(_ name: String) throws {
            switch name.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "") {
            case "argon2id": self = .argon2id
            case "scrypt": self = .scrypt
            case "pbkdf2sha256": self = .pbkdf2Sha256
            case "bcrypt": self = .bcrypt
            case "sha512crypt": self = .sha512Crypt
            case "sha256crypt": self = .sha256Crypt
            case "md5crypt": self = .md5Crypt
            case "apr1": self = .apr1
            case "bsdicrypt": self = .bsdiCrypt
            case "descrypt": self = .desCrypt
            default: throw InternalSaoriError.unsupportedAlgorithm
            }
        }
    }

    private static var hashPassword: InternalSaoriFunction {
        InternalSaoriFunction("HashPassword", positionals: 1, options: ["method", "password-in", "charset"]) { call, _ in
            let method = try Method(call.option("method") ?? "argon2id")
            let password = try InternalSaoriCodec.decode(call.positionals[0], format: call.option("password-in"),
                                                         defaultFormat: "text", charset: call.option("charset"))
            return InternalSaoriResult(try hash(password: password, method: method))
        }
    }

    private static var verifyPassword: InternalSaoriFunction {
        InternalSaoriFunction("VerifyPassword", positionals: 2, options: ["password-in", "charset"]) { call, _ in
            let password = try InternalSaoriCodec.decode(call.positionals[0], format: call.option("password-in"),
                                                         defaultFormat: "text", charset: call.option("charset"))
            return InternalSaoriResult(try verify(password: password, hash: call.positionals[1]) ? "1" : "0")
        }
    }

    // MARK: - ハッシュ

    private static func hash(password: Data, method: Method) throws -> String {
        switch method {
        case .argon2id:
            let salt = randomBytes(16)
            let derived = try InternalArgon2.deriveID(password: password, salt: salt, iterations: argonIterations,
                                                      memoryKiB: argonMemory, lanes: argonLanes, length: 32)
            return "$argon2id$v=19$m=\(argonMemory),t=\(argonIterations),p=\(argonLanes)$\(base64(salt))$\(base64(derived))"
        case .scrypt:
            let salt = randomBytes(16)
            let derived = try InternalScrypt.derive(password: password, salt: salt, n: 1 << scryptLog, r: scryptR, p: scryptP, length: 32)
            return "$scrypt$ln=\(scryptLog),r=\(scryptR),p=\(scryptP)$\(base64(salt))$\(base64(derived))"
        case .pbkdf2Sha256:
            let salt = randomBytes(16)
            let derived = try InternalScrypt.pbkdf2(prf: CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), password: password, salt: salt,
                                                    iterations: pbkdf2Iterations, length: 32)
            return "$pbkdf2-sha256$i=\(pbkdf2Iterations),l=32$\(base64(salt))$\(base64(derived))"
        case .bcrypt:
            try checkCryptPassword(password)
            let salt = randomBytes(16)
            let derived = InternalBcrypt.hash(password: password, cost: bcryptCost, salt: salt)
            return "$2b$\(bcryptCost)$\(InternalBcrypt.encode(salt))\(InternalBcrypt.encode(derived))"
        case .sha512Crypt:
            try checkCryptPassword(password)
            let salt = randomSalt(16)
            let hash = InternalUnixCrypt.sha(password: password, salt: Data(salt), rounds: sha512Rounds, variant: .sha512)
            return "$6$rounds=\(sha512Rounds)$\(string(salt))$\(hash)"
        case .sha256Crypt:
            try checkCryptPassword(password)
            let salt = randomSalt(16)
            let hash = InternalUnixCrypt.sha(password: password, salt: Data(salt), rounds: sha256Rounds, variant: .sha256)
            return "$5$rounds=\(sha256Rounds)$\(string(salt))$\(hash)"
        case .md5Crypt, .apr1:
            try checkCryptPassword(password)
            let salt = randomSalt(8)
            let magic = method == .apr1 ? "$apr1$" : "$1$"
            return "\(magic)\(string(salt))$\(InternalUnixCrypt.md5(password: password, salt: Data(salt), magic: magic))"
        case .bsdiCrypt:
            try checkCryptPassword(password)
            let salt = randomSalt(4)
            let saltValue = salt.enumerated().reduce(UInt32(0)) { $0 | InternalDES.value(of: $1.element)! << UInt32(6 * $1.offset) }
            let count = (0..<4).map { InternalDES.alphabet[(bsdiCount >> (6 * $0)) & 0x3f] }
            return "_\(string(count))\(string(salt))\(InternalDES.extended(password: [UInt8](password), count: bsdiCount, salt: saltValue))"
        case .desCrypt:
            try checkCryptPassword(password)
            let salt = randomSalt(2)
            return string(salt) + InternalDES.traditional(password: [UInt8](password), salt: salt)
        }
    }

    // MARK: - 照合

    private static func verify(password: Data, hash: String) throws -> Bool {
        let bytes = Array(hash.utf8)
        guard !bytes.isEmpty else { throw InternalSaoriError.invalidParameter }
        if bytes[0] == UInt8(ascii: "$") {
            let parts = hash.split(separator: "$", omittingEmptySubsequences: false).map(String.init)
            switch parts[1] {
            case "argon2id": return try verifyArgon2id(password: password, parts: parts)
            case "scrypt": return try verifyScrypt(password: password, parts: parts)
            case "pbkdf2-sha1": return try verifyPBKDF2(password: password, parts: parts, prf: kCCPRFHmacAlgSHA1)
            case "pbkdf2-sha256": return try verifyPBKDF2(password: password, parts: parts, prf: kCCPRFHmacAlgSHA256)
            case "pbkdf2-sha512": return try verifyPBKDF2(password: password, parts: parts, prf: kCCPRFHmacAlgSHA512)
            case "2a", "2b", "2y": return try verifyBcrypt(password: password, parts: parts)
            case "6": return try verifySHACrypt(password: password, parts: parts, variant: .sha512)
            case "5": return try verifySHACrypt(password: password, parts: parts, variant: .sha256)
            case "1": return try verifyMD5Crypt(password: password, parts: parts, magic: "$1$")
            case "apr1": return try verifyMD5Crypt(password: password, parts: parts, magic: "$apr1$")
            default: throw InternalSaoriError.unsupportedAlgorithm
            }
        }
        if bytes[0] == UInt8(ascii: "_") {
            guard bytes.count == 20, bytes.dropFirst().allSatisfy({ InternalDES.value(of: $0) != nil }) else {
                throw InternalSaoriError.invalidParameter
            }
            return try verifyBSDi(password: password, bytes: bytes)
        }
        if bytes.count == 13 {
            guard bytes.allSatisfy({ InternalDES.value(of: $0) != nil }) else { throw InternalSaoriError.invalidParameter }
            try checkCryptPassword(password)
            let computed = String(decoding: Array(bytes[0..<2]), as: UTF8.self)
                + InternalDES.traditional(password: [UInt8](password), salt: Array(bytes[0..<2]))
            return equal(computed, hash)
        }
        throw InternalSaoriError.unsupportedAlgorithm
    }

    // MARK: PHC

    private static func verifyArgon2id(password: Data, parts: [String]) throws -> Bool {
        // ["", "argon2id", ("v=19",) "m=..,t=..,p=..", salt, hash]
        guard parts.count == 5 || parts.count == 6 else { throw InternalSaoriError.invalidParameter }
        var version = 0x10
        var index = 2
        if parts.count == 6 {
            let versionParameters = try parameters(parts[2], allowed: ["v"])
            guard let text = versionParameters["v"], versionParameters.count == 1 else { throw InternalSaoriError.invalidParameter }
            version = try integer(text)
            // v=16（0x10）と v=19（0x13）だけ。
            guard version == 16 || version == 19 else { throw InternalSaoriError.invalidParameter }
            version = version == 19 ? 0x13 : 0x10
            index = 3
        }
        let values = try parameters(parts[index], allowed: ["m", "t", "p"])
        guard values.count == 3, let m = values["m"], let t = values["t"], let p = values["p"] else { throw InternalSaoriError.invalidParameter }
        let memory = try integer(m), iterations = try integer(t), lanes = try integer(p)
        let salt = try decodeBase64(parts[index + 1])
        let expected = try decodeBase64(parts[index + 2])
        guard (1...1000).contains(iterations), (1...16).contains(lanes), (lanes * 8...12288).contains(memory),
              salt.count >= 8, (4...1024).contains(expected.count) else { throw InternalSaoriError.outOfRange }
        let derived = try InternalArgon2.deriveID(password: password, salt: salt, iterations: iterations, memoryKiB: memory,
                                                  lanes: lanes, length: expected.count, version: version)
        return Support.constantTimeEqual(derived, expected)
    }

    private static func verifyScrypt(password: Data, parts: [String]) throws -> Bool {
        guard parts.count == 5 else { throw InternalSaoriError.invalidParameter }
        let values = try parameters(parts[2], allowed: ["ln", "r", "p"])
        guard values.count == 3, let ln = values["ln"], let r = values["r"], let p = values["p"] else { throw InternalSaoriError.invalidParameter }
        let log = try integer(ln)
        // N × r × 128 が 12MiB 以内になる N（2^log）だけ。log が極端に大きければ範囲外。
        guard (1...23).contains(log) else { throw InternalSaoriError.outOfRange }
        let salt = try decodeBase64(parts[3])
        let expected = try decodeBase64(parts[4])
        let derived = try InternalScrypt.derive(password: password, salt: salt, n: 1 << log, r: try integer(r), p: try integer(p),
                                                length: expected.count)
        return Support.constantTimeEqual(derived, expected)
    }

    private static func verifyPBKDF2(password: Data, parts: [String], prf: Int) throws -> Bool {
        guard parts.count == 5 else { throw InternalSaoriError.invalidParameter }
        let values = try parameters(parts[2], allowed: ["i", "l"])
        guard let i = values["i"] else { throw InternalSaoriError.invalidParameter }
        let iterations = try integer(i)
        let salt = try decodeBase64(parts[3])
        let expected = try decodeBase64(parts[4])
        if let l = values["l"], try integer(l) != expected.count { throw InternalSaoriError.invalidParameter }
        guard (1...maximumRounds).contains(iterations), (1...1024).contains(expected.count) else { throw InternalSaoriError.outOfRange }
        let derived = try InternalScrypt.pbkdf2(prf: CCPseudoRandomAlgorithm(prf), password: password, salt: salt,
                                                iterations: iterations, length: expected.count)
        return Support.constantTimeEqual(derived, expected)
    }

    // MARK: crypt(3)

    private static func verifyBcrypt(password: Data, parts: [String]) throws -> Bool {
        // ["", "2b", "12", salt(22)+hash(31)]
        guard parts.count == 4, parts[2].utf8.count == 2, parts[3].utf8.count == 53 else { throw InternalSaoriError.invalidParameter }
        let cost = try integer(parts[2])
        guard let salt = InternalBcrypt.decode(String(parts[3].prefix(22)), count: 16),
              InternalBcrypt.decode(String(parts[3].suffix(31)), count: 23) != nil else { throw InternalSaoriError.invalidParameter }
        guard (4...16).contains(cost) else { throw InternalSaoriError.outOfRange }
        try checkCryptPassword(password)
        let computed = InternalBcrypt.encode(InternalBcrypt.hash(password: password, cost: cost, salt: salt))
        return equal(computed, String(parts[3].suffix(31)))
    }

    private static func verifySHACrypt(password: Data, parts: [String], variant: InternalUnixCrypt.SHAVariant) throws -> Bool {
        // ["", "6", ("rounds=N",) salt, hash]
        guard parts.count == 4 || parts.count == 5 else { throw InternalSaoriError.invalidParameter }
        var rounds = 5000
        if parts.count == 5 {
            guard parts[2].hasPrefix("rounds=") else { throw InternalSaoriError.invalidParameter }
            let value = try integer(String(parts[2].dropFirst(7)))
            guard value <= maximumRounds else { throw InternalSaoriError.outOfRange }
            rounds = max(1000, value)
        }
        let salt = parts[parts.count - 2], expected = parts[parts.count - 1]
        guard salt.utf8.count <= 16, expected.utf8.count == variant.encodedLength, isCryptCharacters(expected) else {
            throw InternalSaoriError.invalidParameter
        }
        try checkCryptPassword(password)
        return equal(InternalUnixCrypt.sha(password: password, salt: Data(salt.utf8), rounds: rounds, variant: variant), expected)
    }

    private static func verifyMD5Crypt(password: Data, parts: [String], magic: String) throws -> Bool {
        guard parts.count == 4, parts[2].utf8.count <= 8, parts[3].utf8.count == 22, isCryptCharacters(parts[3]) else {
            throw InternalSaoriError.invalidParameter
        }
        try checkCryptPassword(password)
        return equal(InternalUnixCrypt.md5(password: password, salt: Data(parts[2].utf8), magic: magic), parts[3])
    }

    /// `_` ＋ 反復回数 4 文字 ＋ ソルト 4 文字 ＋ ハッシュ 11 文字。
    private static func verifyBSDi(password: Data, bytes: [UInt8]) throws -> Bool {
        func number(_ range: Range<Int>) -> UInt32 {
            range.enumerated().reduce(UInt32(0)) { $0 | InternalDES.value(of: bytes[$1.element])! << UInt32(6 * $1.offset) }
        }
        let count = Int(number(1..<5)), salt = number(5..<9)
        // 回数が多すぎると、1 回の照合で長い時間を使う。
        guard (1...1_000_000).contains(count) else { throw InternalSaoriError.outOfRange }
        try checkCryptPassword(password)
        let computed = InternalDES.extended(password: [UInt8](password), count: count, salt: salt)
        return equal(computed, String(decoding: Array(bytes[9...]), as: UTF8.self))
    }

    // MARK: - 部品

    private static func checkCryptPassword(_ password: Data) throws {
        guard !password.contains(0) else { throw InternalSaoriError.invalidParameter }
        guard password.count <= maximumCryptPasswordBytes else { throw InternalSaoriError.outOfRange }
    }

    private static func equal(_ a: String, _ b: String) -> Bool {
        Support.constantTimeEqual(Data(a.utf8), Data(b.utf8))
    }

    private static func isCryptCharacters(_ text: String) -> Bool {
        text.utf8.allSatisfy { InternalDES.value(of: $0) != nil }
    }

    /// `k=v,k=v`。許可した名前だけ、同じ名前は 1 回だけ。
    private static func parameters(_ text: String, allowed: Set<String>) throws -> [String: String] {
        var result: [String: String] = [:]
        for item in text.split(separator: ",", omittingEmptySubsequences: false) {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, allowed.contains(String(pair[0])), result[String(pair[0])] == nil else {
                throw InternalSaoriError.invalidParameter
            }
            result[String(pair[0])] = String(pair[1])
        }
        return result
    }

    /// 10 進数字だけの整数。桁あふれは範囲外。
    private static func integer(_ text: String) throws -> Int {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { throw InternalSaoriError.invalidParameter }
        guard let value = Int(text) else { throw InternalSaoriError.outOfRange }
        return value
    }

    /// パディングなしの base64（標準の文字）。
    private static func decodeBase64(_ text: String) throws -> Data {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8)
        guard text.utf8.allSatisfy({ allowed.contains($0) }), text.utf8.count % 4 != 1 else { throw InternalSaoriError.invalidParameter }
        return try InternalSaoriCodec.decodeBase64(text)
    }

    private static func base64(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            for index in 0..<count { bytes[index] = UInt8.random(in: 0...255) }
        }
        return Data(bytes)
    }

    /// `./0-9A-Za-z` の文字のソルト。
    private static func randomSalt(_ count: Int) -> [UInt8] {
        randomBytes(count).map { InternalDES.alphabet[Int($0 & 0x3f)] }
    }

    private static func string(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
}
