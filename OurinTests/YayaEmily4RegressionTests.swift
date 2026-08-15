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

    /// `OnFirstBoot` の実リクエストがフレームワーク経由で 200 応答になり、
    /// 初回起動用の Sakura Script を返すことを確認する。
    /// ロード直後は Emily4 の仕様で初期化スクリプトが前置されるため、全文 golden では固定しない。
    @Test
    func emily4OnFirstBootFrameworkRequestProducesSakuraScript() throws {
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
        #expect(resp?["status"] as? Int == 200)
        let value = resp?["value"] as? String
        #expect(value != nil && !(value?.isEmpty ?? true))
        #expect(value != "0")
        #expect(value?.contains("\\") == true)
    }

    /// 実再生前の `GhostManager.translateForDisplay` が利用する `OnTranslate` は、
    /// 入力 Sakura Script をそのまま返す必要がある。ここが数値の `0` を返すと、
    /// 表示前にスクリプト全体が `0` へ置換され、バルーンが「0」だけになる。
    @Test
    func emily4OnTranslatePreservesSakuraScript() throws {
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

        let script = #"\0\s[0]こんにちは\e"#
        let response = session.exchange([
            "cmd": "request", "method": "GET", "id": "OnTranslate",
            "ref": [script], "headers": ["Charset": "UTF-8"]
        ])

        #expect(response?["ok"] as? Bool == true)
        #expect(response?["status"] as? Int == 200)
        let value = response?["value"] as? String ?? ""
        #expect(value != "0")
        #expect(value.contains("\\s[0]"))
        #expect(value.contains("こんにちは"))
    }

    /// CommunicateBox が生成する ECHO/1.0 配置を Emily4 の実辞書で検証する。
    /// R1 の空要素を省略すると、Emily4 は種別を R2、本文を R3 として読めず、
    /// OnCommunicate が入力を処理できない。
    @Test
    func emily4OnCommunicateReadsCommunicateBoxReference3() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping Emily4 regression test")
            return
        }
        guard let master = try Self.copyEmily4Master() else {
            print("[skip] emily4/ghost/master fixture not found; skipping")
            return
        }
        defer { try? FileManager.default.removeItem(at: master) }

        // Emily4 の通常設定では台本コミュニケートを無効にしているため、
        // Reference 配置の検証用に有効化関数だけを一時辞書で追加する。
        let wrapperDic = """
        台本コミュニケート有効 {
        1
        }
        On_CommunicateReferenceProbe {
        "r0=%(reference[0])|r1=%(reference[1])|r2=%(reference[2])|r3=%(reference[3])"
        }
        """
        try wrapperDic.write(to: master.appendingPathComponent("_regression_communicate_wrapper.dic"),
                            atomically: true, encoding: .utf8)

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master,
                            extraEntries: [["path": "_regression_communicate_wrapper.dic", "encoding": "UTF-8"]])

        let sentence = "こんにちは"
        let response = session.exchange([
            "cmd": "request", "method": "GET", "id": "OnCommunicate",
            "ref": GhostManager.communicateBoxReferences(sentence: sentence),
            "headers": ["Charset": "UTF-8", "SecurityLevel": "local"]
        ])
        let probe = session.exchange([
            "cmd": "request", "method": "GET", "id": "On_CommunicateReferenceProbe",
            "ref": GhostManager.communicateBoxReferences(sentence: sentence),
            "headers": ["Charset": "UTF-8", "SecurityLevel": "local"]
        ])
        #expect(response?["ok"] as? Bool == true)
        #expect(response?["status"] as? Int == 200)
        #expect((response?["value"] as? String)?.isEmpty == false)
        #expect(response?["value"] as? String != "0")
        #expect(probe?["value"] as? String == "r0=user|r1=|r2=ECHO/1.0|r3=こんにちは",
                "Unexpected parsed References: \(String(describing: probe))")
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

    /// Mouse hover events may return an integer control value when no surface
    /// hit occurred. That value must not be exposed as a spoken Sakura Script.
    @Test
    func emily4NoOpMouseMoveDoesNotBecomeTalk() throws {
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

        let response = session.exchange([
            "cmd": "request", "method": "GET", "id": "OnMouseMove",
            "ref": ["442", "234", "0", "0", "", "", "mouse"],
            "headers": ["Charset": "UTF-8", "SecurityLevel": "local"]
        ])

        #expect(response?["ok"] as? Bool == true)
        let value = response?["value"] as? String ?? ""
        #expect(value.isEmpty)
    }

    /// クリック対象が無い場合も、内部ハンドラ名や終了タグ断片を返り値として表示しない。
    @Test
    func emily4NoOpMouseClickDoesNotExposeGeneratedHandlerName() throws {
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

        let response = session.exchange([
            "cmd": "request", "method": "GET", "id": "OnMouseClick",
            "ref": ["442", "234", "0", "0", "", "0", "mouse"],
            "headers": ["Charset": "UTF-8", "SecurityLevel": "local"]
        ])

        #expect(response?["ok"] as? Bool == true)
        let value = response?["value"] as? String ?? ""
        #expect(value.isEmpty)
        #expect(!value.contains("Mouse_Click0"))
        #expect(!value.contains("\\e"))
    }

    /// Framework が組み立てた `reference` 配列を動的 EVAL から参照できることを確認する。
    ///
    /// `reference[0]` が SHIORI の parsed Reference0 ではなく、request() に渡した生の
    /// リクエスト文字列へ解決されると、Emily4 の `OnChoiceSelect` が
    /// `OnChoiceSelect_GET SHIORI/3.0...` を再帰的に EVAL してスタックオーバーフローする。
    @Test
    func emily4ChoiceSelectUsesParsedReferenceWithoutRecursion() throws {
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

        let response = session.exchange([
            "cmd": "request", "method": "GET", "id": "OnChoiceSelect",
            "ref": ["CANCEL"],
            "headers": ["Charset": "UTF-8", "SecurityLevel": "local"]
        ])

        #expect(response?["ok"] as? Bool == true)
        #expect(response?["status"] as? Int == 200)
        let value = response?["value"] as? String ?? ""
        #expect(value.contains("\\e"))
        #expect(!value.contains("OnChoiceSelect_GET"))
    }

    /// YAYA フレームワークの request() が保持する REQ.COMMAND、出力候補エリア、
    /// `void`、裸の `return` を、実在ゴースト辞書上で検証する。
    @Test
    func emily4FrameworkRequestDispatchesGetCommand() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping Emily4 regression test")
            return
        }
        guard let master = try Self.copyEmily4Master() else {
            print("[skip] emily4/ghost/master fixture not found; skipping")
            return
        }
        defer { try? FileManager.default.removeItem(at: master) }

        let wrapperDic = """
        On_ProbeRequestCommand {
            REQ.COMMAND
        }
        On_ProbeCaseDispatch {
            case REQ.COMMAND {
                when "GET" { "matched" }
                others { "other" }
            }
        }
        On_ProbeOutputAreas {
            "prefix"
            --
            "suffix"
        }
        On_ProbeVoidPreservesValue {
            "value"
            void SHIORI3FW.GetLastErrorLog
        }
        On_ProbeBareReturnPreservesValue {
            "value"
            return
            "unreachable"
        }
        On_ProbeNumericControlValue {
            0
        }
        """
        try wrapperDic.write(to: master.appendingPathComponent("_regression_request_probe.dic"),
                            atomically: true, encoding: .utf8)

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master,
                            extraEntries: [["path": "_regression_request_probe.dic", "encoding": "UTF-8"]])

        func request(_ id: String) -> String {
            session.exchange([
                "cmd": "request", "method": "GET", "id": id,
                "ref": [], "headers": ["Charset": "UTF-8"]
            ])?["value"] as? String ?? ""
        }

        #expect(request("On_ProbeRequestCommand") == "GET")
        #expect(request("On_ProbeCaseDispatch") == "matched")
        #expect(request("On_ProbeOutputAreas") == "prefixsuffix")
        #expect(request("On_ProbeVoidPreservesValue") == "value")
        #expect(request("On_ProbeBareReturnPreservesValue") == "value")
        #expect(request("On_ProbeNumericControlValue").isEmpty)
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

        let wrapperDic = "On_SeededRandomTalkNormal {\n\tvoid SRAND(TOINT(reference[0]))\n\tRandomTalkNormal\n}\n"
        try wrapperDic.write(to: master.appendingPathComponent("_regression_seed_wrapper.dic"),
                              atomically: true, encoding: .utf8)

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master,
                             extraEntries: [["path": "_regression_seed_wrapper.dic", "encoding": "UTF-8"]])

        func talk(seed: String) -> String? {
            session.exchange([
                "cmd": "request", "method": "GET", "id": "On_SeededRandomTalkNormal",
                "ref": [seed], "headers": ["Charset": "UTF-8"]
            ])?["value"] as? String
        }

        let first = talk(seed: "42")
        let second = talk(seed: "42")
        let third = talk(seed: "7")

        #expect(first != nil && !(first?.isEmpty ?? true))
        #expect(first == second, "Same SRAND seed must reproduce the same random talk selection")
        #expect(third != nil && !(third?.isEmpty ?? true))
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
        On_EMArrayProbe {
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
            "cmd": "request", "method": "GET", "id": "On_EMArrayProbe",
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

        let wrapperDic = "On_SeededEMTalk {\n\tvoid SRAND(TOINT(reference[0]))\n\tEMRandomTalkSub\n}\n"
        try wrapperDic.write(to: master.appendingPathComponent("_regression_parallel_seed.dic"),
                              atomically: true, encoding: .utf8)

        let session = try YayaCoreSession(exe: exe)
        defer { session.finish() }
        try Self.loadEmily4(session: session, master: master,
                             extraEntries: [["path": "_regression_parallel_seed.dic", "encoding": "UTF-8"]])

        func talk(seed: String) -> String? {
            session.exchange([
                "cmd": "request", "method": "GET", "id": "On_SeededEMTalk",
                "ref": [seed], "headers": ["Charset": "UTF-8"]
            ])?["value"] as? String
        }

        let first = talk(seed: "42")
        let second = talk(seed: "42")
        let third = talk(seed: "7")

        #expect(first != nil && !(first?.isEmpty ?? true), "parallel in non-array context must select one candidate")
        #expect(first == second, "Same SRAND seed must reproduce the same parallel selection")
        #expect(third != nil && !(third?.isEmpty ?? true))
    }
}
