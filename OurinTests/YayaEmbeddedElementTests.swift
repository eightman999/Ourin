import Foundation
import Testing

/// yaya_core の文字列の埋め込み要素が YAYA 本家と同じ規則で展開されることを確認する。
/// - `%(…)` は名前に関係なく式として評価する（`CParser0::ConvertEmbedStringToFormula` で `TOSTR(…)`）。
/// - 括弧なしの `%名前` は、実行時にある変数・関数・システム関数の名前の最長一致で展開し、
///   一致しなければ `%` を含めてそのまま残す（`CFunction::SolveEmbedCell`）。
/// - `%[n]` は括弧なしの埋め込みだけを、文字列の先頭から 0 始まりで数える。
/// - シングルクォートの文字列は埋め込みを展開しない。
/// 例は yaya-docs の「文字列内埋め込み要素の展開」から取った。
struct YayaEmbeddedElementTests {
    @Test
    func parenthesizedEmbedEvaluatesNamesSharedWithSspVariables() throws {
        let value = try evaluate("""
        Test
        {
        	username = 'お兄さん'
        	selfname = 'さくら'
        	"[%(username)]|%(username)君|%(selfname)|%(STRLEN(username))"
        }
        """)
        #expect(value == "[お兄さん]|お兄さん君|さくら|4")
    }

    @Test
    func bareSspVariablesAreLeftForBaseware() throws {
        // YAYA に同じ名前が無ければ、SSP の環境変数は % ごとベースウェアへ渡る。
        let value = try evaluate("""
        Test
        {
        	"%username|%selfname|%month|%charname(0)|50%|a%%b"
        }
        """)
        #expect(value == "%username|%selfname|%month|%charname(0)|50%|a%%b")
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

    @Test
    func bareEmbedUsesLongestMatchingName() throws {
        let value = try evaluate("""
        Test
        {
        	o      = "pen"
        	obj    = "eraser"
        	object = "world"
        	_name  = 'x'
        	arr    = ('a', 'b')
        	"This is a %object.|%_name|%_namex|%_nam|%STRLEN('abc')|%arr[1]x"
        }
        obje
        {
        	"television"
        }
        """)
        #expect(value == "This is a world.|x|xx|%_nam|3|bx")
    }

    @Test
    func bareEmbedFollowsVariablesAtRuntime() throws {
        let value = try evaluate("""
        Test
        {
        	val   = "red"
        	trans
        	--
        	value = "blue"
        	trans
        	--
        	_r = ERASEVAR('value') + ERASEVAR('val')
        	"|" + trans
        }
        trans
        {
        	"%value"
        }
        """)
        #expect(value == "redueblue|%value")
    }

    @Test
    func yayaNameSharedWithSspVariableIsExpandedOnlyOutsideSingleQuotes() throws {
        let value = try evaluate(#"""
        Test
        {
        	username = 'お兄さん'
        	_plain = <<'
        [%username]
        '>>
        	_double = <<"
        [%username]
        ">>
        	"[%username]" + '[%username]' + '[%(username)]|' + _plain + '|' + _double
        }
        """#)
        let parts = value.split(separator: "|").map { $0.trimmingCharacters(in: .newlines) }
        #expect(parts == ["[お兄さん][%username][%(username)]", "[%username]", "[お兄さん]"])
    }

    @Test
    func bracketsAfterNameAreCountedLikeYaya() throws {
        // 本家は名前の直後を確かめずに ( ) と [ ] を数えるので、`%username,0]` は式として読めず文字列のまま残る。
        let value = try evaluate(#"""
        Test
        {
        	username = 'U'
        	"\![set,x,%username,0]|\q[%username]|%username(z)"
        }
        """#)
        #expect(value == #"\![set,x,%username,0]|\q[U]|U(z)"#)
    }

    @Test
    func historyCountsBareEmbedsFromTheStart() throws {
        let value = try evaluate("""
        Test
        {
        	"「%planet」は遠い。「%city」も遠い。もっとも%[1]になら行けなくもない。%[0]"
        }
        planet
        {
        	"mars"
        }
        city
        {
        	"newyork"
        }
        """)
        #expect(value == "「mars」は遠い。「newyork」も遠い。もっともnewyorkになら行けなくもない。mars")
    }

    @Test
    func historySkipsParenthesizedEmbedsAndCountsUnmatchedText() throws {
        // %(…) は数えない（本家では前に括弧なしの埋め込みが無い %[n] は読み込み時に E0081）。
        // 一致しなかった %名前 は、続く文字列ごと 1 つと数える。
        let value = try evaluate("""
        Test
        {
        	object = 'world'
        	"%(1)%[0]|%zzz|%object|%[0]|%[1]|%[2]"
        }
        """)
        #expect(value == "1%[0]|%zzz|world|%zzz||world|%[2]")
    }

    @Test
    func bareEmbedReadsReferences() throws {
        let value = try evaluate("""
        Test
        {
        	"%reference[0]|%reference[1]"
        }
        """, references: ["r0", "r1"])
        #expect(value == "r0|r1")
    }

    private func evaluate(_ dictionary: String, references: [String] = []) throws -> String {
        let core = try YayaCoreLineHarness(name: "Embed", dictionary: dictionary)
        defer { core.close() }
        let loaded = try core.load()
        #expect(loaded["ok"] as? Bool == true)
        let response = try core.request(id: "Test", references: references)
        return try #require(response["value"] as? String)
    }
}
