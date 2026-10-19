import Foundation
import Testing

/// yaya_core の文字列・時刻・正規表現の組み込み関数が YAYA 本家と同じ値を返すことを確認する。
/// 実ゴースト（Emily/Phase4.5）の起動トークが空になる・壊れる原因になった挙動の回帰テスト。
struct YayaBuiltinCompatibilityTests {
    @Test
    func stringLiteralsKeepBackslashesAndDoubleQuotesToEscape() throws {
        let value = try evaluate(#"""
        Test
        {
        	STRLEN('\\p') + '|' + STRLEN("\\p") + '|' + "1""2" + '|' + '1''2' + '|' + STRLEN('\')
        }
        """#)
        #expect(value == #"3|3|1"2|1'2|1"#)
    }

    @Test
    func gettimeReturnsYayaArrayAndSupportsDirectIndex() throws {
        let value = try evaluate("""
        Test
        {
        	_g = GETTIME
        	ARRAYSIZE(_g) + '|' + (GETTIME[4] * 100 + GETTIME[5] == _g[4] * 100 + _g[5]) + '|' + GETTIME(0)[0]
        }
        """)
        let parts = value.split(separator: "|").map(String.init)
        #expect(parts.count == 3)
        #expect(parts.first == "9")
        // 分の境界をまたいだ場合だけ一致しない。GETTIME(0) は 1970 年（ローカル時刻）。
        #expect(parts.last == "1970" || parts.last == "1969")
    }

    @Test
    func reSplitExposesSeparatorsThroughReGetstr() throws {
        let value = try evaluate(#"""
        Test
        {
        	_a = RE_SPLIT('\u\s[10]\h\s[5]X','\\_*[0-9a-z!?]\[.+?\]')
        	_t = RE_GETSTR
        	ARRAYSIZE(_a) + '/' + ARRAYSIZE(_t) + ':' + _t[0] + _t[1] + '|' + ARRAYSIZE(RE_SPLIT('a,b,c', ',', 2))
        }
        """#)
        #expect(value == #"3/2:\s[10]\s[5]|2"#)
    }

    @Test
    func positionsAndRegexClassesCountCharactersNotBytes() throws {
        let value = try evaluate(#"""
        Test
        {
        	_hit = RE_SEARCH('おすしー！（H5）','[(（](.+?[\|｜].+?|[HＨ][0-9０-９]+)[)）]')
        	_pos = RE_GETPOS[0] + ',' + RE_GETLEN[0]
        	_miss = RE_SEARCH('やったー！\w9','[(（](.+?[\|｜].+?|[HＨ][0-9０-９]+)[)）]')
        	_hit + ':' + _pos + '|' + _miss + '|' + STRSTR('あいう','う',0) + '|' + ARRAYSIZE(RE_SPLIT('1' + CHR(1) + '2','[\x1,]'))
        }
        """#)
        #expect(value == "1:5,4|0|2|2")
    }

    @Test
    func arrayFunctionConcatenatesArrayCandidatesInsteadOfNesting() throws {
        // 本家の例: request : array { "This is a pen." ("A","B","C") 3.14 } → 5 要素。
        let value = try evaluate("""
        Test
        {
        	_a = Candidates
        	_e = Empty
        	ARRAYSIZE(_a) + ':' + _a[1] + _a[2] + '|' + GETTYPE(_a[1]) + '|' + ARRAYSIZE(_e)
        }
        Candidates : array
        {
        	'x'
        	('p','q')
        	IARRAY
        }
        Empty : array
        {
        	if 0 {
        		'a'
        	}
        	else {
        		IARRAY
        	}
        }
        """)
        #expect(value == "3:pq|3|0")
    }

    private func evaluate(_ dictionary: String) throws -> String {
        let core = try YayaCoreLineHarness(name: "Builtin", dictionary: dictionary)
        defer { core.close() }
        let loaded = try core.load()
        #expect(loaded["ok"] as? Bool == true)
        let response = try core.request(id: "Test")
        return try #require(response["value"] as? String)
    }
}
