import Foundation

/// `\![updateother]` が更新できる、ゴースト以外のインストール済み対象。
///
/// SSP のインストール先は種別によって異なる（shell はゴースト配下に
/// ネストされる）ため、更新処理がファイルシステムの配置を直接推測しない
/// ように、ここで対象と descriptor のメタデータを正規化する。
struct ComponentUpdateTarget: Hashable {
    let type: String
    let name: String
    let path: URL
    let aliases: Set<String>
    let homeURL: String?

    func matches(name requested: String) -> Bool {
        let normalized = requested.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return aliases.contains { alias in
            alias.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == normalized
        }
    }
}

enum ComponentUpdateTargetDiscovery {
    static let supportedTypes: Set<String> = ["balloon", "shell", "plugin", "headline", "language"]

    static func discover(types requestedTypes: Set<String> = supportedTypes) -> [ComponentUpdateTarget] {
        let types = requestedTypes.intersection(supportedTypes)
        guard !types.isEmpty else { return [] }

        var candidates: [ComponentUpdateTarget] = []
        let registry = NarRegistry.shared
        let fileManager = FileManager.default

        for type in types where type != "shell" {
            for item in registry.installedItems(ofType: type) {
                candidates.append(makeTarget(type: type, path: item.path))
            }
        }

        if types.contains("shell") {
            // 標準配置: ghost/<ghost>/shell/<shell>。
            for ghost in registry.installedItems(ofType: "ghost") {
                let shellRoot = ghost.path.appendingPathComponent("shell", isDirectory: true)
                guard let entries = try? fileManager.contentsOfDirectory(
                    at: shellRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for entry in entries where isDirectory(entry, fileManager: fileManager) {
                    candidates.append(makeTarget(type: "shell", path: entry))
                }
            }

            // 旧形式の共有 shell/<name> も保持する。
            for item in registry.installedItems(ofType: "shell") {
                candidates.append(makeTarget(type: "shell", path: item.path))
            }
        }

        var unique: [String: ComponentUpdateTarget] = [:]
        for candidate in candidates {
            unique[candidate.path.standardizedFileURL.path] = candidate
        }
        return unique.values.sorted {
            if $0.type != $1.type { return $0.type < $1.type }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func makeTarget(type: String, path: URL) -> ComponentUpdateTarget {
        let descriptor = descriptorValues(at: path)
        let directoryName = path.lastPathComponent
        let descriptorName = descriptor["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (descriptorName?.isEmpty == false ? descriptorName : nil) ?? directoryName
        var aliases = Set([name, directoryName])
        if let id = descriptor["id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            aliases.insert(id)
        }
        let homeURL = ["homeurl", "updateurl", "update.url"]
            .compactMap { key -> String? in
                guard let value = descriptor[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !value.isEmpty else { return nil }
                return value
            }
            .first
        return ComponentUpdateTarget(
            type: type,
            name: name,
            path: path,
            aliases: aliases,
            homeURL: homeURL
        )
    }

    private static func descriptorValues(at root: URL) -> [String: String] {
        let candidates = [
            root.appendingPathComponent("descript.txt"),
            root.appendingPathComponent("Contents/Resources/descript.txt")
        ]
        for candidate in candidates {
            if let values = LegacyDescriptor.readDictionary(from: candidate) {
                return values
            }
        }
        return [:]
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { return false }
        return values.isDirectory == true
    }
}
