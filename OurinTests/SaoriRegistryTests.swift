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

    @Test
    func resolveModuleURLFindsPluginBundleCandidate() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // .dll 名から .plugin バンドル候補が生成されることを検証する
        let moduleURL = root.appendingPathComponent("saori_sample.plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: moduleURL, withIntermediateDirectories: true)

        let registry = SaoriRegistry(searchPaths: [root])
        let found = registry.resolveModuleURL(named: "saori_sample.dll")

        #expect(found == moduleURL)
    }

    @Test
    func cacheUsesResolvedURLWhenSameModuleNameExistsInMultipleSearchPaths() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot.appendingPathComponent("satori_core/build/external_saori.dylib")
        try #require(FileManager.default.fileExists(atPath: fixture.path))

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let firstPath = root.appendingPathComponent("first", isDirectory: true)
        let secondPath = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstModule = firstPath.appendingPathComponent("same.dylib")
        let secondModule = secondPath.appendingPathComponent("same.dylib")
        try FileManager.default.copyItem(at: fixture, to: firstModule)
        try FileManager.default.copyItem(at: fixture, to: secondModule)

        let registry = SaoriRegistry(searchPaths: [firstPath, secondPath])
        let firstLoader = try registry.loadModule(named: "same")
        defer { firstLoader.unload() }
        #expect(firstLoader.moduleURL.standardizedFileURL == firstModule.standardizedFileURL)

        registry.setSearchPaths([secondPath])
        let secondLoader = try registry.loadModule(named: "same")
        defer { secondLoader.unload() }
        #expect(secondLoader.moduleURL.standardizedFileURL == secondModule.standardizedFileURL)
    }
}
