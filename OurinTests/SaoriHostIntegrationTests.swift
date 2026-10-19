import Foundation
import Testing
@testable import Ourin

struct SaoriHostIntegrationTests {
    @Test
    func yayaAdapterRequestsStandardSaoriWithoutExplicitLoad() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = repositoryRoot.appendingPathComponent("yaya_core/build/yaya_core")
        let fixtureLibrary = repositoryRoot.appendingPathComponent("satori_core/build/external_saori.dylib")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))
        try #require(FileManager.default.fileExists(atPath: fixtureLibrary.path))

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ourin-SaoriHost-\(UUID().uuidString)", isDirectory: true)
        let saoriDirectory = fixtureRoot.appendingPathComponent("saori", isDirectory: true)
        try FileManager.default.createDirectory(at: saoriDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        try FileManager.default.copyItem(
            at: fixtureLibrary,
            to: saoriDirectory.appendingPathComponent("external_saori.dylib")
        )

        let runtime = try #require(YayaAdapter(executableURL: executable))
        defer { runtime.unload() }
        let context = ShioriRuntimeLoadContext(
            ghostURL: fixtureRoot,
            ghostRoot: fixtureRoot,
            moduleName: "yaya.dll",
            dictionaryEntries: []
        )
        #expect(runtime.load(context: context))

        let request = "EXECUTE SAORI/1.0\r\nCharset: UTF-8\r\nArgument0: ping\r\n\r\n"
        let result = runtime.handlePluginOperation(
            "saori_request",
            params: ["module": "external_saori", "request": request, "charset": "UTF-8"]
        )
        #expect(result["ok"] as? Bool == true)
        #expect(result["result"] as? String == "external-saori-ok")
        #expect(result["values"] as? [String] == ["fixture-value"])

        let unload = runtime.handlePluginOperation(
            "saori_unload",
            params: ["module": "external_saori"]
        )
        #expect(unload["ok"] as? Bool == true)
    }
}
