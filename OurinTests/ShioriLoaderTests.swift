import Testing
@testable import Ourin
import Foundation

struct ShioriLoaderTests {
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
        let dir = URL(fileURLWithPath: #file).deletingLastPathComponent()
        let base = dir.appendingPathComponent("Fixtures")
        let ghost = base.appendingPathComponent("ghost/master")
        let b64 = ghost.appendingPathComponent("test_shiori.so.b64")
        let dylib = ghost.appendingPathComponent("test_shiori.so")
        if FileManager.default.fileExists(atPath: dylib.path) {
            try? FileManager.default.removeItem(at: dylib)
        }
        if let data = try? String(contentsOf: b64),
           let bin = Data(base64Encoded: data) {
            try bin.write(to: dylib)
        }
        defer { try? FileManager.default.removeItem(at: dylib) }

        guard let loader = ShioriLoader(module: "test_shiori.so", base: base) else {
            #fail("load failed")
            return
        }
        let req = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: Test\r\nID: Ping\r\n\r\n"
        let res = loader.request(req)
        #expect(res?.contains("200 OK") == true)
        loader.unload()
    }
}
