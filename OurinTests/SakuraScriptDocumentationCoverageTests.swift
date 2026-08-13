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
