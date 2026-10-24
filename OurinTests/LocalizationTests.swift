import Foundation
import Testing
@testable import Ourin

/// UI の多言語化（#164）。
struct LocalizationTests {
    private static let languages = ["en", "ja", "zh-Hans", "zh-Hant", "ko"]

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func table(_ language: String) throws -> [String: String] {
        let url = repositoryRoot.appendingPathComponent("Ourin/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String], "\(language)")
    }

    @Test
    func everyLanguageHasTheSameKeys() throws {
        let english = try Self.table("en")
        #expect(english.count > 400)
        for language in Self.languages {
            let keys = Set(try Self.table(language).keys)
            #expect(keys == Set(english.keys), "\(language): missing \(Set(english.keys).subtracting(keys).sorted().prefix(5)) extra \(keys.subtracting(english.keys).sorted().prefix(5))")
        }
    }

    @Test
    func formatSpecifiersMatchTheKeyInEveryLanguage() throws {
        let pattern = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:lld|ld|d|@|f|lf|s)"#)
        func specifiers(_ text: String) -> [String] {
            pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range) }.sorted()
        }
        for language in Self.languages {
            for (key, value) in try Self.table(language) {
                #expect(specifiers(value) == specifiers(key), "\(language): \(key) → \(value)")
            }
        }
    }

    @Test
    func uiStringsInTheSourceHaveEnglishTranslations() throws {
        let english = try Self.table("en")
        let source = Self.repositoryRoot.appendingPathComponent("Ourin")
        let ui = try NSRegularExpression(pattern: #"\b(?:Text|Button|Toggle|Picker|TextField|SecureField|Menu|Section|Label|TableColumn|navigationTitle|help|LocalizedStringKey)\s*\(\s*"((?:[^"\\]|\\.)*)""#)
        let localized = try NSRegularExpression(pattern: #"NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)""#)
        let japanese = try NSRegularExpression(pattern: #"[぀-ヿ一-鿿]"#)
        var missing: [String] = []
        let files = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(files.count > 100)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                let range = NSRange(line.startIndex..., in: line)
                let keys = (ui.matches(in: line, range: range) + localized.matches(in: line, range: range))
                    .map { (line as NSString).substring(with: $0.range(at: 1)) }
                    .filter { !$0.contains("\\(") } // 補間付きは書式のキー（%@ など）で別に載せている
                    // ソースのエスケープ（\\n・\\"・\\\\）を、表のキーと同じ実際の文字にする。
                    .map { $0.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") }
                for key in keys where japanese.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil {
                    if english[key] == nil { missing.append("\(file.lastPathComponent): \(key)") }
                }
            }
        }
        #expect(missing.isEmpty, "\(missing.prefix(10))")
    }

    @Test
    func languageChangeReportsTheLanguageUsedForDisplay() throws {
        let info = SystemNotificationData.currentLanguageInfo(bundle: .main)
        let expected = try #require(Bundle.main.preferredLocalizations.first(where: { $0 != "Base" }))
        #expect(info.languageID == expected)
        #expect(!info.languageName.isEmpty)
        #expect(info.resourcePath.hasSuffix("/\(expected).lproj"))
        // 同梱しているすべての言語の lproj がある。
        for language in Self.languages {
            #expect(Bundle.main.path(forResource: language, ofType: "lproj") != nil, "\(language)")
        }
    }

    @Test
    func bundledTranslationsResolveForEachLanguage() throws {
        for (language, expected) in [("en", "Quit(Q)"), ("ja", "終了(Q)"), ("zh-Hans", "退出(Q)"), ("zh-Hant", "結束(Q)"), ("ko", "종료(Q)")] {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: "終了(Q)", value: nil, table: nil) == expected, "\(language)")
        }
    }
}
