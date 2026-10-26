import Foundation

/// Windows の `*.dll` 名を、明示的に対応する macOS 同梱エンジンへ解決する。
enum BundledShioriEngine: String, CaseIterable {
    case kawari
    case kagari
    case akari
    case eseShiori
    case niseShiori
    case shino
    case hisui
    case yuhna
    case misaka
    /// Optional personal build only; never embedded by engines/package.sh.
    case aosora

    /// 上流ビルド成果物の候補名（Frameworks または検証用 override から探す）。
    var artifactNames: [String] {
        switch self {
        case .kawari:
            return ["libkawari_shiori.dylib", "libshiori.dylib", "shiori.dylib", "kawari.dylib"]
        case .kagari:
            return ["libkagari.dylib", "kagari.dylib", "libkagari.so"]
        case .akari: return ["libakari.dylib"]
        case .eseShiori: return ["libese-shiori.dylib"]
        case .niseShiori: return ["libniseshiori.dylib"]
        case .shino: return ["libshino.dylib"]
        case .hisui: return ["libhisui.dylib"]
        case .yuhna: return ["libyuhna.dylib"]
        case .misaka: return ["libmisaka.dylib"]
        case .aosora: return ["libaosora.dylib"]
        }
    }

    /// 同梱モジュールに付与する `OurinShioriABI`（ビルドスクリプトが plist に書き込む）。
    var shioriABI: String {
        switch self {
        case .kawari: return "ukagaka-long"
        case .kagari: return "kagari"
        case .aosora: return "aosora"
        case .akari, .eseShiori, .niseShiori, .shino, .hisui, .yuhna, .misaka: return "ukagaka-int32"
        }
    }

    private var environmentOverrideKey: String {
        switch self {
        case .kawari: return "OURIN_KAWARI_ENGINE"
        case .kagari: return "OURIN_KAGARI_ENGINE"
        case .akari: return "OURIN_AKARI_ENGINE"
        case .eseShiori: return "OURIN_ESE_SHIORI_ENGINE"
        case .niseShiori: return "OURIN_NISE_SHIORI_ENGINE"
        case .shino: return "OURIN_SHINO_ENGINE"
        case .hisui: return "OURIN_HISUI_ENGINE"
        case .yuhna: return "OURIN_YUHNA_ENGINE"
        case .misaka: return "OURIN_MISAKA_ENGINE"
        case .aosora: return "OURIN_AOSORA_ENGINE"
        }
    }

    /// ゴースト同梱の macOS モジュールを優先し、無いときだけ同梱エンジンへフォールバックする。
    static func resolveModuleURL(moduleName: String, ghostURL: URL, ghostRoot: URL) -> URL? {
        let paths = ShioriLoader.searchPaths(base: ghostURL)
        if let local = ShioriLoader.find(name: moduleName, in: paths) { return local }
        guard let engine = recognize(moduleName: moduleName, ghostRoot: ghostRoot) else { return nil }
        return bundledURL(for: engine)
    }

    static func recognize(moduleName: String, ghostRoot: URL) -> BundledShioriEngine? {
        let normalized = moduleName.replacingOccurrences(of: "\\", with: "/")
        let stem = URL(fileURLWithPath: normalized).deletingPathExtension().lastPathComponent.lowercased()
        let bare = stem.hasPrefix("lib") ? String(stem.dropFirst(3)) : stem
        switch bare {
        case "kawari", "kosui":
            return .kawari
        case "kagari":
            return .kagari
        case "akari": return .akari
        case "ese-shiori": return .eseShiori
        case "niseshiori", "nise-shiori": return .niseShiori
        case "shino": return .shino
        case "hisui": return .hisui
        case "yuhna": return .yuhna
        case "misaka": return .misaka
        case "aosora": return .aosora
        case "shiori":
            return isKawariDictionaryRoot(dictionaryDirectory(moduleName: moduleName, ghostRoot: ghostRoot)) ? .kawari : nil
        default:
            return nil
        }
    }

    static func bundledURL(for engine: BundledShioriEngine) -> URL? {
        if let override = ProcessInfo.processInfo.environment[engine.environmentOverrideKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Source-derived Aosora requires separate redistribution permission.
        guard engine != .aosora else { return nil }
        let fm = FileManager.default
        for directory in bundledSearchDirectories() {
            for name in engine.artifactNames {
                if let url = UkagakaModuleABI.resolveCaseInsensitive(name, in: directory, fileManager: fm) {
                    return url
                }
            }
        }
        return nil
    }

    private static func dictionaryDirectory(moduleName: String, ghostRoot: URL) -> URL {
        ghostRoot.appendingPathComponent(moduleName.replacingOccurrences(of: "\\", with: "/")).deletingLastPathComponent()
    }

    private static func isKawariDictionaryRoot(_ directory: URL) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return false }
        let markers = ["kawarirc.ini", "kawarirc.kis", "KAWARIRC.INI", "KAWARIRC.KIS"]
        return entries.contains { entry in
            markers.contains { entry.lastPathComponent.caseInsensitiveCompare($0) == .orderedSame }
        }
    }

    private static func bundledSearchDirectories() -> [URL] {
        var directories: [URL] = []
        if let frameworks = Bundle.main.executableURL?
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Frameworks") {
            directories.append(frameworks)
        }
        if let engines = Bundle.main.resourceURL?.appendingPathComponent("Engines", isDirectory: true) {
            directories.append(engines)
        }
        if let auxiliary = Bundle.main.privateFrameworksURL {
            directories.append(auxiliary)
        }
        return directories
    }
}
