import Testing
import Foundation
@testable import Ourin

/// SHIORI Resource のファイル永続化（`data/profile/<ghost>/shiori_resources.txt`）と
/// UserDefaults → ファイル移行の検証。
///
/// `OurinPaths.testBaseOverride`（Thread.local）へ一時ディレクトリを注入し、
/// `ProfileResourceFileStore` が本物のファイル I/O を行う経路をテストする。
/// 実環境の `~/Documents/Ourin` は触らない。
struct ResourceManagerFileMigrationTests {
    private static let ghost = "emily4"

    /// テスト用の一時 base ディレクトリを生成し、`OurinPaths.testBaseOverride` へ設定する。
    /// 戻り値の cleanup を defer で呼ぶことで threadDictionary と tmpDir を掃除する。
    private func makeTempBase() -> (URL, () -> Void) {
        let fm = FileManager.default
        let url = fm.temporaryDirectory
            .appendingPathComponent("OurinRMTests.\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        let previous = OurinPaths.testBaseOverride
        OurinPaths.testBaseOverride = url
        let cleanup: () -> Void = {
            OurinPaths.testBaseOverride = previous
            try? fm.removeItem(at: url)
        }
        return (url, cleanup)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "OurinTests.ResourceFile.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return (d, suite)
    }

    private func profileFileURL(base: URL) -> URL {
        base.appendingPathComponent("data/profile", isDirectory: true)
            .appendingPathComponent(Self.ghost, isDirectory: true)
            .appendingPathComponent(ProfileResourceFileStore.fileName)
    }

    // (a) UserDefaults のみ存在 → ファイルへ移行される
    @Test
    func migratesUserDefaultsToFileWhenFileAbsent() throws {
        let (base, cleanup) = makeTempBase()
        defer { cleanup() }
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        // 旧ビルド相当: UserDefaults のゴースト別プレフィックスへ値を仕込む
        defaults.set("Alice", forKey: "OurinResource.emily4.username")
        defaults.set("https://example.com/ghost/", forKey: "OurinResource.emily4.homeurl")

        let fileURL = profileFileURL(base: base)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path), "移行前はファイル無し")

        let rm = ResourceManager(defaults: defaults, ghostKey: Self.ghost)

        // ファイルへ移行されている
        #expect(rm.get("username") == "Alice")
        #expect(rm.get("homeurl") == "https://example.com/ghost/")
        #expect(FileManager.default.fileExists(atPath: fileURL.path), "移行後にファイル生成")

        // UserDefaults の元エントリは削除されていない（データ消失防止）
        #expect(defaults.string(forKey: "OurinResource.emily4.username") == "Alice")
        #expect(defaults.string(forKey: "OurinResource.emily4.homeurl") == "https://example.com/ghost/")

        // ファイル内容を直接読んで検証
        let loaded = ProfileResourceFileStore(ghostKey: Self.ghost).load()
        #expect(loaded?["username"] == "Alice")
        #expect(loaded?["homeurl"] == "https://example.com/ghost/")

        // 冪等性: もう一度初期化しても値は壊れない・重複書き込みしない
        let rm2 = ResourceManager(defaults: defaults, ghostKey: Self.ghost)
        #expect(rm2.get("username") == "Alice")
        #expect(rm2.get("homeurl") == "https://example.com/ghost/")
    }

    // (b) ファイル既存 → ファイル優先
    @Test
    func prefersExistingFileOverUserDefaults() throws {
        let (base, cleanup) = makeTempBase()
        defer { cleanup() }
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        // ファイルへ値を置く
        let store = ProfileResourceFileStore(ghostKey: Self.ghost)
        try store.write(["username": "FromFile", "homeurl": "https://file.example/"])

        // UserDefaults には別の値（ファイルと矛盾）を仕込む
        defaults.set("FromDefaults", forKey: "OurinResource.emily4.username")
        defaults.set("https://defaults.example/", forKey: "OurinResource.emily4.homeurl")

        let rm = ResourceManager(defaults: defaults, ghostKey: Self.ghost)

        // ファイル側が勝つ
        #expect(rm.get("username") == "FromFile")
        #expect(rm.get("homeurl") == "https://file.example/")

        // UserDefaults 側は触られていない（ファイル優先で上書き回去動はしない）
        #expect(defaults.string(forKey: "OurinResource.emily4.username") == "FromDefaults")
    }

    // (c) 新規書き込み → ファイルに載る
    @Test
    func newWritesGoToFile() throws {
        let (base, cleanup) = makeTempBase()
        defer { cleanup() }
        let (defaults, suite) = makeDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let fileURL = profileFileURL(base: base)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        let rm = ResourceManager(defaults: defaults, ghostKey: Self.ghost)
        rm.set("username", value: "NewValue")
        rm.set("sakura.defaultleft", value: "123")

        // ファイルへ即時永続化
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // ファイルを直接読んで検証
        let loaded = ProfileResourceFileStore(ghostKey: Self.ghost).load()
        #expect(loaded?["username"] == "NewValue")
        #expect(loaded?["sakura.defaultleft"] == "123")

        // 別インスタンスで再読込 → ファイルから復元される（UserDefaults には無い）
        let rm2 = ResourceManager(defaults: defaults, ghostKey: Self.ghost)
        #expect(rm2.get("username") == "NewValue")
        #expect(rm2.get("sakura.defaultleft") == "123")
        #expect(defaults.string(forKey: "OurinResource.emily4.username") == nil,
                "新規書き込みはファイルのみ（UserDefaults への二重書き込みしない）")

        // remove もファイルへ反映
        rm2.remove("username")
        let rm3 = ResourceManager(defaults: defaults, ghostKey: Self.ghost)
        #expect(rm3.get("username") == nil)
        #expect(rm3.get("sakura.defaultleft") == "123")
    }
}
