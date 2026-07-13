import Testing
import Foundation
@testable import Ourin

struct ShioriRuntimeTests {
    private func makeRestartableHelper() throws -> (directory: URL, executable: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ourin-RuntimeHelper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("helper.zsh")
        let script = #"""
        #!/bin/zsh
        while IFS= read -r line; do
          case "$line" in
            *'"cmd":"load"'*)
              print -r -- '{"ok":true,"status":200,"loaded_dics":[]}'
              ;;
            *'"id":"capability"'*)
              print -r -- '{"ok":true,"status":204}'
              ;;
            *'"id":"Hang"'*)
              trap '' TERM
              while true; do :; done
              ;;
            *)
              print -r -- '{"ok":true,"status":200,"value":"restored"}'
              ;;
          esac
        done
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (directory, executable)
    }

    private final class FakeLoader: ShioriRequesting {
        var response: String?
        var requests: [String] = []
        var unloadCount = 0

        init(response: String?) {
            self.response = response
        }

        func request(_ text: String) -> String? {
            requests.append(text)
            return response
        }

        func unload() {
            unloadCount += 1
        }
    }

    private final class FakeRuntime: GhostShioriRuntime {
        let kind: ShioriRuntimeKind = .native
        var isLoaded = true
        var resourceManager: ResourceManager?
        var requestedIDs: [String] = []
        var unloadCount = 0

        func load(context: ShioriRuntimeLoadContext) -> Bool { true }
        func request(
            method: String,
            id: String,
            headers: [String : String],
            refs: [String],
            timeout: TimeInterval
        ) -> ShioriRuntimeResponse? {
            requestedIDs.append(id)
            return ShioriRuntimeResponse(ok: true, status: 204)
        }
        func unload() {
            unloadCount += 1
            isLoaded = false
        }
    }

    @Test
    func makotoWireUsesTranslatorProtocolAndStringHeader() throws {
        let request = MakotoWireCodec.makeRequest("\\0こんにちは\\e")
        #expect(request.hasPrefix("TRANSLATE Sentence MAKOTO/2.0\r\n"))
        #expect(request.contains("Charset: UTF-8\r\n"))
        #expect(request.contains("Sender: Ourin\r\n"))
        #expect(request.contains("String: \\0こんにちは\\e\r\n"))
        #expect(request.hasSuffix("\r\n\r\n"))

        #expect(MakotoWireCodec.parseResponse(
            "MAKOTO/2.0 200 OK\r\nCharset: UTF-8\r\nString: \\0翻訳済み\\e\r\n\r\n"
        ) == "\\0翻訳済み\\e")
        #expect(MakotoWireCodec.parseResponse(
            "MAKOTO/2.0 200 OK\r\nString:   padded  \r\n\r\n"
        ) == "  padded  ")
        #expect(MakotoWireCodec.parseResponse("MAKOTO/2.0 204 No Content\r\n\r\n") == nil)
    }

    @Test
    func makotoTranslatorFailsOpenAtPipelineBoundary() throws {
        let fake = FakeLoader(response: "MAKOTO/2.0 200 OK\r\nString: translated\r\n\r\n")
        let translator = MakotoTranslator(loader: fake)
        #expect(translator.translate("original") == "translated")
        let request = try #require(fake.requests.first)
        #expect(request.contains("String: original\r\n"))
        translator.unload()
        #expect(fake.unloadCount == 1)
    }

    @Test
    func shioriRuntimeCacheReusesMatchingContextAndEvictsWithDestroy() throws {
        let base = URL(fileURLWithPath: "/tmp/cache-fixture")
        let contextA = ShioriRuntimeLoadContext(
            ghostURL: base.appendingPathComponent("a"),
            ghostRoot: base.appendingPathComponent("a/ghost/master"),
            moduleName: "a.dylib",
            communication: .init(cache: true)
        )
        let contextB = ShioriRuntimeLoadContext(
            ghostURL: base.appendingPathComponent("b"),
            ghostRoot: base.appendingPathComponent("b/ghost/master"),
            moduleName: "b.dylib",
            communication: .init(cache: true)
        )
        let first = FakeRuntime()
        let second = FakeRuntime()
        let cache = ShioriRuntimeCache(capacity: 1)

        cache.store(runtime: first, context: contextA)
        #expect(cache.count == 1)
        cache.store(runtime: second, context: contextB)
        #expect(first.requestedIDs == ["OnDestroy"])
        #expect(first.unloadCount == 1)
        #expect(cache.take(context: contextA) == nil)
        #expect(cache.take(context: contextB) === second)
        #expect(second.unloadCount == 0)
    }

    @Test
    func shioriRuntimeCacheRemoveAllDestroysEveryRuntime() {
        let base = URL(fileURLWithPath: "/tmp/cache-remove-all")
        let context = ShioriRuntimeLoadContext(
            ghostURL: base,
            ghostRoot: base.appendingPathComponent("ghost/master"),
            moduleName: "shiori.dylib",
            communication: .init(cache: true)
        )
        let runtime = FakeRuntime()
        let cache = ShioriRuntimeCache()
        cache.store(runtime: runtime, context: context)
        cache.removeAll()
        #expect(runtime.requestedIDs == ["OnDestroy"])
        #expect(runtime.unloadCount == 1)
        #expect(cache.count == 0)
    }

    @Test
    func runtimeFactoryRecognizesProcessNames() {
        #expect(ShioriRuntimeFactory.kind(for: "yaya.dll") == .yaya)
        #expect(ShioriRuntimeFactory.kind(for: "/tmp/libYAYA.dylib") == .yaya)
        #expect(ShioriRuntimeFactory.kind(for: "/tmp/satori_core") == .satori)
        #expect(ShioriRuntimeFactory.kind(for: "SATORIYA.DLL") == .satori)
        #expect(ShioriRuntimeFactory.kind(for: "shiori.bundle") == .native)
    }

    @Test
    func configuredModuleNameIsPassedThroughUnchanged() {
        let config = GhostConfiguration(name: "fixture", shiori: "custom_shiori.bundle")
        #expect(ShioriRuntimeFactory.moduleName(for: config) == "custom_shiori.bundle")
        #expect(ShioriRuntimeFactory.moduleName(for: nil) == "yaya.dll")
    }

    @Test
    func translationContextUsesSpecifiedReasonAndReferenceDelimiters() {
        let context = ScriptTranslationContext(
            reasons: ["owned", "sstp-send"],
            eventID: "OnBoot",
            references: ["alpha", "beta"]
        )
        #expect(context.reasonHeader == "owned,sstp-send")
        #expect(context.sourceReferencesHeader == "alpha\u{1}beta")
        #expect(ScriptTranslationContext.baseware.reasonHeader == nil)
    }

    @Test
    func responseKeepsYayaIpcFields() {
        let response = ShioriRuntimeResponse(
            ok: true,
            status: 200,
            headers: ["Charset": "UTF-8"],
            value: "\\0Hello",
            loaded_dics: ["main.dic"]
        )
        let legacy: YayaResponse = response
        #expect(legacy == response)
        #expect(legacy.loaded_dics == ["main.dic"])
    }

    @Test
    func nativeRuntimeBuildsCanonicalRequestAndParsesAllHeaders() throws {
        let fake = FakeLoader(response: "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nReference0: target\r\nReference1: next\r\nValueNotify: state\r\nValue: \\0Hello\\e\r\n\r\n")
        var capturedModule = ""
        let runtime = NativeShioriRuntime { context in
            capturedModule = context.moduleName
            return fake
        }
        let context = ShioriRuntimeLoadContext(
            ghostURL: URL(fileURLWithPath: "/tmp/fixture"),
            ghostRoot: URL(fileURLWithPath: "/tmp/fixture/ghost/master"),
            moduleName: "custom_shiori.bundle"
        )

        #expect(runtime.load(context: context))
        #expect(runtime.isLoaded)
        let response = try #require(runtime.request(
            method: "GET",
            id: "OnBoot",
            headers: ["SecurityLevel": "local"],
            refs: ["master", "secondary"],
            timeout: 1
        ))

        #expect(capturedModule == "custom_shiori.bundle")
        let request = try #require(fake.requests.first)
        #expect(request.hasPrefix("GET SHIORI/3.0\r\n"))
        #expect(request.contains("Charset: UTF-8\r\n"))
        #expect(request.contains("Sender: Ourin\r\n"))
        #expect(request.contains("ID: OnBoot\r\n"))
        #expect(request.contains("Reference0: master\r\n"))
        #expect(request.contains("Reference1: secondary\r\n"))
        #expect(request.hasSuffix("\r\n\r\n"))
        #expect(response.ok)
        #expect(response.status == 200)
        #expect(response.value == "\\0Hello\\e")
        #expect(response.headers?["Reference0"] == "target")
        #expect(response.headers?["Reference1"] == "next")
        #expect(response.headers?["ValueNotify"] == "state")

        runtime.unload()
        #expect(!runtime.isLoaded)
        #expect(fake.unloadCount == 1)
    }

    @Test
    func nativeRuntimeSupportsNotifyAndRejectsMalformedResponse() {
        let fake = FakeLoader(response: "not a shiori response")
        let runtime = NativeShioriRuntime { _ in fake }
        let context = ShioriRuntimeLoadContext(
            ghostURL: URL(fileURLWithPath: "/tmp/fixture"),
            ghostRoot: URL(fileURLWithPath: "/tmp/fixture/ghost/master"),
            moduleName: "custom.bundle"
        )
        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "NOTIFY", id: "OnSecondChange", headers: [:], refs: [], timeout: 1) == nil)
        #expect(fake.requests.first?.hasPrefix("NOTIFY SHIORI/3.0\r\n") == true)
    }

    @Test
    func nativeRuntimeAppliesConfiguredProtocolVersionAndCharset() throws {
        let fake = FakeLoader(response: "SHIORI/2.6 204 No Content\r\nCharset: Shift_JIS\r\n\r\n")
        let runtime = NativeShioriRuntime { _ in fake }
        let context = ShioriRuntimeLoadContext(
            ghostURL: URL(fileURLWithPath: "/tmp/fixture"),
            ghostRoot: URL(fileURLWithPath: "/tmp/fixture/ghost/master"),
            moduleName: "legacy.bundle",
            communication: ShioriCommunicationOptions(
                version: "SHIORI/2.6",
                encoding: "Shift_JIS",
                forceEncoding: nil,
                escapeUnknown: true,
                cache: false
            )
        )

        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "OnBoot", headers: [:], refs: [], timeout: 1)?.status == 204)
        let request = try #require(fake.requests.first)
        #expect(request.hasPrefix("GET SHIORI/2.6\r\n"))
        #expect(request.contains("Charset: Shift_JIS\r\n"))
    }

    @Test
    func escapeUnknownRoundTripsUnicodeScalarsForLegacyEncoding() throws {
        let source = "ASCII😀終端"
        let encoded = EncodingAdapter.encode(source, charset: "Shift_JIS", escapeUnknown: true)
        let wire = try #require(EncodingAdapter.decode(encoded, charset: "Shift_JIS"))
        #expect(wire.contains("?escape!unicode[0x1F600]"))
        #expect(EncodingAdapter.restoreEscapedUnicode(in: wire) == source)
    }

    @Test
    func macOSModuleSearchSkipsWindowsDLLAndFindsBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ourin-ShioriRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: root.appendingPathComponent("custom.dll").path, contents: Data())
        try FileManager.default.createDirectory(at: root.appendingPathComponent("custom.bundle"), withIntermediateDirectories: true)

        let found = ShioriLoader.find(name: "custom.dll", in: [root])
        #if os(macOS)
        #expect(found?.lastPathComponent == "custom.bundle")
        #else
        #expect(found?.lastPathComponent == "custom.dll")
        #endif
    }

    @Test
    func yayaRestartsHelperAndRestoresLoadContextAfterTimeout() throws {
        let helper = try makeRestartableHelper()
        defer { try? FileManager.default.removeItem(at: helper.directory) }
        let runtime = try #require(YayaAdapter(executableURL: helper.executable))
        defer { runtime.unload() }
        let context = ShioriRuntimeLoadContext(
            ghostURL: helper.directory,
            ghostRoot: helper.directory,
            moduleName: "yaya.dll"
        )

        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "Hang", headers: [:], refs: [], timeout: 0.05) == nil)
        let restored = runtime.request(method: "GET", id: "AfterHang", headers: [:], refs: [], timeout: 2)

        #expect(restored?.value == "restored")
        #expect(runtime.isLoaded)
    }

    @Test
    func satoriRestartsHelperAndRestoresLoadContextAfterTimeout() throws {
        let helper = try makeRestartableHelper()
        defer { try? FileManager.default.removeItem(at: helper.directory) }
        let runtime = try #require(SatoriAdapter(executableURL: helper.executable))
        defer { runtime.unload() }
        let context = ShioriRuntimeLoadContext(
            ghostURL: helper.directory,
            ghostRoot: helper.directory,
            moduleName: "satori_core"
        )

        #expect(runtime.load(context: context))
        #expect(runtime.request(method: "GET", id: "Hang", headers: [:], refs: [], timeout: 0.05) == nil)
        let restored = runtime.request(method: "GET", id: "AfterHang", headers: [:], refs: [], timeout: 2)

        #expect(restored?.value == "restored")
        #expect(runtime.isLoaded)
    }

    @Test
    func vendoredSatoriLoadsUtf8DictionaryAndAnswersOnBoot() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = repositoryRoot.appendingPathComponent("satori_core/build/satori_core")
        let sourceFixture = repositoryRoot.appendingPathComponent("satori_core/tests/fixtures/basic", isDirectory: true)
        let workingFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ourin-SatoriFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: sourceFixture, to: workingFixture)
        defer { try? FileManager.default.removeItem(at: workingFixture) }

        let runtime = try #require(SatoriAdapter(executableURL: executable))
        defer { if runtime.isLoaded { runtime.unload() } }
        let context = ShioriRuntimeLoadContext(
            ghostURL: workingFixture,
            ghostRoot: workingFixture,
            moduleName: "satori_core",
            communication: ShioriCommunicationOptions(escapeUnknown: true)
        )

        #expect(runtime.load(context: context))
        let response = try #require(runtime.request(
            method: "GET",
            id: "OnBoot",
            headers: ["SecurityLevel": "local"],
            refs: [],
            timeout: 3
        ))

        #expect(response.ok)
        #expect(response.status == 200)
        #expect(response.value?.contains("里々統合テスト成功") == true)

        let escaped = try #require(runtime.request(
            method: "GET",
            id: "OnEchoReference",
            headers: [:],
            refs: ["emoji:😀"],
            timeout: 3
        ))
        #expect(escaped.value?.contains("emoji:😀") == true)

        runtime.unload()
        #expect(FileManager.default.fileExists(
            atPath: workingFixture.appendingPathComponent("satori_savedata.txt").path
        ))
    }

    @Test
    func vendoredSatoriLoadsExternalSaoriFromGhostSearchPath() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = repositoryRoot.appendingPathComponent("satori_core/build/satori_core")
        let fixtureLibrary = repositoryRoot.appendingPathComponent("satori_core/build/external_saori.dylib")
        let sourceFixture = repositoryRoot.appendingPathComponent("satori_core/tests/fixtures/external", isDirectory: true)
        let workingFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ourin-SatoriExternalSaori-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: sourceFixture, to: workingFixture)
        defer { try? FileManager.default.removeItem(at: workingFixture) }
        let saoriDirectory = workingFixture.appendingPathComponent("saori", isDirectory: true)
        try FileManager.default.createDirectory(at: saoriDirectory, withIntermediateDirectories: true)
        // 配布ゴーストではWindows版DLLが存在し、それをmacOS版へフォールバックする。
        // テストでも同じ探索条件を再現する。
        try Data([0x4d, 0x5a]).write(
            to: saoriDirectory.appendingPathComponent("external_saori.dll")
        )
        try FileManager.default.copyItem(
            at: fixtureLibrary,
            to: saoriDirectory.appendingPathComponent("external_saori.dylib")
        )

        let runtime = try #require(SatoriAdapter(executableURL: executable))
        defer { if runtime.isLoaded { runtime.unload() } }
        let context = ShioriRuntimeLoadContext(
            ghostURL: workingFixture,
            ghostRoot: workingFixture,
            moduleName: "satori_core"
        )
        #expect(runtime.load(context: context))
        let response = try #require(runtime.request(
            method: "GET",
            id: "OnBoot",
            headers: ["SecurityLevel": "local"],
            refs: [],
            timeout: 3
        ))
        #expect(response.status == 200)
        #expect(response.value?.contains("external-saori-ok") == true)
    }
}
