import Foundation

/// Represents a plugin entry for property system.
public struct PropertyPlugin {
    public let name: String
    public let path: String
    public let id: String
    public let craftmanw: String
    public let craftmanurl: String

    public init(name: String, path: String, id: String, craftmanw: String = "", craftmanurl: String = "") {
        self.name = name
        self.path = path
        self.id = id
        self.craftmanw = craftmanw
        self.craftmanurl = craftmanurl
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
                return getPluginProperty(plugin, prop: prop)
            }
        }

        // pluginlist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard plugins.indices.contains(index) else { return nil }
            return getPluginProperty(plugins[index], prop: prop)
        }

        return nil
    }

    // MARK: - Helpers

    private func getPluginProperty(_ plugin: PropertyPlugin, prop: String) -> String? {
        switch prop {
        case "name":
            return plugin.name
        case "path":
            return plugin.path
        case "id":
            return plugin.id
        case "craftmanw":
            return plugin.craftmanw
        case "craftmanurl":
            return plugin.craftmanurl
        default:
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
