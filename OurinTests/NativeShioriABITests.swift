import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct NativeShioriABITests {
    private func fixture(root: URL, int32: Bool = false, failLoad: Bool = false) throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shiori/standard_fixture.c")
        let module = root.appendingPathComponent("fixture.dylib")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-dynamiclib", source.path, "-o", module.path]
            + (int32 ? ["-DLENGTH32"] : []) + (failLoad ? ["-DFAIL_LOAD"] : [])
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0)
        return module
    }

    private func declare(_ abi: String, for module: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["OurinShioriABI": abi], format: .xml, options: 0)
        try data.write(to: module.appendingPathExtension("plist"))
    }

    private func yayaFixture(root: URL, failLoad: Bool = false) throws -> URL {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/shiori/yaya_multi_fixture.c")
        let module = root.appendingPathComponent("yaya-multi.dylib")
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        compiler.arguments = ["-dynamiclib", "-DOURIN_YAYA_MULTI_FIXTURE", source.path, "-o", module.path]
            + (failLoad ? ["-DFAIL_LOAD"] : [])
        try compiler.run(); compiler.waitUntilExit()
        try #require(compiler.terminationStatus == 0)
        try declare("yaya", for: module)
        return module
    }

    @Test(arguments: [false, true])
    func officialYayaABIUsesLongInstanceIDsAndKeepsTwoGhostsIndependent(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstDirectory = root.appendingPathComponent("最初"), secondDirectory = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try yayaFixture(root: root)
        let first = try #require(ShioriLoader(moduleURL: module, xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
                                             shiori2Compatibility: false, loadDirectory: firstDirectory))
        let second = try #require(ShioriLoader(moduleURL: module, xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
                                              shiori2Compatibility: false, loadDirectory: secondDirectory))
        defer { first.unload(); second.unload() }
        let get = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n"
        let firstResponse = try #require(first.request(get))
        let secondResponse = try #require(second.request(get))
        #expect(firstResponse.contains(":1\r\n"))
        #expect(secondResponse.contains(":1\r\n"))
        if !isolated { #expect(firstResponse != secondResponse) }
        #expect(second.request("NOTIFY SHIORI/3.0\r\nID: OnNotify\r\n\r\n")?.contains("204 No Content") == true)
        first.unload()
        #expect(FileManager.default.fileExists(atPath: firstDirectory.appendingPathComponent("unloaded.marker").path))
        #expect(!FileManager.default.fileExists(atPath: secondDirectory.appendingPathComponent("unloaded.marker").path))
        #expect(second.request(get)?.contains(":2\r\n") == true)
        second.unload()
        #expect(FileManager.default.fileExists(atPath: secondDirectory.appendingPathComponent("unloaded.marker").path))
    }

    @Test(arguments: [false, true])
    func officialYayaABIDoesNotTreatTheReservedZeroInstanceAsSuccess(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try yayaFixture(root: root, failLoad: true)
        #expect(ShioriLoader(moduleURL: module, xpcServiceName: isolated ? "jp.ourin.shiori" : nil) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("unloaded.marker").path))
    }

    @Test(arguments: [false, true], [false, true])
    func standardABIUsesDeclaredWidthAndGhostDirectory(int32: Bool, isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let ghost = root.appendingPathComponent("ghost/shiori")
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try fixture(root: root, int32: int32)
        try declare(int32 ? "ukagaka-int32" : "ukagaka-long", for: module)
        let loader = try #require(ShioriLoader(moduleURL: module,
            xpcServiceName: isolated ? "jp.ourin.shiori" : nil,
            shiori2Compatibility: false, loadDirectory: ghost))
        #expect(loader.request("GET SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnBoot\r\n\r\n")?.contains("Value: standard-fixture") == true)
        #expect(loader.request("NOTIFY SHIORI/3.0\r\nCharset: UTF-8\r\nID: OnNotify\r\n\r\n")?.contains("204 No Content") == true)
        let pid = try #require(Int(String(contentsOf: ghost.appendingPathComponent("loaded.pid"), encoding: .utf8)))
        #expect((pid != ProcessInfo.processInfo.processIdentifier) == isolated)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("loaded.pid").path))
        loader.unload()
        #expect(FileManager.default.fileExists(atPath: ghost.appendingPathComponent("unloaded.marker").path))
        #expect(loader.request("GET SHIORI/3.0\r\n\r\n") == nil)
    }

    @Test(arguments: [false, true])
    func standardLoadFailureIsReported(isolated: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try fixture(root: root, failLoad: true)
        try declare("ukagaka-long", for: module)
        #expect(ShioriLoader(moduleURL: module, xpcServiceName: isolated ? "jp.ourin.shiori" : nil, shiori2Compatibility: false) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("unloaded.marker").path))
    }

    @Test
    func ambiguousOrUnknownABIIsRejectedBeforeCallingCode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try fixture(root: root)
        #expect(ShioriLoader(moduleURL: module, xpcServiceName: nil) == nil)
        try declare("guess", for: module)
        #expect(ShioriLoader(moduleURL: module, xpcServiceName: nil) == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("loaded.pid").path))
    }

    @Test
    func nativeSearchPreservesWindowsSubdirectoriesAndCase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let subdir = root.appendingPathComponent("Engine")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = subdir.appendingPathComponent("Custom.dylib")
        try Data().write(to: module)
        #expect(ShioriLoader.find(name: "engine\\custom.dll", in: [root])?.path.lowercased() == module.path.lowercased())
    }
}
