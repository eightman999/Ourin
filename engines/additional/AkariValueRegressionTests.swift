// Self-authored regression fixtures. No third-party dictionaries are embedded.
// Reference: https://le.silk.to/akari.php (_eventdict / _customrequest example).
import Foundation
import ModuleProtocol
import Testing
@testable import AkariCore

private let dispatchSource = #"""
array _customrequest(dict ref) {
    string s = _eventdict[ref["ID"]];
    if (s == "") s = _fncstr(ref["ID"], ref);
    array ar;
    ar += "PLUGIN/2.0 200 OK";
    ar += "Charset: UTF-8";
    if (s != "") ar += "Script: " + s;
    ar += "";
    return ar;
}
"""#
private func pluginRequest(_ id: String) -> ShioriRequest {
    ShioriRequest(method: "GET", version: "PLUGIN/2.0M", headers: .init([
        .init(name: "ID", value: id), .init(name: "Sender", value: "OurinRegression"),
        .init(name: "SecurityLevel", value: "Local"), .init(name: "Reference0", value: "0"),
        .init(name: "Reference1", value: "Ourin"), .init(name: "Reference2", value: "master"),
        .init(name: "Reference3", value: "fixture")]))
}
private func withScript(_ source: String, body: (AkariSession) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "ourin-akari-regression-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try (source + "\n" + dispatchSource).write(to: root.appending(path: "main.azr"), atomically: true, encoding: .utf8)
    let session = try AkariSession(masterDirectoryURL: root, httpFetcher: FixtureHTTP())
    try await body(session)
    try await session.shutdown()
}
private struct FixtureHTTP: AkariHTTPFetching {
    func fetch(url: URL, maximumBytes: Int) -> Data? {
        guard url.absoluteString == "http://www.jma.go.jp/bosai/common/const/area.json" else { return nil }
        return Data(#"{"centers":{},"offices":{}}"#.utf8)
    }
}

@Test func ourinAkariMissingEventDispatchesFunction() async throws {
    try await withScript(#"string OnMenuExec(dict ref) { return "dispatched"; }"#) { session in
        let response1 = try await session.pluginResponse(for: pluginRequest("OnMenuExec"))
        #expect(response1.headers["Script"] == "dispatched")
    }
}
@Test func ourinAkariEventDictionaryTakesPriority() async throws {
    try await withScript(#"""
load() { _eventdict += $("OnMenuExec", "dictionary"); }
string OnMenuExec(dict ref) { return "function-should-not-run"; }
"""#) { session in
        let response2 = try await session.pluginResponse(for: pluginRequest("OnMenuExec"))
        #expect(response2.headers["Script"] == "dictionary")
    }
}
@Test func ourinAkariEmptyEventIsNotRetried() async throws {
    try await withScript(#"""
int calls;
string OnMenuExec(dict ref) { calls++; if (calls == 1) return ""; return "second"; }
"""#) { session in
        let response3 = try await session.pluginResponse(for: pluginRequest("OnMenuExec"))
        #expect(response3.headers["Script"] == nil)
        let response4 = try await session.pluginResponse(for: pluginRequest("OnMenuExec"))
        #expect(response4.headers["Script"] == "second")
    }
}
@Test func ourinAkariTypedInitializersAndDefaults() async throws {
    try await withScript(#"""
string global = 17;
string OnMenuExec(dict ref) {
    string missing = _eventdict["missing"];
    string number = 42;
    string text;
    array items;
    dict entries;
    double fraction;
    if (missing != "") return "bad-nil";
    return _gettype(global) + ":" + _gettype(number) + ":" + text + ":" + _aryvn(items) + ":" + _dicvn(entries) + ":" + _gettype(fraction);
}
"""#) { session in
        let response5 = try await session.pluginResponse(for: pluginRequest("OnMenuExec"))
        #expect(response5.headers["Script"] == "string:string::0:0:double")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["OURIN_AKARI_PLUGIN_FIXTURES"] != nil))
func ourinAkariRealUnmodifiedPluginMenus() async throws {
    let fixtureRoot = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OURIN_AKARI_PLUGIN_FIXTURES"]))
    for id in ["ukaten", "ukadonyu", "sudohaikuyu"] {
        let state = FileManager.default.temporaryDirectory.appending(path: "ourin-akari-state-\(UUID())")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: state) }
        let session = try AkariSession(masterDirectoryURL: fixtureRoot.appending(path: "\(id)/payload"), variableStoreURL: state.appending(path: "state.json"), httpFetcher: FixtureHTTP())
        let first = try await session.pluginResponse(for: pluginRequest("OnMenuExec"))
        if id == "ukaten" {
            #expect(first.headers["Script"]?.contains("地域の設定") == true)
            #expect(first.headers["Script"]?.contains("地域を設定してください") == true)
        } else {
            #expect(first.headers["Script"] == nil)
            let second = try await session.pluginResponse(for: pluginRequest("OnMenuExec"))
            #expect(second.headers["Script"]?.contains("booting...") == true)
        }
        try await session.shutdown()
    }
}
