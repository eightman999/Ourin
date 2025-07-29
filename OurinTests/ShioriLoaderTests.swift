import Testing
@testable import Ourin

struct ShioriLoaderTests {
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
