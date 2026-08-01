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

    private struct Example: Hashable {
        let line: Int
        let source: String
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
