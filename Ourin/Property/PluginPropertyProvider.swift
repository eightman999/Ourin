import Foundation

/// Represents a plugin entry for property system.
public struct PropertyPlugin {
    public let name: String
    public let path: String
    public let id: String
    public let craftmanw: String
    public let craftmanurl: String
    public let filename: String
    public let native: Bool
    public let localizedMessages: [String: [String: String]]
    /// native `.plugin` / `.bundle` の実パス。
    public let executablePath: String
    /// install.txt 付き package directory のパス（無い場合は nil）。
    public let packagePath: String?

    public init(name: String,
                path: String,
                id: String,
                craftmanw: String = "",
                craftmanurl: String = "",
                filename: String = "",
                native: Bool = true,
                localizedMessages: [String: [String: String]] = [:],
                executablePath: String? = nil,
                packagePath: String? = nil) {
        self.name = name
        self.path = path
        self.id = id
        self.craftmanw = craftmanw
        self.craftmanurl = craftmanurl
        self.filename = filename
        self.native = native
        self.localizedMessages = localizedMessages
        // executablePath が省略された場合は path（互換パス）と同じにする。
        self.executablePath = executablePath ?? path
        self.packagePath = packagePath
    }

    public func message(for key: String, language: String? = nil) -> String? {
        if let language {
            let normalized = normalizeLanguage(language)
            if let value = localizedMessages[normalized]?[key] {
                return value
            }
        }

        for preferred in Locale.preferredLanguages {
            let normalized = normalizeLanguage(preferred)
            if let value = localizedMessages[normalized]?[key] {
                return value
            }
        }

        return localizedMessages["japanese"]?[key]
            ?? localizedMessages["english"]?[key]
            ?? localizedMessages.values.lazy.compactMap { $0[key] }.first
    }

    private func normalizeLanguage(_ language: String) -> String {
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

/// Provides plugin-related properties for `pluginlist.*`.
final class PluginPropertyProvider: PropertyProvider {
    private let plugins: [PropertyPlugin]

    init(plugins: [PropertyPlugin] = []) {
        self.plugins = plugins
    }

    func get(key: String) -> String? {
        if key == "count" {
            return String(plugins.count)
        }

        // pluginlist(name/path/id).property
        if let (identifier, prop) = parseNamedAccess(key: key) {
            if let plugin = findPlugin(by: identifier) {
                let idx = plugins.firstIndex { $0.id == plugin.id && $0.path == plugin.path }
                return getPluginProperty(plugin, prop: prop, index: idx)
            }
        }

        // pluginlist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard plugins.indices.contains(index) else { return nil }
            return getPluginProperty(plugins[index], prop: prop, index: index)
        }

        return nil
    }

    // MARK: - Helpers

    private func getPluginProperty(_ plugin: PropertyPlugin, prop: String, index: Int? = nil) -> String? {
        switch prop {
        case "name":
            return plugin.name
        case "path":
            return plugin.path
        case "executablepath":
            return plugin.executablePath
        case "packagepath":
            return plugin.packagePath
        case "filename":
            return plugin.filename
        case "id":
            return plugin.id
        case "craftmanw":
            return plugin.craftmanw
        case "craftmanurl":
            return plugin.craftmanurl
        case "native":
            return plugin.native ? "1" : "0"
        case "index":
            return index.map(String.init)
        default:
            if prop.hasPrefix("message.") {
                return plugin.message(for: String(prop.dropFirst("message.".count)))
            }
            return nil
        }
    }

    private func findPlugin(by identifier: String) -> PropertyPlugin? {
        return plugins.first { p in
            p.name == identifier || p.path == identifier || p.id == identifier
        }
    }

    /// Parse `(identifier).property` format
    private func parseNamedAccess(key: String) -> (String, String)? {
        guard key.hasPrefix("("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 1)
        let identifier = String(key[start..<close])
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return (identifier, "") }
        let prop = String(rest.dropFirst())
        return (identifier, prop)
    }

    /// Parse `index(n).property` format
    private func parseIndex(key: String) -> (Int, String)? {
        guard key.hasPrefix("index("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 6)
        let idxString = String(key[start..<close])
        guard let idx = Int(idxString) else { return nil }
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        let prop = String(rest.dropFirst())
        return (idx, prop)
    }
}
