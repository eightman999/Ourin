import Foundation

/// Phase 4: ourin.json の読み書きと、既知 DLL/EXE → builtin 実装の対応表を管理する。
///
/// 計画「ourin.json」節のフォーマット:
/// ```json
/// {
///   "format": "ourin-migration-1",
///   "source": { "filename": "...", "kind": "pe32-dll", "sspPluginId": "..." },
///   "mode": "native-replacement",
///   "implementation": "builtin:shared_value",
///   "analysis": { "decompiled": "...", "report": "..." }
/// }
/// ```
///
/// 基本方針: 既存 ourin.json の上書きは呼び出し側で確認する（本型は純粋な IO のみ）。
struct OurinManifest: Codable, Equatable, Hashable {
    static let formatVersion = "ourin-migration-1"

    enum Mode: String, Codable, CaseIterable, Hashable {
        case metadataOnly = "metadata-only"
        case nativeReplacement = "native-replacement"
        case nativePlugin = "native-plugin"
        case scaffold
        case unsupported

        var displayName: String {
            switch self {
            case .metadataOnly: return "metadata-only"
            case .nativeReplacement: return "native-replacement"
            case .nativePlugin: return "native-plugin"
            case .scaffold: return "scaffold"
            case .unsupported: return "unsupported"
            }
        }

        var recommendation: String {
            switch self {
            case .metadataOnly:
                return "DLL/EXE は実行せず、SSP メタデータだけ利用する"
            case .nativeReplacement:
                return "Ourin builtin 実装へ差し替える"
            case .nativePlugin:
                return "macOS .plugin/.bundle を利用する"
            case .scaffold:
                return "雛形生成済み、実装待ち"
            case .unsupported:
                return "現時点では未対応"
            }
        }
    }

    struct Source: Codable, Equatable, Hashable {
        let filename: String
        /// "pe32-dll" / "pe32+ dll" / "pe32-exe" / "pe32+ exe" / "unknown"
        let kind: String
        let sspPluginId: String?

        init(filename: String, kind: String, sspPluginId: String?) {
            self.filename = filename
            self.kind = kind
            self.sspPluginId = sspPluginId
        }
    }

    struct AnalysisRef: Codable, Equatable, Hashable {
        let decompiled: String?
        let report: String?

        init(decompiled: String?, report: String?) {
            self.decompiled = decompiled
            self.report = report
        }
    }

    let format: String
    let source: Source
    var mode: Mode
    var implementation: String?
    var analysis: AnalysisRef?

    init(source: Source, mode: Mode, implementation: String? = nil, analysis: AnalysisRef? = nil) {
        self.format = OurinManifest.formatVersion
        self.source = source
        self.mode = mode
        self.implementation = implementation
        self.analysis = analysis
    }

    // MARK: - IO

    /// ourin.json を読み込む。存在しない・壊れている場合は nil。
    static func read(from url: URL) -> OurinManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(OurinManifest.self, from: data)
    }

    /// ourin.json を書き込む。インデント済み UTF-8。
    /// 既存ファイルの上書き確認は呼び出し側で行うこと（計画「注意点」）。
    @discardableResult
    func write(to url: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
        return url
    }

    // MARK: - 既知 DLL/EXE → builtin 対応表

    /// 計画「既知 DLL/EXE の builtin 置換候補」節に基づく対応表。
    /// ファイル名（小文字） → builtin 実装名。
    static let knownBuiltinMap: [String: String] = [
        "shared_value.dll": "builtin:shared_value",
        "saknife.dll": "builtin:saknife",
        "schedule.dll": "builtin:calendar_schedule",
        "ssph.exe": "builtin:ssph_compat",
        "mcp.exe": "builtin:mcp_compat"
    ]

    /// 既知 DLL なら builtin 実装名を返す。
    static func builtinImplementation(for filename: String) -> String? {
        knownBuiltinMap[filename.lowercased()]
    }

    /// 既知 DLL かどうか。
    static func isKnownBuiltin(_ filename: String) -> Bool {
        knownBuiltinMap[filename.lowercased()] != nil
    }

    /// 既知 DLL の場合は native-replacement + builtin 実装名を、
    /// 未知の場合は scaffold を提案する。
    static func recommendedMode(for filename: String) -> (Mode, String?) {
        if let impl = builtinImplementation(for: filename) {
            return (.nativeReplacement, impl)
        }
        return (.scaffold, nil)
    }

    /// Asset から ourin.json を新規生成する。
    /// 既知 DLL は builtin を自動提案し、未知は scaffold とする。
    static func makeDefault(for asset: LegacyAssetScanner.Asset) -> OurinManifest {
        let kind = sourceKindString(binaryKind: asset.binaryKind, filename: asset.filename)
        let source = Source(
            filename: asset.filename,
            kind: kind,
            sspPluginId: asset.sspID.isEmpty ? nil : asset.sspID
        )
        let (mode, impl) = recommendedMode(for: asset.filename)
        return OurinManifest(source: source, mode: mode, implementation: impl)
    }

    /// BinaryKind + 拡張子 → ourin.json の source.kind 文字列。
    private static func sourceKindString(binaryKind: LegacyAssetScanner.BinaryKind, filename: String) -> String {
        let arch: String
        switch binaryKind {
        case .pe32: arch = "pe32"
        case .pe32Plus: arch = "pe32+"
        case .unknown: return "unknown"
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        let type = ext == "exe" ? "exe" : "dll"
        return "\(arch)-\(type)"
    }
}
