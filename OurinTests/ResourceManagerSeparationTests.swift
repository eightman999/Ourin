import Testing
import Foundation
@testable import Ourin

/// SHIORI Resource のゴースト別分離（`OurinResource.<ghostKey>.<key>` 名前空間）と
/// 旧グローバルキーからの初回 backfill の検証。
/// UserDefaults はテスト専用 suite を使い、実環境の値を汚さない。
struct ResourceManagerSeparationTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "OurinTests.ResourceManager.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return (d, suite)
    }

    @Test
    func ghostsDoNotShareResourceValues() {
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let ghostA = ResourceManager(defaults: defaults, ghostKey: "emily4")
        let ghostB = ResourceManager(defaults: defaults, ghostKey: "sakura")

        ghostA.set("username", value: "Alice")
        ghostB.set("username", value: "Bob")

        #expect(ghostA.get("username") == "Alice")
        #expect(ghostB.get("username") == "Bob")

        ghostA.remove("username")
        #expect(ghostA.get("username") == nil)
        #expect(ghostB.get("username") == "Bob", "他ゴーストの削除の影響を受けない")
    }

    @Test
    func firstGhostBackfillsLegacyGlobalValues() {
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        // 旧ビルドのグローバル値を再現
        let legacy = ResourceManager(defaults: defaults)
        legacy.set("username", value: "LegacyUser")
        legacy.set("homeurl", value: "https://example.com/ghost/")

        // 最初に起動したゴーストが旧値を引き継ぐ
        let first = ResourceManager(defaults: defaults, ghostKey: "emily4")
        #expect(first.get("username") == "LegacyUser")
        #expect(first.get("homeurl") == "https://example.com/ghost/")

        // 2番目以降のゴーストは引き継がない（クレームマーカーで多重移行を防止）
        let second = ResourceManager(defaults: defaults, ghostKey: "sakura")
        #expect(second.get("username") == nil)
        #expect(second.get("homeurl") == nil)
    }

    @Test
    func legacyModeWithoutGhostKeyKeepsGlobalNamespace() {
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let global = ResourceManager(defaults: defaults)
        global.set("useorigin1", value: "1")
        // ghostKey なし同士では従来どおり共有される（互換維持）
        let global2 = ResourceManager(defaults: defaults)
        #expect(global2.get("useorigin1") == "1")
    }
}
