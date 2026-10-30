import Foundation
import Testing
@testable import Ourin

struct PhioriEngineTests {
    private static let products = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("build/engines/phiori")
    private static let python = "/opt/homebrew/bin/python3.14"

    @Test(.enabled(if: FileManager.default.fileExists(atPath: products.appendingPathComponent("phiori-shiolink.py").path),
                   "Stage optional upstream Python engine: python3 engines/phiori/build.py"))
    func upstreamPythonSampleAndPersistentUnicodeCallbacks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-phiori-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: Self.products.appendingPathComponent("upstream-sample"), to: master)
        try """
        @handle("OnOurinUnicodeCounter")
        def ourin_counter(value, **kwargs):
            phiori.var["OurinCounter"] = phiori.var.get("OurinCounter", 0) + 1
            write("{} {}", value, phiori.var["OurinCounter"])
        """.write(to: master.appendingPathComponent("ourin_probe.py"), atomically: true, encoding: .utf8)
        let arguments = ["-I", "-u", Self.products.appendingPathComponent("phiori-shiolink.py").path]
        let json = String(data: try JSONEncoder().encode(arguments), encoding: .utf8)!
        try "[SHIOLINK]\nmodule=phiori.dll\nexecutable=\(Self.python)\narguments=\(json)\ncharmode=UTF-8\n"
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "phiori.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
        #expect(runtime.kind == .shiolink)
        defer { runtime.unload() }
        for expected in [1, 2] {
            try #require(runtime.load(context: context))
            #expect(runtime.request(method: "NOTIFY", id: "ownerghostname", refs: ["phiori-probe"], timeout: 3)?.status == 204)
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 3)?.value == #"\1\s0\0\s0Boot Event.\e"#)
            #expect(runtime.request(method: "GET", id: "OnOurinUnicodeCounter", refs: ["桜鈴 🌸"], timeout: 3)?.value == "桜鈴 🌸 \(expected)")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", refs: ["日本語"], timeout: 3)?.status == 204)
            let close = try #require(runtime.request(method: "GET", id: "OnClose", refs: ["user"], timeout: 3))
            #expect(close.value == #"\0Close Event. reason: user\w8\w8\e"#)
            runtime.unload()
            let data = try Data(contentsOf: master.appendingPathComponent("variable.dat"))
            let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(saved?["OurinCounter"] as? Int == expected)
        }
    }
}
