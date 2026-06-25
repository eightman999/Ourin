import Foundation

final class CalendarSkinPropertyProvider: PropertyProvider {
    private let skins: [CalendarSkin]

    init(skins: [CalendarSkin]) {
        self.skins = skins
    }

    func get(key: String) -> String? {
        if key == "count" {
            return String(skins.count)
        }
        if let (index, prop) = parseIndex(key: key) {
            guard skins.indices.contains(index) else { return nil }
            return value(for: skins[index], prop: prop, index: index)
        }
        if let (identifier, prop) = parseNamedAccess(key: key),
           let skin = skins.first(where: { $0.name == identifier || $0.path.path == identifier || $0.path.lastPathComponent == identifier }) {
            let idx = skins.firstIndex { $0.path == skin.path }
            return value(for: skin, prop: prop, index: idx)
        }
        return nil
    }

    private func value(for skin: CalendarSkin, prop: String, index: Int?) -> String? {
        switch prop {
        case "name": return skin.name
        case "path": return skin.path.path
        case "index": return index.map(String.init)
        case "background.filename":
            return skin.descriptor["background.filename"].map { assetPath(named: $0, under: skin.path) }
        case "icon.count":
            return String(skin.iconMap.count)
        default:
            if let iconName = prop.stripPrefix("icon(")?.dropSuffix(").filename") {
                return skin.iconMap[String(iconName).lowercased()].map { assetPath(named: $0, under: skin.path) }
            }
            return skin.descriptor[prop]
        }
    }
}

private func assetPath(named name: String, under directory: URL) -> String {
    let filename = URL(fileURLWithPath: name).pathExtension.isEmpty ? "\(name).png" : name
    return directory.appendingPathComponent(filename).path
}

final class CalendarPluginPropertyProvider: PropertyProvider {
    private let plugins: [CalendarPluginMeta]

    init(plugins: [CalendarPluginMeta]) {
        self.plugins = plugins
    }

    func get(key: String) -> String? {
        if key == "count" {
            return String(plugins.count)
        }
        if let (index, prop) = parseIndex(key: key) {
            guard plugins.indices.contains(index) else { return nil }
            return value(for: plugins[index], prop: prop, index: index)
        }
        if let (identifier, prop) = parseNamedAccess(key: key),
           let plugin = plugins.first(where: { $0.name == identifier || $0.id == identifier || $0.filename == identifier || $0.path.path == identifier }) {
            let idx = plugins.firstIndex { $0.path == plugin.path }
            return value(for: plugin, prop: prop, index: idx)
        }
        return nil
    }

    private func value(for plugin: CalendarPluginMeta, prop: String, index: Int?) -> String? {
        switch prop {
        case "name": return plugin.name
        case "id": return plugin.id
        case "filename": return plugin.filename
        case "path": return plugin.path.appendingPathComponent(plugin.filename).path
        case "directory", "directory.path": return plugin.path.path
        case "post": return plugin.post
        case "index": return index.map(String.init)
        default: return nil
        }
    }
}

private func parseIndex(key: String) -> (Int, String)? {
    guard key.hasPrefix("index("), let close = key.firstIndex(of: ")") else {
        return nil
    }
    let start = key.index(key.startIndex, offsetBy: 6)
    guard let idx = Int(key[start..<close]) else { return nil }
    let rest = String(key[key.index(after: close)...])
    guard rest.first == "." else { return nil }
    return (idx, String(rest.dropFirst()))
}

private func parseNamedAccess(key: String) -> (String, String)? {
    guard key.hasPrefix("("), let close = key.firstIndex(of: ")") else {
        return nil
    }
    let identifier = String(key[key.index(after: key.startIndex)..<close])
    let rest = String(key[key.index(after: close)...])
    guard rest.first == "." else { return (identifier, "") }
    return (identifier, String(rest.dropFirst()))
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    func dropSuffix(_ suffix: String) -> String? {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : nil
    }
}
