import Foundation
import Testing
@testable import Ourin

/// `docs/SAKURASCRIPT_COMMANDS_SUPPORTED_ja-jp.md` の例とパーサーの同期を検証する。
///
/// このテストは実行結果の互換性ではなく、ドキュメントに掲載した構文例が
/// SakuraScriptEngine の制御トークンへ到達することを検証する。実行レベルの
/// 挙動は GhostManager 側の個別テスト／実ゴースト試験で別途確認する。
struct SakuraScriptDocumentationCoverageTests {
    @Test
    func documentedInlineExamplesProduceControlTokens() throws {
        let documentationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/SAKURASCRIPT_COMMANDS_SUPPORTED_ja-jp.md")
        let documentation = try String(contentsOf: documentationURL, encoding: .utf8)
        let examples = Self.extractInlineExamples(from: documentation)
        #expect(examples.count >= 80)

        let engine = SakuraScriptEngine()
        var failures: [String] = []
        for example in examples {
            let tokens = engine.parse(script: example.source, expandEnvironment: false)
            let hasControlToken = tokens.contains { token in
                switch token {
                case .text(_):
                    return false
                default:
                    return true
                }
            }

            // `\\` と `\%` は仕様上リテラル文字列へ変換されるため、制御トークン不要。
            let isLiteralEscape = example.source == "\\\\"
                || example.source == "\\%"
                || example.source.allSatisfy { $0 == "\\" }
                || example.source.contains("C:\\\\")
                || example.source.contains("100\\%")
            if tokens.isEmpty || (!hasControlToken && !isLiteralEscape) {
                failures.append("line \(example.line): `\(example.source)` -> \(tokens)")
            }
        }

        // 失敗時は件数を含めた配列をデバッガで確認できるよう保持し、
        // Swift Testingの動的Comment変換に依存せずアサートする。
        #expect(failures.isEmpty, Comment(rawValue: failures.joined(separator: "\n")))
    }

    @Test
    func fullUkadocBangCommandsHaveRuntimeDispatch() throws {
        let projectRoot = Self.projectRoot
        let documentationURL = projectRoot
            .appendingPathComponent("docs/SAKURASCRIPT_FULL_1.0M_PATCHED_ja-jp.md")
        let runtimeURL = projectRoot.appendingPathComponent("Ourin/Ghost/GhostManager.swift")
        let documentation = try String(contentsOf: documentationURL, encoding: .utf8)
        let runtimeSource = try String(contentsOf: runtimeURL, encoding: .utf8)
        let tags = Self.extractBangTags(from: documentation)
        #expect(tags.count >= 300)

        let engine = SakuraScriptEngine()
        var parseFailures: [String] = []
        var documentedCommands = Set<String>()
        for tag in tags {
            let tokens = engine.parse(script: tag.source, expandEnvironment: false)
            guard let command = tokens.first(where: { token in
                if case .command(let name, _) = token { return name == "!" }
                return false
            }) else {
                parseFailures.append("line \(tag.line): `\(tag.source)` -> \(tokens)")
                continue
            }

            if case .command(_, let args) = command, let first = args.first {
                // `move(async)` はUKADOCの記法上の説明であり、実行タグは `move`。
                let commandName = first
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true)
                    .first
                    .map(String.init) ?? ""
                if !commandName.isEmpty {
                    documentedCommands.insert(commandName)
                }
            }
        }
        #expect(parseFailures.isEmpty, Comment(rawValue: parseFailures.joined(separator: "\n")))

        let runtimeCommands = Self.firstArgumentDispatches(in: runtimeSource)
        let missing = documentedCommands.subtracting(runtimeCommands).sorted()
        #expect(missing.isEmpty, Comment(rawValue: "Full UKADOC commands without GhostManager dispatch: \(missing.joined(separator: ", "))"))
    }

    @Test
    func fullUkadocCompoundBangCommandsHaveSecondArgumentDispatch() throws {
        let projectRoot = Self.projectRoot
        let documentationURL = projectRoot
            .appendingPathComponent("docs/SAKURASCRIPT_FULL_1.0M_PATCHED_ja-jp.md")
        let documentation = try String(contentsOf: documentationURL, encoding: .utf8)
        let runtimeSource = try Self.ghostManagerSources(in: projectRoot)
        let engine = SakuraScriptEngine()

        // ここに含めるのは、UKADOC上で第2引数が固定のサブコマンド／対象を
        // 表す親だけ。raise/event や open/URL のような自由値は対象外とする。
        let compoundParents: Set<String> = [
            "anim", "call", "change", "close", "create", "enter", "execute", "get",
            "leave", "load", "lock", "moveasync", "open", "reload", "reset", "restore",
            "save", "set", "signal", "sound", "unload", "unlock", "update", "wait"
        ]

        var documentedPairs: [CompoundCommand: Example] = [:]
        for tag in Self.extractBangTags(from: documentation) {
            guard let arguments = Self.bangArguments(from: tag.source, engine: engine),
                  arguments.count >= 2 else { continue }
            let first = arguments[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let second = arguments[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard compoundParents.contains(first),
                  second.range(of: #"^[a-z][a-z0-9_-]*$"#, options: .regularExpression) != nil,
                  !(first == "open" && second == "url") else { continue }
            documentedPairs[CompoundCommand(first: first, second: second)] = tag
        }

        #expect(documentedPairs.count >= 100)

        let missing = documentedPairs.keys
            .filter { !Self.hasSecondArgumentDispatch(first: $0.first, second: $0.second, in: runtimeSource) }
            .sorted { lhs, rhs in
                lhs.first == rhs.first ? lhs.second < rhs.second : lhs.first < rhs.first
            }
            .map { pair in
                let example = documentedPairs[pair]!
                return "line \(example.line): \\![\(pair.first),\(pair.second)]"
            }

        #expect(
            missing.isEmpty,
            Comment(rawValue: "Full UKADOC compound commands without second-argument dispatch: \(missing.joined(separator: ", "))")
        )
    }

    private struct CompoundCommand: Hashable {
        let first: String
        let second: String
    }

    private struct Example: Hashable {
        let line: Int
        let source: String
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func firstArgumentDispatches(in source: String) -> Set<String> {
        let pattern = #"first\s*==\s*\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let searchRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var result: Set<String> = Set(regex.matches(in: source, range: searchRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return source[range].lowercased()
        })

        // \\![*] は通常の `first == "..."` ではなく、マーカー集合で処理される。
        if source.contains("[\"*\", \"#\", \"x\", \"<\", \">\"].contains(first)") {
            result.insert("*")
        }
        return result
    }

    private static func bangArguments(from source: String, engine: SakuraScriptEngine) -> [String]? {
        guard let token = engine.parse(script: source, expandEnvironment: false).first(where: { token in
            if case .command(let name, _) = token { return name.lowercased() == "!" }
            return false
        }), case .command(_, let arguments) = token else { return nil }
        return arguments
    }

    private static func ghostManagerSources(in projectRoot: URL) throws -> String {
        let ghostDirectory = projectRoot.appendingPathComponent("Ourin/Ghost", isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: ghostDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let name = url.lastPathComponent
            return url.pathExtension == "swift" && (name == "GhostManager.swift" || name.hasPrefix("GhostManager+"))
        }
        .sorted { $0.path < $1.path }
        return try urls.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    private static func hasSecondArgumentDispatch(first: String, second: String, in source: String) -> Bool {
        let scopes = dispatchScopes(for: first, in: source)
        let escapedSecond = NSRegularExpression.escapedPattern(for: second)
        let equalityPattern = "\\b[A-Za-z_][A-Za-z0-9_?.\\[\\]]*\\s*(?:\\.lowercased\\(\\))?\\s*==\\s*\"\(escapedSecond)\""
        let casePattern = "(?:\\bcase|,)\\s*\"\(escapedSecond)\""
        let branchConditionPattern = "first\\s*==\\s*\"\(NSRegularExpression.escapedPattern(for: first))\"[^\\n{]*\\b[A-Za-z_][A-Za-z0-9_?.\\[\\]]*\\s*(?:\\.lowercased\\(\\))?\\s*==\\s*\"\(escapedSecond)\""
        let equalityRegex = try? NSRegularExpression(pattern: equalityPattern)
        let caseRegex = try? NSRegularExpression(pattern: casePattern)
        let branchConditionRegex = try? NSRegularExpression(pattern: branchConditionPattern)

        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        if let branchConditionRegex, branchConditionRegex.firstMatch(in: source, range: fullRange) != nil {
            return true
        }

        return scopes.contains { scope in
            let range = NSRange(scope.startIndex..<scope.endIndex, in: scope)
            if let equalityRegex, equalityRegex.firstMatch(in: scope, range: range) != nil {
                return true
            }
            if let caseRegex, caseRegex.firstMatch(in: scope, range: range) != nil {
                return true
            }

            // execute の http/rss 系は、個別の文字列ではなく共通 prefix で
            // ディスパッチしているため、カテゴリ単位の実装も認める。
            if first == "execute" && second.hasPrefix("http-") && scope.contains("subcmd.hasPrefix(\"http-\")") {
                return true
            }
            if first == "execute" && second.hasPrefix("rss-") && scope.contains("subcmd.hasPrefix(\"rss-\")") {
                return true
            }
            return false
        }
    }

    private static func dispatchScopes(for first: String, in source: String) -> [String] {
        var scopes: [String] = []
        let escapedFirst = NSRegularExpression.escapedPattern(for: first)
        let branchPattern = "first\\s*==\\s*\"\(escapedFirst)\""
        if let regex = try? NSRegularExpression(pattern: branchPattern) {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                guard let matchRange = Range(match.range, in: source),
                      let scope = braceScopedSource(after: matchRange.upperBound, in: source) else { continue }
                scopes.append(scope)
            }
        }

        let helperNames: [String: [String]] = [
            "anim": ["executeAnimationCommand"],
            "execute": ["executeSakuraScriptExecuteCommand"],
            "load": ["executeLoad"],
            "lock": ["executeLockCommand"],
            "reload": ["executeReload"],
            "sound": ["executeSoundCommand"],
            "unload": ["executeUnload"],
            "unlock": ["executeUnlockCommand"],
            "update": ["executeUpdate"]
        ]
        for helperName in helperNames[first, default: []] {
            scopes.append(contentsOf: functionBodies(named: helperName, in: source))
        }
        return scopes
    }

    private static func functionBodies(named name: String, in source: String) -> [String] {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(pattern: "\\bfunc\\s+\(escapedName)\\s*\\(") else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: source) else { return nil }
            return braceScopedSource(after: matchRange.upperBound, in: source)
        }
    }

    private static func braceScopedSource(after start: String.Index, in source: String) -> String? {
        var cursor = start
        var openingBrace: String.Index?
        while cursor < source.endIndex {
            if source[cursor] == "{" {
                openingBrace = cursor
                break
            }
            cursor = source.index(after: cursor)
        }
        guard let openingBrace else { return nil }

        var depth = 0
        var index = openingBrace
        var inString = false
        var escaped = false
        var inLineComment = false
        var inBlockComment = false
        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            let nextCharacter = next < source.endIndex ? source[next] : nil

            if inLineComment {
                if character == "\n" { inLineComment = false }
                index = next
                continue
            }
            if inBlockComment {
                if character == "*", nextCharacter == "/" {
                    inBlockComment = false
                    index = source.index(after: next)
                } else {
                    index = next
                }
                continue
            }
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }
            if character == "/", nextCharacter == "/" {
                inLineComment = true
                index = source.index(after: next)
                continue
            }
            if character == "/", nextCharacter == "*" {
                inBlockComment = true
                index = source.index(after: next)
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            }
            index = next
        }
        return nil
    }

    private static func extractBangTags(from markdown: String) -> [Example] {
        var result: [Example] = []
        var seen = Set<String>()

        for (lineIndex, line) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let characters = Array(line)
            guard characters.count >= 3 else { continue }
            var cursor = 0
            while cursor + 2 < characters.count {
                guard characters[cursor] == "\\",
                      characters[cursor + 1] == "!",
                      characters[cursor + 2] == "[" else {
                    cursor += 1
                    continue
                }

                var depth = 1
                var end = cursor + 3
                while end < characters.count {
                    if characters[end] == "\\", end + 1 < characters.count, characters[end + 1] == "]" {
                        end += 2
                        continue
                    }
                    if characters[end] == "[" {
                        depth += 1
                    } else if characters[end] == "]" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    end += 1
                }

                guard end < characters.count, depth == 0 else { break }
                let source = String(characters[cursor...end])
                if seen.insert(source).inserted {
                    result.append(Example(line: lineIndex + 1, source: source))
                }
                cursor = end + 1
            }
        }
        return result
    }

    private static func extractInlineExamples(from markdown: String) -> [Example] {
        var result: [Example] = []
        var seen = Set<String>()

        for (index, line) in markdown.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let characters = Array(line)
            var cursor = 0
            while cursor < characters.count {
                guard let startOffset = characters[cursor...].firstIndex(of: "`") else { break }
                let contentStart = startOffset + 1
                guard let endOffset = characters[contentStart...].firstIndex(of: "`") else { break }
                let source = String(characters[contentStart..<endOffset])
                if (source.contains("\\") || source.contains("%*")),
                   !source.contains("→"),
                   !source.isEmpty,
                   seen.insert(source).inserted {
                    result.append(Example(line: index + 1, source: source))
                }
                cursor = endOffset + 1
            }
        }
        return result
    }
}
