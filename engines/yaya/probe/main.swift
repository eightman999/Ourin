import Foundation
import Darwin

// Compile with the actual Ourin/USL/NativeShioriModule.swift.
let arguments = CommandLine.arguments

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

func library(_ engine: String, products: URL) -> URL {
    products.appendingPathComponent(engine + "/" + (engine == "yaya" ? "libyaya.dylib" : "libaya5compat.dylib"))
}

func request(_ module: NativeShioriModule, engine: String, id: String, reference: String? = nil,
             method: String = "GET") -> String {
    let charset = engine == "yaya" ? "UTF-8" : "Shift_JIS"
    let encoding: String.Encoding = engine == "yaya" ? .utf8 : .shiftJIS
    var wire = "\(method) SHIORI/3.0\r\nCharset: \(charset)\r\nSecurityLevel: local\r\nID: \(id)\r\n"
    if let reference { wire += "Reference0: \(reference)\r\n" }
    wire += "\r\n"
    guard let data = wire.data(using: encoding, allowLossyConversion: false),
          let answer = module.request(data), let text = String(data: answer, encoding: encoding) else {
        fatalError("real engine wire conversion failed: \(engine)/\(id)")
    }
    return text
}

if arguments.count == 6, arguments[1] == "--child" {
    let engine = arguments[2], products = URL(fileURLWithPath: arguments[3])
    let root = URL(fileURLWithPath: arguments[4]), expected = arguments[5]
    let module = try NativeShioriModule(url: library(engine, products: products), loadDirectory: root)
    require(request(module, engine: engine, id: "OnRead").contains("Value: \(expected)\r\n"), "separate-process state reload failed")
    module.unload()
    print("PASS separate-process reload: \(engine)")
    exit(0)
}

guard arguments.count == 3 else { fatalError("usage: probe repository products") }
let repository = URL(fileURLWithPath: arguments[1]), products = URL(fileURLWithPath: arguments[2])
for engine in ["yaya", "aya"] {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-公式YAYA-\(engine)-\(UUID().uuidString)")
    let first = root.appendingPathComponent("一番目"), second = root.appendingPathComponent("二番目")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = repository.appendingPathComponent("engines/\(engine)/example")
    try FileManager.default.copyItem(at: fixture, to: first)
    try FileManager.default.copyItem(at: fixture, to: second)
    let snapshots = try FileManager.default.contentsOfDirectory(at: first, includingPropertiesForKeys: nil)
        .map { ($0, try Data(contentsOf: $0)) }
    let one = try NativeShioriModule(url: library(engine, products: products), loadDirectory: first)
    let two = try NativeShioriModule(url: library(engine, products: products), loadDirectory: second)
    defer { one.unload(); two.unload() }
    require(request(one, engine: engine, id: "version").contains("Value: Tc607-2\r\n"), "official GETSETTING(0) differs")
    require(request(one, engine: engine, id: "name").contains("Value: YAYA\r\n"), "official interpreter name differs")
    require(request(one, engine: engine, id: "OnBoot").contains("公式YAYA起動"), "dictionary boot failed")
    let unicode = engine == "yaya" ? "日本語😀・表ソ・①髙" : "日本語・表ソ・半角ｶﾅ・①髙"
    require(request(one, engine: engine, id: "OnEcho", reference: unicode).contains("Value: \(unicode)\r\n"), "Unicode/CP932 roundtrip failed")
    require(request(one, engine: engine, id: "OnNotify", method: "NOTIFY").contains("204 No Content"), "NOTIFY failed")
    require(request(one, engine: engine, id: "OnLatestRegex").contains("Value: 10/2026\r\n"), "official regex execution failed")
    require(request(one, engine: engine, id: "OnSet", reference: "一番目の保存値").contains("Value: saved"), "first assignment failed")
    require(request(two, engine: engine, id: "OnSet", reference: "二番目の保存値").contains("Value: saved"), "second assignment failed")
    require(request(one, engine: engine, id: "OnRead").contains("Value: 一番目の保存値"), "VMs overwrote each other")
    require(request(two, engine: engine, id: "OnRead").contains("Value: 二番目の保存値"), "VMs shared state")
    one.unload()
    require(request(two, engine: engine, id: "OnRead").contains("Value: 二番目の保存値"), "unloading first VM broke second")
    require(request(two, engine: engine, id: "OnClose").contains("公式YAYA終了"), "OnClose failed")
    two.unload()
    let saveName = engine == "yaya" ? "yaya_variable.cfg" : "aya5_variable.cfg"
    for directory in [first, second] {
        require(FileManager.default.fileExists(atPath: directory.appendingPathComponent(saveName).path), "real save file missing")
    }
    for (path, data) in snapshots {
        let current = try Data(contentsOf: path)
        require(current == data, "source fixture changed")
    }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: arguments[0])
    child.arguments = ["--child", engine, products.path, first.path, "一番目の保存値"]
    try child.run(); child.waitUntilExit()
    require(child.terminationStatus == 0, "real separate-process reload failed")
    print("PASS \(engine): official version, GET/NOTIFY, Unicode/CP932, two independent VMs, unload/save, child reload")
}
