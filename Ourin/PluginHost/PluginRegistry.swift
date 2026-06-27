import Foundation

/// Parsed metadata from descript.txt
public struct PluginMeta {
    public let name: String
    public let id: String
    public let filename: String
    public let charset: String?
    public let secondChangeInterval: Int?
    public let otherGhostTalk: Bool?
    public let otherGhostTalkTiming: PluginOtherGhostTalkTiming?
    public let craftman: String?
    public let craftmanURL: String?
    public let isNative: Bool
    public let installType: String?
    public let installDirectory: String?
    public let localizedMessages: [String: [String: String]]

    /// descript.txt の `filename` 由来の互換パス（元 DLL パス）。
    /// `pluginlist.index(n).path` はこれを返す（従来互換）。
    public let compatibilityPath: String
    /// 実ロード対象。native `.plugin` / `.bundle` のパス。legacy の場合は compatibilityPath と同一。
    public let executablePath: String
    /// install.txt 付き package directory のパス（無い場合は nil）。
    public let packagePath: String?

    /// 従来の `path`。`compatibilityPath` の alias。
    public var path: String { compatibilityPath }

    public func message(for key: String, language: String? = nil) -> String? {
        if let language {
            let normalized = PluginRegistry.normalizedMessageLanguage(language)
            if let value = localizedMessages[normalized]?[key] {
                return value
            }
        }

        for preferred in Locale.preferredLanguages {
            let normalized = PluginRegistry.normalizedMessageLanguage(preferred)
            if let value = localizedMessages[normalized]?[key] {
                return value
            }
        }

        return localizedMessages["japanese"]?[key]
            ?? localizedMessages["english"]?[key]
            ?? localizedMessages.values.lazy.compactMap { $0[key] }.first
    }
}

/// macOS ホスト上で plugin metadata を SSP 互換名と実行実体の両面から見るためのビュー。
///
/// `path` / `compatibilityPath` は descript.txt の `filename` から得られる互換パスを指す。
/// Windows DLL 資産はこのビューには現れるが、`canDispatchRequests == false` の metadata-only として扱う。
public struct PluginCompatibilityEntry: Equatable {
    public enum ExecutionState: String {
        case native
        case metadataOnly
    }

    public let name: String
    public let id: String
    public let filename: String
    public let charset: String
    public let craftman: String?
    public let craftmanURL: String?
    public let native: Bool
    public let executionState: ExecutionState
    public let canDispatchRequests: Bool
    public let compatibilityPath: String
    public let executablePath: String
    public let packagePath: String?
    public let installType: String?
    public let installDirectory: String?
    public let localizedMessages: [String: [String: String]]
    public let localizedMessageLanguages: [String]

    public var path: String {
        compatibilityPath
    }
}

public extension PluginMeta {
    var compatibilityEntry: PluginCompatibilityEntry {
        PluginCompatibilityEntry(
            name: name,
            id: id,
            filename: filename,
            charset: charset ?? "UTF-8",
            craftman: craftman,
            craftmanURL: craftmanURL,
            native: isNative,
            executionState: isNative ? .native : .metadataOnly,
            canDispatchRequests: isNative,
            compatibilityPath: compatibilityPath,
            executablePath: executablePath,
            packagePath: packagePath,
            installType: installType,
            installDirectory: installDirectory,
            localizedMessages: localizedMessages,
            localizedMessageLanguages: localizedMessages.keys.sorted()
        )
    }
}

public enum PluginOtherGhostTalkTiming: String {
    case before
    case after
}

public struct LegacyPluginRecord {
    public let meta: PluginMeta
    public let directoryURL: URL
    /// install.txt 付き package directory の URL（無い場合は nil）。
    public let packageURL: URL?

    init(meta: PluginMeta, directoryURL: URL, packageURL: URL? = nil) {
        self.meta = meta
        self.directoryURL = directoryURL
        self.packageURL = packageURL
    }
}

/// Registry for discovering and managing plugins
public final class PluginRegistry {
    public private(set) var plugins: [Plugin] = []
    public private(set) var metas: [Plugin: PluginMeta] = [:]
    public private(set) var legacyMetas: [LegacyPluginRecord] = []

    public var allMetas: [PluginMeta] {
        metas.values.map { $0 } + legacyMetas.map { $0.meta }
    }

    /// UI・property・診断向けの互換ビュー。
    ///
    /// Native `.plugin` / `.bundle` は `canDispatchRequests == true`、Windows DLL 由来の legacy plugin は
    /// metadata-only として列挙だけ行い、PLUGIN request の送信対象にはしない。
    public var compatibilityEntries: [PluginCompatibilityEntry] {
        allMetas
            .map(\.compatibilityEntry)
            .sorted {
                let lhsName = $0.name.localizedStandardCompare($1.name)
                if lhsName != .orderedSame { return lhsName == .orderedAscending }
                let lhsID = $0.id.localizedStandardCompare($1.id)
                if lhsID != .orderedSame { return lhsID == .orderedAscending }
                return $0.compatibilityPath.localizedStandardCompare($1.compatibilityPath) == .orderedAscending
            }
    }

    /// 現在ロード済みの plugin ID の集合（重複抑止用）。
    private var loadedIDs: Set<String> = []

    public init() {}

    /// Discover plugin bundles and load them.
    ///
    /// 優先順位（同一 ID が複数ある場合は高いものを採用）:
    /// 1. install.txt 付き package directory 内の native `.plugin`
    /// 2. 直置き native `.plugin`
    /// 3. legacy metadata-only directory
    public func discoverAndLoad() {
        // 全検索パスから候補を収集し、ID ごとに優先順位の高いものを選ぶ。
        var candidates: [String: [PluginCandidate]] = [:]  // id -> candidates (descending priority)
        for dir in PluginRegistry.searchPaths() {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items {
                collectCandidates(at: item, into: &candidates)
            }
        }

        // 各 ID について最優先候補をロードする。
        loadedIDs.removeAll()
        for (_, cands) in candidates {
            let winner = cands.sorted { $0.priority < $1.priority }.first
            loadCandidate(winner)
        }
    }

    /// Unload all loaded plugins
    public func unloadAll() {
        for p in plugins { p.unload?() }
        plugins.removeAll()
        metas.removeAll()
        legacyMetas.removeAll()
        loadedIDs.removeAll()
    }

    // MARK: - Event Dispatch

    /// Send GET event to all plugins and collect responses with scripts
    public func dispatchGet(id: String, references: [String: String] = [:]) -> [(Plugin, PluginResponse)] {
        var results: [(Plugin, PluginResponse)] = []
        for plugin in plugins {
            do {
                let response = try plugin.get(id: id, references: references)
                // Only collect responses with script content
                if response.script != nil || response.value != nil {
                    results.append((plugin, response))
                }
            } catch {
                NSLog("Plugin GET dispatch failed for \(id): \(error)")
            }
        }
        return results
    }

    /// Send NOTIFY event to all plugins (responses are typically ignored)
    public func dispatchNotify(id: String, references: [String: String] = [:]) {
        for plugin in plugins {
            do {
                _ = try plugin.notify(id: id, references: references)
            } catch {
                NSLog("Plugin NOTIFY dispatch failed for \(id): \(error)")
            }
        }
    }

    /// Get versions of all loaded plugins
    public func getAllVersions() -> [Plugin: String] {
        var versions: [Plugin: String] = [:]
        for plugin in plugins {
            do {
                if let version = try plugin.version() {
                    versions[plugin] = version
                }
            } catch {
                NSLog("Failed to get plugin version: \(error)")
            }
        }
        return versions
    }

    /// Dispatch specific event types based on PLUGIN/2.0M spec

    /// OnMenuExec - User selected a plugin menu item
    public func dispatchOnMenuExec(reference0: String) -> [(Plugin, PluginResponse)] {
        return dispatchGet(id: "OnMenuExec", references: ["Reference0": reference0])
    }

    /// OnSecondChange - Timer tick (NOTIFY forced event)
    public func dispatchOnSecondChange() {
        dispatchNotify(id: "OnSecondChange")
    }

    /// OnMinuteChange - Minute changed (NOTIFY forced event)
    public func dispatchOnMinuteChange() {
        dispatchNotify(id: "OnMinuteChange")
    }

    /// OnOtherGhostTalk - Another ghost is talking
    public func dispatchOnOtherGhostTalk(script: String, ghostName: String) {
        let refs = [
            "Reference0": script,
            "Reference1": ghostName
        ]
        dispatchNotify(id: "OnOtherGhostTalk", references: refs)
    }

    /// OnGhostChanging - Ghost is about to change
    public func dispatchOnGhostChanging(newGhost: String) -> [(Plugin, PluginResponse)] {
        return dispatchGet(id: "OnGhostChanging", references: ["Reference0": newGhost])
    }

    /// OnGhostChanged - Ghost has changed
    public func dispatchOnGhostChanged(previousGhost: String, currentGhost: String) {
        let refs = [
            "Reference0": previousGhost,
            "Reference1": currentGhost
        ]
        dispatchNotify(id: "OnGhostChanged", references: refs)
    }

    /// OnShellChanging - Shell is about to change
    public func dispatchOnShellChanging(newShell: String) -> [(Plugin, PluginResponse)] {
        return dispatchGet(id: "OnShellChanging", references: ["Reference0": newShell])
    }

    /// OnShellChanged - Shell has changed
    public func dispatchOnShellChanged(previousShell: String, currentShell: String) {
        let refs = [
            "Reference0": previousShell,
            "Reference1": currentShell
        ]
        dispatchNotify(id: "OnShellChanged", references: refs)
    }

    // MARK: - Candidate collection (Fix 2: 同一 ID 二重ロード抑止)

    /// 検出されたプラグイン候補。数値が小さいほど優先度が高い。
    private enum PluginCandidate {
        case nativePackage(bundleURL: URL, packageURL: URL, installManifest: InstallManifest)
        case nativeDirect(bundleURL: URL)
        case legacy(record: LegacyPluginRecord)

        var priority: Int {
            switch self {
            case .nativePackage: return 0
            case .nativeDirect: return 1
            case .legacy: return 2
            }
        }

        var id: String {
            switch self {
            case .nativePackage(_, let pkg, _):
                return PluginRegistry.peekID(at: pkg) ?? ""
            case .nativeDirect(let bundleURL):
                return PluginRegistry.peekID(at: bundleURL.deletingLastPathComponent()) ?? ""
            case .legacy(let record):
                return record.meta.id
            }
        }

        var bundleURL: URL? {
            switch self {
            case .nativePackage(let url, _, _): return url
            case .nativeDirect(let url): return url
            case .legacy: return nil
            }
        }
    }

    /// 1 項目を走査し、候補リストへ追加する。
    private func collectCandidates(at item: URL, into candidates: inout [String: [PluginCandidate]]) {
        if item.pathExtension == "plugin" || item.pathExtension == "bundle" {
            let id = PluginRegistry.peekID(at: item.deletingLastPathComponent()) ?? ""
            candidates[id, default: []].append(.nativeDirect(bundleURL: item))
            return
        }

        if isDirectory(item) {
            // package directory (install.txt 付き)
            if let installManifest = PluginRegistry.readInstallManifest(from: item),
               installManifest.type.lowercased() == "plugin" {
                let bundles = PluginRegistry.nativePluginBundles(in: item)
                if !bundles.isEmpty {
                    for bundleURL in bundles {
                        let id = PluginRegistry.peekID(at: item) ?? ""
                        candidates[id, default: []].append(
                            .nativePackage(bundleURL: bundleURL, packageURL: item, installManifest: installManifest)
                        )
                    }
                    return
                }
                // legacy package
                if let record = PluginRegistry.readLegacyMeta(from: item, installManifest: installManifest, packageURL: item) {
                    candidates[record.meta.id, default: []].append(.legacy(record: record))
                }
                return
            }

            // legacy directory (install.txt 無し)
            if let record = PluginRegistry.readLegacyMeta(from: item) {
                candidates[record.meta.id, default: []].append(.legacy(record: record))
            }
        }
    }

    /// 候補を実際にロード/登録する。同一 ID は最初の1件のみ。
    private func loadCandidate(_ candidate: PluginCandidate?) {
        guard let candidate else { return }
        let id = candidate.id
        if !id.isEmpty && loadedIDs.contains(id) {
            NSLog("Plugin skipped (duplicate ID \(id)): \(candidate.bundleURL?.lastPathComponent ?? "?")")
            return
        }

        switch candidate {
        case .nativePackage(let bundleURL, let packageURL, let installManifest):
            loadNativePlugin(bundleURL: bundleURL, metadataRootURL: packageURL, installManifest: installManifest, loadPathURL: packageURL)
        case .nativeDirect(let bundleURL):
            loadNativePlugin(bundleURL: bundleURL, metadataRootURL: nil, installManifest: nil, loadPathURL: bundleURL)
        case .legacy(let record):
            appendLegacyMeta(record)
        }

        if !id.isEmpty {
            loadedIDs.insert(id)
        }
    }

    /// descript.txt から ID だけ読み取る（候補ソート用・軽量）。
    private static func peekID(at directoryURL: URL) -> String? {
        let descript = LegacyDescriptor.readDictionary(from: directoryURL.appendingPathComponent("descript.txt"))
            ?? LegacyDescriptor.readDictionary(from: directoryURL.appendingPathComponent("Contents/Resources/descript.txt"))
        return descript?["id"].flatMap { $0.isEmpty ? nil : $0 }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: Utilities
    private func loadNativePlugin(bundleURL: URL,
                                  metadataRootURL: URL?,
                                  installManifest: InstallManifest?,
                                  loadPathURL: URL) {
        do {
            let plug = try Plugin(url: bundleURL)
            if let load = plug.load {
                _ = load(loadPathURL.path)
            }
            plugins.append(plug)
            if let meta = PluginRegistry.readMeta(from: plug.bundle,
                                                  metadataRootURL: metadataRootURL,
                                                  installManifest: installManifest) {
                metas[plug] = meta
                if !meta.id.isEmpty {
                    loadedIDs.insert(meta.id)
                }
            }
        } catch {
            NSLog("Plugin load failed: \(error)")
        }
    }

    private func appendLegacyMeta(_ legacy: LegacyPluginRecord) {
        if legacyMetas.contains(where: { $0.directoryURL.standardizedFileURL.path == legacy.directoryURL.standardizedFileURL.path }) {
            return
        }
        if !legacy.meta.id.isEmpty && loadedIDs.contains(legacy.meta.id) {
            NSLog("Legacy plugin skipped (duplicate ID \(legacy.meta.id)): \(legacy.meta.name)")
            return
        }
        legacyMetas.append(legacy)
        if !legacy.meta.id.isEmpty {
            loadedIDs.insert(legacy.meta.id)
        }
        NSLog("Legacy Windows plugin registered as metadata only: \(legacy.meta.name) (\(legacy.meta.filename))")
    }

    private static func searchPaths() -> [URL] {
        var urls: [URL] = []
        if let builtIn = Bundle.main.builtInPlugInsURL {
            urls.append(builtIn)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(appSupport.appendingPathComponent("Ourin/PlugIns", isDirectory: true))
        }
        // 公開リソースの plugin/（SSP 標準・小文字）を NAR 設置先と一致させて探索する。
        if let pluginDir = try? OurinPaths.subdirectory("plugin") {
            urls.append(pluginDir)
        }
        return urls
    }

    private static func readMeta(from bundle: Bundle,
                                 metadataRootURL: URL?,
                                 installManifest: InstallManifest?) -> PluginMeta? {
        let descriptorURL = metadataRootURL?.appendingPathComponent("descript.txt")
            ?? bundle.url(forResource: "descript", withExtension: "txt")
        guard let descriptorURL else { return nil }
        let directoryURL = metadataRootURL ?? bundle.bundleURL
        return readMetaDictionary(
            LegacyDescriptor.readDictionary(from: descriptorURL),
            directoryURL: directoryURL,
            isNative: true,
            installManifest: installManifest,
            localizedMessages: readMessages(from: metadataRootURL) ?? readMessages(from: bundle.resourceURL),
            executableURL: bundle.bundleURL,
            packageURL: metadataRootURL
        )
    }

    private static func readLegacyMeta(from directoryURL: URL,
                                       installManifest: InstallManifest? = nil,
                                       packageURL: URL? = nil) -> LegacyPluginRecord? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        let resolvedPackageURL = packageURL ?? (installManifest != nil ? directoryURL : nil)
        guard let meta = readMetaDictionary(
            LegacyDescriptor.readDictionary(from: directoryURL.appendingPathComponent("descript.txt")),
            directoryURL: directoryURL,
            isNative: false,
            installManifest: installManifest ?? readInstallManifest(from: directoryURL),
            localizedMessages: readMessages(from: directoryURL),
            packageURL: resolvedPackageURL
        ) else { return nil }
        return LegacyPluginRecord(meta: meta, directoryURL: directoryURL, packageURL: resolvedPackageURL)
    }

    private static func readMetaDictionary(_ dict: [String: String]?,
                                           directoryURL: URL,
                                           isNative: Bool,
                                           installManifest: InstallManifest?,
                                           localizedMessages: [String: [String: String]]?,
                                           executableURL: URL? = nil,
                                           packageURL: URL? = nil) -> PluginMeta? {
        guard let dict else { return nil }
        let name = dict["name"] ?? ""
        let id = dict["id"] ?? ""
        let filename = dict["filename"] ?? dict["dllname"] ?? ""
        guard !name.isEmpty, !id.isEmpty, !filename.isEmpty else { return nil }
        let moduleURL = directoryURL.appendingPathComponent(filename)
        let otherGhostTalk = parseOtherGhostTalk(dict["otherghosttalk"])
        return PluginMeta(
            name: name,
            id: id,
            filename: filename,
            charset: dict["charset"],
            secondChangeInterval: dict["secondchangeinterval"].flatMap(Int.init),
            otherGhostTalk: otherGhostTalk.enabled,
            otherGhostTalkTiming: otherGhostTalk.timing,
            craftman: dict["craftman"] ?? dict["craftmanw"],
            craftmanURL: dict["craftmanurl"] ?? dict["homeurl"],
            isNative: isNative,
            installType: installManifest?.type,
            installDirectory: installManifest?.directory,
            localizedMessages: localizedMessages ?? [:],
            compatibilityPath: moduleURL.path,
            executablePath: (executableURL ?? moduleURL).path,
            packagePath: packageURL?.path
        )
    }

    private static func parseOtherGhostTalk(_ raw: String?) -> (enabled: Bool?, timing: PluginOtherGhostTalkTiming?) {
        guard let raw else { return (nil, nil) }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "0", "false", "no", "off":
            return (false, nil)
        case "before":
            return (true, .before)
        case "after", "1", "true", "yes", "on":
            return (true, .after)
        default:
            return (true, .after)
        }
    }

    private static func readInstallManifest(from directoryURL: URL) -> InstallManifest? {
        let url = directoryURL.appendingPathComponent("install.txt")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? InstallTxtParser.parse(data: data)
    }

    private static func nativePluginBundles(in directoryURL: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return items
            .filter { $0.pathExtension == "plugin" || $0.pathExtension == "bundle" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func readMessages(from directoryURL: URL?) -> [String: [String: String]]? {
        guard let directoryURL,
              let items = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return nil }

        var result: [String: [String: String]] = [:]
        for url in items {
            let filename = url.lastPathComponent.lowercased()
            guard filename.hasPrefix("message."), filename.hasSuffix(".txt") else { continue }
            let language = filename
                .dropFirst("message.".count)
                .dropLast(".txt".count)
            guard !language.isEmpty,
                  let messages = LegacyDescriptor.readDictionary(from: url) else { continue }
            result[normalizedMessageLanguage(String(language))] = messages
        }
        return result.isEmpty ? nil : result
    }

    fileprivate static func normalizedMessageLanguage(_ language: String) -> String {
        let lower = language.lowercased()
        if lower.hasPrefix("ja") || lower.contains("japanese") {
            return "japanese"
        }
        if lower.hasPrefix("en") || lower.contains("english") {
            return "english"
        }
        return lower
    }
}
