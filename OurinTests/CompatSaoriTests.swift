import AppKit
import Foundation
import Network
import Testing
@testable import Ourin

// 互換モジュールのテスト。外部とのつなぎ目（CompatSaoriHooks）を差し替えるので、まとめて直列に動かす。

private struct CompatOutcome {
    var status: Int
    var result: String?
    var values: [String]
    var error: String?
}

private func parse(_ text: String) -> CompatOutcome {
    let response = try! SaoriProtocol.parseResponse(text)
    var values: [String] = []
    while let value = response.headerValue("Value\(values.count)") { values.append(value) }
    return CompatOutcome(status: response.statusCode, result: response.headerValue("Result"), values: values, error: response.headerValue("ErrorDescription"))
}

private func requestText(_ arguments: [String], module: String? = nil, charset: String = "UTF-8") -> String {
    var lines = ["EXECUTE SAORI/1.0", "Charset: \(charset)", "Sender: test"]
    if let module { lines.append("Module: \(module)") }
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index): \(value)") }
    return lines.joined(separator: "\r\n") + "\r\n\r\n"
}

/// ゴーストの SAORI の読み込み口（SaoriManager）。一時フォルダを ghost/master にする。
private final class CompatGhost {
    let root: URL
    let manager = SaoriManager()
    private let lock = NSLock()
    private(set) var events: [(name: String, references: [String: String])] = []

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-compat-\(UUID().uuidString)/ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("saori"), withIntermediateDirectories: true)
        manager.internalContext = InternalSaoriContext(ghostRoot: root, deliverEvent: { [weak self] name, params in
            guard let self else { return }
            self.lock.lock(); self.events.append((name, params)); self.lock.unlock()
        })
    }

    func call(_ module: String, _ arguments: [String], charset: String = "UTF-8") -> CompatOutcome {
        parse(try! manager.request(moduleName: module, requestText: requestText(arguments, charset: charset), charset: charset))
    }

    func waitForEvent(_ name: String, timeout: TimeInterval = 10) async throws -> [String: String]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock(); let found = events.first { $0.name == name }; lock.unlock()
            if let found { return found.references }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    func remove() {
        manager.unloadAll()
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent())
    }
}

/// Direct SSTP（ゴーストなし）。
private func direct(_ module: String, _ arguments: [String], charset: String = "UTF-8") -> CompatOutcome {
    parse(InternalSaoriRegistry.shared.handle(requestText: requestText(arguments, module: module, charset: charset)))
}

@Suite(.serialized)
struct CompatSaoriTests {
    // MARK: - 登録・経路

    @Test
    func compatNamesAreRecognisedByFileName() {
        #expect(CompatSaoriRegistry.compatName("string") == "string")
        #expect(CompatSaoriRegistry.compatName("saori/String.DLL") == "string")
        #expect(CompatSaoriRegistry.compatName("saori\\httpc.dll") == "httpc")
        #expect(CompatSaoriRegistry.compatName("/abs/path/Saori_CPUID.dll") == "saori_cpuid")
        #expect(CompatSaoriRegistry.compatName("string2.dll") == nil)
        #expect(CompatSaoriRegistry.compatName("internal_crypto") == nil)
        #expect(Set(CompatSaoriRegistry.factories.keys) == ["houchi", "clipcopy", "textcopy", "saori_ip", "saori_cpuid", "mciaudio", "cpuusage", "httpc", "string", "hanayu"])
        // 互換モジュールは ListModules に出ない。ListFunctions でも unknown module。
        let modules = parse(InternalSaoriRegistry.shared.handle(requestText: requestText(["ListModules"], module: "internal_system")))
        #expect(!(modules.result ?? "").contains("string"))
        #expect(parse(InternalSaoriRegistry.shared.handle(requestText: requestText(["ListFunctions", "string"], module: "internal_system"))).error == "unknown module")
    }

    @Test
    func dllLoadsAreReplacedAndKeepStateUntilUnload() throws {
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        // DLL が無くても load できる（ファイル名で差し替える）。
        #expect(ghost.manager.handlePluginOperation("saori_load", params: ["module": "saori/string.dll"])["ok"] as? Bool == true)
        #expect(ghost.manager.compatHost.loadedModuleKeys == ["saori/string.dll"])
        #expect(ghost.call("saori/string.dll", ["match", "abc123", "/([a-z]+)([0-9]+)/"]).result == "1")
        #expect(ghost.call("saori/string.dll", ["get", "2"]).result == "123")
        // 別の名前で読んだもの・Direct SSTP のものとは状態を共有しない。
        #expect(ghost.call("string.dll", ["get", "2"]).result == "")
        #expect(direct("string", ["get", "2"]).result == "")
        // unload で状態を捨てる。
        #expect(ghost.manager.handlePluginOperation("saori_unload", params: ["module": "saori/string.dll"])["ok"] as? Bool == true)
        #expect(ghost.call("saori/string.dll", ["get", "2"]).result == "")
        // ゴーストの読み直し（internalContext の再設定）でも捨てる。
        _ = ghost.call("saori/string.dll", ["match", "x1", "/(x)/"])
        ghost.manager.internalContext = ghost.manager.internalContext
        #expect(ghost.manager.compatHost.loadedModuleKeys.isEmpty)
        // GET Version は 200。
        let version = parse(try ghost.manager.request(moduleName: "saori/string.dll", requestText: "GET Version SAORI/1.0\r\nCharset: UTF-8\r\n\r\n"))
        #expect(version.status == 200)
    }

    @Test
    func directSSTPCallsUseTheModuleNameWithoutDLL() {
        #expect(direct("string", ["toupper", "abc"]).result == "ABC")
        #expect(direct("String", ["tolower", "ABC"]).result == "abc")
        #expect(direct("string.dll", ["trim", "  x  "]).result == "x")
        #expect(direct("saori/string", ["trim", "x"]).error == "unknown module")
        // ゴーストに依存する処理は ghost required。
        #expect(direct("httpc", ["http://example.com/"]).error == "ghost required")
        #expect(direct("httpc", ["bg", "id", "http://example.com/"]).error == "ghost required")
        #expect(direct("mciaudio", ["load", "a.mp3"]).error == "ghost required")
        #expect(direct("hanayu", ["show"]).error == "ghost required")
        // houchi は何もしない（204）。
        #expect(direct("houchi", ["anything"]).status == 204)
        // Shift_JIS の要求には Shift_JIS で応える（XPC の Direct SSTP）。
        let sjis = requestText(["tozenkaku", "ab"], module: "string", charset: "Shift_JIS")
        let data = InternalSaoriRouting.respond(to: sjis)
        let text = String(data: data, encoding: .shiftJIS) ?? ""
        #expect(text.contains("Result: ａｂ"))
    }

    // MARK: - string

    @Test
    func stringRegularExpressions() throws {
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        func s(_ args: String...) -> CompatOutcome { ghost.call("string.dll", args) }
        // 記述例。i は大文字小文字を区別しない。
        #expect(s("match", "IMAGE.PNG", "/\\.(png|jpg|jpeg|bmp)$/i").result == "1")
        #expect(s("get", "0").result == ".PNG")
        #expect(s("get", "1").result == "PNG")
        #expect(s("get", "5").result == "")
        #expect(s("match", "image.gif", "/\\.(png|jpg)$/").result == "0")
        // g は個数。
        #expect(s("match", "a1b22c333", "/[0-9]+/g").result == "3")
        #expect(s("get", "0").result == "333")
        // 先頭の m と、ほかの区切り文字。
        #expect(s("match", "a/b", "m#a/b#").result == "1")
        #expect(s("match", "a/b", "/a\\/b/").result == "1")
        // h は半角にしてから調べる。
        #expect(s("match", "ＡＢＣ１２３", "/^[A-Z]+[0-9]+$/h").result == "1")
        // replace は置換数。get 0 で置換後、get n で ()。
        #expect(s("replace", "2024-05-06", "s/([0-9]+)-([0-9]+)-([0-9]+)/$3\\/$2\\/$1/").result == "1")
        #expect(s("get", "0").result == "06/05/2024")
        #expect(s("get", "1").result == "2024")
        #expect(s("replace", "aaa", "s/a/b/").result == "1")
        #expect(s("get", "0").result == "baa")
        #expect(s("replace", "aaa", "s/a/b/g").result == "3")
        #expect(s("get", "0").result == "bbb")
        #expect(s("replace", "cat", "s/(c)/[$&|\\1]/").result == "1")
        #expect(s("get", "0").result == "[c|c]at")
        #expect(s("replace", "x", "s/x/$y/").result == "1")
        #expect(s("get", "0").result == "$y")
        // split は個数。get は 0 から。Perl と同じく末尾の空は捨て、() の中も入る。
        #expect(s("split", "a,b,,c,,", "/,/").result == "4")
        #expect(s("get", "0").result == "a")
        #expect(s("get", "2").result == "")
        #expect(s("get", "3").result == "c")
        #expect(s("split", "1-2+3", "/([-+])/").result == "5")
        #expect(s("get", "1").result == "-")
        #expect(s("split", "abc", "//").result == "3")
        // Argument1（と Argument2）を省くと、前回の文字列の続きから調べる（原作どおり）。
        #expect(s("match", "a1b2c3", "/[0-9]/").result == "1")
        #expect(s("get", "0").result == "1")
        #expect(s("match").result == "1")
        #expect(s("get", "0").result == "2")
        #expect(s("match").result == "1")
        #expect(s("match").result == "0")
        #expect(s("get", "0").result == "3") // 同じ正規表現なら、前回の結果が残る
        #expect(s("match", "x", "/y/").result == "0")
        #expect(s("get", "0").result == "") // 正規表現が変われば残らない
        #expect(s("replace", "aaa", "s/a/b/").result == "1")
        #expect(s("get", "0").result == "baa")
        #expect(s("replace").result == "1") // 続きの "aa" を置換する
        #expect(s("get", "0").result == "ba")
        // 形の誤り。
        #expect(s("match", "a", "abc").status == 400)
        #expect(s("match", "a", "/(/").status == 400)
        #expect(s("replace", "a", "/a/b/").status == 400)
        #expect(s("match", "a", "/a/q").status == 400)
        #expect(s("nothing", "a").status == 400)
    }

    @Test
    func stringClassificationAndConversion() throws {
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        func s(_ args: String...) -> String? { ghost.call("string.dll", args).result }
        #expect(s("isalpha", "abcXYZ") == "1")
        #expect(s("isalpha", "abc1") == "0")
        #expect(s("isalpha", "") == "0")
        #expect(s("isupper", "ABC") == "1")
        #expect(s("isupper", "ABc") == "0")
        #expect(s("islower", "abc") == "1")
        #expect(s("isnumber", "0123") == "1")
        #expect(s("isnumber", "１２") == "0") // 全角の数字は数字に数えない
        #expect(s("isalnum", "a1B2") == "1")
        #expect(s("isinteger", "  -42") == "1")
        #expect(s("isinteger", "4.2") == "0")
        #expect(s("isdecimal", "+3.14") == "1")
        #expect(s("isdecimal", ".5") == "1")
        #expect(s("isdecimal", "1.2.3") == "0")
        #expect(s("toupper", "abcａｂｃ") == "ABCａｂｃ") // 英字（半角）だけ
        #expect(s("tolower", "ABCＡ") == "abcＡ")
        #expect(s("tozenkaku", "Ab1 !\"'\\`~ｶﾅ") == "Ａｂ１　！”’￥｀￣ｶﾅ") // 半角カナはそのまま
        #expect(s("tohankaku", "Ａｂ１　！”’￥｀￣カナ") == "Ab1 !\"'\\`~カナ")
        #expect(s("trim", " \t\u{3000}abc \u{3000}") == "abc")
        // 漢字コード。Shift_JIS の要求では、JIS に変換するとエスケープの入った文字列になる。
        let jis = ghost.call("string.dll", ["tojis", "あ"], charset: "Shift_JIS").result ?? ""
        #expect(jis.unicodeScalars.contains("\u{1B}"))
        #expect(ghost.call("string.dll", ["isjis", jis], charset: "Shift_JIS").result == "1")
        #expect(ghost.call("string.dll", ["tosjis", jis], charset: "Shift_JIS").result == "あ")
        #expect(ghost.call("string.dll", ["issjis", "あいう"], charset: "Shift_JIS").result == "1")
        #expect(ghost.call("string.dll", ["isjis", "あいう"], charset: "Shift_JIS").result == "0")
    }

    // MARK: - clipcopy / textcopy

    @Test
    func clipboardModulesCopyText() throws {
        var copied: [String] = []
        let saved = CompatSaoriHooks.writeClipboard
        CompatSaoriHooks.writeClipboard = { copied.append($0); return true }
        defer { CompatSaoriHooks.writeClipboard = saved }
        let ghost = try CompatGhost()
        defer { ghost.remove() }

        // clipcopy: \n は改行、\\n は \n のまま。戻り値なし。
        #expect(ghost.call("clipcopy.dll", ["a\\nb\\\\nc"]).status == 204)
        #expect(copied.last == "a\nb\\nc")
        #expect(ghost.call("clipcopy.dll", []).status == 400)

        // textcopy: Argument1 が 0 以外ならコピーした文字列を返す。
        #expect(ghost.call("textcopy.dll", ["hello"]).status == 204)
        #expect(copied.last == "hello")
        #expect(ghost.call("textcopy.dll", ["hello", "1"]).result == "hello")
        #expect(ghost.call("textcopy.dll", ["hello", "0"]).status == 204)
        #expect(ghost.call("textcopy.dll", ["a|b", "1", "|"]).result == "a|b") // Argument2 は使わない
        #expect(copied.last == "a|b")
        #expect(ghost.call("textcopy.dll", [""]).status == 400)
        // Direct SSTP からも使える。
        #expect(direct("textcopy", ["x", "1"]).result == "x")
    }

    // MARK: - saori_ip / saori_cpuid / cpuusage

    @Test
    func saoriIPReportsAddressesAndHostName() throws {
        let saved = CompatSaoriHooks.fetch
        defer { CompatSaoriHooks.fetch = saved }
        var requested: URL?
        CompatSaoriHooks.fetch = { url in requested = url; return (Data(" 203.0.113.7\n".utf8), nil) }
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        #expect(ghost.call("saori_ip.dll", ["GetInternetIP"]).result == "203.0.113.7")
        #expect(requested == CompatSaoriIPModule.internetIPURL)
        CompatSaoriHooks.fetch = { _ in nil }
        #expect(ghost.call("saori_ip.dll", ["GetInternetIP"]).status == 500)

        var buffer = [CChar](repeating: 0, count: 256)
        gethostname(&buffer, buffer.count)
        #expect(ghost.call("saori_ip.dll", ["getlocalhostname"]).result == String(cString: buffer))
        let local = ghost.call("saori_ip.dll", ["GetLocalIP"])
        if local.status == 200 {
            #expect(local.result?.range(of: #"^\d+\.\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
            #expect(local.result != "127.0.0.1")
        } else {
            #expect(local.status == 500) // ネットワークにつながっていない環境
        }
        #expect(ghost.call("saori_ip.dll", ["GetSomething"]).status == 400)
        #expect(ghost.call("saori_ip.dll", []).status == 400)
    }

    @Test
    func saoriCPUIDAndCPUUsage() throws {
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        func c(_ args: String...) -> CompatOutcome { ghost.call("saori_cpuid.dll", args) }
        #expect(c("os.name").result == "macOS")
        #expect(c("os.version").result?.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil)
        #expect(!(c("os.build").result ?? "").isEmpty)
        #expect(!(c("platform").result ?? "").isEmpty)
        #expect((Int(c("cpu.num").result ?? "") ?? 0) >= 1)
        #expect(!(c("cpu.name").result ?? "").isEmpty)
        #expect(["Ready", "Not Ready"].contains(c("cpu.sse2").result ?? ""))
        #expect(c("cpu.tdn").result == "Not Ready")
        #expect((Int(c("mem.phyt").result ?? "") ?? 0) > 0)
        let load = Int(c("mem.os").result ?? "") ?? -1
        #expect((0...100).contains(load))
        #expect(c("cpu.clockex").result?.range(of: #"^\d+\.\d{3}$"#, options: .regularExpression) != nil)
        // Argument1 は数値として読み、0 なら返さない（数字でなければ 0）。知らないコードは 400（param error）。
        #expect(c("os.name", "0").status == 204)
        #expect(c("os.name", "1").result == "macOS")
        #expect(c("os.name", "cpu.num").status == 204)
        #expect(c("os.name", "1").values.isEmpty)
        #expect(c("nothing").status == 400)
        #expect(c("nothing").result == nil)
        #expect(c().status == 204)

        let usage = Int(ghost.call("cpuusage.dll", ["get"]).result ?? "") ?? -1
        #expect((0...100).contains(usage))
        #expect(ghost.call("cpuusage.dll", ["set"]).status == 400)
    }

    // MARK: - houchi

    @Test
    func houchiNotifiesEveryMinuteOfIdleness() throws {
        let saved = CompatSaoriHooks.idleSeconds
        defer { CompatSaoriHooks.idleSeconds = saved }
        var idle = 0.0
        CompatSaoriHooks.idleSeconds = { idle }
        var sent: [[String]] = []
        let module = CompatHouchiModule(environment: CompatSaoriEnvironment(
            ghostRoot: URL(fileURLWithPath: "/tmp/ghost"), moduleDirectory: nil, deliverEvent: { name, refs in
                #expect(name == "OnHouchi")
                sent.append(refs)
            }))
        defer { module.unload() }
        for (seconds, expected) in [(30.0, 0), (61, 1), (70, 1), (125, 2), (10, 2), (65, 3)] {
            idle = seconds
            module.poll()
            #expect(sent.count == expected, "idle \(seconds)")
        }
        #expect(sent.map { $0.first ?? "" } == ["1", "2", "1"])
        #expect(module.execute(["x"], charset: "UTF-8").status == 204)

        // ゴーストなしでは何も送らない。
        let ghostless = CompatHouchiModule(environment: .ghostless)
        idle = 600
        ghostless.poll()
        #expect(sent.count == 3)
    }

    // MARK: - httpc

    @Test
    func httpcFetchesExtractsAndSaves() throws {
        let saved = (CompatSaoriHooks.fetch, CompatSaoriHooks.isOnline)
        defer { (CompatSaoriHooks.fetch, CompatSaoriHooks.isOnline) = saved }
        let pages: [String: (Data, String?)] = [
            "http://example.com/a": (Data("<html>\r\n<a href=\"x.html\">X</a>\n<a href=\"y.html\">Y</a></html>".utf8), "utf-8"),
            "http://example.com/sjis": ("<p>こんにちは</p>".data(using: .shiftJIS)!, nil),
            "http://example.com/euc": ("<meta charset=\"EUC-JP\">さくら".data(using: .japaneseEUC)!, nil),
            "http://example.com/bin": (Data([0, 1, 2, 255]), nil),
            "http://example.com/tags": (Data("A<br>B<hr><a href=\"u\">link</a><img src=\"i\" alt=\"pic\">&lt;&amp;&gt;&nbsp;&copy;".utf8), "utf-8")
        ]
        CompatSaoriHooks.fetch = { url in pages[url.absoluteString] }
        CompatSaoriHooks.isOnline = { true }
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        func h(_ args: String...) -> CompatOutcome { ghost.call("saori/httpc.dll", args) }

        #expect(h().result == "1")
        // 1 つ: 改行を除いて返す。
        #expect(h("http://example.com/a").result == "<html><a href=\"x.html\">X</a><a href=\"y.html\">Y</a></html>")
        // 3 つ: 囲まれた部分。2 つ目以降は Value0 から。
        let links = h("http://example.com/a", "href=\"", "\"")
        #expect(links.result == "x.html")
        #expect(links.values == ["y.html"])
        // 文字コードの判別と明示。
        #expect(h("http://example.com/sjis").result == "<p>こんにちは</p>")
        #expect(h("sjis", "http://example.com/sjis").result == "<p>こんにちは</p>")
        #expect(h("http://example.com/euc").result?.hasSuffix("さくら") == true)
        // タグの処理（オプションはどの順でもよい）。
        #expect(h("erase_tag", "utf8", "http://example.com/sjis").status == 200)
        #expect(h("sjis", "erase_tag", "http://example.com/sjis").result == "こんにちは")
        #expect(h("translate_tag", "http://example.com/tags").result == "A\\nB\\n-----------------------------------------------\\n\\_a[u]link\\_a〔pic〕<\\&>(c)")
        // 2 つ: DLL と同じ場所を基準に保存（バイナリも可。原作どおり、ファイル名をそのままつなぐ）。
        #expect(h("http://example.com/bin", "out.bin").result == "1")
        #expect(try Data(contentsOf: ghost.root.appendingPathComponent("saori/out.bin")) == Data([0, 1, 2, 255]))
        #expect(h("http://example.com/bin", "..\\up.bin").result == "1")
        #expect(FileManager.default.fileExists(atPath: ghost.root.appendingPathComponent("up.bin").path))
        #expect(h("http://example.com/bin", "no/such/dir/x.bin").result == "0")
        #expect(h("http://example.com/missing", "x.bin").result == "0")
        // 取れなければ空。引数が多すぎても空。
        #expect(h("http://example.com/missing").result == "")
        #expect(h("a", "b", "c", "d").result == "")
        CompatSaoriHooks.isOnline = { false }
        #expect(h().result == "0")
    }

    @Test
    func httpcBackgroundNotifiesTheGhost() async throws {
        let saved = CompatSaoriHooks.fetch
        defer { CompatSaoriHooks.fetch = saved }
        CompatSaoriHooks.fetch = { _ in (Data("[1][2][3]".utf8), "utf-8") }
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        let accepted = ghost.call("httpc.dll", ["bg", "job1", "http://example.com/", "[", "]"])
        #expect(accepted.status == 200)
        #expect(accepted.result == "")
        let references = try #require(try await ghost.waitForEvent("OnHttpcNotify"))
        #expect(references["Reference0"] == "job1")
        #expect(references["Reference1"] == "-")
        #expect(references["Reference2"] == "1")
        #expect(references["Reference3"] == "2")
        #expect(references["Reference4"] == "3")
        // 識別子が無いとき。
        #expect(ghost.call("httpc.dll", ["bg"]).result == "bgするならIDを指定していただけませんと。")
    }

    @Test
    func plainHTTPClientTalksToARealServer() async throws {
        let server = try CompatTestHTTPServer()
        let port = try await server.start()
        defer { server.stop() }
        server.reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=Shift_JIS\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
        let chunked = try #require(PlainHTTP.get(URL(string: "http://127.0.0.1:\(port)/path?q=1")!))
        #expect(chunked.status == 200)
        #expect(String(decoding: chunked.body, as: UTF8.self) == "hello world")
        #expect(server.lastRequest?.hasPrefix("GET /path?q=1 HTTP/1.1\r\n") == true)
        #expect(CompatNetwork.charset(fromContentType: chunked.headers["content-type"]) == "Shift_JIS")

        server.reply = "HTTP/1.1 404 Not Found\r\nContent-Length: 4\r\n\r\nnopeEXTRA"
        let missing = try #require(PlainHTTP.get(URL(string: "http://127.0.0.1:\(port)/")!))
        #expect(missing.status == 404)
        #expect(String(decoding: missing.body, as: UTF8.self) == "nope")

        // リダイレクトをたどる。本文はステータスによらず返す。
        server.reply = "HTTP/1.1 302 Found\r\nLocation: /next\r\nContent-Length: 0\r\n\r\n"
        server.replies["/next"] = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"
        let followed = try #require(CompatNetwork.fetch(URL(string: "http://127.0.0.1:\(port)/start")!))
        #expect(String(decoding: followed.data, as: UTF8.self) == "ok")
        #expect(PlainHTTP.get(URL(string: "http://127.0.0.1:1/")!) == nil) // つながらない
    }

    @Test
    func plainHTTPParsing() {
        let response = PlainHTTP.parse(Data("HTTP/1.0 200 OK\r\nX-A: b\r\n\r\nbody".utf8))
        #expect(response?.status == 200)
        #expect(response?.headers["x-a"] == "b")
        #expect(response.map { String(decoding: $0.body, as: UTF8.self) } == "body")
        #expect(PlainHTTP.parse(Data("garbage".utf8)) == nil)
        #expect(PlainHTTP.dechunk(Data("3;ext=1\r\nabc\r\n0\r\n\r\n".utf8)) == Data("abc".utf8))
        #expect(PlainHTTP.dechunk(Data("zz\r\n".utf8)) == nil)
    }

    // MARK: - mciaudio

    @Test
    func mciaudioLoadsAndTogglesPlayback() throws {
        final class FakePlayer: CompatAudioPlayer {
            var state = CompatAudioState.stopped
            var log: [String] = []
            func start(looping: Bool) { state = .playing; log.append(looping ? "loop" : "play") }
            func pause() { state = .paused; log.append("pause") }
            func resume() { state = .playing; log.append("resume") }
            func stop() { state = .stopped; log.append("stop") }
        }
        var created: [(URL, FakePlayer)] = []
        let saved = CompatSaoriHooks.makeAudioPlayer
        CompatSaoriHooks.makeAudioPlayer = { url in let player = FakePlayer(); created.append((url, player)); return player }
        defer { CompatSaoriHooks.makeAudioPlayer = saved }
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        try FileManager.default.createDirectory(at: ghost.root.appendingPathComponent("sound"), withIntermediateDirectories: true)
        try Data([0]).write(to: ghost.root.appendingPathComponent("sound/bgm.mp3"))
        func m(_ args: String...) -> Int { ghost.call("mciaudio.dll", args).status }

        #expect(m("play") == 204) // 何も読み込んでいない
        #expect(created.isEmpty)
        #expect(m("load", "sound\\bgm.mp3") == 204)
        #expect(m("play") == 204)
        #expect(created.first?.0.path == ghost.root.appendingPathComponent("sound/bgm.mp3").path)
        #expect(m("play") == 204) // 一時停止
        #expect(m("play") == 204) // 再開
        #expect(m("stop") == 204)
        #expect(m("loop") == 204)
        #expect(created.count == 1)
        #expect(created[0].1.log == ["play", "pause", "resume", "stop", "loop"])
        // 無いファイルは読み込んでも鳴らない。
        #expect(m("load", "none.mp3") == 204)
        #expect(m("play") == 204)
        #expect(created.count == 1)
        #expect(m("volume", "10") == 400)
        #expect(m() == 400)
        #expect(m("load") == 400)
        ghost.manager.unloadAll()
        #expect(created[0].1.state == .stopped)
    }

    // MARK: - hanayu

    @Test
    func hanayuConfigParsesBothStyles() {
        let config = CompatHanayuConfig.parse("""
        // コメント
        title,いっしょにいました時間
        line.color.r,3
        [score]
        graph,bar
        bar.color,a0b0f0
        偽AIグラフ
        {
        graph,radar
        title,
        }
        frame.width,1
        """)
        #expect(config.styles[""]?["title"] == "いっしょにいました時間")
        #expect(config.styles[""]?["line.color.r"] == "3")
        #expect(config.styles["score"]?["graph"] == "bar")
        #expect(config.styles["偽AIグラフ"]?["graph"] == "radar")
        #expect(config.styles["偽AIグラフ"]?["title"] == "")
        #expect(config.styles[""]?["frame.width"] == "1")
    }

    @Test
    func hanayuUsageSplitsTimeAcrossMidnight() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hanayud-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 22))!
        let usage = CompatHanayuUsage(file: file, now: start)
        usage.update(now: start.addingTimeInterval(4 * 3600 + 30)) // 22時〜翌2時0分30秒
        #expect(usage.minutes["20261020"] == 120)
        #expect(usage.minutes["20261021"] == 120) // 30 秒は次に持ち越す
        usage.update(now: start.addingTimeInterval(4 * 3600 + 90))
        #expect(usage.minutes["20261021"] == 121)
        let now = start.addingTimeInterval(4 * 3600 + 90)
        let days = usage.lastSevenDays(now: now)
        #expect(days.count == 7)
        #expect(days.last?.label == "10/21")
        #expect(abs((days.last?.hours ?? 0) - 121.0 / 60) < 0.001)
        // 原作と同じ形式: 6 日前から今日までの 7 行、`yyyyMMdd,分`、改行は CR LF。
        usage.save(now: now)
        #expect(try String(contentsOf: file, encoding: .utf8) == "20261015,0\r\n20261016,0\r\n20261017,0\r\n20261018,0\r\n20261019,0\r\n20261020,120\r\n20261021,121\r\n")
        let reloaded = CompatHanayuUsage(file: file)
        #expect(reloaded.minutes["20261021"] == 121)
    }

    @Test
    func hanayuShowsAndHidesGraphs() throws {
        var shown: [(CompatHanayuGraph, String)] = []
        var closed: [String] = []
        let saved = (CompatSaoriHooks.presentGraph, CompatSaoriHooks.dismissGraph)
        CompatSaoriHooks.presentGraph = { shown.append(($0, $1)) }
        CompatSaoriHooks.dismissGraph = { key in closed.append(key); return shown.contains { $0.1 == key } }
        defer { (CompatSaoriHooks.presentGraph, CompatSaoriHooks.dismissGraph) = saved }
        let ghost = try CompatGhost()
        defer { ghost.remove() }
        try "title,テスト\n[score]\ngraph,bar\n[pie]\ngraph,pie\n".write(to: ghost.root.appendingPathComponent("saori/hanayu.txt"), atomically: true, encoding: .utf8)
        func h(_ args: String...) -> Int { ghost.call("saori/hanayu.dll", args).status }

        #expect(h("show") == 204) // 起動時間のグラフ
        #expect(shown.last?.0.kind == .usetime)
        #expect(shown.last?.0.labels.count == 7)
        #expect(shown.last?.0.range == 0...24)
        #expect(shown.last?.0.title == "テスト")
        #expect(h("show", "score", "ステージ１", "10", "ステージ２", "25.5") == 204)
        #expect(shown.last?.0.kind == .bar)
        #expect(shown.last?.0.labels == ["ステージ１", "ステージ２"])
        #expect(shown.last?.0.values == [10, 25.5])
        #expect(h("show", "pie", "a", "1") == 204) // 知らない種類は usetime
        #expect(shown.last?.0.kind == .usetime)
        #expect(h("show", "nothing") == 400)
        #expect(h("hide", "score") == 204)
        #expect(h("hide", "never") == 400)
        #expect(h("draw") == 400)
        // 起動時間は hanayud.txt に残る。
        ghost.manager.unloadAll()
        #expect(FileManager.default.fileExists(atPath: ghost.root.appendingPathComponent("saori/hanayud.txt").path))
        #expect(Set(closed).count >= 2) // unload で開いていた窓を閉じる
    }

    @Test @MainActor
    func hanayuGraphViewsDrawEveryKind() throws {
        for kind in [CompatHanayuGraph.Kind.usetime, .line, .bar, .radar, .radar2] {
            var graph = CompatHanayuGraph(kind: kind, parameters: ["title": "t", "line.color": "0300D7", "bar.color": "a0b0f0", "frame.width": "1"], baseDirectory: nil)
            graph.labels = ["a", "b", "c", "d", "e"]
            graph.values = [1, 5, 3, 0, 4]
            let view = CompatHanayuGraphView(graph: graph)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            #expect(bitmap.pixelsWide >= Int(graph.size.width))
            // 背景は白、線の色の画素がどこかにある。
            let colors = (0..<bitmap.pixelsWide).flatMap { x in stride(from: 0, to: bitmap.pixelsHigh, by: 4).compactMap { bitmap.colorAt(x: x, y: $0) } }
            #expect(colors.contains { $0.blueComponent > 0.6 && $0.redComponent < 0.2 }, "\(kind)")
        }
        // 色の指定の読み方。
        let graph = CompatHanayuGraph(kind: .line, parameters: ["frame.color.r": "255", "font.color": "00FF00"], baseDirectory: nil)
        #expect(graph.color("frame")?.redComponent == 1)
        #expect(graph.color("font")?.greenComponent == 1)
        #expect(graph.color("bar") == nil)
        #expect(graph.color("background") == .white)
    }
}

/// 平文 HTTP の確かめ用のサーバー（決めた応答をそのまま返して閉じる）。
private final class CompatTestHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "jp.ourin.tests.compat-http")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var _reply = ""
    private var _replies: [String: String] = [:]
    private var _lastRequest: String?

    var reply: String {
        get { lock.lock(); defer { lock.unlock() }; return _reply }
        set { lock.lock(); _reply = newValue; lock.unlock() }
    }

    var replies: [String: String] {
        get { lock.lock(); defer { lock.unlock() }; return _replies }
        set { lock.lock(); _replies = newValue; lock.unlock() }
    }

    var lastRequest: String? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequest
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: self?.listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        lock.lock(); let current = connections; connections.removeAll(); lock.unlock()
        current.forEach { $0.forceCancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock(); connections.append(connection); lock.unlock()
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            self.lock.lock()
            self._lastRequest = request
            let body = self._replies[path] ?? self._reply
            self.lock.unlock()
            connection.send(content: Data(body.utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
