import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct SSPCompatTests {
    @Test
    func resolvesSSPDataPathsAndExecutables() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinSSPCompat-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let ghostRoot = base.appendingPathComponent("ghost/test/ghost/master", isDirectory: true)
        try FileManager.default.createDirectory(at: ghostRoot, withIntermediateDirectories: true)

        let ssph = SSPCompat.resolvePath("data\\SSPH.exe", relativeTo: ghostRoot)
        let mcp = SSPCompat.resolvePath("C:\\SSP\\data\\mcp.exe", relativeTo: ghostRoot)
        let bareMcp = SSPCompat.resolvePath("mcp.exe", relativeTo: ghostRoot)
        let readme = SSPCompat.resolvePath("readme.txt", relativeTo: ghostRoot)

        #expect(ssph.path == base.appendingPathComponent("data/SSPH.exe").path)
        #expect(mcp.path == base.appendingPathComponent("data/mcp.exe").path)
        #expect(bareMcp.path == base.appendingPathComponent("data/mcp.exe").path)
        #expect(readme.path == ghostRoot.appendingPathComponent("readme.txt").path)
        #expect(SSPCompat.executableKind(for: ssph) == .ssph)
        #expect(SSPCompat.executableKind(for: mcp) == .mcp)
    }

    @Test
    func basewareProviderExposesPublicDataFolders() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinSSPCompat-\(UUID().uuidString)", isDirectory: true)
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let provider = BasewarePropertyProvider()

        #expect(provider.get(key: "rootpath") == base.path)
        #expect(provider.get(key: "datapath") == base.appendingPathComponent("data").path)
        #expect(provider.get(key: "mcp.path") == base.appendingPathComponent("data/mcp.exe").path)
        #expect(provider.get(key: "ssph.path") == base.appendingPathComponent("data/ssph.exe").path)
    }
}
