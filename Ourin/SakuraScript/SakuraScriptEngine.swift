import Foundation

/// Delegate notified for each parsed token.
public protocol SakuraScriptEngineDelegate: AnyObject {
    func sakuraEngine(_ engine: SakuraScriptEngine, didEmit token: SakuraScriptEngine.Token)
}

/// SakuraScript parser and executor.
public final class SakuraScriptEngine {
    public weak var delegate: SakuraScriptEngineDelegate?
    /// Property manager used for `%property[...]` expansion in text.
    public var propertyManager: PropertyManager = PropertyManager()

    public init() {}

    /// Parse given script and notify delegate token by token.
    public func run(script: String) {
        for token in parse(script: script) {
            delegate?.sakuraEngine(self, didEmit: token)
        }
    }

    // MARK: - Parsing

    /// Individual SakuraScript token.
    public enum Token: Equatable {
        case text(String)
        case scope(Int)
        case surface(Int)
        case animation(Int, wait: Bool)
        case newline
        case end
        case command(name: String, args: [String])
    }

    /// Parse a SakuraScript string into tokens.
    func parse(script: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        let chars = Array(script)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            tokens.append(.text(propertyManager.expand(text: buffer)))
            buffer.removeAll()
        }

        func readBracket(start: Int) -> (String, Int)? {
            var j = start
            var result = ""
            while j < chars.count {
                let c = chars[j]
                if c == "\\" && j + 1 < chars.count && chars[j+1] == "]" {
                    result.append("]")
                    j += 2
                    continue
                }
                if c == "]" {
                    return (result, j + 1)
                }
                result.append(c)
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" { // command prefix
                if i + 1 >= chars.count { buffer.append("\\"); break }
                let next = chars[i+1]
                if next == "\\" { // escaped backslash
                    buffer.append("\\")
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
                    var num = ""
                    if j < chars.count && chars[j] == "[" {
                        if let (content, end) = readBracket(start: j + 1) {
                            num = content
                            j = end
                        }
                    } else {
                        while j < chars.count, chars[j].isNumber { num.append(chars[j]); j += 1 }
                    }
                    tokens.append(.surface(Int(num) ?? 0))
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
                    tokens.append(.newline)
                    i += 2
                case "e":
                    tokens.append(.end)
                    i += 2
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
                default:
                    var name = String(next)
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
        return tokens
    }

    /// Split a comma separated argument string with simple quoting rules.
    private func parseArguments(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\"" {
                if quoted {
                    let next = s.index(after: i)
                    if next < s.endIndex && s[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else {
                        quoted = false
                    }
                } else {
                    quoted = true
                }
            } else if ch == "," && !quoted {
                result.append(current)
                current.removeAll()
            } else {
                current.append(ch)
            }
            i = s.index(after: i)
        }
        result.append(current)
        return result
    }
}
