import Foundation
import Testing
@testable import Ourin

struct SaoriRegistryTests {
    @Test
    func discoverSaoriDirectoryAddsPath() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let saoriDir = base.appendingPathComponent(".saori", isDirectory: true)
        try FileManager.default.createDirectory(at: saoriDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let registry = SaoriRegistry(searchPaths: [])
        registry.discoverSaoriDirectory(under: base)

        #expect(registry.searchPaths.contains(saoriDir))
    }

    @Test
    func resolveModuleURLFindsNormalizedName() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let moduleURL = root.appendingPathComponent("libsample.dylib")
        FileManager.default.createFile(atPath: moduleURL.path, contents: Data("x".utf8))

        let registry = SaoriRegistry(searchPaths: [root])
        let found = registry.resolveModuleURL(named: "sample.dll")

        #expect(found == moduleURL)
    }
}
