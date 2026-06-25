import Foundation

/// Phase 1: SSP 互換資産フォルダを走査し、DLL/EXE/descript.txt/ourin.json を検出・分類する。
///
/// 基本方針（OURIN_MIGRATOR_PLAN.md "基本方針" 参照）:
/// - DLL/EXE は読み取り対象として扱い、実行はしない
/// - 元の SSP ファイル構造は破壊しない（読み取り専用）
/// - `ourin.json` の有無と `ourin/analysis/` の有無で status を決定する
enum LegacyAssetScanner {
    /// 資産の種別。スキャン元ディレクトリの役割で決まる。
    enum AssetKind: String, Codable {
        case plugin
        case calendarPlugin = "calendar-plugin"
        case headline
        case tool
        case unknown

        init(scanRootKind: ScanRootKind) {
            switch scanRootKind {
            case .plugin: self = .plugin
            case .calendarPlugin: self = .calendarPlugin
            case .headline: self = .headline
            case .data: self = .tool
            }
        }
    }

    /// PE バイナリの種別。`file(1)` 相当の先頭バイト判定で分類する。
    enum BinaryKind: String, Codable {
        case pe32       // 32bit PE (Intel 80386)
        case pe32Plus   // 64bit PE (x86_64)
        case unknown

        var displayName: String {
            switch self {
            case .pe32: return "PE32"
            case .pe32Plus: return "PE32+"
            case .unknown: return "unknown"
            }
        }
    }

    /// 移行状態。UI の Status 列に対応する。
    enum MigrationStatus: String, Codable {
        case metadataOnly = "metadata-only"
        case analyzed
        case mapped
        case scaffolded

        var displayName: String {
            switch self {
            case .metadataOnly: return "metadata-only"
            case .analyzed: return "analyzed"
            case .mapped: return "mapped"
            case .scaffolded: return "scaffolded"
            }
        }
    }

    /// スキャン起点の種別。
    enum ScanRootKind {
        case plugin
        case calendarPlugin
        case headline
        case data

        var subfolderName: String {
            switch self {
            case .plugin: return "plugin"
            case .calendarPlugin: return "calendar/plugin"
            case .headline: return "headline"
            case .data: return "data"
            }
        }
    }

    /// 検出された 1 件の資産。バイナリ 1 つ（またはメタデータのみ）に対応する。
    struct Asset: Identifiable, Hashable {
        /// 安定 ID。ディレクトリパスの相対表現から生成。
        let id: String
        let name: String
        let kind: AssetKind
        let binaryKind: BinaryKind
        /// バイナリのファイル名。メタデータのみの場合は空文字列。
        let filename: String
        /// バイナリの絶対パス。メタデータのみの場合は nil。
        let binaryURL: URL?
        /// 資産ディレクトリ（descript.txt と並ぶ場所）。
        let directoryURL: URL
        /// descript.txt の内容（UTF-8/Shift_JIS 自動判定）。
        let descriptor: [String: String]
        /// 既存 ourin.json の内容（あれば）。UI で再読込後に更新するため var。
        var existingManifest: OurinManifest?
        /// 推定移行状態。
        var status: MigrationStatus

        var displayName: String {
            if !name.isEmpty { return name }
            if !filename.isEmpty { return filename }
            return directoryURL.lastPathComponent
        }

        var sspID: String { descriptor["id"] ?? "" }
    }

    /// 既定のスキャン対象ディレクトリを返す。
    /// 計画「対象ディレクトリ」節に基づき plugin/calendar/plugin/headline/data を対象とする。
    static func defaultScanRoots(baseDirectory: URL) -> [(URL, ScanRootKind)] {
        return [ScanRootKind.plugin, .calendarPlugin, .headline, .data].map { kind in
            (baseDirectory.appendingPathComponent(kind.subfolderName, isDirectory: true), kind)
        }
    }

    /// 複数起点を走査して Asset の一覧を返す。
    /// 読み取り専用で、元フォルダ構造は変更しない。
    static func scan(roots: [(URL, ScanRootKind)]) -> [Asset] {
        var results: [Asset] = []
        for (root, kind) in roots {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            results.append(contentsOf: scanDirectory(root, kind: kind))
        }
        return results.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// 単一起点を走査する。
    ///
    /// plugin/, calendar/plugin/ は「1 フォルダ = 1 プラグイン」構造を想定し、
    /// 各サブフォルダの descript.txt と DLL/EXE を対応付ける。
    /// headline/ も同様（1 フォルダ = 1 ヘッドライン）。
    /// data/ はフラットに DLL/EXE を拾う（SSPH.exe, mcp.exe 等のツール類）。
    private static func scanDirectory(_ root: URL, kind: ScanRootKind) -> [Asset] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var assets: [Asset] = []
        let assetKind = AssetKind(scanRootKind: kind)

        for entry in entries {
            if isDirectory(entry) {
                // 1 フォルダ構成（plugin/calendar/headline 系）
                if let asset = makeAssetFromDirectory(entry, kind: assetKind) {
                    assets.append(asset)
                }
            } else if kind == .data, isBinaryFile(entry.pathExtension) {
                // data/ 直下の DLL/EXE（ツール類）。descript.txt 無し。
                if let asset = makeAssetFromBinaryFile(entry, kind: assetKind) {
                    assets.append(asset)
                }
            }
        }
        return assets
    }

    /// 1 フォルダ（descript.txt + DLL/EXE 構成）から Asset を生成する。
    /// descript.txt が無くても DLL/EXE があれば unknown として登録する。
    private static func makeAssetFromDirectory(_ dir: URL, kind: AssetKind) -> Asset? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let descriptorURL = dir.appendingPathComponent("descript.txt")
        let descriptor = LegacyDescriptor.readDictionary(from: descriptorURL) ?? [:]

        // descript.txt の filename/dllname からバイナリを特定する。
        // 無ければフォルダ内の .dll/.exe を拾う。
        var binaryURL: URL?
        if let declared = (descriptor["filename"] ?? descriptor["dllname"]), !declared.isEmpty {
            let candidate = dir.appendingPathComponent(declared)
            if fm.fileExists(atPath: candidate.path) {
                binaryURL = candidate
            }
        }
        if binaryURL == nil {
            binaryURL = entries.first { isBinaryFile($0.pathExtension) }
        }

        let filename = binaryURL?.lastPathComponent ?? ""
        let binaryKind: BinaryKind = binaryURL.map { classifyBinary(at: $0) } ?? .unknown
        let manifest = OurinManifest.read(from: dir.appendingPathComponent("ourin.json"))
        let status = resolveStatus(directoryURL: dir, hasManifest: manifest != nil, manifestMode: manifest?.mode)

        return Asset(
            id: relativeID(for: dir, filename: filename),
            name: descriptor["name"] ?? dir.lastPathComponent,
            kind: kind,
            binaryKind: binaryKind,
            filename: filename,
            binaryURL: binaryURL,
            directoryURL: dir,
            descriptor: descriptor,
            existingManifest: manifest,
            status: status
        )
    }

    /// descript.txt を持たない data/ 直下のツール系バイナリから Asset を生成する。
    private static func makeAssetFromBinaryFile(_ url: URL, kind: AssetKind) -> Asset? {
        let dir = url.deletingLastPathComponent()
        let binaryKind = classifyBinary(at: url)
        let manifest = OurinManifest.read(from: dir.appendingPathComponent("ourin.json"))
        let status = resolveStatus(directoryURL: dir, hasManifest: manifest != nil, manifestMode: manifest?.mode)
        return Asset(
            id: relativeID(for: url, filename: url.lastPathComponent),
            name: url.deletingPathExtension().lastPathComponent,
            kind: kind,
            binaryKind: binaryKind,
            filename: url.lastPathComponent,
            binaryURL: url,
            directoryURL: dir,
            descriptor: [:],
            existingManifest: manifest,
            status: status
        )
    }

    /// バイナリ種別を PE ヘッダから判定する。
    /// PE 以外や判別不能は .unknown。
    /// 参考: MZ ヘッダ → PE\0\0 → COFF Machine フィールド。
    static func classifyBinary(at url: URL) -> BinaryKind {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
        defer { try? handle.close() }

        // MZ ヘッダ
        guard let mz = try? handle.read(upToCount: 2), mz.count == 2,
              mz[0] == 0x4D, mz[1] == 0x5A else { return .unknown }

        // e_lfanew (PE ヘッダオフセット) @ 0x3C
        try? handle.seek(toOffset: 0x3C)
        guard let lfanewData = try? handle.read(upToCount: 4), lfanewData.count == 4 else { return .unknown }
        let lfanew = lfanewData.withUnsafeBytes { $0.load(as: UInt32.self) }

        // PE\0\0
        try? handle.seek(toOffset: numericCast(lfanew))
        guard let peSig = try? handle.read(upToCount: 4), peSig.count == 4,
              peSig[0] == 0x50, peSig[1] == 0x45, peSig[2] == 0, peSig[3] == 0 else { return .unknown }

        // COFF Machine (2 bytes)
        guard let machineData = try? handle.read(upToCount: 2), machineData.count == 2 else { return .unknown }
        let machine = machineData.withUnsafeBytes { $0.load(as: UInt16.self) }

        // Optional Header Magic で 32/64 を判別（より確実）。
        // PE32 = 0x10B, PE32+ = 0x20B。
        // Optional Header は COFF Header (20 bytes) の直後。
        try? handle.seek(toOffset: numericCast(lfanew) + 24)
        if let magicData = try? handle.read(upToCount: 2), magicData.count == 2 {
            let magic = magicData.withUnsafeBytes { $0.load(as: UInt16.self) }
            if magic == 0x20B { return .pe32Plus }
            if magic == 0x10B { return .pe32 }
        }
        // フォールバック: Machine フィールドから推定。
        switch machine {
        case 0x014C: return .pe32   // IMAGE_FILE_MACHINE_I386
        case 0x8664: return .pe32Plus // IMAGE_FILE_MACHINE_AMD64
        default: return .unknown
        }
    }

    /// 安定した一意 ID を生成（パス + ファイル名）。
    private static func relativeID(for url: URL, filename: String) -> String {
        let path = url.standardizedFileURL.path
        return filename.isEmpty ? path : "\(path)/\(filename)"
    }

    /// 移行状態を推定する。
    /// - ourin/analysis/report.md が在れば analyzed 以上
    /// - ourin.json の mode が native-replacement/native-plugin なら mapped
    /// - scaffold なら scaffolded
    /// - それ以外は metadata-only
    private static func resolveStatus(directoryURL: URL, hasManifest: Bool, manifestMode: OurinManifest.Mode?) -> MigrationStatus {
        let reportExists = FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("ourin/analysis/report.md").path
        )
        if let mode = manifestMode {
            switch mode {
            case .nativeReplacement, .nativePlugin: return reportExists ? .mapped : .mapped
            case .scaffold: return .scaffolded
            default: break
            }
        }
        if reportExists { return .analyzed }
        return .metadataOnly
    }

    private static func isBinaryFile(_ ext: String) -> Bool {
        let lower = ext.lowercased()
        return lower == "dll" || lower == "exe"
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
