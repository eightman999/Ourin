import Testing
@testable import Ourin

struct PropertyTests {
    @Test
    func basewareName() async throws {
        let mgr = PropertyManager()
        #expect(mgr.get("baseware.name") == "Ourin")
    }

    @Test
    func ghostlistCount() async throws {
        let mgr = PropertyManager()
        #expect(mgr.get("ghostlist.count") == "1")
    }

    @Test
    func nameParametersPreserveOriginalCase() async throws {
        // 構造部分は小文字化されるが、括弧内の名前パラメータ（shelllist(MyShell) 等）は
        // 原文のままプロバイダへ渡されることを検証する（GhostPropertyProvider の
        // case-sensitive name 照合を破壊しないため）。
        let mgr = PropertyManager()
        final class EchoProvider: PropertyProvider {
            var lastKey = ""
            func get(key: String) -> String? { lastKey = key; return "[\(key)]" }
            func set(key: String, value: String) -> Bool { lastKey = key; return true }
        }
        let provider = EchoProvider()
        mgr.register("testns", provider: provider)
        // 名前パラメータ "MyShell" が小文字化されず届く
        _ = mgr.get("TestNS.ShellList(MyShell).menu")
        #expect(provider.lastKey == "shelllist(MyShell).menu")
    }
}
