import Foundation

/// Phase 3: 解析成果物から `ourin/analysis/report.md` を生成する。
///
/// 計画「Phase 3: レポート生成」節:
/// - binary kind、exports、imports、目立つ文字列、推定機能をまとめる
/// - Ourin 側の推奨移行モードを提示する
///
/// 計画「注意点」に従い、Ghidra の疑似 C は元ソースではないため、
/// 完全自動変換ではなく TODO として扱う。
enum MigrationReport {
    /// imports.json / exports.json の簡易パース結果。
    struct ImportEntry: Codable, Hashable {
        let name: String
        let library: String?
        let address: String?
    }
    struct ExportEntry: Codable, Hashable {
        let name: String
        let address: String?
        let type: String?
        let source: String?
    }

    /// report.md を出力ディレクトリ（ourin/analysis/）に書き出す。
    /// 既存ファイルがある場合は上書きする（呼び出し側で確認済み想定）。
    @discardableResult
    static func write(asset: LegacyAssetScanner.Asset,
                      analysisDirectory: URL,
                      manifest: OurinManifest?,
                      ghidraDurationSeconds: TimeInterval?) -> URL {
        let url = analysisDirectory.appendingPathComponent("report.md")
        let content = render(asset: asset,
                             analysisDirectory: analysisDirectory,
                             manifest: manifest,
                             ghidraDurationSeconds: ghidraDurationSeconds)
        try? content.data(using: .utf8)?.write(to: url, options: [.atomic])
        return url
    }

    /// report.md の内容を組み立てる。
    static func render(asset: LegacyAssetScanner.Asset,
                       analysisDirectory: URL,
                       manifest: OurinManifest?,
                       ghidraDurationSeconds: TimeInterval?) -> String {
        var lines: [String] = []
        let name = asset.displayName
        let binary = asset.filename.isEmpty ? "(no binary)" : asset.filename
        let binKind = asset.binaryKind.displayName

        lines.append("# Migration Report: \(name)")
        lines.append("")
        lines.append("> このレポートは Ghidra の解析結果から自動生成されたものです。")
        lines.append("> 疑似 C は元ソースではないため、Swift/macOS plugin への完全自動変換は行いません。")
        lines.append("")

        lines.append("## Summary")
        lines.append("")
        lines.append("| 項目 | 値 |")
        lines.append("| --- | --- |")
        lines.append("| Name | \(escape(name)) |")
        lines.append("| Kind | \(asset.kind.rawValue) |")
        lines.append("| Binary | \(binKind) |")
        lines.append("| Filename | \(escape(binary)) |")
        if !asset.sspID.isEmpty {
            lines.append("| SSP ID | \(escape(asset.sspID)) |")
        }
        if let impl = manifest?.implementation {
            lines.append("| Implementation | `\(impl)` |")
        }
        if let mode = manifest?.mode {
            lines.append("| Mode | \(mode.rawValue) |")
            lines.append("| Recommendation | \(escape(mode.recommendation)) |")
        } else {
            let (mode, impl) = OurinManifest.recommendedMode(for: asset.filename)
            lines.append("| Recommended Mode | \(mode.rawValue) |")
            lines.append("| Recommendation | \(escape(mode.recommendation)) |")
            if let impl = impl {
                lines.append("| Suggested Implementation | `\(impl)` |")
            }
        }
        if let dur = ghidraDurationSeconds {
            lines.append("| Ghidra 解析時間 | \(String(format: "%.1f", dur)) 秒 |")
        }
        lines.append("")

        // descript.txt summary
        if !asset.descriptor.isEmpty {
            lines.append("## descript.txt")
            lines.append("")
            lines.append("| key | value |")
            lines.append("| --- | --- |")
            for key in asset.descriptor.keys.sorted() {
                lines.append("| \(escape(key)) | \(escape(asset.descriptor[key] ?? "")) |")
            }
            lines.append("")
        }

        // imports / exports
        let imports = readImports(at: analysisDirectory)
        let exports = readExports(at: analysisDirectory)

        lines.append("## Exports (\(exports.count))")
        lines.append("")
        if exports.isEmpty {
            lines.append("(なし)")
        } else {
            lines.append("| name | type | address |")
            lines.append("| --- | --- | --- |")
            for e in exports.prefix(40) {
                lines.append("| \(escape(e.name)) | \(escape(e.type ?? "")) | \(escape(e.address ?? "")) |")
            }
            if exports.count > 40 {
                lines.append("| ... | (\(exports.count - 40) more) | |")
            }
        }
        lines.append("")

        lines.append("## Imports (\(imports.count))")
        lines.append("")
        if imports.isEmpty {
            lines.append("(なし)")
        } else {
            lines.append("| name | library |")
            lines.append("| --- | --- |")
            for e in imports.prefix(60) {
                lines.append("| \(escape(e.name)) | \(escape(e.library ?? "")) |")
            }
            if imports.count > 60 {
                lines.append("| ... | (\(imports.count - 60) more) |")
            }
        }
        lines.append("")

        // 目立つ文字列
        lines.append("## Notable Strings")
        lines.append("")
        let strings = readStringsPreview(at: analysisDirectory)
        if strings.isEmpty {
            lines.append("(取得できませんでした)")
        } else {
            lines.append("```")
            for s in strings {
                lines.append(s)
            }
            lines.append("```")
        }
        lines.append("")

        // 実装 TODO（exports/imports から推定）
        lines.append("## Implementation TODO")
        lines.append("")
        lines.append(contentsOf: implementationTODOs(asset: asset, exports: exports, imports: imports, manifest: manifest))
        lines.append("")

        // 生成ファイル一覧
        lines.append("## Generated Files")
        lines.append("")
        for file in ["decompiled.c", "imports.json", "exports.json", "strings.txt", "resources.txt", "report.md"] {
            let exists = FileManager.default.fileExists(
                atPath: analysisDirectory.appendingPathComponent(file).path
            )
            lines.append("- [\(exists ? "x" : " ")] `\(file)`")
        }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    /// exports/imports/既知 DLL 情報から、実装すべき機能の TODO を推定する。
    /// 計画「.plugin 雛形生成」節の「exports/imports/strings から推定した実装 TODO」に対応。
    private static func implementationTODOs(asset: LegacyAssetScanner.Asset,
                                            exports: [ExportEntry],
                                            imports: [ImportEntry],
                                            manifest: OurinManifest?) -> [String] {
        var todos: [String] = []
        let exportNames = Set(exports.map { $0.name.lowercased() })
        let importNames = Set(imports.flatMap { $0.name.lowercased().split(separator: ".").last.map(String.init) })

        // SSP plugin イベント入口の検出（計画「.plugin 雛形生成」のイベント入口と同期）
        let eventEntryPoints: [(keyword: String, todo: String)] = [
            ("load", "Load / 初期化エントリポイントの実装"),
            ("unload", "Unload / 終了処理の実装"),
            ("request", "SSTP Request (GET/NOTIFY) ハンドラの実装"),
            ("get", "GET イベント処理の実装"),
            ("version", "Version 応答の実装")
        ]
        for ep in eventEntryPoints where exportNames.contains(where: { $0.contains(ep.keyword) }) || importNames.contains(where: { $0.contains(ep.keyword) }) {
            todos.append("- [ ] \(ep.todo)")
        }

        // 最低限のイベント入口 TODO（雛形生成時の基準）
        for required in ["OnBoot", "OnSecondChange", "OnMinuteChange", "OnGhostChanged"] {
            if exportNames.contains(required.lowercased()) {
                todos.append("- [x] \(required) はエクスポート済み（要：macOS 版での等価実装）")
            } else {
                todos.append("- [ ] \(required) イベント入口の実装")
            }
        }

        // 既知 DLL の場合
        if OurinManifest.isKnownBuiltin(asset.filename) {
            todos.append("- [x] 既知 DLL: `\(OurinManifest.builtinImplementation(for: asset.filename) ?? "?")` でネイティブ置換")
            todos.append("- [ ] builtin 側で元 DLL のイベント refs 互換性を確認")
        } else {
            todos.append("- [ ] 未知 DLL: `.plugin` 雛形を生成し、export からエントリポイントを写す")
            todos.append("- [ ] import している Windows API を macOS 等価で置き換える（例: `Kernel32`→Foundation、`WS2_32`→Network フレームワーク）")
        }

        // Win32 API の目立つ import を列挙
        let win32Hints = imports.filter { entry in
            let lib = (entry.library ?? "").lowercased()
            return lib.hasSuffix(".dll") && !lib.isEmpty
        }
        if !win32Hints.isEmpty {
            let libs = Array(Set(win32Hints.compactMap { $0.library })).sorted().prefix(10)
            todos.append("- [ ] 依存 Windows DLL: \(libs.joined(separator: ", "))")
        }

        return todos.isEmpty ? ["- (推定可能な TODO がありません)"] : todos
    }

    // MARK: - 成果物読み込み

    static func readImports(at dir: URL) -> [ImportEntry] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("imports.json")) else { return [] }
        return (try? JSONDecoder().decode([ImportEntry].self, from: data)) ?? []
    }

    static func readExports(at dir: URL) -> [ExportEntry] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("exports.json")) else { return [] }
        return (try? JSONDecoder().decode([ExportEntry].self, from: data)) ?? []
    }

    static func readStringsPreview(at dir: URL, limit: Int = 20) -> [String] {
        guard let text = try? String(contentsOf: dir.appendingPathComponent("strings.txt"), encoding: .utf8) else {
            return []
        }
        // タブ区切り 4 カラムの末尾（文字列値）を拾う。意味ありげな長さで絞る。
        var picked: [String] = []
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let value = parts.last else { continue }
            let s = String(value)
            if s.count >= 5 && s.count <= 120 && s.unicodeScalars.allSatisfy({ $0.isPrintableAscii || $0.value > 0x1F }) {
                picked.append(s)
            }
            if picked.count >= limit { break }
        }
        return picked
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
         .replacingOccurrences(of: "\n", with: " ")
    }
}

private extension Unicode.Scalar {
    /// ASCII 印刷可能範囲（0x20-0x7E）。日本語等は value>0x1F で許容。
    var isPrintableAscii: Bool { value >= 0x20 && value <= 0x7E }
}
