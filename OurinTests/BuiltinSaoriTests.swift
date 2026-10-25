import Foundation
import Testing
@testable import Ourin

/// Windows 専用の汎用 SAORI（proxy_ex.dll）を内蔵実装で置き換える経路。
@Suite(.serialized)
struct BuiltinSaoriTests {
    private func makeModuleDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-proxy-ex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        // Windows 版 DLL の代わりに PE ヘッダだけのファイルを置く（実行はされない）
        try MinimalPE.build(exports: ["load", "request", "unload"], imports: ["KERNEL32.DLL"])
            .write(to: dir.appendingPathComponent("proxy_ex.dll"))
        // foo.exe の macOS 版（拡張子なし）
        let script = dir.appendingPathComponent("bin/foo")
        try "#!/bin/sh\nprintf 'line1\\nline2:%s:%s\\n' \"$1\" \"$2\"\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return dir
    }

    @Test
    func proxyExRunsMacExecutableForWindowsExeName() throws {
        let dir = try makeModuleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SaoriManager(registry: SaoriRegistry(searchPaths: [dir]))

        let delim = try manager.execute(moduleName: "proxy_ex.dll", arguments: ["/delim", "|"])
        #expect(delim.statusCode == 204)

        let response = try manager.execute(moduleName: "proxy_ex.dll", arguments: ["bin\\foo.exe", "a b", "c"])
        #expect(response.statusCode == 200)
        #expect(response.headerValue("Result") == "line1|line2:a b:c|")
    }

    @Test
    func proxyExReportsBadRequestWhenNoMacExecutableExists() throws {
        let dir = try makeModuleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let manager = SaoriManager(registry: SaoriRegistry(searchPaths: [dir]))

        let response = try manager.execute(moduleName: "proxy_ex.dll", arguments: ["missing.exe"])
        #expect(response.statusCode == 400)
        #expect(try manager.execute(moduleName: "proxy_ex.dll", arguments: ["hwnd"]).statusCode == 204)
    }

    @Test
    func otherWindowsOnlySaoriIsStillNotFound() throws {
        let dir = try makeModuleDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try MinimalPE.build(exports: ["load", "request", "unload"], imports: ["USER32.dll"])
            .write(to: dir.appendingPathComponent("textcopy.dll"))
        let manager = SaoriManager(registry: SaoriRegistry(searchPaths: [dir]))
        #expect(throws: (any Error).self) {
            _ = try manager.execute(moduleName: "textcopy.dll", arguments: ["x"])
        }
    }
}
