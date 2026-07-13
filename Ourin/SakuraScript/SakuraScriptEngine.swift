import Foundation

/// Delegate notified for each parsed token.
public protocol SakuraScriptEngineDelegate: AnyObject {
    func sakuraEngine(_ engine: SakuraScriptEngine, didEmit token: SakuraScriptEngine.Token)
}

/// SakuraScript parser and executor.
///
/// # Command Execution Timing
/// According to the Sakura Script specification:
/// - Commands at the END of text should execute AFTER the text finishes speaking
/// - Script lifetime ends at \e (end tag)
/// - Most settings persist until script end, then reset for the next script
///
/// # Escape Sequences
/// - `\\` → literal backslash `\`
/// - `\%` → literal percent sign `%`
/// - `\]` → literal `]` (only inside `[...]` brackets)
/// - `\[` → literal `[` (only inside `[...]` brackets)
///
/// # Argument Quoting Rules
/// - Arguments in `[...]` are comma-separated
/// - To include a comma in an argument, wrap the argument in `""`
/// - To include a `"` inside a quoted argument, use `""`
/// - Example: `\![raise,OnTest,"100,2"]` → args: `["raise", "OnTest", "100,2"]`
/// - Example: `\![call,ghost,"the ""MobileMaster"""]` → args: `["call", "ghost", "the \"MobileMaster\""]`
public final class SakuraScriptEngine {
    public weak var delegate: SakuraScriptEngineDelegate?
    /// Property manager used for `%property[...]` expansion in text.
    public var propertyManager: PropertyManager = PropertyManager() {
        didSet { envExpander.propertyManager = propertyManager }
    }
    /// Environment/placeholder expander
    public private(set) var envExpander: EnvironmentExpander

    public init() {
        self.envExpander = EnvironmentExpander(propertyManager: propertyManager)
    }

    /// Quick check whether the script contains any visible text token.
    public func containsText(in script: String) -> Bool {
        for token in parse(script: script) {
            if case .text(let t) = token, !t.isEmpty { return true }
        }
        return false
    }

    /// Parse given script and notify delegate token by token.
    ///
    /// **Important**: According to Sakura Script specification, commands should be
    /// executed AFTER all preceding text finishes speaking. The delegate is responsible
    /// for implementing this timing behavior by:
    /// 1. Buffering commands that appear after text
    /// 2. Executing them only after speech/display completes
    /// 3. Resetting state when `.end` token is received
    public func run(script: String) {
        for token in parse(script: script) {
            delegate?.sakuraEngine(self, didEmit: token)
        }
    }

    /// UKADOCの表示前変換順序（環境変数→OnTranslate→MAKOTO）の先頭段を明示する。
    /// 変換後スクリプトは `runPreprocessed` へ渡し、OnTranslate/MAKOTOの返値を再展開しない。
    public func expandEnvironment(in script: String) -> String {
        envExpander.expand(text: script)
    }

    public func containsTextInPreprocessedScript(_ script: String) -> Bool {
        parse(script: script, expandEnvironment: false).contains { token in
            if case .text(let text) = token { return !text.isEmpty }
            return false
        }
    }

    public func runPreprocessed(script: String) {
        for token in parse(script: script, expandEnvironment: false) {
            delegate?.sakuraEngine(self, didEmit: token)
        }
    }

    // MARK: - Parsing

    /// Individual SakuraScript token.
    public enum Token: Equatable {
        case text(String)
        case scope(Int)
        case surface(Int)
        case surfaceNamed(String) // \s[alias] 文字列サーフェス別名（非数値）
        case animation(Int, wait: Bool)
        case newline
        case newlineVariation(String) // \n[half] or \n[percent]
        case end
        case moveAway          // \4 - move away from other character
        case moveClose         // \5 - move close to other character
        case balloon(Int)      // \bN or \b[ID] - change balloon ID
        case appendMode        // \C - append to previous balloon
        case wait              // \t - click wait / quick wait
        case endConversation(clearBalloon: Bool) // \x or \x[noclear]
        case choiceCancel      // \z - choice cancellation
        case choiceMarker      // \* - choice marker
        case anchor            // \a - anchor marker (for choices)
        case choiceLineBr      // \- - line break in choice
        case bootGhost         // \+ - boot/call other ghost
        case bootAllGhosts     // \_+ - boot all ghosts
        case openPreferences   // \v - open preferences/settings
        case openURL           // \6 - open URL
        case openEmail         // \7 - open email
        case playSound(String) // \8[filename] - play sound
        case command(name: String, args: [String])
        /// \__q メタタグ（選択肢キュー / choice queue）。
        /// 単一形式 `\__q[ID,r0,...]` は title=""。
        /// 範囲形式 `\__q[ID,r0,...]表示テキスト\__q` は title=範囲内の表示テキスト。
        /// ID 仕様は \q と同一（"script:" プレフィックスや On* イベント）。
        /// references は ID に続く引数（\q の R0,R1,... に相当）。
        case choiceQueue(title: String, id: String, references: [String])

        /// Returns true if this token represents displayable text or speech.
        var isTextLike: Bool {
            switch self {
            case .text: return true
            case .newline: return true
            case .newlineVariation: return true
            default: return false
            }
        }
    }

    /// Parse a SakuraScript string into tokens.
    func parse(script: String, expandEnvironment: Bool = true) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        let chars = Array(script)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            tokens.append(.text(expandEnvironment ? envExpander.expand(text: buffer) : buffer))
            buffer.removeAll()
        }

        func readBracket(start: Int) -> (String, Int)? {
            var j = start
            var result = ""
            var nestedDepth = 0
            while j < chars.count {
                let c = chars[j]
                // Handle escape sequences inside brackets: \], \[
                if c == "\\" && j + 1 < chars.count {
                    let next = chars[j+1]
                    if next == "]" {
                        result.append("]")
                        j += 2
                        continue
                    } else if next == "[" {
                        result.append("[")
                        j += 2
                        continue
                    }
                }
                if c == "[" {
                    nestedDepth += 1
                    result.append(c)
                    j += 1
                    continue
                }
                if c == "]" {
                    if nestedDepth == 0 {
                        return (result, j + 1)
                    }
                    nestedDepth -= 1
                    result.append(c)
                    j += 1
                    continue
                }
                result.append(c)
                j += 1
            }
            return nil
        }

        // Helper to find the closing tag for tag passthrough commands
        func readUntilClosingTag(start: Int, closingTag: String) -> (String, Int)? {
            var j = start
            var result = ""
            let closingChars = Array(closingTag)
            while j < chars.count {
                // Check if we've found the closing tag
                var matchFound = true
                if j + closingChars.count <= chars.count {
                    for (offset, ch) in closingChars.enumerated() {
                        if chars[j + offset] != ch {
                            matchFound = false
                            break
                        }
                    }
                    if matchFound {
                        return (result, j + closingChars.count)
                    }
                }
                result.append(chars[j])
                j += 1
            }
            return nil // Closing tag not found
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "%" { // percent variable shortcut checks
                // Special-case: %* -> same as \![*] (marker)
                if i + 1 < chars.count, chars[i+1] == "*" {
                    flush()
                    tokens.append(.command(name: "!", args: ["*"]))
                    i += 2
                    continue
                }
                // Otherwise, treat as plain text; expansion happens in flush()
                buffer.append(ch)
                i += 1
                continue
            } else if ch == "\\" { // command prefix or escape sequence
                if i + 1 >= chars.count { buffer.append("\\"); break }
                let next = chars[i+1]
                // Handle escape sequences: \\, \%
                if next == "\\" { // escaped backslash → literal \
                    buffer.append("\\")
                    i += 2
                    continue
                }
                if next == "%" { // escaped percent → literal %
                    buffer.append("%")
                    i += 2
                    continue
                }
                flush()
                switch next {
                case "0", "h":
                    tokens.append(.scope(0))
                    i += 2
                case "1", "u":
                    tokens.append(.scope(1))
                    i += 2
                case "p":
                    var j = i + 2
                    var num = ""
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            num = content
                            j = end
                        }
                    } else {
                        while j < chars.count, chars[j].isNumber { num.append(chars[j]); j += 1 }
                    }
                    tokens.append(.scope(Int(num) ?? 0))
                    i = j
                case "s":
                    var j = i + 2
                    var raw = ""
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            raw = content
                            j = end
                        }
                    } else {
                        while j < chars.count, chars[j].isNumber { raw.append(chars[j]); j += 1 }
                    }
                    if let n = Int(raw) {
                        tokens.append(.surface(n))
                    } else if raw.isEmpty {
                        tokens.append(.surface(0))
                    } else {
                        // \s[alias] 非数値サーフェス別名は文字列のまま保持し、実行時に解決する
                        tokens.append(.surfaceNamed(raw))
                    }
                    i = j
                case "i":
                    var j = i + 2
                    var args: [String] = []
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                    } else {
                        var num = ""
                        while j < chars.count, chars[j].isNumber { num.append(chars[j]); j += 1 }
                        if !num.isEmpty { args = [num] }
                    }
                    if let idStr = args.first, let id = Int(idStr) {
                        let wait = args.dropFirst().first?.lowercased() == "wait"
                        tokens.append(.animation(id, wait: wait))
                    } else {
                        tokens.append(.command(name: "i", args: args))
                    }
                    i = j
                case "n":
                    let j = i + 2
                    // Check for \n[half] or \n[percent]
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            tokens.append(.newlineVariation(content))
                            i = end
                        } else {
                            tokens.append(.newline)
                            i += 2
                        }
                    } else {
                        tokens.append(.newline)
                        i += 2
                    }
                case "e":
                    tokens.append(.end)
                    i += 2
                case "4":
                    tokens.append(.moveAway)
                    i += 2
                case "5":
                    tokens.append(.moveClose)
                    i += 2
                case "w":
                    var j = i + 2
                    var num = ""
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            num = content
                            j = end
                        }
                    } else {
                        while j < chars.count, chars[j].isNumber { num.append(chars[j]); j += 1 }
                    }
                    if num.isEmpty {
                        tokens.append(.command(name: "w", args: []))
                    } else {
                        tokens.append(.command(name: "w", args: [num]))
                    }
                    i = j
                case "!":
                    var j = i + 2
                    var args: [String] = []
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                    }
                    tokens.append(.command(name: "!", args: args))
                    i = j
                case "b":
                    // Balloon ID: \bN or \b[ID] or \b[ID1,--fallback=ID2,...]
                    var j = i + 2
                    var balloonID = ""
                    if j < chars.count && chars[j] == "[" {
                        // \b[...] format
                        if let (content, end) = readBracket(start: j + 1) {
                            // For now, just take the first ID (ignore fallbacks)
                            let parts = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            balloonID = String(parts.first ?? "0")
                            j = end
                        }
                    } else if j < chars.count, chars[j].isNumber || chars[j] == "-" {
                        // \bN format (single digit or negative)
                        while j < chars.count, (chars[j].isNumber || chars[j] == "-") {
                            balloonID.append(chars[j])
                            j += 1
                        }
                    }
                    if let id = Int(balloonID) {
                        tokens.append(.balloon(id))
                    } else {
                        tokens.append(.command(name: "b", args: balloonID.isEmpty ? [] : [balloonID]))
                    }
                    i = j
                case "C":
                    // Append mode - prepend to previous balloon
                    tokens.append(.appendMode)
                    i += 2
                case "c":
                    // Text clear commands: \c or \c[char,N] or \c[char,N,start] or \c[line,N] or \c[line,N,start]
                    var j = i + 2
                    var args: [String] = []
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                    }
                    tokens.append(.command(name: "c", args: args))
                    i = j
                case "t":
                    // Quick wait / click wait
                    tokens.append(.wait)
                    i += 2
                case "x":
                    // End conversation: \x or \x[noclear]
                    var j = i + 2
                    var clearBalloon = true
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            if content.lowercased() == "noclear" {
                                clearBalloon = false
                            }
                            j = end
                        }
                    }
                    tokens.append(.endConversation(clearBalloon: clearBalloon))
                    i = j
                case "z":
                    // Choice cancellation
                    tokens.append(.choiceCancel)
                    i += 2
                case "*":
                    // Choice marker
                    tokens.append(.choiceMarker)
                    i += 2
                case "a":
                    // Anchor marker or command: \a or \a[...]
                    var j = i + 2
                    if j < chars.count && chars[j] == "[" {
                        var args: [String] = []
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                        // Route \a[...] to anchor action command path (\_a compatible handling).
                        tokens.append(.command(name: "_a", args: args))
                        i = j
                    } else {
                        tokens.append(.anchor)
                        i += 2
                    }
                case "-":
                    // Line break in choice
                    tokens.append(.choiceLineBr)
                    i += 2
                case "+":
                    // Boot/call other ghost
                    tokens.append(.bootGhost)
                    i += 2
                case "v":
                    // Open preferences/settings
                    tokens.append(.openPreferences)
                    i += 2
                case "6":
                    // Open URL
                    tokens.append(.openURL)
                    i += 2
                case "7":
                    // Open email
                    tokens.append(.openEmail)
                    i += 2
                case "8":
                    // Play sound: \8[filename]
                    var j = i + 2
                    var filename = ""
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            filename = content
                            j = end
                        }
                    }
                    tokens.append(.playSound(filename))
                    i = j
                case "q":
                    // Choice commands: \q[title,ID] or various other forms
                    var j = i + 2
                    var args: [String] = []
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                    }
                    // Special handling for \q[ID][title] format
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            // This is the title for \q[ID][title] format
                            args.append(content)
                            j = end
                        }
                    }
                    tokens.append(.command(name: "q", args: args))
                    i = j
                case "f":
                    // Font commands: \f[align,center] etc.
                    var j = i + 2
                    var args: [String] = []
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                    }
                    tokens.append(.command(name: "f", args: args))
                    i = j
                case "_":
                    // Support underscore-prefixed commands.
                    var j = i + 2
                    var name = "_"

                    if j < chars.count {
                        let c = chars[j]
                        if c == "+" {
                            tokens.append(.bootAllGhosts)
                            i = j + 1
                            continue
                        } else if c == "!" || c == "?" {
                            name.append(c)
                            j += 1
                        } else if c == "_" {
                            name.append(c)
                            j += 1
                            if j < chars.count, chars[j].isLetter {
                                name.append(chars[j])
                                j += 1
                            }
                        } else if c.isLetter {
                            name.append(c)
                            j += 1
                        }
                    }

                    // Special handling for \_! and \_? tag passthrough commands.
                    if name == "_!" || name == "_?" {
                        tokens.append(.command(name: name, args: []))
                        // Read until closing tag (same as opening tag)
                        let closingTag = "\\" + name
                        if let (passthroughText, end) = readUntilClosingTag(start: j, closingTag: closingTag) {
                            if !passthroughText.isEmpty {
                                tokens.append(.text(passthroughText))
                            }
                            tokens.append(.command(name: name, args: []))
                            i = end
                        } else {
                            // Closing tag not found, treat as regular command
                            i = j
                        }
                        continue
                    }

                    var args: [String] = []
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                    }
                    tokens.append(.command(name: name, args: args))
                    i = j
                default:
                    let name = String(next)
                    var j = i + 2
                    var args: [String] = []
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            args = parseArguments(content)
                            j = end
                        }
                    }
                    tokens.append(.command(name: name, args: args))
                    i = j
                }
            } else {
                buffer.append(ch)
                i += 1
            }
        }
        flush()
        let merged = Self.mergeChoiceQueueRanges(tokens)
        return Self.resolveScriptLabelJumps(merged)
    }

    // Note: Do not attempt to auto-normalize scripts; adhere to UKADOC.

    /// `\__q` の範囲ベース構文（`\__q[ID,...]text\__q`）を1トークンにマージする。
    ///
    /// UKADOC (SAKURASCRIPT_FULL §\__q): `\__q` がくるまでの範囲を選択肢の表示テキストとする。
    /// 開始タグ `.command("__q", non-empty args)` と閉じタグ `.command("__q", [])` に挟まれた
    /// テキスト系トークンを結合して title とし、`.choiceQueue` に変換する。
    /// 単一形式（閉じタグなし）も title="" の `.choiceQueue` に変換する。
    /// ID の取扱いは `\q` と同じ: args[0]=ID, args[1...]=references。
    private static func mergeChoiceQueueRanges(_ tokens: [Token]) -> [Token] {
        var result: [Token] = []
        result.reserveCapacity(tokens.count)
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if case .command(let name, let args) = token, name == "__q" {
                if args.isEmpty {
                    // 単独の閉じタグ（開始タグなし）は無視して捨てる
                    i += 1
                    continue
                }
                // 後続トークンから閉じタグ .command("__q", []) を探す
                var j = i + 1
                var titleParts: [String] = []
                var closingIndex: Int? = nil
                while j < tokens.count {
                    let t = tokens[j]
                    if case .command(let n, let a) = t, n == "__q", a.isEmpty {
                        closingIndex = j
                        break
                    }
                    switch t {
                    case .text(let s):
                        titleParts.append(s)
                    case .newline, .newlineVariation:
                        titleParts.append("\n")
                    default:
                        // \s, \i, \_l 等の制御/リッチ要素は title から除外（プレーンテキスト化）
                        break
                    }
                    j += 1
                }
                let id = args[0]
                let references = Array(args.dropFirst())
                let title = closingIndex != nil ? titleParts.joined() : ""
                result.append(.choiceQueue(title: title, id: id, references: references))
                i = (closingIndex ?? i) + 1
                continue
            }
            result.append(token)
            i += 1
        }
        return result
    }

    /// `\j[ID]` のうち、URL/file/mailto でも On* イベントでもないものを、
    /// 同一スクリプト内で確認できる ID 付きアンカー位置へ解決する。
    ///
    /// UKADOC の `\j` 節は「IDにジャンプする」とだけ規定し、ラベル専用タグ名は
    /// 明示していない。ここでは docs で ID 付き範囲として確認できる `\_a[ID]...\_a`
    /// だけをジャンプ先として扱い、未知のラベル定義構文は追加しない。
    private static func resolveScriptLabelJumps(_ tokens: [Token]) -> [Token] {
        let labels = scriptLabelIndexes(in: tokens)
        guard !labels.isEmpty else { return tokens }

        var result: [Token] = []
        result.reserveCapacity(tokens.count)
        var i = 0
        var visitedJumpIndexes: Set<Int> = []

        while i < tokens.count {
            if case .command(let name, let args) = tokens[i],
               name.lowercased() == "j",
               let target = normalizedJumpTarget(args),
               isLocalScriptJumpTarget(target),
               let destination = labels[target] {
                if visitedJumpIndexes.contains(i) {
                    // 後方ジャンプ等で同じ \j に戻った場合は無限再生を避けるため当該ジャンプだけ捨てる。
                    i += 1
                } else {
                    visitedJumpIndexes.insert(i)
                    i = destination
                }
                continue
            }
            result.append(tokens[i])
            i += 1
        }
        return result
    }

    private static func scriptLabelIndexes(in tokens: [Token]) -> [String: Int] {
        var labels: [String: Int] = [:]
        for (index, token) in tokens.enumerated() {
            guard case .command(let name, let args) = token,
                  name.lowercased() == "_a",
                  let target = normalizedJumpTarget(args),
                  isLocalScriptJumpTarget(target),
                  labels[target] == nil else { continue }
            labels[target] = index
        }
        return labels
    }

    private static func normalizedJumpTarget(_ args: [String]) -> String? {
        guard let first = args.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else {
            return nil
        }
        return first
    }

    private static func isLocalScriptJumpTarget(_ target: String) -> Bool {
        return !isExternalOpenTarget(target) && !isEventJumpTarget(target)
    }

    private static func isExternalOpenTarget(_ target: String) -> Bool {
        let lowered = target.lowercased()
        return lowered.hasPrefix("http://")
            || lowered.hasPrefix("https://")
            || lowered.hasPrefix("file://")
            || lowered.hasPrefix("mailto:")
    }

    private static func isEventJumpTarget(_ target: String) -> Bool {
        let lowered = target.lowercased()
        return !target.hasPrefix("\\") && lowered.hasPrefix("on")
    }

    /// Split a comma separated argument string with quoting rules.
    /// - Arguments separated by commas
    /// - Arguments can be quoted with "" to allow commas inside
    /// - Inside quotes, "" becomes a literal "
    private func parseArguments(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var bracketDepth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\"" {
                if quoted {
                    // Inside quotes: check for escaped quote ""
                    let next = s.index(after: i)
                    if next < s.endIndex && s[next] == "\"" {
                        // "" inside quotes → literal "
                        current.append("\"")
                        i = next
                    } else {
                        // End of quoted section
                        quoted = false
                    }
                } else {
                    // Start of quoted section
                    quoted = true
                }
            } else if !quoted && ch == "[" {
                bracketDepth += 1
                current.append(ch)
            } else if !quoted && ch == "]" {
                if bracketDepth > 0 { bracketDepth -= 1 }
                current.append(ch)
            } else if ch == "," && !quoted && bracketDepth == 0 {
                // Unquoted comma → argument separator
                result.append(current)
                current.removeAll()
            } else {
                current.append(ch)
            }
            i = s.index(after: i)
        }
        if !current.isEmpty || !result.isEmpty {
            result.append(current)
        }
        return result
    }
}
