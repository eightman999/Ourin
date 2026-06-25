import Foundation

/// Phase 5: 未知 DLL 向けに macOS plugin 雛形パッケージを生成する。
///
/// 標準形（PLUGIN_COMPAT_FIX_PROPOSAL.md 修正 1 / SPEC_PLUGIN_2.0M_ja-jp.md）:
/// ```text
/// ourin/macos/<name>_mac/
///   install.txt
///   descript.txt
///   message.japanese.txt
///   message.english.txt
///   <name>.plugin/
///     Contents/
///       Info.plist
///       MacOS/<name>
///       Resources/
///         descript.txt
///         ourin.json
///   Sources/
///     <name>Plugin.c
///   OriginalDocs/
///     ReadMe.txt
/// ```
///
/// 責務分離: Ourin ホスト側が install.txt/descript.txt/message.*.txt を解釈し、
/// `.plugin` bundle は DLL の load/loadu/request/unload 互換に集中する。
///
/// 計画「注意点」に従い、元ファイルは破壊せず `ourin/` 配下にのみ生成物を置く。
enum PluginScaffolder {

    /// 雛形生成の結果。
    struct ScaffoldResult {
        /// `<name>_mac/` パッケージディレクトリ。
        let packageURL: URL
        /// `<name>.plugin` バンドルの URL。
        let pluginURL: URL
        /// `.plugin/Contents/Resources/ourin.json` の URL。
        let manifestURL: URL
        let overwritten: Bool
    }

    /// 指定 asset に対して `*_mac/` パッケージ雛形を生成する。
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

        let pluginURL = packageURL.appendingPathComponent("\(pluginName).plugin", isDirectory: true)
        let manifestURL = pluginURL.appendingPathComponent("Contents/Resources/ourin.json")
        return ScaffoldResult(packageURL: packageURL,
                              pluginURL: pluginURL,
                              manifestURL: manifestURL,
                              overwritten: exists)
    }

    // MARK: - Structure

    /// `*_mac/` パッケージ全体を書き出す。
    private static func writeStructure(packageURL: URL, pluginName: String, asset: LegacyAssetScanner.Asset) throws {
        let fm = FileManager.default

        // 1. パッケージルートのメタデータファイル
        try writePackageMetadata(at: packageURL, asset: asset)

        // 2. .plugin バンドル
        let pluginURL = packageURL.appendingPathComponent("\(pluginName).plugin", isDirectory: true)
        try writePluginBundle(at: pluginURL, pluginName: pluginName, asset: asset)

        // 3. Sources/ プレースホルダ
        let sourcesDir = packageURL.appendingPathComponent("Sources", isDirectory: true)
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try sourcePlaceholder(pluginName: pluginName, asset: asset)
            .data(using: .utf8)?
            .write(to: sourcesDir.appendingPathComponent("\(pluginName)Plugin.c"))

        // 4. OriginalDocs/ 既存ドキュメントのコピー
        let docsDir = packageURL.appendingPathComponent("OriginalDocs", isDirectory: true)
        try fm.createDirectory(at: docsDir, withIntermediateDirectories: true)
        copyOriginalDocs(into: docsDir, from: asset.directoryURL)

        // 5. README.md（実装 TODO）
        try readme(pluginName: pluginName, asset: asset)
            .data(using: .utf8)?
            .write(to: packageURL.appendingPathComponent("README.md"))
    }

    /// パッケージルートの descript.txt / install.txt / message.*.txt を配置する。
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

        // install.txt: 元をコピー、無ければ生成
        let srcInstall = srcDir.appendingPathComponent("install.txt")
        if fm.fileExists(atPath: srcInstall.path) {
            try? fm.copyItem(at: srcInstall, to: packageURL.appendingPathComponent("install.txt"))
        } else {
            try "type,plugin\ndirectory,\(pluginBundleName(for: asset))\n"
                .data(using: .utf8)?
                .write(to: packageURL.appendingPathComponent("install.txt"))
        }

        // message.*.txt: 元ディレクトリにあればコピー
        if let entries = try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for entry in entries where entry.lastPathComponent.lowercased().hasPrefix("message.") {
                try? fm.copyItem(at: entry, to: packageURL.appendingPathComponent(entry.lastPathComponent))
            }
        }
    }

    /// `.plugin` バンドルの中身を書き出す。
    private static func writePluginBundle(at pluginURL: URL, pluginName: String, asset: LegacyAssetScanner.Asset) throws {
        let fm = FileManager.default
        let contents = pluginURL.appendingPathComponent("Contents", isDirectory: true)
        let macosDir = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesDir = contents.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macosDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        // Info.plist
        try infoPlist(pluginName: pluginName, asset: asset)
            .data(using: .utf8)?
            .write(to: contents.appendingPathComponent("Info.plist"))

        // 実行ファイル placeholder
        let execURL = macosDir.appendingPathComponent(pluginName)
        let placeholder = "#!/bin/sh\n# Ourin plugin scaffold placeholder. Replace with native implementation.\nexit 0\n"
        try placeholder.data(using: .utf8)?.write(to: execURL)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)

        // Resources/descript.txt
        let srcDescript = asset.directoryURL.appendingPathComponent("descript.txt")
        if fm.fileExists(atPath: srcDescript.path) {
            try? fm.copyItem(at: srcDescript, to: resourcesDir.appendingPathComponent("descript.txt"))
        } else {
            try generatedDescript(pluginName: pluginName, asset: asset)
                .data(using: .utf8)?
                .write(to: resourcesDir.appendingPathComponent("descript.txt"))
        }

        // Resources/ourin.json
        let manifest = OurinManifest.makeDefault(for: asset)
        var manifestCopy = manifest
        manifestCopy.mode = .scaffold
        manifestCopy.implementation = "plugin:\(pluginName)"
        manifestCopy.analysis = OurinManifest.AnalysisRef(
            decompiled: "ourin/analysis/decompiled.c",
            report: "ourin/analysis/report.md"
        )
        try manifestCopy.write(to: resourcesDir.appendingPathComponent("ourin.json"))
    }

    // MARK: - Generated content

    /// descript.txt が元資産に無い場合の最小生成物。
    private static func generatedDescript(pluginName: String, asset: LegacyAssetScanner.Asset) -> String {
        var lines: [String] = []
        lines.append("Charset,UTF-8")
        lines.append("name,\(asset.displayName.isEmpty ? pluginName : asset.displayName)")
        lines.append("filename,\(pluginName).plugin")
        if !asset.sspID.isEmpty {
            lines.append("id,\(asset.sspID)")
        } else {
            lines.append("id,\(UUID().uuidString)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Info.plist の中身（XML 形式）。
    private static func infoPlist(pluginName: String, asset: LegacyAssetScanner.Asset) -> String {
        let bundleID = "jp.ourin.plugin.\(sanitizedIdentifier(pluginName))"
        let displayName = asset.displayName.isEmpty ? pluginName : asset.displayName
        let sspID = asset.sspID
        var plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleExecutable</key>
            <string>\(pluginName)</string>
            <key>CFBundleIdentifier</key>
            <string>\(bundleID)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(escapeXML(displayName))</string>
            <key>CFBundleDisplayName</key>
            <string>\(escapeXML(displayName))</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>CFBundleShortVersionString</key>
            <string>0.1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>NSPrincipalClass</key>
            <string></string>
            <key>OurinPluginKind</key>
            <string>\(asset.kind.rawValue)</string>
        """
        if !sspID.isEmpty {
            plist += """
                <key>SSPPluginID</key>
                <string>\(escapeXML(sspID))</string>
            """
        }
        plist += """
        </dict>
        </plist>
        """
        return plist
    }

    /// Sources/<name>Plugin.c プレースホルダ。
    /// PLUGIN/2.0M の load/loadu/request/unload/unloadu エントリを模擬。
    private static func sourcePlaceholder(pluginName: String, asset: LegacyAssetScanner.Asset) -> String {
        let sspID = asset.sspID.isEmpty ? "TODO" : asset.sspID
        return """
        // \(pluginName)Plugin.c — Ourin Migrator 生成プレースホルダ
        // PLUGIN/2.0M 互換エントリポイントを実装してください。
        // 疑似 C は ourin/analysis/decompiled.c を参照。

        #include <stdint.h>
        #include <string.h>

        // SSP plugin ID: \(sspID)

        // int32_t load(const char* path) / loadu(const char* path)
        int32_t loadu(const char* path) {
            // TODO: 初期化処理
            (void)path;
            return 1;
        }

        // const uint8_t* request(const uint8_t* in, int64_t in_len, int64_t* out_len)
        const uint8_t* request(const uint8_t* in, int64_t in_len, int64_t* out_len) {
            // TODO: PLUGIN/2.0M リクエスト処理
            static const char resp[] = "PLUGIN/2.0M 200 OK\\r\\n\\r\\n";
            (void)in; (void)in_len;
            *out_len = (int64_t)strlen(resp);
            return (const uint8_t*)resp;
        }

        // void unload() / unloadu()
        void unloadu(void) {
            // TODO: 終了処理
        }
        """;
    }

    /// パッケージルートの README.md（実装 TODO）。
    private static func readme(pluginName: String, asset: LegacyAssetScanner.Asset) -> String {
        var lines: [String] = []
        lines.append("# \(pluginName)_mac — Implementation TODO")
        lines.append("")
        lines.append("このパッケージは Ourin Migrator が生成した雛形です。")
        lines.append("責務分離: Ourin ホスト側が descript.txt / message.*.txt を解釈し、")
        lines.append("`.plugin` バンドルは load/request/unload 互換に集中します。")
        lines.append("")
        lines.append("## 必須イベント入口（PLUGIN/2.0M 相当）")
        lines.append("")
        for ev in ["OnBoot", "OnSecondChange", "OnMinuteChange", "OnGhostChanged"] {
            lines.append("- [ ] \(ev)")
        }
        lines.append("- [ ] GET / NOTIFY placeholder")
        lines.append("")
        lines.append("## 実装手順")
        lines.append("")
        lines.append("1. `Sources/\(pluginName)Plugin.c` を本体実装へ置き換える")
        lines.append("2. `descript.txt` の `filename` を実バンドル名に合わせる")
        lines.append("3. `message.*.txt` でメニュー文言を調整する")
        lines.append("")
        lines.append("## 元資産")
        lines.append("")
        lines.append("- filename: `\(asset.filename)`")
        lines.append("- binary: \(asset.binaryKind.displayName)")
        lines.append("- OriginalDocs/ に元ドキュメントをコピー済み")
        lines.append("")
        lines.append("解析詳細は `ourin/analysis/report.md` を参照してください。")
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

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
