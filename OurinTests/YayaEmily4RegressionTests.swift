import Testing
@testable import Ourin
import Foundation

/// 実在の Emily4 ゴースト辞書一式を yaya_core にロードし、実際の SHIORI イベントを発火して
/// 応答文字列を検証する回帰テスト。
///
/// `docs/AUDITS_TODO.md` の「実在YAYAゴーストの回帰テストセット不足」に対応する。
/// これまでのテスト（`ShioriLoaderTests.swift`）は自作の最小限 `.dic` スニペットのみを検証しており、
/// Emily4 本体（`emily4/ghost/master/*.dic`）を実際にロードして発話結果を確認するテストは無かった。
///
/// yaya_core 実行ファイルが見つからない環境ではスキップする（既存の yaya_core 統合テストと同じ方針）。
struct YayaEmily4RegressionTests {
    // MARK: - Locate fixtures

    private static func repoRoot() -> URL? {
        var dir = URL(fileURLWithPath: #file).deletingLastPathComponent() // OurinTests/
        for _ in 0..<4 {
            dir = dir.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("emily4/ghost/master/yaya.txt").path) {
                return dir
            }
        }
        return nil
    }

    private static func locateYayaCore() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "yaya_core") { return url }
        guard let root = repoRoot() else { return nil }
        let candidate = root.appendingPathComponent("yaya_core/build/yaya_core")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    /// Emily4 の `ghost/master` を一時ディレクトリへコピーしたものを返す。
    /// テスト専用の追加辞書（SRAND シード検証用ラッパー等）を、git 管理下の実データを汚さずに
    /// 追加投入できるようにするため。
    private static func copyEmily4Master() throws -> URL? {
        guard let root = repoRoot() else { return nil }
        let source = root.appendingPathComponent("emily4/ghost/master")
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    /// Emily4 の `yaya.txt` を実際の本番パーサー（`collectDicEntries`）で解決し、
    /// `include`/`dic`/文字コード指定を本番と同じ手順で辞書エントリ一覧に展開する。
    private static func resolveEmily4DicEntries(master: URL) throws -> (entries: [DicEntry], charset: String?) {
        let yayaTxtURL = master.appendingPathComponent("yaya.txt")
        let content = try String(contentsOf: yayaTxtURL, encoding: .utf8)
        var collector = DicCollector()
        collectDicEntries(content: content, baseURL: master, sourceName: "yaya.txt", collector: &collector, visited: [])
        return (collector.entries, collector.globalCharset)
    }

    /// yaya_core をサブプロセスとして起動し、host_op 行には汎用 ack を返しつつ、
    /// 通常のレスポンス行だけを蓄積して返す。
    ///
    /// stderr は常時バックグラウンドでドレインする（本番の `YayaAdapter` と同じパターン）。
    /// yaya_core の VM は関数呼び出しごとに大量の `std::cerr` トレースを出力するため、
    /// stderr パイプを読み捨てないままだと OS のパイプバッファ（macOS では 64KB）が
    /// 満杯になり、子プロセス側の `cerr` 書き込みが永久にブロックしてデッドロックする。
    /// `EMRandomTalkSub`（`parallel` 経由で深くネストした埋め込み値評価を大量に行う）は
    /// この閾値を容易に超えるため、ドレインなしでは決定論的にハングしていた。
    private final class YayaCoreSession {
        private let proc = Process()
        private let inPipe = Pipe()
        private let outPipe = Pipe()
        private let errPipe = Pipe()
        private var lastStderrTail = Data()
        private let stderrLock = NSLock()

        init(exe: URL) throws {
            proc.executableURL = exe
            proc.standardInput = inPipe
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self.stderrLock.lock()
                self.lastStderrTail.append(data)
                if self.lastStderrTail.count > 8192 {
                    self.lastStderrTail.removeFirst(self.lastStderrTail.count - 8192)
                }
                self.stderrLock.unlock()
            }
            try proc.run()
        }

        /// 直近の stderr 出力（診断用、末尾最大 8KB）。
        var stderrTail: String {
            stderrLock.lock()
            defer { stderrLock.unlock() }
            return String(data: lastStderrTail, encoding: .utf8) ?? ""
        }

        private func send(_ obj: [String: Any]) {
            let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
            inPipe.fileHandleForWriting.write(data)
            inPipe.fileHandleForWriting.write(Data([0x0A]))
        }

        /// 1 行読み取る。`timeoutSeconds` 以内に応答が無ければ `nil` を返す
        /// （yaya_core がハング/クラッシュした場合にテストを無限待機させないため）。
        private func readLine(timeoutSeconds: Double = 20) -> [String: Any]? {
            let h = outPipe.fileHandleForReading
            let sem = DispatchSemaphore(value: 0)
            var buf = Data()
            var eof = false
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    let d = h.readData(ofLength: 1)
                    if d.isEmpty { eof = true; break }
                    if d == Data([0x0A]) { break }
                    buf.append(d)
                }
                sem.signal()
            }
            if sem.wait(timeout: .now() + timeoutSeconds) == .timedOut {
                return nil
            }
            if eof { return nil }
            return (try? JSONSerialization.jsonObject(with: buf)) as? [String: Any]
        }

        /// リクエストを送り、host_op には汎用 ack で応答しつつ、最終レスポンスを返す。
        /// タイムアウトまたは EOF の場合は `nil`（呼び出し側は `stderrTail` で診断可能）。
        func exchange(_ req: [String: Any]) -> [String: Any]? {
            send(req)
            while true {
                guard let obj = readLine() else { return nil }
                if obj["host_op"] != nil {
                    send(["ok": true])
                    continue
                }
                return obj
            }
        }

        func finish() {
            inPipe.fileHandleForWriting.closeFile()
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async { [proc] in
                proc.waitUntilExit()
                sem.signal()
            }
            if sem.wait(timeout: .now() + 10) == .timedOut {
                proc.terminate()
            }
            errPipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private static func loadEmily4(session: YayaCoreSession, master: URL, extraEntries: [[String: String]] = []) throws {
        let (entries, charset) = try resolveEmily4DicEntries(master: master)
        var dicEntries: [[String: String]] = entries.map { entry in
            var dict = ["path": entry.path]
            if let enc = entry.encoding { dict["encoding"] = enc }
            return dict
        }
        dicEntries.append(contentsOf: extraEntries)
        let loadReq: [String: Any] = [
            "cmd": "load",
            "ghost_root": master.path,
            "dic_entries": dicEntries,
            "encoding": charset ?? "UTF-8"
        ]
        let resp = session.exchange(loadReq)
        #expect(resp?["ok"] as? Bool == true, "Emily4 dictionary set failed to load: \(String(describing: resp))")
    }

    // MARK: - Tests

    /// `OnFirstBoot` は Emily4 の中で唯一に近い「完全固定文字列」トークで、RAND/ANY に依存しない。
    /// yaya_core の実出力をそのままゴールデン値として固定し、将来のパーサー/VM変更で
    /// 応答内容が意図せず変わっていないかを検証する。
    @Test
    func emily4OnFirstBootProducesExactGoldenTalk() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping Emily4 regression test")
            return
        }
        guard let master = try Self.copyEmily4Master() else {
            print("[skip] emily4/ghost/master fixture not found; skipping")
            return
        }
        defer { try? FileManager.default.removeItem(at: master) }

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master)

        let resp = session.exchange([
            "cmd": "request", "method": "GET", "id": "OnFirstBoot",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ])
        #expect(resp?["ok"] as? Bool == true)
        let value = resp?["value"] as? String

        let golden = "\\t\\u\\s[10]\\h\\s[5]はじめまして！\\w9\\w9\\n\\s[0]ボク、\\w5%(charname(0))っていいます。\\w9\\n\\s[6]あと、\\w5となりのちっちゃいのが%(charname(1))ね。\\w9\\w9\\n\\s[5]紹介終わり！\\w9\\u\\s[11]ちょっと待ってよそれ。\\w9\\w9\\h\\s[4]\\n\\nえー。\\w9\\w9\\u\\n\\nちっちゃいのって言うこともないと思うんだけど。\\w9\\nあと、\\w5誰か忘れてない？\\w9\\w9\\h\\n\\n…\\w5…\\p2\\s[214]\\h\\w5…\\w5…\\w5\\s[2]あ！\\w9\\w9\\p2まぁ、\\w5いいけどさ\\w5…\\w5…\\w9\\w9\\h\\s[4]\\n\\nごめんごめん。\\w9\\n\\s[0]この中くらいのが%(charname(2))っていいます。\\w9\\s[8]\\nちょっと生意気なボクの弟です。\\w9\\w9\\p2\\n\\n…\\w5…\\w5相変わらず自己紹介が下手だね。\\w9\\nもういいや。\\w9\\w9\\w9\\s[-1]\\b[-1]\\h\\s[4]\\n\\n…\\w5…\\w5ええと、\\w5とにかく、\\w5よろしくね。\\w9\\w9\\u\\n\\n\\s[10]そうそう、\\w5僕達は一応SSPの案内役ってことになってます。\\w9\\n…\\w5…\\w5\\s[11]見てのとおりなので、\\w5案内どころか足ひきずって谷底におっことしそうだけど。\\w9\\w9\\h\\n\\n…\\w5…\\w5ごめんなさい。\\w9\\n\\s[5]でも、\\w5なんとかがんばるから、\\w5わからないところがあったら呼んでね！\\w9\\w9\\u\\n\\n\\_a[GHOST_所長たん]SSPの開発者さんまでゴーストとして来てるみたいだし\\_a、\\w5そっちに聞いてみることをおすすめするよ。\\w9\\w9\\h\\s[4]\\n\\nそれちょっと待って。\\w9\\w9\\w9\\w9\\w9\\h\\s[0]\\n\\nあ、\\w5そういえば\\w5…\\w5…\\w9\\n\\s[6]できれば、\\w5あなたのお名前を教えてください。\\w9\\![open,configurationdialog,setup]\\e"

        #expect(value == golden)
    }

    /// 全33辞書が構文エラー無しでロードできることを回帰確認する
    /// （`docs/AUDITS_TODO.md`/`IMPLEMENTATION_STATUS.md` の「33/33ロード成功」主張の裏付け）。
    @Test
    func emily4AllDictionariesLoadWithoutParseFailure() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping Emily4 regression test")
            return
        }
        guard let master = try Self.copyEmily4Master() else {
            print("[skip] emily4/ghost/master fixture not found; skipping")
            return
        }
        defer { try? FileManager.default.removeItem(at: master) }

        let (entries, _) = try Self.resolveEmily4DicEntries(master: master)
        #expect(entries.count == 33, "Expected 33 resolved dic entries from yaya.txt/include chain, got \(entries.count)")

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master)
    }

    /// Emily4 実データの雑談配列（`RandomTalkNormal`）に対し、SRAND(seed) で固定シードした場合に
    /// 選択結果が再現可能であることを検証する（`yaya_core` の SRAND スタブ修正の回帰テスト）。
    /// 実行毎に変わってよい内容なので、golden 文字列ではなく「同一シード→同一出力」を確認する。
    @Test
    func emily4RandomTalkIsReproducibleWithFixedSeed() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping Emily4 regression test")
            return
        }
        guard let master = try Self.copyEmily4Master() else {
            print("[skip] emily4/ghost/master fixture not found; skipping")
            return
        }
        defer { try? FileManager.default.removeItem(at: master) }

        let wrapperDic = "SeededRandomTalkNormal {\n\tSRAND(_argv[0])\n\tRandomTalkNormal\n}\n"
        try wrapperDic.write(to: master.appendingPathComponent("_regression_seed_wrapper.dic"),
                              atomically: true, encoding: .utf8)

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master,
                             extraEntries: [["path": "_regression_seed_wrapper.dic", "encoding": "UTF-8"]])

        func talk(seed: String) -> String? {
            session.exchange([
                "cmd": "request", "method": "GET", "id": "SeededRandomTalkNormal",
                "ref": [seed], "headers": ["Charset": "UTF-8"]
            ])?["value"] as? String
        }

        let first = talk(seed: "42")
        let second = talk(seed: "42")
        let third = talk(seed: "7")

        #expect(first != nil && !(first?.isEmpty ?? true))
        #expect(first == second, "Same SRAND seed must reproduce the same random talk selection")
        #expect(first != third, "Different SRAND seeds are expected to (very likely) select a different talk")
    }

    /// `EMRandomTalkSubArray : array` が `parallel` 修飾子によって正しくフラット化されることを検証する。
    /// `parallel` 未実装時代は各 `parallel F(...)` 行が「未定義変数参照＋別文」に化けて
    /// 候補配列が入れ子（要素に配列が混入）のまま返っており、雑談トークがサイレントに壊れていた。
    @Test
    func emily4RandomTalkSubArrayIsFlattenedByParallel() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping Emily4 regression test")
            return
        }
        guard let master = try Self.copyEmily4Master() else {
            print("[skip] emily4/ghost/master fixture not found; skipping")
            return
        }
        defer { try? FileManager.default.removeItem(at: master) }

        // 候補配列のサイズと「要素自体が配列(GETTYPE==4)である個数」を数えるプローブ
        let wrapperDic = """
        EMArrayProbe {
        \t_a = EMRandomTalkSubArray
        \t_n = ARRAYSIZE(_a)
        \t_nested = 0
        \tfor _i = 0; _i < _n; _i++ {
        \t\tif GETTYPE(_a[_i]) == 4 {
        \t\t\t_nested += 1
        \t\t}
        \t}
        \t"size=%(_n) nested=%(_nested)"
        }
        """
        try wrapperDic.write(to: master.appendingPathComponent("_regression_parallel_probe.dic"),
                              atomically: true, encoding: .utf8)

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master,
                             extraEntries: [["path": "_regression_parallel_probe.dic", "encoding": "UTF-8"]])

        let resp = session.exchange([
            "cmd": "request", "method": "GET", "id": "EMArrayProbe",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ])
        #expect(resp?["ok"] as? Bool == true)
        let value = resp?["value"] as? String ?? ""

        // "size=NNN nested=M" を分解
        var size = -1
        var nested = -1
        for part in value.split(separator: " ") {
            if part.hasPrefix("size=") { size = Int(part.dropFirst(5)) ?? -1 }
            if part.hasPrefix("nested=") { nested = Int(part.dropFirst(7)) ?? -1 }
        }
        // RandomTalkNormal だけで100件超あるため、フラット化されていれば十分大きくなる。
        // 壊れている場合は入れ子配列が数個入るだけでサイズが極端に小さい。
        #expect(size >= 50, "Expected flattened candidate pool (>=50 talks), got size=\(size) from '\(value.prefix(80))'")
        #expect(nested == 0, "Candidate pool must not contain nested arrays, got nested=\(nested)")
    }

    /// `EMRandomTalkSub : nonoverlap { parallel EMRandomTalkSubArray }`（非 array 文脈の parallel =
    /// 候補から1つ選択）が SRAND 固定シードで決定的に動作することを検証する。
    /// 既存の SeededRandomTalkNormal テストが意図的に回避していた `parallel` 経路のカバレッジ。
    @Test
    func emily4SeededEMRandomTalkSubIsReproducible() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping Emily4 regression test")
            return
        }
        guard let master = try Self.copyEmily4Master() else {
            print("[skip] emily4/ghost/master fixture not found; skipping")
            return
        }
        defer { try? FileManager.default.removeItem(at: master) }

        let wrapperDic = "SeededEMTalk {\n\tSRAND(_argv[0])\n\tEMRandomTalkSub\n}\n"
        try wrapperDic.write(to: master.appendingPathComponent("_regression_parallel_seed.dic"),
                              atomically: true, encoding: .utf8)

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master,
                             extraEntries: [["path": "_regression_parallel_seed.dic", "encoding": "UTF-8"]])

        func talk(seed: String) -> String? {
            session.exchange([
                "cmd": "request", "method": "GET", "id": "SeededEMTalk",
                "ref": [seed], "headers": ["Charset": "UTF-8"]
            ])?["value"] as? String
        }

        let first = talk(seed: "42")
        let second = talk(seed: "42")
        let third = talk(seed: "7")

        #expect(first != nil && !(first?.isEmpty ?? true), "parallel in non-array context must select one candidate")
        #expect(first == second, "Same SRAND seed must reproduce the same parallel selection")
        #expect(first != third, "Different SRAND seeds are expected to (very likely) select a different talk")
    }
}
