import Foundation

/// string（りゅう氏作）。正規表現（Perl 5 風。原作は bregexp.dll）・文字の種類の判定・変換。
///
/// - match（`/正規表現/オプション`）: マッチすれば 1（g なら個数）。get 0 で全体、get n で n 番目の () の文字列
/// - replace（`s/正規表現/置換/オプション`）: 置換した数。get 0 で置換後の文字列、get n で n 番目の ()
/// - split（`/正規表現/オプション`）: 分割した数。get n で n 番目（0 から）の文字列
/// - オプション: g（すべて）・i（大文字小文字を区別しない）・m・s・x・h（先に半角に変換）
/// - isalpha / isupper / islower / isnumber / isalnum / isinteger / isdecimal / issjis / isjis / iseuc: 1 か 0
/// - toupper / tolower / tozenkaku / tohankaku / tosjis / tojis / toeuc / trim: 変換した文字列
/// 漢字コードの関数（issjis など）は、要求の Charset で文字列をバイト列に戻してから調べる・変換する。
final class CompatStringModule: CompatSaoriModule {
    private enum Last {
        case none
        case match(groups: [String])
        case replace(result: String, groups: [String])
        case split(pieces: [String])
    }

    private var last = Last.none
    private let lock = NSLock()

    init(environment: CompatSaoriEnvironment) {}

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard let function = arguments.first?.lowercased() else { return .badRequest }
        let text = arguments.count >= 2 ? arguments[1] : ""
        let regex = arguments.count >= 3 ? arguments[2] : ""
        lock.lock(); defer { lock.unlock() }
        switch function {
        case "match": return match(text, regex)
        case "replace": return replace(text, regex)
        case "split": return split(text, regex)
        case "get": return get(CompatSaoriHost.leadingInteger(text))
        case "isalpha": return flag(!text.isEmpty && text.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic })
        case "isupper": return flag(!text.isEmpty && text.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) })
        case "islower": return flag(!text.isEmpty && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) })
        case "isnumber": return flag(!text.isEmpty && text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) })
        case "isalnum":
            return flag(!text.isEmpty && text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("A"..."Z").contains($0) || ("a"..."z").contains($0) })
        case "isinteger": return flag(text.range(of: #"^[ \t]*[+-]?[0-9]+$"#, options: .regularExpression) != nil)
        case "isdecimal": return flag(text.range(of: #"^[ \t]*[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)$"#, options: .regularExpression) != nil)
        case "issjis": return flag(Self.isValid(Self.bytes(text, charset), as: .shiftJIS))
        case "iseuc": return flag(Self.isValid(Self.bytes(text, charset), as: .japaneseEUC))
        case "isjis":
            let bytes = Self.bytes(text, charset)
            return flag(bytes.allSatisfy { $0 < 0x80 } && bytes.contains(0x1B))
        case "toupper": return .ok(String(String.UnicodeScalarView(text.unicodeScalars.map { ("a"..."z").contains($0) ? Unicode.Scalar($0.value - 32)! : $0 })))
        case "tolower": return .ok(String(String.UnicodeScalarView(text.unicodeScalars.map { ("A"..."Z").contains($0) ? Unicode.Scalar($0.value + 32)! : $0 })))
        case "tozenkaku": return .ok(Self.toZenkaku(text))
        case "tohankaku": return .ok(Self.toHankaku(text))
        case "tosjis": return .ok(Self.convert(text, to: .shiftJIS, charset: charset))
        case "tojis": return .ok(Self.convert(text, to: .iso2022JP, charset: charset))
        case "toeuc": return .ok(Self.convert(text, to: .japaneseEUC, charset: charset))
        case "trim": return .ok(text.trimmingCharacters(in: CharacterSet(charactersIn: " \t\u{3000}")))
        default: return .badRequest
        }
    }

    private func flag(_ value: Bool) -> CompatSaoriResult { .ok(value ? "1" : "0") }

    // MARK: - 正規表現

    private struct Pattern {
        var regex: NSRegularExpression
        var global: Bool
        var hankaku: Bool
        var replacement: String?
    }

    private static let invalidRegex = CompatSaoriResult(status: 400, error: "invalid regular expression")

    private func match(_ text: String, _ source: String) -> CompatSaoriResult {
        guard let pattern = Self.parse(source, replace: false) else { return Self.invalidRegex }
        let target = pattern.hankaku ? Self.toHankaku(text) : text
        let range = NSRange(target.startIndex..., in: target)
        if pattern.global {
            let matches = pattern.regex.matches(in: target, range: range)
            last = matches.last.map { .match(groups: Self.groups(of: $0, in: target)) } ?? .none
            return .ok(String(matches.count))
        }
        guard let found = pattern.regex.firstMatch(in: target, range: range) else {
            last = .none
            return .ok("0")
        }
        last = .match(groups: Self.groups(of: found, in: target))
        return .ok("1")
    }

    private func replace(_ text: String, _ source: String) -> CompatSaoriResult {
        guard let pattern = Self.parse(source, replace: true), let template = pattern.replacement else { return Self.invalidRegex }
        let target = pattern.hankaku ? Self.toHankaku(text) : text
        let all = pattern.regex.matches(in: target, range: NSRange(target.startIndex..., in: target))
        let used = pattern.global ? all : Array(all.prefix(1))
        let output = NSMutableString(string: target)
        for found in used.reversed() {
            let replacement = pattern.regex.replacementString(for: found, in: target, offset: 0, template: template)
            output.replaceCharacters(in: found.range, with: replacement)
        }
        last = .replace(result: output as String, groups: used.last.map { Self.groups(of: $0, in: target) } ?? [])
        return .ok(String(used.count))
    }

    /// Perl の split と同じく、() の中も要素に入れ、末尾の空の要素は捨てる。
    private func split(_ text: String, _ source: String) -> CompatSaoriResult {
        guard let pattern = Self.parse(source, replace: false) else { return Self.invalidRegex }
        let target = pattern.hankaku ? Self.toHankaku(text) : text
        let nsTarget = target as NSString
        var pieces: [String] = []
        var cursor = 0
        for found in pattern.regex.matches(in: target, range: NSRange(location: 0, length: nsTarget.length)) {
            // 先頭の幅 0 のマッチでは区切らない。
            if found.range.length == 0 && found.range.location == 0 { continue }
            if found.range.length == 0 && found.range.location >= nsTarget.length { break }
            pieces.append(nsTarget.substring(with: NSRange(location: cursor, length: found.range.location - cursor)))
            for group in 1..<max(1, found.numberOfRanges) where found.range(at: group).location != NSNotFound {
                pieces.append(nsTarget.substring(with: found.range(at: group)))
            }
            cursor = found.range.location + found.range.length
        }
        pieces.append(nsTarget.substring(from: cursor))
        while pieces.last?.isEmpty == true { pieces.removeLast() }
        last = .split(pieces: pieces)
        return .ok(String(pieces.count))
    }

    private func get(_ index: Int) -> CompatSaoriResult {
        func element(_ list: [String]) -> String { list.indices.contains(index) ? list[index] : "" }
        switch last {
        case .none: return .ok("")
        case .match(let groups): return .ok(element(groups))
        case .replace(let result, let groups): return .ok(index == 0 ? result : element(groups))
        case .split(let pieces): return .ok(element(pieces))
        }
    }

    private static func groups(of found: NSTextCheckingResult, in text: String) -> [String] {
        let nsText = text as NSString
        return (0..<found.numberOfRanges).map { index in
            let range = found.range(at: index)
            return range.location == NSNotFound ? "" : nsText.substring(with: range)
        }
    }

    /// `/正規表現/オプション`（先頭の m は省略可）か `s/正規表現/置換/オプション`。区切りは / 以外の記号でもよい。
    private static func parse(_ source: String, replace: Bool) -> Pattern? {
        var characters = Array(source.trimmingCharacters(in: .whitespaces))
        if replace {
            guard characters.first == "s" else { return nil }
            characters.removeFirst()
        } else if characters.first == "m" {
            characters.removeFirst()
        }
        guard let delimiter = characters.first, !delimiter.isLetter, !delimiter.isNumber, !delimiter.isWhitespace, delimiter != "\\" else { return nil }
        var index = 1
        func readPart() -> String? {
            var part = ""
            while index < characters.count {
                let character = characters[index]
                if character == "\\", index + 1 < characters.count {
                    // 区切り文字のエスケープは区切り文字そのものにする。ほかのエスケープはそのまま正規表現・置換に渡す。
                    if characters[index + 1] == delimiter {
                        part.append(delimiter)
                    } else {
                        part.append(character)
                        part.append(characters[index + 1])
                    }
                    index += 2
                    continue
                }
                if character == delimiter {
                    index += 1
                    return part
                }
                part.append(character)
                index += 1
            }
            return nil
        }
        guard let body = readPart() else { return nil }
        var replacement: String?
        if replace {
            guard let text = readPart() else { return nil }
            replacement = template(fromPerl: text)
        }
        var options: NSRegularExpression.Options = []
        var global = false
        var hankaku = false
        for flag in characters[index...] {
            switch flag {
            case "g": global = true
            case "i": options.insert(.caseInsensitive)
            case "m": options.insert(.anchorsMatchLines)
            case "s": options.insert(.dotMatchesLineSeparators)
            case "x": options.insert(.allowCommentsAndWhitespace)
            case "h": hankaku = true
            case "k", "o": break // k（漢字コード）・o（一度だけコンパイル）は意味を持たない
            default: return nil
            }
        }
        // 空の正規表現（split // で 1 文字ずつ）は、NSRegularExpression では空に一致する (?:) と書く。
        guard let regex = try? NSRegularExpression(pattern: body.isEmpty ? "(?:)" : body, options: options) else { return nil }
        return Pattern(regex: regex, global: global, hankaku: hankaku, replacement: replacement)
    }

    /// Perl の置換文字列（$1・${1}・$&・\1・\n・\t）を NSRegularExpression のテンプレートにする。
    private static func template(fromPerl text: String) -> String {
        var output = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "$", let next {
                if next.isNumber {
                    output += "$\(next)"; index += 2; continue
                }
                if next == "&" {
                    output += "$0"; index += 2; continue
                }
                if next == "{", let close = characters[(index + 2)...].firstIndex(of: "}"),
                   let number = Int(String(characters[(index + 2)..<close])) {
                    output += "$\(number)" // NSRegularExpression のテンプレートに ${n} は無い
                    index = close + 1
                    continue
                }
            }
            if character == "$" { output += "\\$"; index += 1; continue }
            if character == "\\", let next {
                switch next {
                case "n": output += "\n"
                case "t": output += "\t"
                case "\\": output += "\\\\"
                case "$": output += "\\$"
                default: output += next.isNumber ? "$\(next)" : String(next)
                }
                index += 2
                continue
            }
            output.append(character)
            index += 1
        }
        return output
    }

    // MARK: - 全角・半角

    /// 原作（Windows の _mbbtombc）と同じく、" ' \ ` ~ は ” ’ ￥ ｀ ￣ になる。
    private static let zenkakuSpecial: [Unicode.Scalar: Unicode.Scalar] = [
        "\"": "\u{201D}", "'": "\u{2019}", "\\": "\u{FFE5}", "`": "\u{FF40}", "~": "\u{FFE3}", " ": "\u{3000}"
    ]

    static func toZenkaku(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            if let special = zenkakuSpecial[scalar] { return special }
            if (0x21...0x7E).contains(scalar.value) { return Unicode.Scalar(scalar.value + 0xFEE0)! }
            return scalar
        }))
    }

    static func toHankaku(_ text: String) -> String {
        let reverse = Dictionary(uniqueKeysWithValues: zenkakuSpecial.map { ($1, $0) })
        return String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            if let plain = reverse[scalar] { return plain }
            if (0xFF01...0xFF5E).contains(scalar.value) { return Unicode.Scalar(scalar.value - 0xFEE0)! }
            return scalar
        }))
    }

    // MARK: - 漢字コード

    private static func transportEncoding(_ charset: String) -> String.Encoding {
        SaoriProtocol.stringEncoding(for: charset) ?? .utf8
    }

    private static func bytes(_ text: String, _ charset: String) -> [UInt8] {
        [UInt8](text.data(using: transportEncoding(charset), allowLossyConversion: true) ?? Data(text.utf8))
    }

    private static func isValid(_ bytes: [UInt8], as encoding: String.Encoding) -> Bool {
        if bytes.contains(0x1B) { return false }
        return String(data: Data(bytes), encoding: encoding) != nil
    }

    /// JIS のエスケープが入っていれば JIS として読み直してから、目的の漢字コードのバイト列にし、要求の Charset の文字列として返す。
    private static func convert(_ text: String, to target: String.Encoding, charset: String) -> String {
        let transport = transportEncoding(charset)
        var source = text
        let raw = Data(bytes(text, charset))
        if raw.contains(0x1B), let decoded = String(data: raw, encoding: .iso2022JP) { source = decoded }
        guard let converted = source.data(using: target, allowLossyConversion: true) else { return text }
        if let reinterpreted = String(data: converted, encoding: transport) { return reinterpreted }
        return String(decoding: converted, as: UTF8.self)
    }
}
