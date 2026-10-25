import Foundation
import Testing
@testable import Ourin

/// 実在のプラグイン群（SSP 用に配布されているフォルダ）を一時コピーして変換・実行する検証。
/// `OURIN_PLUGIN_CORPUS`（xcodebuild では `TEST_RUNNER_OURIN_PLUGIN_CORPUS`）にフォルダ群の親を渡したときだけ動く。
@Suite(.serialized)
struct RealPluginCorpusTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OURIN_PLUGIN_CORPUS"] != nil))
    func convertAndRunRealPlugins() throws {
        let corpus = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OURIN_PLUGIN_CORPUS"]))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        var lines: [String] = []
        let items = try FileManager.default.contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for item in items where FileManager.default.fileExists(atPath: item.appendingPathComponent("descript.txt").path) {
            let copy = work.appendingPathComponent(item.lastPathComponent)
            try FileManager.default.copyItem(at: item, to: copy)
            guard let report = DLLPluginConverter.convert(pluginDirectory: copy) else {
                lines.append("\(item.lastPathComponent)\tno-descript")
                continue
            }
            guard case .converted(let bundleURL, let engine) = report.outcome else {
                lines.append("\(item.lastPathComponent)\t\(report.moduleName)\t\(report.outcome)")
                continue
            }
            let plugin = try Plugin(url: bundleURL)
            let loaded = plugin.load(directoryURL: copy)
            let descript = LegacyDescriptor.readDictionary(from: copy.appendingPathComponent("descript.txt")) ?? [:]
            let charset = descript["charset"] ?? "Shift_JIS"
            let version = plugin.send(PluginFrame(id: "version", charset: charset).build(), charset: charset)
            let boot = plugin.send(PluginFrame(
                id: "OnGhostBoot",
                references: ["1\u{1}2", "テスト", "master", "abcdef", copy.path + "/"],
                charset: charset
            ).build(), charset: charset)
            let menu = plugin.send(PluginFrame(
                id: "OnMenuExec",
                references: ["1\u{1}2", "テスト", "master", "abcdef", copy.path + "/"],
                charset: charset
            ).build(), charset: charset)
            plugin.unload()
            func head(_ text: String) -> String {
                text.replacingOccurrences(of: "\r\n", with: " | ").prefix(160).description
            }
            lines.append("\(item.lastPathComponent)\t\(engine.rawValue)\tload=\(loaded)\n  version: \(head(version))\n  boot: \(head(boot))\n  menu: \(head(menu))")
        }
        let output = lines.joined(separator: "\n")
        print("=== REAL PLUGIN CORPUS ===\n\(output)\n=== END ===")
        if let out = ProcessInfo.processInfo.environment["OURIN_PLUGIN_CORPUS_REPORT"] {
            try output.write(toFile: out, atomically: true, encoding: .utf8)
        }
    }
}
