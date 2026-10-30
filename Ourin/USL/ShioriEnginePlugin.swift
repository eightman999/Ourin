import Foundation

/// An installed macOS SHIORI implementation, separate from the PLUGIN event API.
struct ShioriEnginePlugin: Decodable, Identifiable {
    let schema: Int
    let id: String
    let name: String
    let kind: String
    let module: String?
    let executable: String?
    let arguments: [String]?
    let charset: String?
    let environment: [String: String]?
    let moduleNames: [String]
    let markers: [String]?
    let commandHints: [String]?
    let architectures: [String]?
    let licenseScope: String?
    let limitations: String?
    let launchTimeout: TimeInterval?
    let minimumOSVersion: String?

    var isDevelopmentSample: Bool { kind == "development-sample" }
    var supportsCurrentArchitecture: Bool {
        guard let architectures, !architectures.isEmpty else { return true }
        #if arch(arm64)
        return architectures.contains("arm64")
        #else
        return architectures.contains("x86_64")
        #endif
    }
    var supportsCurrentSystem: Bool {
        guard let minimumOSVersion else { return true }
        let parts = minimumOSVersion.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return false }
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: parts[0], minorVersion: parts.count > 1 ? parts[1] : 0,
                                   patchVersion: parts.count > 2 ? parts[2] : 0))
    }
}

struct InstalledShioriEngine: Identifiable {
    let descriptor: ShioriEnginePlugin
    let directory: URL
    let packageURL: URL
    var id: String { descriptor.id }
}

enum ShioriEnginePlugins {
    enum Resolution {
        case noMatch
        case selected(InstalledShioriEngine)
        case unavailableSelection
        case ambiguous
    }

    enum Failure: LocalizedError {
        case invalidPackage(String), alreadyInstalled(String), ambiguous
        var errorDescription: String? {
            switch self {
            case .invalidPackage(let reason): return "SHIORIパッケージが不正です：\(reason)"
            case .alreadyInstalled(let id): return "\(id) は導入済みです。"
            case .ambiguous: return "この辞書に一致するSHIORIエンジンが複数あります。"
            }
        }
    }

    static func installationRoot() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["OURIN_SHIORI_ENGINE_PLUGINS"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return try OurinPaths.baseDirectory().appendingPathComponent("shiori-engines", isDirectory: true)
    }

    /// All package paths must remain inside the package, including symlink targets.
    static func containedURL(_ relative: String, in directory: URL) throws -> URL {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.hasPrefix("/"), !relative.contains("\\"),
              !relative.contains("\0"), !components.contains(".."), !components.contains(""),
              !components.contains(".") else { throw Failure.invalidPackage("相対パス") }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let target = root.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard target.path.hasPrefix(root.path + "/") else { throw Failure.invalidPackage("パッケージ外の参照") }
        return target
    }

    static func read(from directory: URL) throws -> InstalledShioriEngine {
        let directoryValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
            throw Failure.invalidPackage("パッケージは実ディレクトリである必要があります")
        }
        var payload = directory
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Contents/Info.plist").path) {
            let infoURL = try containedURL("Contents/Info.plist", in: directory)
            let infoHandle = try FileHandle(forReadingFrom: infoURL)
            defer { try? infoHandle.close() }
            let infoData = try infoHandle.read(upToCount: 65_537) ?? Data()
            guard infoData.count <= 65_536,
                  let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
                  info["CFBundlePackageType"] as? String == "BNDL",
                  info["OurinShioriEnginePackageVersion"] as? Int == 1 else {
                throw Failure.invalidPackage("Ourin SHIORI用の.pluginではありません")
            }
            payload = try containedURL("Contents/Resources", in: directory)
        }
        let manifest = try containedURL("engine.json", in: payload)
        let handle = try FileHandle(forReadingFrom: manifest)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 262_145) ?? Data()
        guard data.count <= 262_144 else { throw Failure.invalidPackage("manifestのサイズ") }
        let descriptor = try JSONDecoder().decode(ShioriEnginePlugin.self, from: data)
        guard descriptor.schema == 1,
              descriptor.id.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil,
              !descriptor.name.isEmpty,
              ["native", "shiolink", "development-sample"].contains(descriptor.kind),
              !(descriptor.module != nil && descriptor.executable != nil) else {
            throw Failure.invalidPackage("schema・ID・種類")
        }
        if descriptor.kind == "native", descriptor.module == nil { throw Failure.invalidPackage("module") }
        if descriptor.kind == "shiolink", descriptor.executable == nil { throw Failure.invalidPackage("executable") }
        for path in [descriptor.module, descriptor.executable].compactMap({ $0 }) {
            let url = try containedURL(path, in: payload)
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.invalidPackage("実行ファイルがありません") }
            if path == descriptor.executable, !FileManager.default.isExecutableFile(atPath: url.path) {
                throw Failure.invalidPackage("実行権限がありません")
            }
        }
        for name in descriptor.moduleNames {
            guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.contains("\0") else {
                throw Failure.invalidPackage("モジュール名")
            }
        }
        for marker in descriptor.markers ?? [] { _ = try containedURL(marker, in: payload) }
        if let timeout = descriptor.launchTimeout, !timeout.isFinite || timeout <= 0 || timeout > 60 {
            throw Failure.invalidPackage("起動期限")
        }
        if let version = descriptor.minimumOSVersion,
           version.range(of: "^[0-9]{1,3}(\\.[0-9]{1,3}){0,2}$", options: .regularExpression) == nil {
            throw Failure.invalidPackage("必要OSバージョン")
        }
        guard (descriptor.arguments ?? []).allSatisfy({ !$0.contains("\0") && !$0.contains("\n") && !$0.contains("\r") }),
              (descriptor.environment ?? [:]).allSatisfy({ key, value in
                  key.range(of: "^[A-Z_][A-Z0-9_]*$", options: .regularExpression) != nil && !value.contains("\0")
              }) else { throw Failure.invalidPackage("引数・環境変数") }
        return InstalledShioriEngine(descriptor: descriptor, directory: payload, packageURL: directory)
    }

    static func installed(in root: URL? = nil) -> [InstalledShioriEngine] {
        guard let root = root ?? (try? installationRoot()),
              let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                                        options: .skipsHiddenFiles) else { return [] }
        return entries.compactMap { entry in
            let name = entry.pathExtension.lowercased() == "plugin" ? entry.deletingPathExtension().lastPathComponent : entry.lastPathComponent
            guard let engine = try? read(from: entry), engine.id == name else { return nil }
            return engine
        }.sorted { $0.descriptor.name.localizedStandardCompare($1.descriptor.name) == .orderedAscending }
    }

    private struct Selections: Codable {
        var schema = 1
        var ghosts: [String: String] = [:]
    }

    private static func selections(in root: URL) throws -> Selections {
        let path = root.appendingPathComponent(".selections.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return Selections() }
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 262_145) ?? Data()
        guard data.count <= 262_144 else { throw Failure.invalidPackage("割当設定のサイズ") }
        let result = try JSONDecoder().decode(Selections.self, from: data)
        guard result.schema == 1 else { throw Failure.invalidPackage("割当設定のschema") }
        return result
    }

    /// Store a per-ghost choice in Ourin's profile, without changing its descriptor.
    static func assign(engineID: String?, to ghostURL: URL, root: URL? = nil) throws {
        let root = try root ?? installationRoot()
        if let engineID {
            guard installed(in: root).contains(where: { $0.id == engineID && !$0.descriptor.isDevelopmentSample }) else {
                throw Failure.invalidPackage("割り当てるエンジンがありません")
            }
        }
        var choices = try selections(in: root)
        choices.ghosts[ghostURL.resolvingSymlinksInPath().standardizedFileURL.path] = engineID
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(choices).write(to: root.appendingPathComponent(".selections.json"), options: .atomic)
    }

    /// Importing never executes code and never replaces an existing package.
    @discardableResult
    static func install(from source: URL, into root: URL? = nil) throws -> InstalledShioriEngine {
        let fm = FileManager.default
        let root = try root ?? installationRoot()
        let temporary = fm.temporaryDirectory.appendingPathComponent("Ourin-Shiori-Import-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw Failure.invalidPackage("入力がありません") }
        var package = source
        if !isDirectory.boolValue {
            let payload = temporary.appendingPathComponent("payload")
            try ZipUtil.extractZip(source, to: payload)
            package = payload
        }
        if !fm.fileExists(atPath: package.appendingPathComponent("engine.json").path),
           !fm.fileExists(atPath: package.appendingPathComponent("Contents/Resources/engine.json").path) {
            let children = try fm.contentsOfDirectory(at: package, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            guard children.count == 1 else { throw Failure.invalidPackage("engine.jsonがありません") }
            package = children[0]
        }
        let engine = try read(from: package)
        try validateContents(in: package)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let bundle = engine.packageURL.path != engine.directory.path
        let destination = root.appendingPathComponent(engine.id + (bundle ? ".plugin" : ""))
        guard !fm.fileExists(atPath: root.appendingPathComponent(engine.id).path),
              !fm.fileExists(atPath: root.appendingPathComponent(engine.id + ".plugin").path) else {
            throw Failure.alreadyInstalled(engine.id)
        }
        let staging = root.appendingPathComponent(".install-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: package, to: staging)
        _ = try read(from: staging)
        try validateContents(in: staging)
        try fm.moveItem(at: staging, to: destination)
        return try read(from: destination)
    }

    private static func validateContents(in package: URL) throws {
        let fm = FileManager.default
        let resolvedRoot = package.resolvingSymlinksInPath().path + "/"
        let enumerator = fm.enumerator(at: package, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        var count = 0, bytes: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            count += 1
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            if values.isSymbolicLink == true && !file.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot) {
                throw Failure.invalidPackage("外部symlink")
            }
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            guard count <= 100_000, bytes <= 4 * 1024 * 1024 * 1024 else { throw Failure.invalidPackage("サイズ上限") }
        }
    }

    static func dictionaryDirectory(for context: ShioriRuntimeLoadContext) -> URL? {
        let name = context.moduleName.replacingOccurrences(of: "\\", with: "/")
        guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else { return nil }
        let relative = (name as NSString).deletingLastPathComponent
        if relative.isEmpty { return context.ghostRoot }
        return UkagakaModuleABI.resolveCaseInsensitive(relative, in: context.ghostRoot)
    }

    static func ghostProvidedNativeModule(context: ShioriRuntimeLoadContext) -> URL? {
        ShioriLoader.find(name: context.moduleName,
                         in: [context.ghostRoot, context.ghostRoot.appendingPathComponent("modules")])
    }

    static func matching(context: ShioriRuntimeLoadContext, root: URL? = nil) -> InstalledShioriEngine? {
        if case .selected(let engine) = resolution(context: context, root: root) { return engine }
        return nil
    }

    /// Keep refusal distinct from absence so a requested engine never becomes an older built-in VM.
    static func resolution(context: ShioriRuntimeLoadContext, root: URL? = nil) -> Resolution {
        guard let directory = dictionaryDirectory(for: context) else { return .noMatch }
        // A user-selected port must not silently turn into a different engine.
        if UkagakaModuleABI.resolveCaseInsensitive("SHIOLINK.ourin.ini", in: directory) != nil { return .noMatch }
        // A ghost-provided macOS implementation has priority over a shared plugin.
        if ghostProvidedNativeModule(context: context) != nil { return .noMatch }
        let available = installed(in: root)
        if let selectionRoot = root ?? (try? installationRoot()),
           let choices = try? selections(in: selectionRoot),
           let selected = choices.ghosts[context.ghostURL.resolvingSymlinksInPath().standardizedFileURL.path] {
            guard let engine = available.first(where: { $0.id == selected && !$0.descriptor.isDevelopmentSample
                && $0.descriptor.supportsCurrentArchitecture && $0.descriptor.supportsCurrentSystem }) else {
                return .unavailableSelection
            }
            return .selected(engine)
        }
        let moduleName = URL(fileURLWithPath: context.moduleName.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
        let iniURL = UkagakaModuleABI.resolveCaseInsensitive("SHIOLINK.INI", in: directory)
        let iniData = iniURL.flatMap { url -> Data? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            return try? handle.read(upToCount: 65_537)
        }
        let command = iniData.flatMap { data -> String? in
            guard data.count <= 65_536 else { return nil }
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS)
        }?.lowercased() ?? ""
        let matches = available.filter { installed in
            let engine = installed.descriptor
            guard !engine.isDevelopmentSample, engine.supportsCurrentArchitecture, engine.supportsCurrentSystem else { return false }
            let named = engine.moduleNames.contains { name in
                let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent.lowercased()
                let requested = URL(fileURLWithPath: moduleName).deletingPathExtension().lastPathComponent
                return stem == requested || "lib" + stem == requested
            }
            let stem = URL(fileURLWithPath: moduleName).deletingPathExtension().lastPathComponent
            let canonical = stem.hasPrefix("lib") ? String(stem.dropFirst(3)) : stem
            let generic = ["shiori", "shiolink"].contains(canonical)
            if named && !generic { return true }
            guard generic else { return false }
            let markers = engine.markers ?? []
            let hasMarker = !markers.isEmpty && markers.contains { UkagakaModuleABI.resolveCaseInsensitive($0, in: directory) != nil }
            let hasHint = (engine.commandHints ?? []).contains { command.contains($0.lowercased()) }
            return (named && hasMarker) || hasHint
        }
        guard !matches.isEmpty else { return .noMatch }
        guard matches.count == 1 else { return .ambiguous }
        return .selected(matches[0])
    }

    static func processConfiguration(context: ShioriRuntimeLoadContext) -> ShiolinkConfiguration? {
        guard let installed = matching(context: context), installed.descriptor.kind == "shiolink",
              let path = installed.descriptor.executable,
              let executable = try? containedURL(path, in: installed.directory),
              let directory = dictionaryDirectory(for: context) else { return nil }
        func expand(_ value: String) -> String {
            value.replacingOccurrences(of: "{engineRoot}", with: installed.directory.path)
                .replacingOccurrences(of: "{ghostRoot}", with: directory.path)
        }
        return ShiolinkConfiguration(executable: executable,
            arguments: (installed.descriptor.arguments ?? []).map(expand), directory: directory,
            charset: installed.descriptor.charset ?? "UTF-8", moduleOverride: nil,
            environment: (installed.descriptor.environment ?? [:]).mapValues(expand),
            launchTimeout: installed.descriptor.launchTimeout)
    }

    static func nativeModule(context: ShioriRuntimeLoadContext) -> URL? {
        guard let installed = matching(context: context), installed.descriptor.kind == "native",
              let module = installed.descriptor.module else { return nil }
        return try? containedURL(module, in: installed.directory)
    }
}
