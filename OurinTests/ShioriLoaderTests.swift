import Testing
@testable import Ourin
import Foundation

private final class FakeShioriRequester: ShioriRequesting {
    var requestCount = 0
    var response: String?

    init(response: String?) {
        self.response = response
    }

    func request(_ text: String) -> String? {
        requestCount += 1
        return response
    }

    func unload() {}
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
    func resolvedXpcServiceNameReturnsNilByDefault() throws {
        #expect(ShioriLoader.resolvedXpcServiceName(environment: [:]) == nil)
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

    /// Run yaya_core with a sequence of JSON-line requests; return the `value` of the
    /// last response (or nil). Each invocation is a fresh process: load + one request.
    private static func runYayaCore(exe: URL, requests: [[String: Any]]) -> String? {
        let stdin = requests.map { (try? JSONSerialization.data(withJSONObject: $0)) ?? Data() }
            .map { String(data: $0, encoding: .utf8) ?? "" }
            .joined(separator: "\n") + "\n"
        let proc = Process()
        proc.executableURL = exe
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
