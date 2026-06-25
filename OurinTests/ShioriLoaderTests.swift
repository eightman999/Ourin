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

struct ShioriLoaderTests {
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
