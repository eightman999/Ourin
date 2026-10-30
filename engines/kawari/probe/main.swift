import Foundation
import Darwin

// Compile together with the production Ourin/USL/NativeShioriModule.swift.
// argv: repository, staged-native-resources (or build/engines)
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("usage: native-probe repository products") }
let repository = URL(fileURLWithPath: arguments[1])
let products = URL(fileURLWithPath: arguments[2])

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

for engine in ["kawari", "aosora"] {
    let name = engine == "kawari" ? "libkawari_shiori.dylib" : "libaosora.dylib"
    let fixture = repository.appendingPathComponent("engines/\(engine)/example")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-実Native-\(engine)-\(UUID().uuidString)")
    try FileManager.default.copyItem(at: fixture, to: directory)
    defer { try? FileManager.default.removeItem(at: directory) }
    for pass in 0..<2 {
        let module = try NativeShioriModule(url: products.appendingPathComponent("\(engine)/\(name)"), loadDirectory: directory)
        func request(_ id: String, reference: String? = nil) -> String {
            var wire = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSecurityLevel: local\r\nID: \(id)\r\n"
            if let reference { wire += "Reference0: \(reference)\r\n" }
            wire += "\r\n"
            return module.request(Data(wire.utf8)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        check(request("OnBoot").contains("起動"), "missing real \(engine) OnBoot")
        check(request("OnEcho", reference: "日本語・表ソ😀").contains("Value: 日本語・表ソ😀\r\n"), "Unicode roundtrip failed")
        if pass == 0 {
            check(request("OnSet", reference: "実Native保存😀").contains("Value: saved\r\n"), "save assignment failed")
        } else {
            check(request("OnRead").contains("Value: 実Native保存😀\r\n"), "real persisted state was not restored")
        }
        check(request("OnClose").contains("終了"), "missing real OnClose")
        module.unload()
        check(module.request(Data()) == nil, "request survived unload")
        let state = engine == "kawari" ? "state.kis" : "savedata.asv"
        check(FileManager.default.fileExists(atPath: directory.appendingPathComponent(state).path), "missing persisted file")
    }
    print("PASS \(engine): production Native loader, Unicode path/response, save, reload, unload")
}
