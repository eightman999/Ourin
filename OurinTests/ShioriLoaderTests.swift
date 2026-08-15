import Testing
@testable import Ourin
import Foundation

private final class FakeShioriRequester: ShioriRequesting {
    var requestCount = 0
    var unloadCount = 0
    var response: String?

    init(response: String?) {
        self.response = response
    }

    func request(_ text: String) -> String? {
        requestCount += 1
        return response
    }

    func unload() { unloadCount += 1 }
}

private final class MockShiori2Backend: ShioriBackend {
    var requests: [String] = []
    var encodedRequests: [Data] = []
    var handler: (String) -> String?

    init(handler: @escaping (String) -> String?) {
        self.handler = handler
    }

    func request(_ text: String) -> String? {
        requests.append(text)
        let charset = EncodingAdapter.detectCharset(in: Data(text.utf8), default: "UTF-8")
        encodedRequests.append(EncodingAdapter.encode(text, charset: charset))
        return handler(text)
    }

    func unload() {}
}

private extension Data {
    func containsBytes(_ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        let bytes = Array(self)
        for start in 0...(bytes.count - needle.count) {
            if Array(bytes[start..<(start + needle.count)]) == needle {
                return true
            }
        }
        return false
    }
}

// 埋め込みSHIORI XPCサービスをfixtureから起動するため、suite内の並列実行を禁止する。
@Suite(.serialized)
struct ShioriLoaderTests {
    @Test
    func shiori2DetectionUsesGetVersionThenConvertsEventRequest() throws {
        let backend = MockShiori2Backend { request in
            if request.hasPrefix("GET Version SHIORI/2.0\r\n") {
                return "SHIORI/2.6 200 OK\r\nCharset: Shift_JIS\r\n\r\n"
            }
            return "SHIORI/2.2 204 No Content\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend)
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnBoot\r
        Reference0: master\r
        SecurityLevel: local\r
        \r
        """

        let response = adapter.request(request)

        #expect(response == "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n")
        #expect(backend.requests.count == 2)
        #expect(backend.requests[0].hasPrefix("GET Version SHIORI/2.0\r\n"))
        #expect(backend.requests[1].hasPrefix("GET Sentence SHIORI/2.2\r\n"))
    }

    @Test
    func shiori2EventRequestUsesSentence22ReferencesSecurityAndCRLFTerminator() throws {
        let backend = MockShiori2Backend { _ in
            "SHIORI/2.2 204 No Content\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnBoot\r
        Reference0: r0\r
        Reference1: r1\r
        Reference2: r2\r
        Reference3: r3\r
        Reference4: r4\r
        Reference5: r5\r
        Reference6: r6\r
        Reference7: r7\r
        Reference8: r8-drop\r
        SecurityLevel: external\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        let expected = """
        GET Sentence SHIORI/2.2\r
        Sender: Ourin\r
        Event: OnBoot\r
        Reference0: r0\r
        Reference1: r1\r
        Reference2: r2\r
        Reference3: r3\r
        Reference4: r4\r
        Reference5: r5\r
        Reference6: r6\r
        Reference7: r7\r
        SecurityLevel: external\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
        #expect(!sent.contains("Reference8"))
        #expect(sent.hasSuffix("\r\n\r\n"))
    }

    @Test
    func shiori2OtherObjectDropEventsReachLegacyBackend() throws {
        let backend = MockShiori2Backend { _ in
            "SHIORI/2.2 204 No Content\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnOtherObjectDropped\r
        Reference0: 1\r
        Reference1: 仮想コンピュータ\r
        Reference2: com.example.virtual-object\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        #expect(sent.contains("Event: OnOtherObjectDropped\r\n"))
        #expect(sent.contains("Reference0: 1\r\n"))
        #expect(sent.contains("Reference1: 仮想コンピュータ\r\n"))
        #expect(sent.contains("Reference2: com.example.virtual-object\r\n"))
    }

    @Test
    func shiori2SentenceResponseBecomesShiori3ValueResponse() throws {
        let backend = MockShiori2Backend { _ in
            """
            SHIORI/2.2 200 OK\r
            Charset: Shift_JIS\r
            Sentence: \\h\\s0こんにちは\\e\r
            BalloonOffset: 12,34\r
            \r
            """
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnBoot\r
        SecurityLevel: local\r
        \r
        """

        let response = try #require(adapter.request(request))

        #expect(response.hasPrefix("SHIORI/3.0 200 OK\r\n"))
        #expect(response.contains("Charset: UTF-8\r\n"))
        #expect(response.contains("Value: \\h\\s0こんにちは\\e\r\n"))
        #expect(response.contains("BalloonOffset: 12,34\r\n"))
    }

    @Test
    func shiori2NoContentResponseMapsToShiori3NoContent() throws {
        let backend = MockShiori2Backend { _ in
            "SHIORI/2.2 204 No Content\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnClose\r
        SecurityLevel: local\r
        \r
        """

        let response = try #require(adapter.request(request))

        #expect(response == "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n")
    }

    @Test
    func shiori2UnknownEventIsNotSentToBackend() throws {
        let backend = MockShiori2Backend { _ in
            "SHIORI/2.2 200 OK\r\nSentence: should-not-be-used\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnMouseGesture\r
        Reference0: left\r
        SecurityLevel: local\r
        \r
        """

        let response = try #require(adapter.request(request))

        #expect(response == "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n")
        #expect(backend.requests.isEmpty)
    }

    @Test
    func shiori2TeachMapsToTeach24AndPreserves311And312() throws {
        var responseIndex = 0
        let backend = MockShiori2Backend { _ in
            responseIndex += 1
            if responseIndex == 1 {
                return "SHIORI/2.4 311 Not Enough\r\nSentence: \\h\\s0もっと教えてください\\e\r\n\r\n"
            }
            return "SHIORI/2.4 312 Advice\r\nSentence: \\h\\s0解釈できません\\e\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        TEACH SHIORI/3.0\r
        Charset: UTF-8\r
        Word: ガッツ石松\r
        Reference0: boxer\r
        SecurityLevel: local\r
        \r
        """

        let first = try #require(adapter.request(request))
        let second = try #require(adapter.request(request))

        #expect(backend.requests[0].hasPrefix("TEACH SHIORI/2.4\r\n"))
        #expect(backend.requests[0].contains("Word: ガッツ石松\r\n"))
        #expect(backend.requests[0].contains("Reference0: boxer\r\n"))
        #expect(first.hasPrefix("SHIORI/3.0 311 Not Enough\r\n"))
        #expect(first.contains("Value: \\h\\s0もっと教えてください\\e\r\n"))
        #expect(second.hasPrefix("SHIORI/3.0 312 Advice\r\n"))
        #expect(second.contains("Value: \\h\\s0解釈できません\\e\r\n"))
    }

    @Test
    func shiori2RequestIsEncodedAsShiftJISBytes() throws {
        let backend = MockShiori2Backend { _ in
            "SHIORI/2.2 204 No Content\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnBoot\r
        Reference0: おはよう\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let encoded = try #require(backend.encodedRequests.first)
        #expect(encoded.containsBytes([0x82, 0xA8, 0x82, 0xCD, 0x82, 0xE6, 0x82, 0xA4]))
        #expect(!encoded.containsBytes(Array("おはよう".utf8)))
    }

    // MARK: - AUDITS_TODO P2: OnTalkRequest → GET Sentence/2.0 (ユーザー入力) 変換テスト
    // buildRequest は EventID.OnTalkRequest（"OnTalkRequest"）と照合する。存在しない "OnTalk" 判定は誤りだった。

    @Test
    func shiori2TalkRequestMapsToUserSentenceGet() throws {
        let backend = MockShiori2Backend { _ in
            "SHIORI/2.0 200 OK\r\nSender: First\r\nSentence: \\0\\s0おはよー。\\e\r\n\r\n"
        }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnTalkRequest\r
        Sentence: おはよー。\r
        SecurityLevel: local\r
        \r
        """

        let response = try #require(adapter.request(request))

        let sent = try #require(backend.requests.first)
        let expected = """
        GET Sentence SHIORI/2.0\r
        Sender: User\r
        Sentence: おはよー。\r
        SecurityLevel: local\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
        #expect(response.hasPrefix("SHIORI/3.0 200 OK\r\n"))
        #expect(response.contains("Value: \\0\\s0おはよー。\\e\r\n"))
    }

    // MARK: - AUDITS_TODO P2: Word/String/Status/OwnerGhostName/OtherGhostName/Communicate builder テスト

    @Test
    func shiori2WordRequestUsesReference0AsTypeWhenTypeHeaderMissing() throws {
        let backend = MockShiori2Backend { _ in "SHIORI/2.0 200 OK\r\nWord: dummy\r\n\r\n" }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: Word\r
        Reference0: A\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        let expected = """
        GET Word SHIORI/2.0\r
        Sender: Ourin\r
        Type: A\r
        SecurityLevel: local\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
    }

    @Test
    func shiori2StatusRequestHasNoBody() throws {
        let backend = MockShiori2Backend { _ in "SHIORI/2.0 200 OK\r\n\r\n" }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: Status\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        let expected = """
        GET Status SHIORI/2.0\r
        Sender: Ourin\r
        SecurityLevel: local\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
    }

    @Test
    func shiori2StringRequestUsesReference0AsIDAndOmitsSender() throws {
        let backend = MockShiori2Backend { _ in "SHIORI/2.5 200 OK\r\nString: dummy\r\n\r\n" }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: Resource\r
        Reference0: name\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        let expected = """
        GET String SHIORI/2.5\r
        ID: name\r
        SecurityLevel: local\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
    }

    @Test
    func shiori2OwnerGhostNameRequestMapsReference0ToGhostHeader() throws {
        let backend = MockShiori2Backend { _ in "SHIORI/2.3 204 No Content\r\n\r\n" }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OwnerGhostName\r
        Reference0: Emily\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        let expected = """
        NOTIFY OwnerGhostName SHIORI/2.3\r
        Sender: Ourin\r
        Ghost: Emily\r
        SecurityLevel: local\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
    }

    @Test
    func shiori2OtherGhostNameRequestMapsReferencesToRepeatedGhostExHeaders() throws {
        let backend = MockShiori2Backend { _ in "SHIORI/2.3 204 No Content\r\n\r\n" }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OtherGhostName\r
        Reference0: GhostA\r
        Reference1: GhostB\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        let expected = """
        NOTIFY OtherGhostName SHIORI/2.3\r
        Sender: Ourin\r
        GhostEx: GhostA\r
        GhostEx: GhostB\r
        SecurityLevel: local\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
    }

    @Test
    func shiori2CommunicateRequestMapsFirstTwoReferencesToSenderAndSentence() throws {
        let backend = MockShiori2Backend { _ in "SHIORI/2.3 204 No Content\r\n\r\n" }
        let adapter = Shiori2CompatBackend(wrapping: backend, detectedVersion: "SHIORI/2.6")
        let request = """
        GET SHIORI/3.0\r
        Charset: UTF-8\r
        Sender: Ourin\r
        ID: OnCommunicate\r
        Reference0: OtherGhost\r
        Reference1: hello\r
        Reference2: extra1\r
        Reference3: extra2\r
        Age: 5\r
        Surface: 0\r
        SecurityLevel: local\r
        \r
        """

        _ = adapter.request(request)

        let sent = try #require(backend.requests.first)
        let expected = """
        GET Sentence SHIORI/2.3\r
        Sender: OtherGhost\r
        Sentence: hello\r
        Age: 5\r
        Surface: 0\r
        Reference0: extra1\r
        Reference1: extra2\r
        SecurityLevel: local\r
        Charset: Shift_JIS\r
        \r\n
        """
        #expect(sent == expected)
    }

    @Test
    func yayaParseRequestSupportsShiori2TeachAndSentence() throws {
        let request = """
        TEACH SHIORI/2.6\r
        Charset: UTF-8\r
        Sentence: hello from teach\r
        \r
        """
        let parsed = YayaBackend.parseRequest(request)
        #expect(parsed != nil)
        #expect(parsed?.method == "NOTIFY")
        #expect(parsed?.originalMethod == "TEACH")
        #expect(parsed?.protocolVersion == "SHIORI/2.6")
        #expect(parsed?.id == "OnTeach")
        #expect(parsed?.refs == ["hello from teach"])
    }

    @Test
    func yayaParseRequestSupportsLowercaseEventAndReference() throws {
        let request = """
        GET SHIORI/2.5\r
        charset: UTF-8\r
        event: Resource\r
        reference0: test.key\r
        \r
        """
        let parsed = YayaBackend.parseRequest(request)
        #expect(parsed != nil)
        #expect(parsed?.method == "GET")
        #expect(parsed?.id == "Resource")
        #expect(parsed?.refs == ["test.key"])
    }

    @Test
    func yayaBuildResponseMapsTeachNoContentTo312ForShiori2() throws {
        let response = YayaResponse(
            ok: true,
            status: 204,
            headers: ["Charset": "UTF-8"],
            value: nil,
            error: nil,
            loaded_dics: nil
        )
        let wire = YayaBackend.buildResponse(
            from: response,
            requestVersion: "SHIORI/2.6",
            requestMethod: "TEACH"
        )
        #expect(wire.hasPrefix("SHIORI/2.6 312 No Content (Not Trusted)\r\n"))
    }

    @Test
    func yayaDispatchFailsWithoutExecutable() throws {
        // Create a temporary directory for our ghost fixture
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let ghostMasterDir = tempDir.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(atPath: ghostMasterDir.path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a fake descript.txt for YAYA
        let descriptContent = """
        charset,UTF-8
        shiori,yaya.dll
        yaya.dic,test.dic
        """
        try descriptContent.write(to: ghostMasterDir.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)

        // Create a fake dictionary file
        try "this is a dictionary".write(to: ghostMasterDir.appendingPathComponent("test.dic"), atomically: true, encoding: .utf8)

        // Attempt to load the YAYA module.
        // This is expected to FAIL because the `yaya_core` executable is not in the test bundle.
        // This test proves that the loader *tries* to initialize YayaBackend, which is the correct dispatch logic.
        let loader = ShioriLoader(module: "yaya.dll", base: tempDir)

        #expect(loader == nil, "ShioriLoader should fail to initialize YayaBackend without yaya_core executable")
    }

    @Test
    func loadRequestUnload() throws {
        let srcDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
        let fixtureBase = srcDir.appendingPathComponent("Fixtures")
        let fixtureB64 = fixtureBase.appendingPathComponent("ghost/master/test_shiori.so.b64")

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let base = tempDir.appendingPathComponent("Fixtures")
        let ghost = base.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dylib = ghost.appendingPathComponent("test_shiori.so")
        let data = try String(contentsOf: fixtureB64, encoding: .utf8)
        if let bin = Data(base64Encoded: data, options: .ignoreUnknownCharacters) {
            try bin.write(to: dylib)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dylib.path)
        }

        guard let loader = ShioriLoader(module: "test_shiori.so", base: base) else {
            // Some environments cannot load the bundled test dylib (e.g. architecture/signing mismatch).
            return
        }
        let req = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Test\r\nID: Ping\r\n\r\n"
        let res = loader.request(req)
        #expect(res?.contains("200 OK") == true)
        loader.unload()
    }

    @Test
    func nativeDylibFixturePerformsRealLoadRequestUnload() throws {
        let source = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shiori/native_fixture.c")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-native-shiori-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dylib = tempDir.appendingPathComponent("native_fixture.dylib")

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-dynamiclib", source.path, "-o", dylib.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)

        let loader = try #require(ShioriLoader(
            moduleURL: dylib,
            xpcServiceName: nil,
            shiori2Compatibility: false
        ))
        let response = try #require(loader.request(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Test\r\nID: Ping\r\n\r\n"
        ))
        #expect(response.contains("200 OK"))
        #expect(response.contains("Reference2: native-fixture"))
        #expect(response.contains("Value: \\h\\s0native-fixture\\e"))

        loader.unload()
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("native_unloaded.marker").path))
    }

    @Test
    func nativeDylibFixtureRunsThroughEmbeddedXpcService() throws {
        let source = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shiori/native_fixture.c")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-native-shiori-xpc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dylib = tempDir.appendingPathComponent("native_fixture.dylib")

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-dynamiclib", source.path, "-o", dylib.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)

        let loader = try #require(ShioriLoader(
            moduleURL: dylib,
            xpcServiceName: "jp.ourin.shiori",
            shiori2Compatibility: false
        ))
        let response = try #require(loader.request(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Test\r\nID: Ping\r\n\r\n"
        ))
        #expect(response.contains("Reference2: native-fixture"))

        let pidMarker = tempDir.appendingPathComponent("native_loaded_pid.marker")
        let pidText = try String(contentsOf: pidMarker, encoding: .utf8)
        let servicePID = try #require(Int(pidText))
        #expect(servicePID != ProcessInfo.processInfo.processIdentifier)

        loader.unload()
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("native_unloaded.marker").path))
    }

    @Test
    func nativeShiori2FixtureMapsLegacySentenceToShiori3Value() throws {
        let source = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shiori/native_fixture.c")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-shiori2-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let dylib = tempDir.appendingPathComponent("legacy_fixture.dylib")

        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-dynamiclib", source.path, "-o", dylib.path]
        try compiler.run()
        compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)

        let loader = try #require(ShioriLoader(
            moduleURL: dylib,
            xpcServiceName: nil,
            shiori2Compatibility: true
        ))
        let response = try #require(loader.request(
            "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Test\r\nID: OnBoot\r\nReference0: boot\r\n\r\n"
        ))
        #expect(response.hasPrefix("SHIORI/3.0 200 OK\r\n"))
        #expect(response.contains("Value: \\h\\s0legacy-fixture\\e"))
        loader.unload()
    }

    @Test
    func xpcFailureDoesNotFallbackToInProcess() throws {
        let fixtureBase = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ghost/master/test_shiori.so.b64")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dylib = tempDir.appendingPathComponent("test_shiori.so")
        let encoded = try String(contentsOf: fixtureBase, encoding: .utf8)
        let binary = try #require(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
        try binary.write(to: dylib)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dylib.path)

        let missingService = "jp.ourin.shiori.missing.\(UUID().uuidString)"
        let loader = ShioriLoader(moduleURL: dylib, xpcServiceName: missingService)
        #expect(loader == nil, "XPC failure must not silently load native SHIORI in the app process")
    }
    
    @Test
    func bundleBackendLoadFailsForInvalidBundle() throws {
        // Create a temporary directory
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(atPath: tempDir.path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create an invalid bundle (missing executable)
        let bundleDir = tempDir.appendingPathComponent("TestInvalid.bundle")
        try FileManager.default.createDirectory(atPath: bundleDir.appendingPathComponent("Contents").path, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>TestInvalid</string>
            <key>CFBundleIdentifier</key>
            <string>com.ourin.test.invalid</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """
        try infoPlist.write(to: bundleDir.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        
        // Attempt to load - should fail because executable is missing
        let loader = ShioriLoader(module: "TestInvalid.bundle", base: tempDir)
        #expect(loader == nil, "ShioriLoader should fail to load invalid bundle")
    }
    
    @Test
    func normalizedNamesIncludesBundleAndPlugin() throws {
        // Test that normalizedNames generates correct variants for .bundle/.plugin
        let variants = ShioriLoader.normalizedNames(for: "TestModule")
        
        let expectedVariants = ["TestModule", "TestModule.dylib", "libTestModule.dylib", "TestModule.bundle", "TestModule.plugin", "TestModule.so", "libTestModule.so"]
        
        #expect(variants.count == expectedVariants.count)
        for variant in expectedVariants {
            #expect(variants.contains(variant), "Expected to find \(variant) in variants")
        }
    }

    @Test
    func resolvedXpcServiceNamePrefersExplicitVariables() throws {
        let env: [String: String] = [
            "SHIORI_XPC_SERVICE_NAME": "jp.ourin.custom",
            "OURIN_SHIORI_XPC_SERVICE": "jp.ourin.secondary",
            "OURIN_SHIORI_ISOLATION_MODE": "xpc"
        ]
        #expect(ShioriLoader.resolvedXpcServiceName(environment: env) == "jp.ourin.custom")
    }

    @Test
    func resolvedXpcServiceNameUsesIsolationModeDefault() throws {
        let env: [String: String] = ["OURIN_SHIORI_ISOLATION_MODE": "xpc"]
        #expect(ShioriLoader.resolvedXpcServiceName(environment: env) == "jp.ourin.shiori")
    }

    @Test
    func resolvedXpcServiceNameUsesEmbeddedServiceByDefault() throws {
        #expect(ShioriLoader.resolvedXpcServiceName(environment: [:]) == "jp.ourin.shiori")
        #expect(ShioriLoader.resolvedXpcServiceName(environment: ["OURIN_SHIORI_ISOLATION_MODE": "inprocess"]) == nil)
    }

    @Test
    func shioriXpcServiceRejectsInvalidPayload() throws {
        let service = ShioriXPCServiceHost(
            listener: .anonymous(),
            loaderFactory: { _ in FakeShioriRequester(response: "ok") }
        )
        var receivedData: Data?
        var receivedError: String?
        service.execute(Data(), bundlePath: "/tmp/dummy") { data, errorText in
            receivedData = data
            receivedError = errorText
        }
        #expect(receivedData == nil)
        #expect(receivedError?.contains("Invalid SHIORI request payload") == true)
    }

    @Test
    func shioriXpcServiceCachesLoaderPerModulePath() throws {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-shiori-\(UUID().uuidString).so")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        var factoryCalls = 0
        let requester = FakeShioriRequester(response: "SHIORI/3.0 200 OK\r\n\r\n")
        let service = ShioriXPCServiceHost(
            listener: .anonymous(),
            loaderFactory: { _ in
                factoryCalls += 1
                return requester
            }
        )
        let request = Data("GET SHIORI/3.0\r\nID: Ping\r\n\r\n".utf8)

        service.execute(request, bundlePath: tempFile.path) { _, _ in }
        service.execute(request, bundlePath: tempFile.path) { _, _ in }

        #expect(factoryCalls == 1)
        #expect(requester.requestCount == 2)
    }

    @Test
    func shioriXpcServiceScopesRawAndCompatibleModulesIndependently() throws {
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-makoto-\(UUID().uuidString).dylib")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data(), attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let compatible = FakeShioriRequester(response: "SHIORI/3.0 204 No Content\r\n\r\n")
        let raw = FakeShioriRequester(response: "MAKOTO/2.0 200 OK\r\nString: translated\r\n\r\n")
        let service = ShioriXPCServiceHost(
            listener: .anonymous(),
            loaderFactory: { _ in compatible },
            rawLoaderFactory: { _ in raw }
        )
        let request = Data("TRANSLATE Sentence MAKOTO/2.0\r\nString: source\r\n\r\n".utf8)

        service.execute(request, bundlePath: tempFile.path, shiori2Compatibility: false) { data, error in
            #expect(error == nil)
            #expect(data.flatMap { String(data: $0, encoding: .utf8) }?.contains("translated") == true)
        }
        service.execute(request, bundlePath: tempFile.path, shiori2Compatibility: true) { _, _ in }
        #expect(raw.requestCount == 1)
        #expect(compatible.requestCount == 1)

        service.unload(tempFile.path, shiori2Compatibility: false) {}
        #expect(raw.unloadCount == 1)
        #expect(compatible.unloadCount == 0)
    }

    // MARK: - YAYA config parsing (dicdir / _loading_order.txt / dicif / encoding)

    @Test
    func collectDicEntriesParsesDicdirLoadingOrderWithDicAndDicif() throws {
        // Build a yaya-dic-like layout under a temp ghost/master.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let master = tempDir.appendingPathComponent("ghost/master")
        let base = master.appendingPathComponent("yaya_base")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // yaya.txt references the dicdir
        let yayaTxt = """
        charset.dic, UTF-8
        dicdir, yaya_base
        dic, my_ghost.dic
        """
        try yayaTxt.write(to: master.appendingPathComponent("yaya.txt"), atomically: true, encoding: .utf8)

        // _loading_order.txt in the real yaya-dic format: dic, and dicif, with encoding
        let orderTxt = """
        dic, config.dic, UTF-8
        dic, shiori3.dic, UTF-8
        dicif, optional.dic, UTF-8
        dicif, compatible.dic, UTF-8
        """
        try orderTxt.write(to: base.appendingPathComponent("_loading_order.txt"), atomically: true, encoding: .utf8)
        // config.dic / shiori3.dic / optional.dic exist; compatible.dic intentionally MISSING
        for f in ["config.dic", "shiori3.dic", "optional.dic"] {
            try "OnX { \"x\" }".write(to: base.appendingPathComponent(f), atomically: true, encoding: .utf8)
        }
        try "OnMyGhost { \"g\" }".write(to: master.appendingPathComponent("my_ghost.dic"), atomically: true, encoding: .utf8)

        var collector = DicCollector()
        collectDicEntries(content: yayaTxt, baseURL: master, sourceName: "yaya.txt",
                          collector: &collector, visited: [])

        let paths = collector.entries.map { $0.path }
        // compatible.dic must be skipped (dicif + missing); others present in order.
        #expect(paths == ["yaya_base/config.dic", "yaya_base/shiori3.dic", "yaya_base/optional.dic", "my_ghost.dic"])
        // Encoding carried through from _loading_order.txt third field.
        #expect(collector.entries[0].encoding == "UTF-8")
        // charset.dic detected as the global dic charset.
        #expect(collector.globalCharset == "UTF-8")
    }

    @Test
    func collectDicEntriesParsesPerDicEncoding() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let master = tempDir.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let yayaTxt = """
        dic, sjis.dic, Shift_JIS
        dic, utf8.dic, UTF-8
        dic, auto.dic
        """
        var collector = DicCollector()
        collectDicEntries(content: yayaTxt, baseURL: master, sourceName: "yaya.txt",
                          collector: &collector, visited: [])

        #expect(collector.entries.count == 3)
        #expect(collector.entries[0].path == "sjis.dic")
        #expect(collector.entries[0].encoding == "CP932")
        #expect(collector.entries[1].encoding == "UTF-8")
        #expect(collector.entries[2].encoding == nil)
    }

    @Test
    func collectDicEntriesSuppressesDuplicates() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let master = tempDir.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let yayaTxt = """
        dic, a.dic
        dic, b.dic
        dic, a.dic
        """
        var collector = DicCollector()
        collectDicEntries(content: yayaTxt, baseURL: master, sourceName: "yaya.txt",
                          collector: &collector, visited: [])

        #expect(collector.entries.count == 2)
        #expect(collector.entries.map { $0.path } == ["a.dic", "b.dic"])
    }

    // MARK: - yaya_core parser regression (-- block, switch, variable elements)
    // These exercise the C++ parser end-to-end when the yaya_core executable is
    // discoverable. They are skipped (not failed) when the binary is absent, so
    // environments without a built helper are not broken.

    /// Locate the yaya_core executable in known locations (bundle, repo build dir).
    private static func locateYayaCore() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "yaya_core") { return url }
        // Repo-relative build output: <repo>/yaya_core/build/yaya_core
        let testFile = URL(fileURLWithPath: #file)
        var dir = testFile.deletingLastPathComponent() // OurinTests/
        for _ in 0..<4 {
            let candidate = dir.appendingPathComponent("yaya_core/build/yaya_core")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    @Test
    func yayaCoreBlockLiteralDoesNotMutateVariableElements() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        // { _x -- _y -- _x } must produce a 3-element array and leave _x unchanged.
        let dic = """
        BlkSizeVar {
            _x = 10
            _y = 20
            _b = { _x -- _y -- _x }
            ARRAYSIZE(_b)
        }
        BlkFirstVar {
            _x = 10
            _y = 20
            _b = { _x -- _y -- _x }
            _b[0]
        }
        BlkXUnchanged {
            _x = 10
            _y = 20
            _ignored = { _x -- _y -- _x }
            _x
        }
        DecrementWorks {
            _i = 5
            _i--
            _i
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        func request(_ id: String) -> String? {
            let req: [String: Any] = ["cmd": "request", "method": "GET", "id": id,
                                      "ref": [], "headers": ["Charset": "UTF-8"]]
            return Self.runYayaCore(exe: exe, requests: [loadReq, req])
        }

        // 3 elements; first is 10; _x stays 10 (no postfix-decrement side effect);
        // decrement still works outside block context (=4).
        #expect(request("BlkSizeVar") == "3")
        #expect(request("BlkFirstVar") == "10")
        #expect(request("BlkXUnchanged") == "10")
        #expect(request("DecrementWorks") == "4")
    }

    @Test
    func yayaCoreSwitchWithDashDashBlockSelectsByIndex() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        SwitchStr {
            switch _argv[0] {
                { "alpha" -- "beta" -- "gamma" }
            }
        }
        SwitchNoMutate {
            _x = 10
            _y = 20
            switch 0 {
                _x -- _y -- _x
            }
            _x
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        let r0: [String: Any] = ["cmd": "request", "method": "GET", "id": "SwitchStr",
                                 "ref": ["0"], "headers": ["Charset": "UTF-8"]]
        let r1: [String: Any] = ["cmd": "request", "method": "GET", "id": "SwitchStr",
                                 "ref": ["1"], "headers": ["Charset": "UTF-8"]]
        let r2: [String: Any] = ["cmd": "request", "method": "GET", "id": "SwitchStr",
                                 "ref": ["2"], "headers": ["Charset": "UTF-8"]]
        let rNm: [String: Any] = ["cmd": "request", "method": "GET", "id": "SwitchNoMutate",
                                  "ref": [], "headers": ["Charset": "UTF-8"]]

        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, r0]) == "alpha")
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, r1]) == "beta")
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, r2]) == "gamma")
        // switch with variable elements must not mutate _x.
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, rNm]) == "10")
    }

    @Test
    func yayaCoreCaseWhenFirstMatchAndOthers() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        GetInfo {
            case _argv[0] {
                when 'name','キャラクター名' {
                    'エミリ'
                }
                when '性別' {
                    '女性'
                }
                others {
                    'unknown'
                }
            }
        }
        SideEffectFirstMatch {
            _s = ""
            case _argv[0] {
                when 'a' {
                    _s ,= 'A'
                }
                when 'a' {
                    _s ,= 'B'
                }
            }
            _s
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        func req(_ id: String, _ ref: String) -> [String: Any] {
            return ["cmd": "request", "method": "GET", "id": id, "ref": [ref], "headers": ["Charset": "UTF-8"]]
        }

        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("GetInfo", "name")]) == "エミリ")
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("GetInfo", "性別")]) == "女性")
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("GetInfo", "other")]) == "unknown")
        // Only the first matching 'a' clause runs; the second is skipped.
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("SideEffectFirstMatch", "a")]) == "A")
    }

    /// `&` 参照渡しによる E.Swap の in-place 交換を検証する（ローカル変数・配列要素・グローバル）。
    @Test
    func yayaCoreESwapByReference() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        SwapLocal {
            _a = '1'
            _b = '2'
            E.Swap(&_a, &_b)
            _a + ',' + _b
        }
        SwapArrayElem {
            _arr = IARRAY
            _arr ,= 'x'
            _arr ,= 'y'
            _arr ,= 'z'
            E.Swap(&_arr[0], &_arr[2])
            _arr[0] + _arr[1] + _arr[2]
        }
        SwapGlobal {
            gv = 'A'
            gw = 'B'
            E.Swap(&gv, &gw)
            gv + gw
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        func req(_ id: String) -> [String: Any] {
            return ["cmd": "request", "method": "GET", "id": id, "ref": [], "headers": ["Charset": "UTF-8"]]
        }

        // E.Swap must actually mutate the referenced storage in-place.
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("SwapLocal")]) == "2,1")
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("SwapArrayElem")]) == "zyx")
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("SwapGlobal")]) == "BA")
    }

    /// 入れ子配列の要素（`&matrix[row][column]`）も E.Swap の参照先として
    /// ルート配列へ書き戻されることを検証する。
    @Test
    func yayaCoreESwapByReferenceSupportsNestedArrayElements() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        SwapNestedArrayElem {
            _rowA = { 'a' -- 'b' }
            _rowB = { 'c' -- 'd' }
            _matrix = { _rowA -- _rowB }
            E.Swap(&_matrix[0][1], &_matrix[1][0])
            _matrix[0][0] + _matrix[0][1] + _matrix[1][0] + _matrix[1][1]
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let loadReq: [String: Any] = [
            "cmd": "load", "ghost_root": ghost.path,
            "encoding": "UTF-8", "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "SwapNestedArrayElem",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        // [a,b]/[c,d] -> [a,c]/[b,d]
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "acbd")
    }

    /// `&` を受け取る通常のユーザー関数でも、関数内の `_argv` 更新を呼び出し元へ
    /// 書き戻す。Emily4 の再帰的な `E.SortArray.Qsort` がこの経路を使用する。
    @Test
    func yayaCoreGenericByReferencePropagatesThroughNestedCall() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        MutateArgument {
            _argv[0] = _argv[0] + '!'
        }
        Caller {
            _value = 'before'
            MutateArgument(&_value)
            _value
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let loadReq: [String: Any] = [
            "cmd": "load", "ghost_root": ghost.path,
            "encoding": "UTF-8", "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "Caller",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "before!")
    }

    /// 配列要素代入 `arr[i] = value` が、配列全体ではなく正確にその要素だけを
    /// 書き換え、隣接要素には影響しないことを検証する。
    @Test
    func yayaCoreArrayElementAssignmentWritesOnlyIndexedElement() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        ArrElemAssign {
            _arr = { 'a' -- 'b' -- 'c' }
            _arr[1] = 'X'
            _arr[0] + _arr[1] + _arr[2]
        }
        ArrElemNeighborsUnchanged {
            _arr = { 'a' -- 'b' -- 'c' }
            _arr[1] = 'X'
            _arr[0] + ',' + _arr[2]
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        func req(_ id: String) -> [String: Any] {
            return ["cmd": "request", "method": "GET", "id": id, "ref": [], "headers": ["Charset": "UTF-8"]]
        }

        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("ArrElemAssign")]) == "aXc")
        // 要素1だけを書き換え、要素0と要素2は元のまま残る。
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, req("ArrElemNeighborsUnchanged")]) == "a,c")
    }

    /// 配列要素の複合代入 `arr[i] += / -= / *= / /= / %= value` が、対象要素のみに
    /// 反映され、他の要素を巻き込まないことを検証する。
    @Test
    func yayaCoreArrayElementCompoundAssignmentAppliesToElementOnly() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        ArrElemCompound {
            _arr = { 1 -- 2 -- 3 -- 4 -- 5 -- 6 }
            _arr[0] += 5
            _arr[1] -= 5
            _arr[2] *= 2
            _arr[3] /= 4
            _arr[4] %= 7
            _arr[0] + ',' + _arr[1] + ',' + _arr[2] + ',' + _arr[3] + ',' + _arr[4] + ',' + _arr[5]
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "ArrElemCompound",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        // [1,2,3,4,5,6] → [6,-3,6,1,5,6]（末尾要素6は不変）
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "6,-3,6,1,5,6")
    }

    /// 配列要素の連結代入 `arr[i] ,= value`（文字列要素は文字列連結）が、
    /// 対象要素のみに反映されることを検証する。
    @Test
    func yayaCoreArrayElementConcatAssignmentAppliesToElementOnly() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        ArrElemConcat {
            _arr = { 'a' -- 'b' -- 'c' }
            _arr[1] ,= 'X'
            _arr[0] + _arr[1] + _arr[2]
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "ArrElemConcat",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "abXc")
    }

    /// 範囲/スライス左辺値 `arr[a, b] = IARRAY` が、両端を含む閉区間を削除することを
    /// 検証する。`{1--2--3--4--5}` の `[2, 4]`（= 要素 3,4,5）を空配列で置換すると
    /// 先頭の `1,2` だけが残る。
    @Test
    func yayaCoreRangeLvalueEmptyArrayRemovesInterval() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        RangeLvalueClear {
            _a = { 1 -- 2 -- 3 -- 4 -- 5 }
            _a[2, 4] = IARRAY
            _a[0] + ',' + _a[1]
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "RangeLvalueClear",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        // [1,2,3,4,5] → [1,2]（閉区間 [2,4] の要素 3,4,5 が削除される）
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "1,2")
    }

    /// 範囲/スライス左辺値 `arr[a, b] = { ... }` が、閉区間を配列で置換（スプライス）
    /// することを検証する。`{1--2--3--4}` の `[1, 2]` を `{8--9}` で置き換えると
    /// `1,8,9,4` になる。
    @Test
    func yayaCoreRangeLvalueSplicesArrayIntoInterval() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        RangeLvalueSplice {
            _a = { 1 -- 2 -- 3 -- 4 }
            _a[1, 2] = { 8 -- 9 }
            _a[0] + ',' + _a[1] + ',' + _a[2] + ',' + _a[3]
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "RangeLvalueSplice",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        // [1,2,3,4] → [1,8,9,4]（閉区間 [1,2] の要素 2,3 が {8,9} に置き換わる）
        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "1,8,9,4")
    }

    /// 範囲読み `arr[start, end]` が、長さではなく両端を含む閉区間を返すことを検証する。
    /// `{1--2--3--4--5}` の `[1, 2]` は長さ2で要素1,2（= 2,3）を返す。もし length 解釈なら
    /// 要素 1,2,3（= 2,3,4）になってしまうため、この違いで閉区間セマンティクスを確定する。
    @Test
    func yayaCoreRangeReadIsInclusive() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        RangeReadInclusive {
            _a = { 1 -- 2 -- 3 -- 4 -- 5 }
            _sub = _a[1, 2]
            ARRAYSIZE(_sub) + ':' + _sub[0] + ',' + _sub[1]
        }
        RangeReadReversed {
            _a = { 1 -- 2 -- 3 -- 4 -- 5 }
            _sub = _a[2, 1]
            ARRAYSIZE(_sub) + ':' + _sub[0] + ',' + _sub[1]
        }
        RangeWriteReversed {
            _a = { 1 -- 2 -- 3 -- 4 -- 5 }
            _a[4, 2] = IARRAY
            _a[0] + ',' + _a[1]
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let entries: [[String: String]] = [["path": "t.dic", "encoding": "UTF-8"]]
        let loadReq: [String: Any] = ["cmd": "load", "ghost_root": ghost.path,
                                      "encoding": "UTF-8", "dic_entries": entries]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "RangeReadInclusive",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

    // 要素1,2 のみ（= [2,3]）。length 解釈だと [2,3,4] になる。
    #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "2:2,3")

    let reversedRead: [String: Any] = [
        "cmd": "request", "method": "GET", "id": "RangeReadReversed",
        "ref": [], "headers": ["Charset": "UTF-8"]
    ]
    let reversedWrite: [String: Any] = [
        "cmd": "request", "method": "GET", "id": "RangeWriteReversed",
        "ref": [], "headers": ["Charset": "UTF-8"]
    ]
    // 公式YAYAと同じく、終端が逆でも範囲端を交換して [1,2] として扱う。
    #expect(Self.runYayaCore(exe: exe, requests: [loadReq, reversedRead]) == "2:2,3")
    #expect(Self.runYayaCore(exe: exe, requests: [loadReq, reversedWrite]) == "1,2")
}

    /// `READFMO(name)` が host_op:"fmo" 経由で現在の FMO スナップショットを同期的に取得できるか。
    /// yaya_core と行ベースで双方向 IPC し、READFMO 呼び出し時に発行される host_op へ応答する。
    @Test
    func yayaCoreReadFmoViaHostOp() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ parser integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        ReadFmoTest {
            READFMO('Sakura')
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let snapshot = "0.name\u{01}TestGhost\r\n0.path\u{01}/tmp/ghost\r\n0.hwnd\u{01}42\r\n"

        let proc = Process()
        proc.executableURL = exe
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        try proc.run()

        func send(_ obj: [String: Any]) {
            let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
            inPipe.fileHandleForWriting.write(data)
            inPipe.fileHandleForWriting.write(Data([0x0A]))
        }
        func readLine() -> [String: Any]? {
            var buf = Data()
            let h = outPipe.fileHandleForReading
            while true {
                let d = h.readData(ofLength: 1)
                if d.isEmpty { return buf.isEmpty ? nil : nil }
                if d == Data([0x0A]) { break }
                buf.append(d)
            }
            return (try? JSONSerialization.jsonObject(with: buf)) as? [String: Any]
        }
        // host_op と最終応答を区別しながら応答する
        func exchange(_ req: [String: Any]) -> [String: Any]? {
            send(req)
            while true {
                guard let obj = readLine() else { return nil }
                if obj["host_op"] != nil {
                    // READFMO の host_op:"fmo" にスナップショットで応答
                    send(["ok": true, "snapshot": snapshot])
                    continue
                }
                return obj
            }
        }

        exchange(["cmd": "load", "ghost_root": ghost.path, "encoding": "UTF-8",
                  "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]])
        let resp = exchange(["cmd": "request", "method": "GET", "id": "ReadFmoTest",
                             "ref": [], "headers": ["Charset": "UTF-8"]])
        inPipe.fileHandleForWriting.closeFile()
        proc.waitUntilExit()

        // READFMO は FMO スナップショット文字列（id.key SOH value CRLF 形式）をそのまま返す
        #expect(resp?["value"] as? String == snapshot)
    }

    /// GETMEMINFO が空配列や32bit整数に丸められず、OSの実メモリ値を返すことを検証する。
    @Test
    func yayaCoreGetMemInfoReturnsHostMemoryArray() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping C++ memory integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        GetMemoryInfo {
            _info = GETMEMINFO()
            _count = ARRAYSIZE(_info)
            "count=%(_count), load=%(_info[0]), total=%(_info[1]), available=%(_info[2])"
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let loadReq: [String: Any] = [
            "cmd": "load", "ghost_root": ghost.path, "encoding": "UTF-8",
            "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "GetMemoryInfo",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]
        let value = Self.runYayaCore(exe: exe, requests: [loadReq, request]) ?? ""

        #expect(value.contains("count=5"))
        let fields = Dictionary(uniqueKeysWithValues: value.split(separator: ",").compactMap { field -> (String, String)? in
            let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: .whitespaces), parts[1])
        })
        let load = Int(fields["load"] ?? "-1")
        let total = Int64(fields["total"] ?? "0") ?? 0
        let available = Int64(fields["available"] ?? "-1") ?? -1
        #expect((0...100).contains(load ?? -1))
        #expect(total > 0)
        #expect(available >= 0 && available <= total)
    }

    /// YAYA の文字列埋め込み履歴参照を検証する。
    @Test
    func yayaCoreEmbeddedHistoryReferencesPreviousValues() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping embedded history integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        EmbeddedHistory {
            "prefix %(1) %[0] middle %(2) %[0] %[1]"
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let loadReq: [String: Any] = [
            "cmd": "load", "ghost_root": ghost.path, "encoding": "UTF-8",
            "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "EmbeddedHistory",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) ==
                "prefix 1 1 middle 2 2 1")
    }

    /// macOS では HWND を直接送信できないため、SETTAMAHWND の指定値を
    /// 論理設定として保持し、GETSETTING で読み戻せることを検証する。
    @Test
    func yayaCoreTamaWindowHandleIsStoredAsLogicalSetting() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping TAMA window integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        TamaWindow {
            SETTAMAHWND(123456789012)
            GETSETTING("tama.hwnd")
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let loadReq: [String: Any] = [
            "cmd": "load", "ghost_root": ghost.path, "encoding": "UTF-8",
            "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "TamaWindow",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        #expect(Self.runYayaCore(exe: exe, requests: [loadReq, request]) == "123456789012")
    }

    /// FCHARSET の CP932 テキスト入出力と、FATTRIB の POSIX 属性変換を検証する。
    @Test
    func yayaCoreFileCharsetAndAttributesAreImplemented() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found; skipping file function integration test")
            return
        }
        let ghost = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghost) }

        let dic = """
        FileFunctions {
            FCHARSET(0)
            _h = FOPEN("cp932.txt", "w")
            FWRITE(_h, "日本語")
            FCLOSE(_h)
            _h = FOPEN("cp932.txt", "r")
            _text = FREAD(_h)
            FCLOSE(_h)
            _a = FATTRIB("cp932.txt")
            "text=%(_text),count=%(_a[0] + 11),directory=%(_a[2]),normal=%(_a[4]),created=%(_a[9]),modified=%(_a[10])"
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let loadReq: [String: Any] = [
            "cmd": "load", "ghost_root": ghost.path, "encoding": "UTF-8",
            "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ]
        let request: [String: Any] = [
            "cmd": "request", "method": "GET", "id": "FileFunctions",
            "ref": [], "headers": ["Charset": "UTF-8"]
        ]

        let value = Self.runYayaCore(exe: exe, requests: [loadReq, request], currentDirectory: ghost) ?? ""
        #expect(value.contains("text=日本語"))
        #expect(value.contains("count=11"))
        #expect(value.contains("directory=0"))
        #expect(value.contains("normal=1"))
        #expect(value.contains("created="))
        #expect(value.contains("modified="))

        let bytes = try Data(contentsOf: ghost.appendingPathComponent("cp932.txt"))
        #expect(bytes == Data([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA]))
    }

    /// Run yaya_core with a sequence of JSON-line requests; return the `value` of the
    /// last response (or nil). Each invocation is a fresh process: load + one request.
    private static func runYayaCore(exe: URL, requests: [[String: Any]], currentDirectory: URL? = nil) -> String? {
        let stdin = requests.map { (try? JSONSerialization.data(withJSONObject: $0)) ?? Data() }
            .map { String(data: $0, encoding: .utf8) ?? "" }
            .joined(separator: "\n") + "\n"
        let proc = Process()
        proc.executableURL = exe
        proc.currentDirectoryURL = currentDirectory
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        inPipe.fileHandleForWriting.write(Data(stdin.utf8))
        inPipe.fileHandleForWriting.closeFile()
        // Read all stdout
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        var lastValue: String?
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n") ?? [] {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if obj["host_op"] != nil { continue }
            if let v = obj["value"] as? String { lastValue = v }
        }
        return lastValue
    }
}
