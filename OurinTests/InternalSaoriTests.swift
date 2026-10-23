import Foundation
import Testing
@testable import Ourin

private struct Outcome {
    var status: Int
    var result: String?
    var values: [String]
    var error: String?
    var charset: String?
}

/// 内蔵モジュールを SAORI/1.0 の要求として呼ぶ。
private func call(
    _ module: String, _ function: String, _ arguments: [String] = [],
    context: InternalSaoriContext = .none, registry: InternalSaoriRegistry = .shared
) -> Outcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: \(module)", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let responseText = registry.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: context)
    let response = try! SaoriProtocol.parseResponse(responseText)
    var values: [String] = []
    while let value = response.headerValue("Value\(values.count)") { values.append(value) }
    return Outcome(status: response.statusCode, result: response.headerValue("Result"), values: values,
                   error: response.headerValue("ErrorDescription"), charset: response.headerValue("Charset"))
}

private func ok(_ outcome: Outcome, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == 200, "status \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.result == expected, sourceLocation: sourceLocation)
}

private func fails(_ outcome: Outcome, _ status: Int, _ description: String, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(outcome.status == status, "got \(outcome.status) \(outcome.error ?? "")", sourceLocation: sourceLocation)
    #expect(outcome.error == description, sourceLocation: sourceLocation)
}

// MARK: - 共通規約

struct InternalSaoriProtocolTests {
    @Test
    func versionCheckAndErrorsFollowTheCommonRules() {
        func raw(_ text: String) -> SaoriResponse {
            try! SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(requestText: text))
        }
        // GET Version + Module: 使えれば 200。
        let version = raw("GET Version SAORI/1.0\r\nCharset: UTF-8\r\nModule: internal_text\r\n\r\n")
        #expect(version.statusCode == 200)
        #expect(version.headerValue("Result") == "Ourin Internal")
        // Module が無ければ invalid parameter、知らないモジュールは unknown module（大文字小文字は区別しない）。
        #expect(raw("GET Version SAORI/1.0\r\nCharset: UTF-8\r\n\r\n").headerValue("ErrorDescription") == "invalid parameter")
        #expect(raw("GET Version SAORI/1.0\r\nModule: internal_nothing\r\n\r\n").headerValue("ErrorDescription") == "unknown module")
        #expect(raw("GET Version SAORI/1.0\r\nModule: INTERNAL_TEXT\r\n\r\n").statusCode == 200)

        fails(call("internal_nothing", "Normalize"), 400, "unknown module")
        fails(call("internal_text", "Nothing"), 400, "unknown function")
        // 関数名は大文字小文字を区別しない。
        ok(call("internal_text", "normalize", ["NFC", "abc"]), "abc")
        // Argument0（関数名）が無い。
        let noFunction = try! SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(
            requestText: "EXECUTE SAORI/1.0\r\nModule: internal_text\r\n\r\n"))
        #expect(noFunction.headerValue("ErrorDescription") == "invalid parameter")
    }

    @Test
    func positionalArgumentsAndOptionsAreSeparatedStrictly() {
        // 位置引数の位置にある値は `--` で始まっていてもデータとして読む。
        ok(call("internal_text", "Normalize", ["NFC", "--not-an-option"]), "--not-an-option")
        // 引数が足りない。
        fails(call("internal_text", "Normalize", ["NFC"]), 400, "invalid parameter")
        // 位置引数より後ろにある `--` で始まらない値、受け付けないオプションは不正。
        fails(call("internal_text", "Normalize", ["NFC", "abc", "extra"]), 400, "invalid parameter")
        fails(call("internal_text", "Normalize", ["NFC", "abc", "--nothing=1"]), 400, "invalid parameter")
        // オプションは大文字小文字を区別せず、同じ名前は後のものが有効。
        ok(call("internal_data", "Convert", ["48656c6c6f", "--DATA-IN=base64", "--data-in=hex", "--out=base64"]), "SGVsbG8=")
    }

    @Test
    func emptyResultsAre204AndWiresCarryTheRequestCharset() {
        // 結果が空文字列なら 204。
        #expect(call("internal_text", "Normalize", ["NFC", ""]).status == 204)
        let wire = InternalSaoriRegistry.shared.handle(requestText: "EXECUTE SAORI/1.0\r\nCharset: Shift_JIS\r\nModule: internal_text\r\nArgument0: Normalize\r\nArgument1: NFC\r\nArgument2: a\r\n\r\n")
        #expect(wire.hasPrefix("SAORI/1.0 200 OK\r\n"))
        #expect(wire.contains("Charset: Shift_JIS"))
        #expect(wire.contains("Result: a"))
    }

    @Test
    func internalNamesAndRoutingAreRecognized() {
        #expect(InternalSaoriRegistry.isInternalName("internal_crypto"))
        #expect(InternalSaoriRegistry.isInternalName("Internal_Crypto"))
        #expect(!InternalSaoriRegistry.isInternalName("string"))
        #expect(InternalSaoriRouting.isSaoriRequest("EXECUTE SAORI/1.0\r\nModule: internal_text\r\n\r\n"))
        #expect(InternalSaoriRouting.isSaoriRequest("GET Version SAORI/1.0\r\nModule: internal_text\r\n\r\n"))
        #expect(!InternalSaoriRouting.isSaoriRequest("SEND SSTP/1.4\r\nSender: x\r\n\r\n"))
        #expect(!InternalSaoriRouting.isSaoriRequest("EXECUTE SSTP/1.4\r\nSender: x\r\n\r\n"))
        // Direct SSTP 以外では direct sstp only。
        let rejection = try! SaoriProtocol.parseResponse(InternalSaoriRouting.directSSTPOnlyResponse)
        #expect(rejection.statusCode == 400)
        #expect(rejection.headerValue("ErrorDescription") == "direct sstp only")
        // Direct SSTP で受けた応答は、要求の Charset の文字コードで返る。
        let data = InternalSaoriRouting.respond(to: "EXECUTE SAORI/1.0\r\nCharset: Shift_JIS\r\nModule: internal_text\r\nArgument0: Normalize\r\nArgument1: NFC\r\nArgument2: あ\r\n\r\n")
        #expect(String(data: data, encoding: .shiftJIS)?.contains("Result: あ") == true)
    }

    @Test
    func internalModulesAreCalledThroughTheSaoriManagerWithoutALoadedDLL() throws {
        let manager = SaoriManager()
        // YAYA の FUNCTIONEX は、モジュール名（.dll 付きでも）と Module ヘッダの無い要求で呼ぶ。
        let response = try manager.request(
            moduleName: "internal_text.dll",
            requestText: "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\nArgument0: Normalize\r\nArgument1: NFKC\r\nArgument2: ｶﾞｲﾄﾞ①\r\n\r\n"
        )
        #expect(try SaoriProtocol.parseResponse(response).headerValue("Result") == "ガイド1")
        // 内蔵モジュールは読み込み不要で、知らない名前は失敗する。
        #expect(manager.handlePluginOperation("saori_load", params: ["module": "internal_text"])["ok"] as? Bool == true)
        #expect(manager.handlePluginOperation("saori_load", params: ["module": "internal_nothing"])["ok"] as? Bool == false)
        #expect(manager.handlePluginOperation("saori_unload", params: ["module": "internal_text"])["ok"] as? Bool == true)
        let executed = manager.handlePluginOperation("saori_execute", params: [
            "module": "internal_data", "arguments": ["Convert", "abc", "--out=hex"]
        ])
        #expect(executed["status"] as? Int == 200)
    }
}

// MARK: - 非同期

struct InternalSaoriAsyncTests {
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [(name: String, references: [String: String])] = []
        func add(_ name: String, _ references: [String: String]) { lock.lock(); storage.append((name, references)); lock.unlock() }
        var all: [(name: String, references: [String: String])] { lock.lock(); defer { lock.unlock() }; return storage }
    }

    private func wait(_ events: Events, count: Int = 1) async throws {
        let deadline = Date().addingTimeInterval(8)
        while events.all.count < count, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    }

    private func ghostContext(_ events: Events) -> InternalSaoriContext {
        InternalSaoriContext(ghostRoot: URL(fileURLWithPath: "/tmp/ghost/master"), deliverEvent: { events.add($0, $1) })
    }

    @Test
    func asyncCallsAnswer204ImmediatelyAndDeliverTheResultAsAnEvent() async throws {
        let events = Events()
        let outcome = call("internal_data", "Convert", ["48656c6c6f", "--data-in=hex", "--out=base64", "--async=job1"], context: ghostContext(events))
        #expect(outcome.status == 204)
        try await wait(events)
        let event = try #require(events.all.first)
        // 識別子が On で始まらなければ OnInternalSaoriComplete。
        #expect(event.name == "OnInternalSaoriComplete")
        #expect(event.references["Reference0"] == "job1")
        #expect(event.references["Reference1"] == "SGVsbG8=")
        #expect(event.references["Reference2"] == "internal_data")
        #expect(event.references["Reference3"] == "Convert")
    }

    @Test
    func anOnPrefixedIdentifierBecomesTheEventNameAndFailuresAddFailure() async throws {
        let events = Events()
        let context = ghostContext(events)
        _ = call("internal_text", "Normalize", ["NFC", "abc", "--async=OnNormalized"], context: context)
        // 引数の中身の誤り（読めない 16 進）は、受付ではなく失敗のイベントで届く。
        let accepted = call("internal_data", "Convert", ["zz", "--data-in=hex", "--async=OnConvertDone"], context: context)
        #expect(accepted.status == 204)
        _ = call("internal_data", "Convert", ["zz", "--data-in=hex", "--async=plain"], context: context)
        try await wait(events, count: 3)
        let byName = Dictionary(events.all.map { ($0.name, $0.references) }, uniquingKeysWith: { first, _ in first })
        #expect(byName["OnNormalized"]?["Reference1"] == "abc")
        #expect(byName["OnConvertDoneFailure"]?["Reference0"] == "OnConvertDone")
        #expect(byName["OnConvertDoneFailure"]?["Reference1"] == "invalid encoding")
        #expect(byName["OnConvertDoneFailure"]?["Reference2"] == "internal_data")
        #expect(byName["OnConvertDoneFailure"]?["Reference3"] == "Convert")
        #expect(byName["OnInternalSaoriFailure"]?["Reference0"] == "plain")
    }

    @Test
    func multipleValuesFollowFromReference4() async throws {
        let events = Events()
        _ = call("internal_system", "ListModules", ["--async=OnList"], context: ghostContext(events))
        try await wait(events)
        let event = try #require(events.all.first)
        let names = InternalSaoriRegistry.shared.moduleNames
        #expect(event.references["Reference1"] == names.joined(separator: ","))
        #expect(event.references["Reference4"] == names.first)
    }

    @Test
    func asyncNeedsAGhostAndAnIdentifierAndValidArgumentsAtAcceptance() {
        let events = Events()
        // ゴーストなしの呼び出しでは使えない。
        fails(call("internal_text", "Normalize", ["NFC", "a", "--async=OnX"]), 400, "ghost required")
        // 識別子が空なら invalid parameter。
        fails(call("internal_text", "Normalize", ["NFC", "a", "--async="], context: ghostContext(events)), 400, "invalid parameter")
        // 引数の数やオプションの名前の誤りは、受付の時点で 400。
        fails(call("internal_text", "Normalize", ["--async=OnX"], context: ghostContext(events)), 400, "invalid parameter")
        // 位置引数の位置にある `--async=...` はデータとして読むので、非同期にはならない。
        ok(call("internal_text", "Normalize", ["NFC", "--async=OnX"], context: ghostContext(events)), "--async=OnX")
        fails(call("internal_text", "Normalize", ["NFC", "a", "--bogus=1", "--async=OnX"], context: ghostContext(events)), 400, "invalid parameter")
        #expect(events.all.isEmpty)
    }
}

// MARK: - internal_system / random / text

struct InternalSaoriSmallModuleTests {
    @Test
    func listModulesAndFunctions() {
        let modules = call("internal_system", "ListModules")
        #expect(modules.status == 200)
        let names = modules.result?.split(separator: ",").map(String.init) ?? []
        #expect(names == InternalSaoriRegistry.shared.moduleNames)
        for expected in ["internal_system", "internal_random", "internal_time", "internal_text", "internal_data"] {
            #expect(names.contains(expected))
        }
        #expect(modules.values == names)

        let functions = call("internal_system", "ListFunctions", ["INTERNAL_TIME"])
        ok(functions, "Format,Add,Diff")
        #expect(functions.values == ["Format", "Add", "Diff"])
        fails(call("internal_system", "ListFunctions", ["string"]), 400, "unknown module")
    }

    @Test
    func randomBytesNumberAndUUID() throws {
        let bytes = call("internal_random", "Bytes", ["16"])
        #expect(bytes.status == 200)
        #expect(bytes.result?.count == 32)
        #expect(call("internal_random", "Bytes", ["4", "--out=base64"]).result?.count == 8)
        fails(call("internal_random", "Bytes", ["0"]), 400, "out of range")
        fails(call("internal_random", "Bytes", ["1025"]), 400, "out of range")
        #expect(call("internal_random", "Bytes", ["1024"]).result?.count == 2048)
        // 同じ長さでも、呼ぶたびに違う値になる。
        #expect(call("internal_random", "Bytes", ["16"]).result != bytes.result)
        fails(call("internal_random", "Bytes", ["x"]), 400, "invalid parameter")

        var seen = Set<Int64>()
        for _ in 0..<200 {
            let value = try #require(Int64(call("internal_random", "Number", ["-3", "3"]).result ?? ""))
            #expect((-3...3).contains(value))
            seen.insert(value)
        }
        #expect(seen.count == 7)
        ok(call("internal_random", "Number", ["5", "5"]), "5")
        fails(call("internal_random", "Number", ["6", "5"]), 400, "invalid parameter")
        // 64 ビット符号付き整数の全範囲でも動く。
        #expect(Int64(call("internal_random", "Number", ["-9223372036854775808", "9223372036854775807"]).result ?? "") != nil)

        let v4 = try #require(call("internal_random", "UUID").result)
        #expect(v4.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression) != nil)
        let before = UInt64(Date().timeIntervalSince1970 * 1000)
        let v7 = try #require(call("internal_random", "UUID", ["--version=7"]).result)
        #expect(v7.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#, options: .regularExpression) != nil)
        // 先頭の 48 ビットは現在時刻（ミリ秒）。
        let timestamp = try #require(UInt64(v7.replacingOccurrences(of: "-", with: "").prefix(12), radix: 16))
        #expect(timestamp >= before - 1000 && timestamp <= before + 5000)
        fails(call("internal_random", "UUID", ["--version=5"]), 400, "invalid parameter")
        #expect(call("internal_random", "UUID").result != v4)
    }

    @Test
    func normalizeFollowsTheDocumentedExample() {
        ok(call("internal_text", "Normalize", ["NFKC", "ｶﾞｲﾄﾞ①"]), "ガイド1")
        // 合成済みの文字と結合文字の並び。
        let composed = "\u{00E9}", decomposed = "e\u{0301}"
        ok(call("internal_text", "Normalize", ["NFD", composed]), decomposed)
        ok(call("internal_text", "Normalize", ["nfc", decomposed]), composed)
        fails(call("internal_text", "Normalize", ["NFX", "a"]), 400, "unsupported algorithm")
    }
}

// MARK: - internal_time

struct InternalTimeTests {
    @Test
    func formatFollowsTheDocumentedExample() {
        ok(call("internal_time", "Format", ["0", "%Y/%m/%d %H:%M (%a)", "--tz=+09:00"]), "1970/01/01 09:00 (Thu)")
        ok(call("internal_time", "Format", ["0", "", "--tz=UTC"]), "1970-01-01T00:00:00Z")
        ok(call("internal_time", "Format", ["0", "iso8601", "--tz=+09:00"]), "1970-01-01T09:00:00+09:00")
        ok(call("internal_time", "Format", ["0", "rfc3339", "--tz=-05:30"]), "1969-12-31T18:30:00-05:30")
        ok(call("internal_time", "Format", ["1791720000", "http", "--tz=+09:00"]), "Sun, 11 Oct 2026 12:00:00 GMT")
        ok(call("internal_time", "Format", ["86400", "epoch"]), "86400")
        ok(call("internal_time", "Format", ["86400", "epochms"]), "86400000")
        // 各 % 書式。2026-10-11 は日曜、年の 284 日目。
        ok(call("internal_time", "Format", ["2026-10-11T21:05:09+09:00", "%Y|%y|%m|%d|%H|%M|%S|%j|%u|%w|%a|%A|%b|%B|%z|%:z|%s|%%", "--tz=+09:00"]),
           "2026|26|10|11|21|05|09|284|7|0|Sun|Sunday|Oct|October|+0900|+09:00|1791720309|%")
        ok(call("internal_time", "Format", ["2026-10-12T00:00:00Z", "%u %w %a", "--tz=UTC"]), "1 1 Mon")
        // 知らない書式名・% の文字は invalid parameter。
        fails(call("internal_time", "Format", ["0", "nothing"]), 400, "invalid parameter")
        fails(call("internal_time", "Format", ["0", "%Q"]), 400, "invalid parameter")
        fails(call("internal_time", "Format", ["0", "%Y%"]), 400, "invalid parameter")
    }

    @Test
    func timeZonesAndDateArguments() {
        // IANA の名前（大文字小文字は区別しない）は、その日時の夏時間を反映する。
        ok(call("internal_time", "Format", ["2026-07-01T12:00:00Z", "%H:%M %z", "--tz=america/new_york"]), "08:00 -0400")
        ok(call("internal_time", "Format", ["2026-01-01T12:00:00Z", "%H:%M %z", "--tz=America/New_York"]), "07:00 -0500")
        ok(call("internal_time", "Format", ["0", "%H", "--tz=+0900"]), "09")
        ok(call("internal_time", "Format", ["0", "%H", "--tz=+09"]), "09")
        fails(call("internal_time", "Format", ["0", "%H", "--tz=+19:00"]), 400, "invalid parameter")
        fails(call("internal_time", "Format", ["0", "%H", "--tz=Nowhere/Land"]), 400, "invalid parameter")
        // ゾーンの無い日時は --tz= のゾーンの時刻として読む。
        ok(call("internal_time", "Format", ["2026-10-11 21:00", "epoch", "--tz=+09:00"]), "1791720000")
        ok(call("internal_time", "Format", ["2026-10-11T21:00:00+09:00", "epoch", "--tz=UTC"]), "1791720000")
        ok(call("internal_time", "Format", ["20261011T120000Z", "epoch"]), "1791720000")
        ok(call("internal_time", "Format", ["2026-10-11", "epoch", "--tz=UTC"]), "1791676800")
        ok(call("internal_time", "Format", ["Sun, 11 Oct 2026 12:00:00 GMT", "epoch"]), "1791720000")
        ok(call("internal_time", "Format", ["2026-10-11T21:00:00.987+09:00", "epoch"]), "1791720000")
        // now は現在時刻。
        let now = Int64(Date().timeIntervalSince1970)
        let value = Int64(call("internal_time", "Format", ["now", "epoch"]).result ?? "") ?? 0
        #expect(abs(value - now) <= 2)
        // 存在しない日付や、読めない文字列は invalid parameter。
        fails(call("internal_time", "Format", ["2026-02-30", "epoch"]), 400, "invalid parameter")
        fails(call("internal_time", "Format", ["2026-13-01", "epoch"]), 400, "invalid parameter")
        fails(call("internal_time", "Format", ["2026-10-11T24:00", "epoch"]), 400, "invalid parameter")
        fails(call("internal_time", "Format", ["yesterday", "epoch"]), 400, "invalid parameter")
        fails(call("internal_time", "Format", ["1500-01-01", "epoch"]), 400, "invalid parameter")
        // 範囲（UTC で 0001〜9999 年）の外は out of range。
        fails(call("internal_time", "Format", ["253402300800", "epoch"]), 400, "out of range")
        fails(call("internal_time", "Format", ["-62135596801", "epoch"]), 400, "out of range")
        // 範囲の端は書式にできる（1582 年より前の日付は、OS のカレンダーに従いユリウス暦で数える）。
        #expect(call("internal_time", "Format", ["-62135596800", "%Y", "--tz=UTC"]).result == "0001")
        ok(call("internal_time", "Format", ["-86400", "%Y-%m-%d", "--tz=UTC"]), "1969-12-31")
    }

    @Test
    func addAndDiffUseTheCalendarOfTheZone() {
        // 月末は丸める。
        let endOfMonth = call("internal_time", "Add", ["2026-01-31T10:00", "1", "month", "--tz=UTC"])
        ok(call("internal_time", "Format", [endOfMonth.result ?? "", "%Y-%m-%d %H:%M", "--tz=UTC"]), "2026-02-28 10:00")
        ok(call("internal_time", "Format", [call("internal_time", "Add", ["2024-01-31T10:00", "1", "month", "--tz=UTC"]).result ?? "", "%Y-%m-%d", "--tz=UTC"]), "2024-02-29")
        // second / minute / hour は経過時間で足す。複数形も使える。
        ok(call("internal_time", "Add", ["0", "90", "minutes"]), "5400")
        ok(call("internal_time", "Add", ["0", "-1", "hour"]), "-3600")
        ok(call("internal_time", "Add", ["0", "2", "weeks", "--tz=UTC"]), "1209600")
        let nextYear = call("internal_time", "Add", ["2026-02-28", "1", "year", "--tz=UTC"])
        ok(call("internal_time", "Format", [nextYear.result ?? "", "%Y-%m-%d", "--tz=UTC"]), "2027-02-28")
        // 夏時間の切り替えをまたいでも、day 以上は同じ時刻になる（ニューヨークは 2026-03-08 に切り替わる）。
        let across = call("internal_time", "Add", ["2026-03-07T12:00", "1", "day", "--tz=America/New_York"])
        ok(call("internal_time", "Format", [across.result ?? "", "%Y-%m-%d %H:%M", "--tz=America/New_York"]), "2026-03-08 12:00")
        fails(call("internal_time", "Add", ["0", "1", "fortnight"]), 400, "invalid parameter")
        fails(call("internal_time", "Add", ["0", "x", "day"]), 400, "invalid parameter")
        fails(call("internal_time", "Add", ["253402300799", "1", "second"]), 400, "out of range")

        // Diff: 日時2 − 日時1。端数は 0 の方向へ切り捨て。
        ok(call("internal_time", "Diff", ["2026-12-20T10:00", "2026-12-24", "day", "--tz=UTC"]), "3")
        ok(call("internal_time", "Diff", ["2026-12-24", "2026-12-20T10:00", "day", "--tz=UTC"]), "-3")
        ok(call("internal_time", "Diff", ["0", "7199", "hour"]), "1")
        ok(call("internal_time", "Diff", ["0", "-7199", "hour"]), "-1")
        ok(call("internal_time", "Diff", ["0", "119", "minute"]), "1")
        ok(call("internal_time", "Diff", ["0", "15", "second"]), "15")
        ok(call("internal_time", "Diff", ["2026-01-31", "2026-02-28", "month", "--tz=UTC"]), "1")
        ok(call("internal_time", "Diff", ["2026-01-31", "2026-02-27", "month", "--tz=UTC"]), "0")
        // 年は Add で足して越えない最大の数（2020-02-29 に 6 年足すと 2026-02-28 になる）。
        ok(call("internal_time", "Diff", ["2020-02-29", "2026-02-28", "year", "--tz=UTC"]), "6")
        ok(call("internal_time", "Diff", ["2020-02-29", "2026-02-27", "year", "--tz=UTC"]), "5")
        ok(call("internal_time", "Diff", ["2026-01-01", "2026-01-23", "week", "--tz=UTC"]), "3")
    }
}

// MARK: - 形式と internal_data

struct InternalDataTests {
    @Test
    func convertFollowsTheDocumentedExamples() {
        ok(call("internal_data", "Convert", ["48656c6c6f", "--data-in=hex", "--out=base64"]), "SGVsbG8=")
        let key = "7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e"
        let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        ok(call("internal_data", "Convert", [key, "--data-in=hex", "--out=bech32", "--hrp=npub"]), npub)
        ok(call("internal_data", "Convert", [npub, "--data-in=bech32", "--out=hex"]), key)
        // 大文字だけでも読める。混在・チェックサムの誤りは invalid encoding。
        ok(call("internal_data", "Convert", [npub.uppercased(), "--data-in=bech32", "--out=hex"]), key)
        fails(call("internal_data", "Convert", [String(npub.prefix(10)) + npub.dropFirst(10).uppercased(), "--data-in=bech32"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", [String(npub.dropLast()) + "q", "--data-in=bech32"]), 400, "invalid encoding")
        // --hrp は bech32 の出力でだけ使う（無ければ invalid parameter）。
        fails(call("internal_data", "Convert", [key, "--data-in=hex", "--out=bech32"]), 400, "invalid parameter")
    }

    @Test
    func everyFormatRoundTrips() {
        let samples: [(format: String, text: String, hex: String)] = [
            ("base64", "SGVsbG8=", "48656c6c6f"),
            ("base64url", "-_8", "fbff"),
            ("base32", "MZXW6YTBOI======", "666f6f626172"),
            ("url", "a%20b~%2Fz", "6120627e2f7a"),
            ("hex", "48656C6C6F", "48656c6c6f")
        ]
        for sample in samples {
            ok(call("internal_data", "Convert", [sample.text, "--data-in=\(sample.format)", "--out=hex"]), sample.hex)
        }
        ok(call("internal_data", "Convert", ["fbff", "--data-in=hex", "--out=base64url"]), "-_8")
        ok(call("internal_data", "Convert", ["fbff", "--data-in=hex", "--out=base64"]), "+/8=")
        ok(call("internal_data", "Convert", ["666f6f626172", "--data-in=hex", "--out=base32"]), "MZXW6YTBOI======")
        ok(call("internal_data", "Convert", ["6120627e2f7a", "--data-in=hex", "--out=url"]), "a%20b~%2Fz")
        ok(call("internal_data", "Convert", ["48656c6c6f", "--data-in=hex", "--out=HEX"]), "48656C6C6F")
        // base64 と base64url の両方の文字を、パディングの有無によらず読む。base32 は大文字小文字を問わない。
        ok(call("internal_data", "Convert", ["+/8", "--data-in=base64", "--out=hex"]), "fbff")
        ok(call("internal_data", "Convert", ["-_8=", "--data-in=base64", "--out=hex"]), "fbff")
        ok(call("internal_data", "Convert", ["mzxw6ytboi", "--data-in=base32", "--out=hex"]), "666f6f626172")
        // + は空白に戻さない。
        ok(call("internal_data", "Convert", ["a+b", "--data-in=url", "--out=hex"]), "612b62")
    }

    @Test
    func textCharsetAndInvalidEncodings() {
        // 既定は UTF-8。--charset= で別の文字コードのバイト列にする。
        ok(call("internal_data", "Convert", ["あ", "--out=hex"]), "e38182")
        ok(call("internal_data", "Convert", ["あ", "--out=hex", "--charset=Shift_JIS"]), "82a0")
        ok(call("internal_data", "Convert", ["82a0", "--data-in=hex", "--charset=Shift_JIS"]), "あ")
        fails(call("internal_data", "Convert", ["あ", "--charset=UTF-16"]), 400, "invalid parameter")
        fails(call("internal_data", "Convert", ["あ", "--charset=Nowhere"]), 400, "invalid parameter")
        // その文字コードで表せない文字。
        fails(call("internal_data", "Convert", ["😀", "--out=hex", "--charset=Shift_JIS"]), 400, "invalid encoding")
        // 奇数桁・16 進以外・不正なパディング・% の後ろが 16 進 2 桁でない。
        fails(call("internal_data", "Convert", ["abc", "--data-in=hex"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["zz", "--data-in=hex"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["a", "--data-in=base64"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["ab=c", "--data-in=base64"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["a!", "--data-in=base64"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["MZXW1", "--data-in=base32"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["%4", "--data-in=url"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["%zz", "--data-in=url"]), 400, "invalid encoding")
        fails(call("internal_data", "Convert", ["a", "--data-in=nothing"]), 400, "invalid parameter")
        // 文字列に戻せないバイト列、NUL・改行を含むものは 500 not text。
        fails(call("internal_data", "Convert", ["ff", "--data-in=hex", "--out=text"]), 500, "not text")
        fails(call("internal_data", "Convert", ["610a62", "--data-in=hex", "--out=text"]), 500, "not text")
        fails(call("internal_data", "Convert", ["610062", "--data-in=hex", "--out=text"]), 500, "not text")
    }

    @Test
    func compressionRoundTripsAndMatchesAKnownGzip() throws {
        // 記述例: gzip の "Hello"。
        ok(call("internal_data", "Decompress", ["gzip", "H4sIAAAAAAAACvNIzcnJBwCCidH3BQAAAA=="]), "Hello")
        // SAORI のヘッダの値は、先頭・末尾の空白を書けない。
        let text = String(repeating: "桜鈴 Ourin 0123456789 ", count: 400) + "end"
        for method in ["gzip", "zlib", "deflate"] {
            let compressed = call("internal_data", "Compress", [method, text])
            #expect(compressed.status == 200, "\(method)")
            let packed = try #require(compressed.result)
            #expect(packed.count < text.utf8.count, "\(method) should shrink repetitive text")
            ok(call("internal_data", "Decompress", [method, packed]), text)
        }
        // 他の形式で受け渡す（--data-in / --out）。--level は 0〜9。
        let binary = call("internal_data", "Compress", ["zlib", "000102030405", "--data-in=hex", "--out=hex", "--level=9"])
        #expect(binary.result?.hasPrefix("789c") == true)
        ok(call("internal_data", "Decompress", ["zlib", binary.result ?? "", "--data-in=hex", "--out=hex"]), "000102030405")
        fails(call("internal_data", "Compress", ["zlib", "a", "--level=10"]), 400, "invalid parameter")
        fails(call("internal_data", "Compress", ["lzma", "a"]), 400, "unsupported algorithm")
        fails(call("internal_data", "Decompress", ["lzma", "AA=="]), 400, "unsupported algorithm")
        // 空のデータも往復できる。
        let empty = call("internal_data", "Compress", ["gzip", ""])
        #expect(call("internal_data", "Decompress", ["gzip", empty.result ?? ""]).status == 204)
    }

    @Test
    func brokenTruncatedAndOversizedDataIsRejected() throws {
        let packed = try #require(call("internal_data", "Compress", ["gzip", "Hello, Ourin"]).result)
        let bytes = try InternalSaoriCodec.decodeBase64(packed)
        func decompress(_ data: Data, _ method: String = "gzip") -> Outcome {
            call("internal_data", "Decompress", [method, data.base64EncodedString()])
        }
        ok(decompress(bytes), "Hello, Ourin")
        // 途中で切れている・壊れている・後ろに余計なデータがある。
        fails(decompress(bytes.dropLast(3)), 400, "invalid encoding")
        var broken = bytes
        broken[broken.count - 6] ^= 0xFF // CRC を壊す
        fails(decompress(broken), 400, "invalid encoding")
        fails(decompress(bytes + Data([0x00])), 400, "invalid encoding")
        fails(decompress(Data([0x01, 0x02, 0x03])), 400, "invalid encoding")
        // 複数のメンバーをつないだ gzip は読める。
        ok(decompress(bytes + bytes), "Hello, OurinHello, Ourin")
        // zlib / deflate も同じ。
        let zlib = try #require(call("internal_data", "Compress", ["zlib", "abc"]).result)
        fails(decompress(try InternalSaoriCodec.decodeBase64(zlib).dropLast(), "zlib"), 400, "invalid encoding")
        fails(decompress(try InternalSaoriCodec.decodeBase64(zlib) + Data([0]), "zlib"), 400, "invalid encoding")
        // 展開した後の大きさも 8MB まで（圧縮爆弾を防ぐ）。
        let bomb = try InternalCompression.compress(Data(repeating: 0, count: InternalSaoriCodec.maximumBytes + 1024), method: "gzip")
        #expect(bomb.count < 100_000)
        fails(decompress(bomb), 400, "too large")
        // zstd の展開は OS の圧縮フレームワークに無いので、未対応と返す。
        fails(call("internal_data", "Decompress", ["zstd", "KLUv/QA="]), 400, "unsupported algorithm")
    }

    @Test
    func base32AndBech32MatchPublishedVectors() throws {
        // RFC 4648 のテストベクタ。
        let vectors = [("", ""), ("f", "MY======"), ("fo", "MZXQ===="), ("foo", "MZXW6==="), ("foob", "MZXW6YQ="), ("fooba", "MZXW6YTB"), ("foobar", "MZXW6YTBOI======")]
        for (plain, encoded) in vectors {
            #expect(InternalSaoriCodec.encodeBase32(Data(plain.utf8)) == encoded)
            #expect(try InternalSaoriCodec.decodeBase32(encoded) == Data(plain.utf8))
        }
        // BIP-173 の例（bech32）。
        let valid = "a12uel5l" // hrp=a、データなし
        #expect(try Bech32.decodeData(valid).isEmpty)
        #expect(try Bech32.encode(hrp: "a", data: Data()) == valid)
        // bech32m は読めない。
        #expect(throws: InternalSaoriError.self) { try Bech32.decodeData("a1lqfn3a") }
        #expect(InternalCompression.crc32(Data("123456789".utf8)) == 0xCBF43926)
        #expect(InternalCompression.adler32(Data("Wikipedia".utf8)) == 0x11E60398)
    }
}

// MARK: - YAYA から

/// 本物の yaya_core から `FUNCTIONEX` で内蔵モジュールを呼ぶ。yaya_core が無い環境ではスキップする。
struct InternalSaoriYayaTests {
    private func makeRuntime(dic: String) throws -> (YayaAdapter, URL)? {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let executable = repositoryRoot.appendingPathComponent("yaya_core/build/yaya_core")
        guard FileManager.default.isExecutableFile(atPath: executable.path),
              let runtime = YayaAdapter(executableURL: executable) else {
            print("[skip] yaya_core is not built; skipping the FUNCTIONEX test")
            return nil
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-InternalSaori-\(UUID().uuidString)", isDirectory: true)
        let master = root.appendingPathComponent("ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        try Data(dic.utf8).write(to: master.appendingPathComponent("test.dic"))
        let context = ShioriRuntimeLoadContext(
            ghostURL: root, ghostRoot: master, moduleName: "yaya.dll",
            dictionaryEntries: [DicEntry(path: "test.dic", encoding: "UTF-8", sourceConfig: "yaya.txt", sourceLine: 1)]
        )
        guard runtime.load(context: context) else {
            runtime.unload()
            try? FileManager.default.removeItem(at: root)
            Issue.record("YAYA could not load the dictionary")
            return nil
        }
        return (runtime, root)
    }

    @Test
    func functionExCallsInternalModulesSynchronouslyWithoutALoadedDLL() throws {
        let dic = """
        OnNormalize
        {
        	FUNCTIONEX('internal_text', 'Normalize', 'NFKC', 'ｶﾞｲﾄﾞ①')
        }
        OnDigestLike
        {
        	FUNCTIONEX('internal_data', 'Convert', '48656c6c6f', '--data-in=hex', '--out=base64')
        }
        OnUnknown
        {
        	"[" + FUNCTIONEX('internal_nothing', 'X') + "]"
        }
        """
        guard let (runtime, root) = try makeRuntime(dic: dic) else { return }
        defer { runtime.unload(); try? FileManager.default.removeItem(at: root) }

        func value(_ id: String) -> String {
            runtime.request(method: "GET", id: id, headers: ["Charset": "UTF-8"], refs: [], timeout: 10)?.value ?? ""
        }
        #expect(value("OnNormalize") == "ガイド1")
        #expect(value("OnDigestLike") == "SGVsbG8=")
        // 知らないモジュールの呼び出しは、YAYA からは空の結果になる。
        #expect(value("OnUnknown") == "[]")
        // 内蔵モジュールは読み込み不要（LOADLIB の呼び出し先は、名前を確かめるだけで成功する）。
        #expect(runtime.handlePluginOperation("saori_load", params: ["module": "internal_text"])["ok"] as? Bool == true)
        #expect(runtime.handlePluginOperation("saori_load", params: ["module": "internal_nothing"])["ok"] as? Bool == false)
        #expect(runtime.handlePluginOperation("saori_unload", params: ["module": "internal_text"])["ok"] as? Bool == true)
    }
}

// MARK: - 結果をそのゴーストだけに届ける

private final class InternalSaoriCapturingRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    private let lock = NSLock()
    private var storage: [(method: String, id: String, refs: [String])] = []

    var requests: [(method: String, id: String, refs: [String])] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(method: String, id: String, headers: [String: String], refs: [String], timeout: TimeInterval) -> ShioriRuntimeResponse? {
        lock.lock(); storage.append((method, id, refs)); lock.unlock()
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

@Suite(.serialized, .eventBridgeIsolated)
struct InternalSaoriDeliveryTests {
    @Test @MainActor
    func theAsyncResultReachesOnlyTheGhostThatCalledAndNeverAFinishedOne() async throws {
        EventBridge.shared.stop()
        let callerURL = URL(fileURLWithPath: "/tmp/ourin-internal-saori-caller")
        let otherURL = URL(fileURLWithPath: "/tmp/ourin-internal-saori-other")
        let caller = GhostManager(ghostURL: callerURL)
        let other = GhostManager(ghostURL: otherURL)
        let callerRuntime = InternalSaoriCapturingRuntime()
        let otherRuntime = InternalSaoriCapturingRuntime()
        caller.shioriRuntime = callerRuntime
        other.shioriRuntime = otherRuntime
        let callerToken = EventBridge.shared.register(runtime: callerRuntime, ghostManager: caller)
        let otherToken = EventBridge.shared.register(runtime: otherRuntime, ghostManager: other)
        defer {
            EventBridge.shared.unregister(otherToken)
            EventBridge.shared.stop()
            _ = caller.shutdown()
            _ = other.shutdown()
        }

        let context = InternalSaoriContext(
            ghostRoot: callerURL.appendingPathComponent("ghost/master"),
            deliverEvent: { name, params in EventBridge.shared.notifyCustom(name, params: params, toGhostAt: callerURL) }
        )
        let accepted = call("internal_data", "Convert", ["abc", "--out=hex", "--async=OnHexDone"], context: context)
        #expect(accepted.status == 204)

        let deadline = Date().addingTimeInterval(30)
        while !callerRuntime.requests.contains(where: { $0.id == "OnHexDone" }), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let delivered = try #require(callerRuntime.requests.first { $0.id == "OnHexDone" })
        #expect(delivered.method == "NOTIFY")
        #expect(delivered.refs.prefix(4) == ["OnHexDone", "616263", "internal_data", "Convert"])
        // 呼び出したゴースト以外には届かない。
        #expect(otherRuntime.requests.allSatisfy { $0.id != "OnHexDone" })

        // 結果が届く前にゴーストが終了していたら、届けない。
        EventBridge.shared.unregister(callerToken)
        let before = callerRuntime.requests.count
        _ = call("internal_data", "Convert", ["abc", "--out=hex", "--async=OnLate"], context: context)
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(callerRuntime.requests.count == before)
        #expect(otherRuntime.requests.allSatisfy { $0.id != "OnLate" })
    }
}
