import Foundation
import Testing

/// yaya_core の埋め込み要素 `%(…)` が YAYA 本家と同じく、名前に関係なく YAYA の式として評価されることを確認する。
/// 本家は `CParser0::ConvertEmbedStringToFormula` で `%(…)` を `TOSTR(…)` に変換する。
/// SSP の環境変数と同じ名前（username など）を残していたため、Taromati2 の「%(username)君」が展開されなかった回帰テスト。
struct YayaEmbeddedElementTests {
    @Test
    func parenthesizedEmbedEvaluatesNamesSharedWithSspVariables() throws {
        let value = try evaluate("""
        Test
        {
        	username = 'お兄さん'
        	selfname = 'さくら'
        	"[%(username)]|%(username)君|%(selfname)|%(STRLEN(username))|%[0]"
        }
        """)
        #expect(value == "[お兄さん]|お兄さん君|さくら|4|4")
    }

    @Test
    func bareSspVariablesAreLeftForBaseware() throws {
        let value = try evaluate("""
        Test
        {
        	_n = 'x'
        	"%username|%selfname|%month|%(_n)|%[0]"
        }
        """)
        #expect(value == "%username|%selfname|%month|x|x")
    }

    @Test
    func undefinedGlobalInParenthesizedEmbedBecomesEmpty() throws {
        // 本家では未定義の名前はグローバル変数として作られ、TOSTR で空文字列になる。
        let value = try evaluate("""
        Test
        {
        	"[%(keroname)]|[%(property[0])]"
        }
        """)
        #expect(value == "[]|[]")
    }

    private func evaluate(_ dictionary: String) throws -> String {
        let core = try YayaCoreLineHarness(name: "Embed", dictionary: dictionary)
        defer { core.close() }
        let loaded = try core.load()
        #expect(loaded["ok"] as? Bool == true)
        let response = try core.request(id: "Test")
        return try #require(response["value"] as? String)
    }
}
