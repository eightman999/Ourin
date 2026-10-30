import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct YayaEngineTests {
    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private static func module(_ engine: String) -> URL {
        let name = engine == "yaya" ? "libyaya.dylib" : "libaya5compat.dylib"
        return repository.appendingPathComponent("build/engines/\(engine)/\(name)")
    }
    private static var built: Bool {
        ["yaya", "aya"].allSatisfy { FileManager.default.fileExists(atPath: module($0).path) }
    }
    private func fixture(_ engine: String, at root: URL) throws -> URL {
        let dictionary = root.appendingPathComponent("ghost/master/公式・\(engine)")
        try FileManager.default.createDirectory(at: dictionary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.repository.appendingPathComponent("engines/\(engine)/example"), to: dictionary)
        return dictionary
    }
    private func request(_ loader: ShioriLoader, engine: String, id: String, ref: String? = nil,
                         method: String = "GET") throws -> ShioriRuntimeResponse {
        let charset = engine == "yaya" ? "UTF-8" : "Shift_JIS"
        let wire = ShioriWireCodec.makeRequest(method: method, id: id, headers: ["SecurityLevel": "local"],
                                               refs: ref.map { [$0] } ?? [], charset: charset)
        let answer = try #require(loader.request(wire))
        return try #require(ShioriWireCodec.parseResponse(answer))
    }

    @Test(.enabled(if: built, "Build official YAYA and the AYA5 compatibility variant first"),
          arguments: ["yaya", "aya"], [false, true])
    func officialVersionRealWireAndPersistence(engine: String, isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Yaya-\(UUID().uuidString)")
        let dictionary = try fixture(engine, at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let communication = ShioriCommunicationOptions(encoding: engine == "yaya" ? "UTF-8" : "Shift_JIS")
        let text = engine == "yaya" ? "桜鈴😀・日本語・表ソ" : "桜鈴・表ソ・半角ｶﾅ・①髙"
        for pass in 0..<2 {
            let loader = try #require(ShioriLoader(moduleURL: Self.module(engine),
                xpcServiceName: isolated ? "jp.ourin.shiori" : nil, communication: communication, loadDirectory: dictionary))
            defer { loader.unload() }
            #expect(try request(loader, engine: engine, id: "version").value == "Tc607-2")
            #expect(try request(loader, engine: engine, id: "name").value == "YAYA")
            #expect(try request(loader, engine: engine, id: "OnBoot").value?.contains("公式YAYA起動") == true)
            #expect(try request(loader, engine: engine, id: "OnEcho", ref: text).value == text)
            #expect(try request(loader, engine: engine, id: "OnNotify", method: "NOTIFY").status == 204)
            #expect(try request(loader, engine: engine, id: "OnLatestRegex").value == "10/2026")
            if pass == 0 {
                #expect(try request(loader, engine: engine, id: "OnSet", ref: text).value == "saved")
            } else {
                #expect(try request(loader, engine: engine, id: "OnRead").value == text)
            }
            #expect(try request(loader, engine: engine, id: "OnClose").value?.contains("公式YAYA終了") == true)
            loader.unload()
            let save = engine == "yaya" ? "yaya_variable.cfg" : "aya5_variable.cfg"
            #expect(FileManager.default.fileExists(atPath: dictionary.appendingPathComponent(save).path))
            #expect(loader.request("GET SHIORI/3.0\r\n\r\n") == nil)
        }
    }

    @Test(.enabled(if: built, "Build official YAYA and AYA5 compatibility engines first"), arguments: ["yaya", "aya"])
    func simultaneousVMsRemainIndependentAfterOneUnload(engine: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Yaya-Multi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try fixture(engine, at: root.appendingPathComponent("first"))
        let second = try fixture(engine, at: root.appendingPathComponent("second"))
        let communication = ShioriCommunicationOptions(encoding: engine == "yaya" ? "UTF-8" : "Shift_JIS")
        let one = try #require(ShioriLoader(moduleURL: Self.module(engine), xpcServiceName: nil,
                                           communication: communication, loadDirectory: first))
        let two = try #require(ShioriLoader(moduleURL: Self.module(engine), xpcServiceName: nil,
                                           communication: communication, loadDirectory: second))
        defer { one.unload(); two.unload() }
        #expect(try request(one, engine: engine, id: "OnSet", ref: "一番目").value == "saved")
        #expect(try request(two, engine: engine, id: "OnSet", ref: "二番目").value == "saved")
        #expect(try request(one, engine: engine, id: "OnRead").value == "一番目")
        #expect(try request(two, engine: engine, id: "OnRead").value == "二番目")
        one.unload()
        #expect(try request(two, engine: engine, id: "OnRead").value == "二番目")
        two.unload()
        let save = engine == "yaya" ? "yaya_variable.cfg" : "aya5_variable.cfg"
        #expect(FileManager.default.fileExists(atPath: first.appendingPathComponent(save).path))
        #expect(FileManager.default.fileExists(atPath: second.appendingPathComponent(save).path))
    }
}
