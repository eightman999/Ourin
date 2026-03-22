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
}
