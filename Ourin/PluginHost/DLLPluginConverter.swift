import Foundation

/// Windows の PE 形式 DLL のヘッダを読み、CPU 種別・エクスポート・インポート DLL を取り出す。
///
/// 伺かのモジュール DLL は x86 / x64 の Windows コードで、macOS では実行できない。
/// ここでは実行せず、変換可否の判定と診断に必要な情報だけを読む。
struct PEImageInfo: Equatable {
    enum Machine: String {
        case x86, x64, arm64, unknown

        init(rawMachine: UInt16) {
            switch rawMachine {
            case 0x014C: self = .x86
            case 0x8664: self = .x64
            case 0xAA64: self = .arm64
            default: self = .unknown
            }
        }
    }

    let machine: Machine
    let exports: [String]
    let imports: [String]
    /// 本体に埋め込まれたエンジン名（改名された yaya.dll 等の判定用）。
    let embeddedEngine: PluginEngineKind?

    /// 伺かモジュール共通の ABI（`load` / `unload` / `request`）を備えるか。
    var exportsUkagakaModuleABI: Bool {
        let names = Set(exports.map { $0.lowercased() })
        return names.contains("request") && (names.contains("load") || names.contains("loadu"))
    }

    static func read(from url: URL) -> PEImageInfo? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> PEImageInfo? {
        let bytes = [UInt8](data)
        func u16(_ offset: Int) -> UInt16? {
            guard offset >= 0, offset + 2 <= bytes.count else { return nil }
            return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        }
        func u32(_ offset: Int) -> UInt32? {
            guard let lo = u16(offset), let hi = u16(offset + 2) else { return nil }
            return UInt32(lo) | UInt32(hi) << 16
        }
        func cString(_ offset: Int) -> String? {
            guard offset >= 0, offset < bytes.count else { return nil }
            guard let end = bytes[offset...].firstIndex(of: 0) else { return nil }
            return String(bytes: bytes[offset..<end], encoding: .ascii)
        }

        guard bytes.count >= 0x40, bytes[0] == 0x4D, bytes[1] == 0x5A,
              let peOffset = u32(0x3C).map(Int.init),
              u32(peOffset) == 0x0000_4550,
              let rawMachine = u16(peOffset + 4),
              let sectionCount = u16(peOffset + 6).map(Int.init),
              let optionalSize = u16(peOffset + 20).map(Int.init) else { return nil }
        let optional = peOffset + 24
        guard let magic = u16(optional) else { return nil }
        let directories: Int
        switch magic {
        case 0x10B: directories = optional + 96
        case 0x20B: directories = optional + 112
        default: return nil
        }

        struct Section { let virtualAddress: Int; let virtualSize: Int; let rawPointer: Int; let rawSize: Int }
        var sections: [Section] = []
        let sectionTable = optional + optionalSize
        for index in 0..<sectionCount {
            let base = sectionTable + index * 40
            guard let vsize = u32(base + 8), let vaddr = u32(base + 12),
                  let rsize = u32(base + 16), let rptr = u32(base + 20) else { break }
            sections.append(Section(virtualAddress: Int(vaddr), virtualSize: Int(max(vsize, rsize)),
                                    rawPointer: Int(rptr), rawSize: Int(rsize)))
        }
        func fileOffset(_ rva: UInt32) -> Int? {
            let rva = Int(rva)
            for section in sections where rva >= section.virtualAddress && rva < section.virtualAddress + section.virtualSize {
                let delta = rva - section.virtualAddress
                guard delta < section.rawSize else { return nil }
                return section.rawPointer + delta
            }
            return nil
        }

        var exports: [String] = []
        if let exportRVA = u32(directories), exportRVA != 0, let exportDir = fileOffset(exportRVA),
           let nameCount = u32(exportDir + 24), let namesRVA = u32(exportDir + 32),
           let names = fileOffset(namesRVA) {
            for index in 0..<Int(min(nameCount, 4096)) {
                guard let nameRVA = u32(names + index * 4), let offset = fileOffset(nameRVA),
                      let name = cString(offset) else { break }
                exports.append(name)
            }
        }

        var imports: [String] = []
        if let importRVA = u32(directories + 8), importRVA != 0, var descriptor = fileOffset(importRVA) {
            while imports.count < 512, let nameRVA = u32(descriptor + 12), nameRVA != 0 {
                if let offset = fileOffset(nameRVA), let name = cString(offset) {
                    imports.append(name)
                }
                descriptor += 20
            }
        }

        return PEImageInfo(
            machine: Machine(rawMachine: rawMachine),
            exports: exports,
            imports: imports,
            embeddedEngine: embeddedEngine(in: data)
        )
    }

    /// 本体に残るエンジン固有の文字列で判定する（ファイル名だけに頼らない）。
    private static func embeddedEngine(in data: Data) -> PluginEngineKind? {
        let markers: [(PluginEngineKind, String)] = [
            (.yaya, "YAYA"),
            (.kagari, "KAGARI"),
            (.kagari, "kagari")
        ]
        for (kind, marker) in markers where data.range(of: Data(marker.utf8)) != nil {
            return kind
        }
        return nil
    }
}

/// SSP 形式のプラグインフォルダ（descript.txt + Windows DLL）を、Ourin が読み込める `.plugin` バンドルへ変換する。
///
/// - 本体 DLL が汎用エンジン（YAYA / KAGARI）なら、DLL の隣に `<DLL名>.plugin` を作り、
///   Info.plist の `OurinPluginEngine` で内蔵エンジンを指定する。処理は同梱の辞書・スクリプトがそのまま担う。
/// - 独自のネイティブコード DLL は機械語の変換ができないため変換しない。結果に CPU 種別・エクスポート・
///   インポート DLL を残し、macOS 向けに作り直したモジュール（`.dylib` / `.plugin`）を置けば読み込まれる。
///
/// 元の DLL・descript.txt・辞書には手を加えない。
enum DLLPluginConverter {
    static let formatVersion = 1
    static let engineKey = "OurinPluginEngine"
    static let originalModuleKey = "OurinOriginalModule"

    enum Outcome: Equatable {
        /// 内蔵エンジンで動く `.plugin` を作成した（または作成済みで最新）。
        case converted(bundleURL: URL, engine: PluginEngineKind)
        /// macOS 向けモジュールが既にある。
        case nativeModuleExists(URL)
        /// ネイティブコードの DLL で、内蔵エンジンへ置き換えられない。
        case unsupported(reason: String)
    }

    struct Report: Equatable {
        let pluginDirectory: URL
        let moduleName: String
        let image: PEImageInfo?
        let outcome: Outcome
    }

    /// プラグインフォルダを調べ、必要なら `.plugin` を作る。
    @discardableResult
    static func convert(pluginDirectory: URL, fileManager: FileManager = .default) -> Report? {
        guard let descript = LegacyDescriptor.readDictionary(from: pluginDirectory.appendingPathComponent("descript.txt")),
              let moduleName = (descript["filename"] ?? descript["dllname"])?.trimmingCharacters(in: .whitespaces),
              !moduleName.isEmpty else { return nil }

        let relative = moduleName.replacingOccurrences(of: "\\", with: "/")
        let moduleURL = UkagakaModuleABI.resolveCaseInsensitive(relative, in: pluginDirectory)
            ?? pluginDirectory.appendingPathComponent(relative)
        let image = PEImageInfo.read(from: moduleURL)

        for candidate in UkagakaModuleABI.nativeModuleCandidates(forDLLName: moduleName) {
            guard let url = UkagakaModuleABI.resolveCaseInsensitive(candidate, in: pluginDirectory),
                  !UkagakaModuleABI.isWindowsPortableExecutable(at: url) else { continue }
            if let engine = engineKind(ofBundleAt: url) {
                return Report(pluginDirectory: pluginDirectory, moduleName: moduleName, image: image,
                              outcome: .converted(bundleURL: url, engine: engine))
            }
            return Report(pluginDirectory: pluginDirectory, moduleName: moduleName, image: image,
                          outcome: .nativeModuleExists(url))
        }

        let engine = PluginEngineKind.recognize(moduleName: moduleName) ?? image?.embeddedEngine
        guard let engine else {
            return Report(pluginDirectory: pluginDirectory, moduleName: moduleName, image: image,
                          outcome: .unsupported(reason: unsupportedReason(moduleName: moduleName, image: image)))
        }
        if let image, !image.exportsUkagakaModuleABI {
            return Report(pluginDirectory: pluginDirectory, moduleName: moduleName, image: image,
                          outcome: .unsupported(reason: "\(moduleName) は load/request をエクスポートしていない"))
        }

        let bundleURL = moduleURL.deletingPathExtension().appendingPathExtension("plugin")
        do {
            try writeBundle(at: bundleURL, engine: engine, moduleName: moduleName,
                            pluginID: descript["id"] ?? "", pluginName: descript["name"] ?? "",
                            image: image, fileManager: fileManager)
        } catch {
            return Report(pluginDirectory: pluginDirectory, moduleName: moduleName, image: image,
                          outcome: .unsupported(reason: "変換先を書き込めない: \(error.localizedDescription)"))
        }
        return Report(pluginDirectory: pluginDirectory, moduleName: moduleName, image: image,
                      outcome: .converted(bundleURL: bundleURL, engine: engine))
    }

    /// `.plugin` の Info.plist に内蔵エンジンの指定があればその種別を返す。
    static func engineKind(ofBundleAt url: URL) -> PluginEngineKind? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let raw = info[engineKey] as? String else { return nil }
        return PluginEngineKind(rawValue: raw.lowercased())
    }

    private static func writeBundle(at bundleURL: URL, engine: PluginEngineKind, moduleName: String,
                                    pluginID: String, pluginName: String, image: PEImageInfo?,
                                    fileManager: FileManager) throws {
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try fileManager.createDirectory(at: contents, withIntermediateDirectories: true)
        let identifierSuffix = pluginID.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "-" }
            .joined()
        var info: [String: Any] = [
            "CFBundleIdentifier": "jp.ourin.converted-plugin." + (identifierSuffix.isEmpty ? "unknown" : identifierSuffix),
            "CFBundleName": pluginName.isEmpty ? bundleURL.deletingPathExtension().lastPathComponent : pluginName,
            "CFBundlePackageType": "BNDL",
            "CFBundleInfoDictionaryVersion": "6.0",
            engineKey: engine.rawValue,
            originalModuleKey: moduleName,
            "OurinConverterVersion": formatVersion
        ]
        if let image {
            info["OurinOriginalMachine"] = image.machine.rawValue
            info["OurinOriginalExports"] = image.exports
            info["OurinOriginalImports"] = image.imports
        }
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    private static func unsupportedReason(moduleName: String, image: PEImageInfo?) -> String {
        guard let image else {
            return "\(moduleName) が見つからないか PE 形式ではない"
        }
        let imports = image.imports.prefix(8).joined(separator: ", ")
        return "\(moduleName) は \(image.machine.rawValue) 向けの独自コード（import: \(imports)）。macOS 向けにビルドした .dylib / .plugin が必要"
    }
}
