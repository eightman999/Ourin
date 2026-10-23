import Foundation

/// httpc（櫛ヶ浜やぎ氏作。satoriya の httpc.dll）。Web 上のデータを HTTP で取得する。
///
/// 引数の数で動作が変わる（先頭に文字コード・タグ処理のオプション、さらに前に `bg`・識別子を置ける）:
/// - なし: インターネットに接続できれば 1、できなければ 0
/// - 1 つ（URL）: 取得したものを、改行を除いて返す
/// - 2 つ（URL・ファイル名）: 取得したものを DLL と同じ場所にファイル名で保存し、成功なら 1、失敗なら 0（バイナリも可）
/// - 3 つ（URL・開始文字列・終了文字列）: 開始と終了で囲まれた部分を、1 つ目は Result に、2 つ目以降は Value0 から返す
/// 応答はいつも 200（取れなければ Result が空）。`bg` なら取得を裏で行い、終わったら OnHttpcNotify
/// （Reference0 = 識別子、Reference1 = `-`、Reference2 = 戻り値、Reference3 以降 = 2 つ目以降の部分）を送る。
final class CompatHttpcModule: CompatSaoriModule {
    private let environment: CompatSaoriEnvironment
    private let queue = DispatchQueue(label: "jp.ourin.compat.httpc", qos: .utility, attributes: .concurrent)
    private var unloaded = false
    private let lock = NSLock()

    init(environment: CompatSaoriEnvironment) {
        self.environment = environment
    }

    func unload() {
        lock.lock(); unloaded = true; lock.unlock()
    }

    struct Options {
        var encoding: String.Encoding?
        var eraseTag = false
        var translateTag = false
    }

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        var arguments = arguments
        if arguments.first == "bg" {
            arguments.removeFirst()
            guard let id = arguments.first else { return .ok("bgするならIDを指定していただけませんと。") }
            arguments.removeFirst()
            guard environment.hasGhost, let deliver = environment.deliverEvent else { return .ghostRequired }
            let work = arguments
            queue.async { [weak self] in
                guard let self else { return }
                let outcome = self.run(work)
                self.lock.lock(); let gone = self.unloaded; self.lock.unlock()
                // 取得の間にゴーストが終了していたら、通知しない。
                guard !gone else { return }
                deliver("OnHttpcNotify", [id, "-", outcome.result ?? ""] + outcome.values)
            }
            return .ok("")
        }
        if Self.split(arguments).rest.isEmpty {
            return .ok(CompatSaoriHooks.isOnline() ? "1" : "0")
        }
        guard environment.hasGhost else { return .ghostRequired }
        return run(arguments)
    }

    /// オプションと残りの引数に分ける。オプションは先頭にいくつでも、どの順でも書ける。
    private static func split(_ arguments: [String]) -> (options: Options, rest: [String]) {
        var options = Options()
        var rest = arguments[...]
        while let first = rest.first {
            switch first.lowercased() {
            case "euc": options.encoding = .japaneseEUC
            case "jis": options.encoding = .iso2022JP
            case "sjis": options.encoding = .shiftJIS
            case "utf8", "utf-8": options.encoding = .utf8
            case "utf-16be": options.encoding = .utf16BigEndian
            case "utf-16le": options.encoding = .utf16LittleEndian
            case "erase_tag": options.eraseTag = true
            case "translate_tag": options.translateTag = true
            default: return (options, Array(rest))
            }
            rest = rest.dropFirst()
        }
        return (options, [])
    }

    private func run(_ arguments: [String]) -> CompatSaoriResult {
        let (options, rest) = Self.split(arguments)
        switch rest.count {
        case 0:
            return .ok(CompatSaoriHooks.isOnline() ? "1" : "0")
        case 1:
            return .ok(Self.getText(rest[0], options: options) ?? "")
        case 2:
            return .ok(save(rest[0], to: rest[1]) ? "1" : "0")
        case 3:
            guard let text = Self.getText(rest[0], options: options) else { return .ok("") }
            let found = Self.extract(text, start: rest[1], end: rest[2])
            return .ok(found.first ?? "", values: Array(found.dropFirst()))
        default:
            return .ok("")
        }
    }

    /// 取得して文字列にし、改行を除き、タグを処理する。
    static func getText(_ address: String, options: Options) -> String? {
        guard let url = URL(string: address), let reply = CompatSaoriHooks.fetch(url) else { return nil }
        var text = decode(reply.data, charset: reply.charset, forced: options.encoding)
        text = text.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        if options.translateTag {
            text = translateTag(text)
        } else if options.eraseTag {
            text = eraseTag(text)
        }
        return text
    }

    /// DLL と同じ場所を基準に保存する（原作どおり、DLL のフォルダにファイル名をつないだ場所）。
    private func save(_ address: String, to name: String) -> Bool {
        guard let base = environment.moduleDirectory ?? environment.ghostRoot,
              let url = URL(string: address), let reply = CompatSaoriHooks.fetch(url) else { return false }
        let target = base.appendingPathComponent(name.replacingOccurrences(of: "\\", with: "/"))
        return (try? reply.data.write(to: target, options: .atomic)) != nil
    }

    static func extract(_ text: String, start: String, end: String) -> [String] {
        guard !start.isEmpty, !end.isEmpty else { return [] }
        var found: [String] = []
        var rest = text[...]
        while let open = rest.range(of: start) {
            rest = rest[open.upperBound...]
            guard let close = rest.range(of: end) else { break }
            found.append(String(rest[..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return found
    }

    // MARK: - 文字コード

    /// 明示されていなければ、BOM・Content-Type・ページ内の charset= / encoding= ・中身から判別する。
    static func decode(_ data: Data, charset: String?, forced: String.Encoding?) -> String {
        if let forced, let text = String(data: data, encoding: forced) { return text }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE]), let text = String(data: data, encoding: .utf16) { return text }
        if data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) { return text }
        let declared = charset ?? declaredCharset(in: data)
        if let declared, let encoding = encoding(named: declared), let text = String(data: data, encoding: encoding) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.contains(0x1B), let text = String(data: data, encoding: .iso2022JP) { return text }
        var converted: NSString?
        var lossy: ObjCBool = false
        let detected = NSString.stringEncoding(for: data, encodingOptions: [
            .suggestedEncodingsKey: [String.Encoding.shiftJIS.rawValue, String.Encoding.japaneseEUC.rawValue],
            .useOnlySuggestedEncodingsKey: true
        ], convertedString: &converted, usedLossyConversion: &lossy)
        if detected != 0, let converted { return converted as String }
        return String(data: data, encoding: .shiftJIS) ?? String(decoding: data, as: UTF8.self)
    }

    private static func declaredCharset(in data: Data) -> String? {
        let head = String(decoding: data.prefix(4096).map { $0 < 0x80 ? $0 : 0x20 }, as: UTF8.self)
        for pattern in [#"charset\s*=\s*["']?([A-Za-z0-9_\-]+)"#, #"encoding\s*=\s*["']([A-Za-z0-9_\-]+)"#] {
            if let match = head.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let found = String(head[match])
                if let value = found.range(of: #"[A-Za-z0-9_\-]+$"#, options: .regularExpression) { return String(found[value]) }
            }
        }
        return nil
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    // MARK: - タグの処理

    /// `<` から `>` までを消す。
    static func eraseTag(_ text: String) -> String {
        var output = ""
        var inside = false
        for character in text {
            if inside {
                if character == ">" { inside = false }
            } else if character == "<" {
                inside = true
            } else {
                output.append(character)
            }
        }
        return output
    }

    /// タグをさくらスクリプトに翻訳する（原作の「極めて暫定」の動きのまま）。
    static func translateTag(_ text: String) -> String {
        var output = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            if characters[index] == "<" {
                var area = ""
                index += 1
                while index < characters.count, characters[index] != ">" {
                    area.append(characters[index])
                    index += 1
                }
                if index < characters.count { index += 1 }
                output += script(for: area)
            } else {
                output.append(characters[index])
                index += 1
            }
        }
        output = output.replacingOccurrences(of: "&nbsp;", with: "")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "\\&")
            .replacingOccurrences(of: "&copy;", with: "(c)")
        while output.contains("\\n\\n") { output = output.replacingOccurrences(of: "\\n\\n", with: "\\n") }
        return truncate(output, columns: 48, rows: 120)
    }

    private static func script(for area: String) -> String {
        let (name, properties) = parseTag(area)
        switch name.lowercased() {
        case "/tr", "/li", "br", "p": return "\\n"
        case "hr": return "\\n-----------------------------------------------\\n"
        case "a": return properties["href"].map { "\\_a[\($0)]" } ?? ""
        case "/a": return "\\_a"
        case "img":
            guard let alt = properties["alt"], !alt.isEmpty else { return "" }
            return "〔\(alt)〕"
        default: return ""
        }
    }

    /// タグの名前と属性（名前="値" / 名前=値 / 名前）。
    private static func parseTag(_ area: String) -> (String, [String: String]) {
        let characters = Array(area)
        var index = 0
        func skipSpaces() { while index < characters.count, characters[index].isWhitespace { index += 1 } }
        func readWord() -> String {
            skipSpaces()
            var word = ""
            if index < characters.count, characters[index] == "\"" {
                index += 1
                while index < characters.count, characters[index] != "\"" { word.append(characters[index]); index += 1 }
                if index < characters.count { index += 1 }
            } else {
                while index < characters.count, !characters[index].isWhitespace, characters[index] != "=", characters[index] != ">" {
                    word.append(characters[index]); index += 1
                }
            }
            skipSpaces()
            return word
        }
        let name = readWord()
        var properties: [String: String] = [:]
        while index < characters.count {
            let before = index
            let key = readWord()
            if index < characters.count, characters[index] == "=" {
                index += 1
                properties[key.lowercased()] = readWord()
            } else {
                properties[key.lowercased()] = ""
            }
            if index == before { index += 1 }
        }
        return (name, properties)
    }

    /// 1 行 48 桁（全角は 2 桁）・120 行までで切る。`\n` で改行と数える。
    private static func truncate(_ text: String, columns: Int, rows: Int) -> String {
        var column = 0
        var row = 1
        var output = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count, row < rows {
            if characters[index] == "\\", index + 1 < characters.count, characters[index + 1] == "n" {
                output += "\\n"
                column = 0
                row += 1
                index += 2
                continue
            }
            let character = characters[index]
            output.append(character)
            column += character.unicodeScalars.allSatisfy({ $0.isASCII || (0xFF61...0xFF9F).contains($0.value) }) ? 1 : 2
            if column >= columns {
                column = 0
                row += 1
            }
            index += 1
        }
        return output
    }
}
