import Foundation

/// Phase 5: 未知 DLL 向けに macOS 移行記録パッケージを生成する。
///
/// 標準形（PLUGIN_COMPAT_FIX_PROPOSAL.md 修正 1 / SPEC_PLUGIN_2.0M_ja-jp.md）:
/// ```text
/// ourin/macos/<name>_mac/
///   descript.txt
///   message.japanese.txt
///   message.english.txt
///   ourin.json
///   OriginalDocs/
///     ReadMe.txt
///   README.md
/// ```
///
/// 未知 DLL は自動変換できないため、実行可能な偽プラグインや固定応答を生成しない。
/// このパッケージは元資産と解析成果物を保持し、ネイティブ実装へ移行するための
/// 記録としてのみ機能する。これにより、生成物が誤って実行可能なプラグインとして
/// 発見されることを防ぐ。
///
/// 計画「注意点」に従い、元ファイルは破壊せず `ourin/` 配下にのみ生成物を置く。
enum PluginScaffolder {

    /// 移行記録パッケージ生成の結果。
    struct ScaffoldResult {
        /// `<name>_mac/` パッケージディレクトリ。
        let packageURL: URL
        /// パッケージ直下の `ourin.json` の URL。
        let manifestURL: URL
        let overwritten: Bool
    }

    /// 指定 asset に対して実行体を含まない `*_mac/` 移行記録を生成する。
    /// - Parameters:
    ///   - asset: 対象資産。
    ///   - force: 既存パッケージがあっても上書きするか。
    /// - Returns: 生成物のパス。既存かつ force=false の場合は nil。
    static func scaffold(for asset: LegacyAssetScanner.Asset, force: Bool = false) -> ScaffoldResult? {
        let fm = FileManager.default
        let macosRoot = asset.directoryURL.appendingPathComponent("ourin/macos", isDirectory: true)
        let pluginName = pluginBundleName(for: asset)
        let packageURL = macosRoot.appendingPathComponent("\(pluginName)_mac", isDirectory: true)

        let exists = fm.fileExists(atPath: packageURL.path)
        if exists && !force { return nil }

        do {
            try fm.createDirectory(at: macosRoot, withIntermediateDirectories: true)
            if exists {
                try fm.removeItem(at: packageURL)
            }
            try fm.createDirectory(at: packageURL, withIntermediateDirectories: true)
            try writeStructure(packageURL: packageURL, pluginName: pluginName, asset: asset)
        } catch {
            return nil
        }

        let manifestURL = packageURL.appendingPathComponent("ourin.json")
        return ScaffoldResult(packageURL: packageURL,
                              manifestURL: manifestURL,
                              overwritten: exists)
    }

    // MARK: - Structure

    /// `*_mac/` パッケージ全体を書き出す。
    private static func writeStructure(packageURL: URL, pluginName: String, asset: LegacyAssetScanner.Asset) throws {
        let fm = FileManager.default

        // 1. パッケージルートのメタデータファイル
        try writePackageMetadata(at: packageURL, asset: asset)

        // 2. 実行体を生成せず、移行状態をパッケージ直下に記録する。
        var manifest = OurinManifest.makeDefault(for: asset)
        manifest.mode = .unsupported
        manifest.implementation = nil
        manifest.analysis = OurinManifest.AnalysisRef(
            decompiled: "../../analysis/decompiled.c",
            report: "../../analysis/report.md"
        )
        try manifest.write(to: packageURL.appendingPathComponent("ourin.json"))

        // 3. OriginalDocs/ 既存ドキュメントのコピー
        let docsDir = packageURL.appendingPathComponent("OriginalDocs", isDirectory: true)
        try fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
        copyOriginalDocs(into: docsDir, from: asset.directoryURL)

        // 4. README.md（実装要件）
        try readme(pluginName: pluginName, asset: asset)
            .data(using: .utf8)?
            .write(to: packageURL.appendingPathComponent("README.md"))
    }

    /// パッケージルートの descript.txt / message.*.txt を配置する。
    private static func writePackageMetadata(at packageURL: URL, asset: LegacyAssetScanner.Asset) throws {
        let fm = FileManager.default
        let srcDir = asset.directoryURL

        // descript.txt: 元をコピー、無ければ生成
        let srcDescript = srcDir.appendingPathComponent("descript.txt")
        if fm.fileExists(atPath: srcDescript.path) {
            try? fm.copyItem(at: srcDescript, to: packageURL.appendingPathComponent("descript.txt"))
        } else {
            try generatedDescript(pluginName: pluginBundleName(for: asset), asset: asset)
                .data(using: .utf8)?
                .write(to: packageURL.appendingPathComponent("descript.txt"))
        }

        // install.txt は生成しない。実行体のない移行記録を SSP が
        // インストール可能なプラグインとして扱うことを防ぐ。
        let srcInstall = srcDir.appendingPathComponent("install.txt")
        if fm.fileExists(atPath: srcInstall.path) {
            let docsDir = packageURL.appendingPathComponent("OriginalDocs", isDirectory: true)
            try fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
            try? fm.copyItem(at: srcInstall, to: docsDir.appendingPathComponent("install.txt"))
        }

        // message.*.txt: 元ディレクトリにあればコピー
        if let entries = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent.lowercased().hasPrefix("message.") {
                try? fm.copyItem(at: entry, to: packageURL.appendingPathComponent(entry.lastPathComponent))
            }
        }
    }

    // MARK: - Generated content

    /// descript.txt が元資産に無い場合の最小生成物。
    private static func generatedDescript(pluginName: String, asset: LegacyAssetScanner.Asset) -> String {
        var lines: [String] = []
        lines.append("Charset,UTF-8")
        lines.append("name,\(asset.displayName.isEmpty ? pluginName : asset.displayName)")
        let sourceFilename = asset.filename.isEmpty ? pluginName : asset.filename
        lines.append("filename,\(sourceFilename)")
        if !asset.sspID.isEmpty {
            lines.append("id,\(asset.sspID)")
        } else {
            lines.append("id,\(UUID().uuidString)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// パッケージルートの README.md（ネイティブ移行要件）。
    private static func readme(pluginName: String, asset: LegacyAssetScanner.Asset) -> String {
        var lines: [String] = []
        lines.append("# \(pluginName)_mac — Native migration record")
        lines.append("")
        lines.append("このパッケージは Ourin Migrator が生成した移行記録です。")
        lines.append("未知の DLL を自動実行する実装や、固定応答のプラグインは生成していません。")
        lines.append("元の資産は変更せず、OriginalDocs/ と解析成果物への参照だけを保存します。")
        lines.append("")
        lines.append("## 実装が必要な内容")
        lines.append("")
        lines.append("- macOS のネイティブ実装を作成し、実際の PLUGIN/2.0M 契約を実装する")
        lines.append("- 必要なイベント入口と GET / NOTIFY の仕様を解析結果から確定する")
        lines.append("- 実装後に `ourin.json` の mode を `native-plugin` または `native-replacement` に更新する")
        lines.append("")
        lines.append("## 参照資料")
        lines.append("")
        lines.append("- `OriginalDocs/` に元資産のドキュメントを保存")
        lines.append("- `../../analysis/report.md` に解析レポートを保存")
        lines.append("- `../../analysis/decompiled.c` は解析結果であり、実装そのものではない")
        lines.append("")
        lines.append("## 元資産")
        lines.append("")
        lines.append("- filename: `\(asset.filename)`")
        lines.append("- binary: \(asset.binaryKind.displayName)")
        lines.append("- OriginalDocs/ に元ドキュメントをコピー済み")
        lines.append("")
        lines.append("解析詳細は `../../analysis/report.md` を参照してください。")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// 元資産ディレクトリからドキュメント類（ReadMe, license 等）を OriginalDocs/ へコピー。
    private static func copyOriginalDocs(into docsDir: URL, from srcDir: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: srcDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        let docExtensions: Set<String> = ["txt", "md", "rtf", "html", "dau"]
        let knownNonDocs: Set<String> = ["descript.txt", "install.txt", "ourin.json"]
        for entry in entries {
            let name = entry.lastPathComponent.lowercased()
            if knownNonDocs.contains(name) { continue }
            if name.hasPrefix("message.") { continue }
            let ext = entry.pathExtension.lowercased()
            if docExtensions.contains(ext) || entry.lastPathComponent.hasPrefix("ReadMe") {
                let dest = docsDir.appendingPathComponent(entry.lastPathComponent)
                try? fm.copyItem(at: entry, to: dest)
            }
        }
    }

    // MARK: - Helpers

    /// asset からプラグインバンドル名を決定する。
    /// descript の name > ディレクトリ名 > 拡張子なしバイナリ名。
    static func pluginBundleName(for asset: LegacyAssetScanner.Asset) -> String {
        if !asset.name.isEmpty {
            return sanitizedIdentifier(asset.name)
        }
        if !asset.filename.isEmpty {
            return sanitizedIdentifier((asset.filename as NSString).deletingPathExtension)
        }
        return sanitizedIdentifier(asset.directoryURL.lastPathComponent)
    }

    private static func sanitizedIdentifier(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = s.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "_" }
            .map { String($0) }
            .joined()
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let result = trimmed.isEmpty ? "plugin" : trimmed
        return result.lowercased()
    }

}
