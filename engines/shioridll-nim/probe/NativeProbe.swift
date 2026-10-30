import Foundation
import Darwin

/// Compile together with Ourin/USL/NativeShioriModule.swift. All ABI calls use
/// that production loader; the real compiler-built Nim modules supply behavior.
@main struct NativeProbe {
    struct Failure: Error, CustomStringConvertible { let description: String }
    final class Operation<T>: @unchecked Sendable {
        let action: () throws -> T
        var result: Result<T, Error>?
        init(_ action: @escaping () throws -> T) { self.action = action }
    }
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }
    static func foreign<T>(_ action: @escaping () throws -> T) throws -> T {
        let operation = Operation(action), done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            operation.result = Result { try operation.action() }
            done.signal()
        }
        try check(done.wait(timeout: .now() + 10) == .success, "Foreign thread timed out")
        guard let result = operation.result else { throw Failure(description: "Foreign thread produced no result") }
        return try result.get()
    }
    static func wire(_ id: String, method: String = "GET", reference: String? = nil) -> Data {
        Data(("\(method) SHIORI/3.0\r\nCharset: UTF-8\r\nID: \(id)\r\n" +
            (reference.map { "Reference0: \($0)\r\n" } ?? "") + "\r\n").utf8)
    }
    static func response(_ module: NativeShioriModule, _ id: String, method: String = "GET", reference: String? = nil) throws -> String {
        guard let bytes = module.request(wire(id, method: method, reference: reference)),
              let text = String(data: bytes, encoding: .utf8) else { throw Failure(description: "Missing UTF-8 response for " + id) }
        return text
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw Failure(description: "Usage: NativeProbe products-directory") }
        let products = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Nim-CLI-\(UUID().uuidString)/日本語 master")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        for name in ["libnimshiori.dylib", "libupstream-basic.dylib"] {
            for file in [name, name + ".plist"] {
                try FileManager.default.copyItem(at: products.appendingPathComponent(file), to: root.appendingPathComponent(file))
            }
        }
        let basic = try NativeShioriModule(url: root.appendingPathComponent("libupstream-basic.dylib"), loadDirectory: root)
        defer { basic.unload() }
        try check(try response(basic, "OnBoot").contains(#"Value: \0\s[0]aaaaaa\e"#), "Upstream example changed")
        for _ in 0..<2 {
            let module = try foreign { try NativeShioriModule(url: root.appendingPathComponent("libnimshiori.dylib"), loadDirectory: root) }
            defer { module.unload() }
            for _ in 0..<10 {
                try check(try response(basic, "name").contains("Value: nimshiori"), "Other Nim module corrupted")
                let boot = try foreign { try response(module, "OnBoot") }
                try check(boot.contains("こんにちは、桜鈴。"), "Japanese callback failed")
                let echo = try foreign { try response(module, "OnEcho", reference: "桜鈴 🌸") }
                try check(echo.contains("Value: 桜鈴 🌸\r\n"), "Unicode echo failed")
            }
            try check(try foreign { try response(module, "OnNotify", method: "NOTIFY") }.hasPrefix("SHIORI/3.0 204"), "NOTIFY failed")
            try check(try foreign { try response(module, "OnClose") }.contains(#"\0終了します。\-"#), "OnClose failed")
            let path = try String(contentsOf: root.appendingPathComponent("nim-loaded.path"), encoding: .utf8)
            try check(URL(fileURLWithPath: path).standardizedFileURL.path == root.standardizedFileURL.path, "Unicode load path changed")
            try foreign { module.unload() }
            try check(try String(contentsOf: root.appendingPathComponent("nim-unloaded.marker"), encoding: .utf8) == "unloaded", "Actual Nim unload did not run")
        }
        #if arch(x86_64)
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        print("PASS NativeShioriModule x86_64 translated=\(status == 0 ? translated : 0): upstream/basic + Japanese/emoji, two reloads, fresh foreign pthread entries, actual unload markers")
        #elseif arch(arm64)
        print("PASS NativeShioriModule arm64: upstream/basic + Japanese/emoji, two reloads, fresh foreign pthread entries, actual unload markers")
        #endif
    }
}
