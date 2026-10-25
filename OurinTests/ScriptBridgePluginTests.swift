import Foundation
import Testing
@testable import Ourin

/// Plugins/ScriptBridge（他の伺か形式のスクリプトを解釈するプラグイン）を実際にビルドし、
/// PluginRegistry 経由でロードして応答を検証する。
@Suite(.serialized)
@MainActor
struct ScriptBridgePluginTests {
    @Test
    func registryLoadsPackageAndReportsVersion() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, registry in
            #expect(registry.metas[plugin]?.id == "scriptbridge")
            let version = try plugin.get(id: "version").value
            #expect(version == "ScriptBridge/1.0")
        }
    }

    @Test
    func satoriNamedTalkIsRendered() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, _ in
            let response = try plugin.get(id: "OnScriptBridgePlay", references: [
                "Reference0": "satori_sample.txt",
                "Reference1": "OnScriptBridgeHello"
            ])
            #expect(response.script == "\\0ScriptBridge の名前付きトークです。\\e")
        }
    }

    @Test
    func satoriRandomTalkExpandsWordGroupAndSwitchesSpeaker() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, _ in
            let script = try #require(try plugin.get(id: "OnScriptBridgePlay", references: [
                "Reference0": "satori_sample.txt"
            ]).script)
            #expect(script.hasPrefix("\\0こんにちは。") || script.hasPrefix("\\0やあ。"))
            #expect(script.hasSuffix("\\1へえ、辞書をそのまま読めるんだ。\\e"))
        }
    }

    @Test
    func shiftJISSatoriDictionaryIsDecoded() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, registry in
            let package = try #require(registry.metas[plugin]?.packagePath)
            let text = "＊\n：シフトJISの辞書です\n"
            try EncodingAdapter.encode(text, charset: "Shift_JIS")
                .write(to: URL(fileURLWithPath: package).appendingPathComponent("scripts/sjis.txt"))
            let response = try plugin.get(id: "OnScriptBridgePlay", references: ["Reference0": "sjis.txt"])
            #expect(response.script == "\\0\\1シフトJISの辞書です\\e")
        }
    }

    @Test
    func kawariAndAyaDictionariesProduceTalk() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, _ in
            let kawari = try plugin.get(id: "OnScriptBridgePlay", references: [
                "Reference0": "kawari_sample.kis", "Reference3": "1"
            ]).script
            #expect(kawari?.hasSuffix("、華和梨形式の辞書から再生しています。\\e") == true)
            #expect(kawari?.contains("${") == false)

            let aya = try plugin.get(id: "OnScriptBridgePlay", references: [
                "Reference0": "aya_sample.dic", "Reference3": "1"
            ]).script
            #expect(aya?.hasSuffix("、AYA 形式の辞書から再生しています。\\e") == true)
            #expect(aya?.contains("%(") == false)
        }
    }

    @Test
    func kawariDoesNotSplitWordsOnCommasInsideSakuraScriptBrackets() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, _ in
            // 本文の改行は U+0001 で渡す
            let body = "sentence : \\![raise,OnTest,${w}]\\e\u{1}w : kawari"
            let script = try plugin.get(id: "OnScriptBridgeEval", references: [
                "Reference0": body, "Reference2": "kawari"
            ]).script
            #expect(script == "\\![raise,OnTest,kawari]\\e")
        }
    }

    @Test
    func legacyTagsAreConvertedToCurrentSpec() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, _ in
            let legacy = "\\q[OnA][はい]\\q1[OnB][いいえ]\\z\\__t\\__c\\a\\![reloadsurface]"
                + "\\![move,100,fix,500,screen]\\_!\\q[x][y]\\_!"
            let value = try plugin.get(id: "OnScriptBridgeConvert", references: ["Reference0": legacy]).value
            #expect(value == "\\q[はい,OnA]\\n\\q[いいえ,OnB]\\n\\e\\![open,teachbox]\\![open,communicatebox]"
                + "\\![raise,OnAITalk]\\![reload,shell]\\![move,--X=100,--time=500,--base=screen]\\_?\\q[x][y]\\_?")

            let played = try plugin.get(id: "OnScriptBridgePlay", references: ["Reference0": "legacy_sample.txt"]).script
            #expect(played?.contains("\\q[はい,OnScriptBridgeYes]\\n") == true)
            #expect(played?.hasSuffix("\\e") == true)
        }
    }

    @Test
    func menuChoicesParseAsScriptChoicesThatRaiseThePlugin() throws {
        try ScriptBridgeFixture.withInstalledPlugin { plugin, _ in
            let script = try #require(try plugin.get(id: "OnMenuExec").script)
            let choices = SakuraScriptEngine().parse(script: script).compactMap { token -> [String]? in
                if case .command(let name, let args) = token, name == "q" { return args }
                return nil
            }
            #expect(choices.contains([
                "satori_sample.txt",
                "script:\\![raiseplugin,scriptbridge,OnScriptBridgePlay,satori_sample.txt]"
            ]))
            #expect(choices.last == ["閉じる", "script:\\e"])
        }
    }
}

private enum ScriptBridgeFixture {
    static var projectURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Plugins/ScriptBridge", isDirectory: true)
    }

    /// package/ を plugin/ScriptBridge へ複製し、ソースをビルドした .plugin を置いてロードする。
    static func withInstalledPlugin(_ body: (Plugin, PluginRegistry) throws -> Void) throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("OurinScriptBridge-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? fm.removeItem(at: base)
        }
        let packageURL = try OurinPaths.subdirectory("plugin").appendingPathComponent("ScriptBridge", isDirectory: true)
        try fm.copyItem(at: projectURL.appendingPathComponent("package", isDirectory: true), to: packageURL)
        let bundleURL = packageURL.appendingPathComponent("ScriptBridge.plugin", isDirectory: true)
        let macOS = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.copyItem(at: projectURL.appendingPathComponent("Info.plist"),
                        to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        try compile(to: macOS.appendingPathComponent("ScriptBridge"))

        let registry = PluginRegistry()
        registry.discoverAndLoad()
        defer { registry.unloadAll() }
        let plugin = try #require(registry.plugins.first { $0.url.standardizedFileURL == bundleURL.standardizedFileURL })
        try body(plugin, registry)
    }

    private static func compile(to outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = [
            "-std=c11", "-fvisibility=default", "-bundle",
            projectURL.appendingPathComponent("src/scriptbridge.c").path,
            "-liconv", "-o", outputURL.path
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "ScriptBridgePluginTests", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "clang failed: \(stderr)"])
        }
    }
}
