import Foundation

/// Entry for rateofuselist.* properties.
public struct RateOfUseEntry {
    public let name: String
    public let sakuraname: String
    public let keroname: String
    public let boottime: Int
    public let bootminute: Int
    public let percent: Int

    public init(name: String, sakuraname: String = "", keroname: String = "",
                boottime: Int = 0, bootminute: Int = 0, percent: Int = 0) {
        self.name = name
        self.sakuraname = sakuraname.isEmpty ? name : sakuraname
        self.keroname = keroname
        self.boottime = boottime
        self.bootminute = bootminute
        self.percent = percent
    }
}

/// Provides history.* properties.
/// Supported keys:
/// - history.ghost.count / history.ghost(name|path).prop / history.ghost.index(n).prop
/// - history.balloon.count / history.balloon(name|path).prop / history.balloon.index(n).prop
/// - history.headline.count / history.headline(name|path).prop / history.headline.index(n).prop
/// - history.plugin.count / history.plugin(name|path|id).prop / history.plugin.index(n).prop
final class HistoryPropertyProvider: PropertyProvider {
    private let ghosts: [Ghost]
    private let balloons: [Balloon]
    private let headlines: [Headline]
    private let plugins: [PropertyPlugin]

    init(ghosts: [Ghost] = [], balloons: [Balloon] = [],
         headlines: [Headline] = [], plugins: [PropertyPlugin] = []) {
        self.ghosts = ghosts
        self.balloons = balloons
        self.headlines = headlines
        self.plugins = plugins
    }

    func get(key: String) -> String? {
        if key == "ghost.count" { return String(ghosts.count) }
        if key == "balloon.count" { return String(balloons.count) }
        if key == "headline.count" { return String(headlines.count) }
        if key == "plugin.count" { return String(plugins.count) }

        if let (index, prop) = parseIndexAccess(key: key, listName: "ghost"), ghosts.indices.contains(index) {
            return ghostProperty(ghosts[index], prop: prop)
        }
        if let (index, prop) = parseIndexAccess(key: key, listName: "balloon"), balloons.indices.contains(index) {
            return balloonProperty(balloons[index], prop: prop)
        }
        if let (index, prop) = parseIndexAccess(key: key, listName: "headline"), headlines.indices.contains(index) {
            return headlineProperty(headlines[index], prop: prop)
        }
        if let (index, prop) = parseIndexAccess(key: key, listName: "plugin"), plugins.indices.contains(index) {
            return pluginProperty(plugins[index], prop: prop)
        }

        if let (identifier, prop) = parseNamedAccess(key: key, listName: "ghost"),
           let ghost = ghosts.first(where: { $0.name == identifier || $0.path == identifier }) {
            return ghostProperty(ghost, prop: prop)
        }
        if let (identifier, prop) = parseNamedAccess(key: key, listName: "balloon"),
           let balloon = balloons.first(where: { $0.name == identifier || $0.path == identifier }) {
            return balloonProperty(balloon, prop: prop)
        }
        if let (identifier, prop) = parseNamedAccess(key: key, listName: "headline"),
           let headline = headlines.first(where: { $0.name == identifier || $0.path == identifier }) {
            return headlineProperty(headline, prop: prop)
        }
        if let (identifier, prop) = parseNamedAccess(key: key, listName: "plugin"),
           let plugin = plugins.first(where: { $0.name == identifier || $0.path == identifier || $0.id == identifier }) {
            return pluginProperty(plugin, prop: prop)
        }

        return nil
    }

    private func ghostProperty(_ ghost: Ghost, prop: String) -> String? {
        switch prop {
        case "name": return ghost.name
        case "sakuraname": return ghost.sakuraname
        case "keroname": return ghost.keroname
        case "craftmanw": return ghost.craftmanw
        case "craftmanurl": return ghost.craftmanurl
        case "path": return ghost.path
        case "icon": return ghost.icon
        case "homeurl": return ghost.homeurl
        case "username": return ghost.username
        default: return nil
        }
    }

    private func balloonProperty(_ balloon: Balloon, prop: String) -> String? {
        switch prop {
        case "name": return balloon.name
        case "path": return balloon.path
        case "craftmanw": return balloon.craftmanw
        case "craftmanurl": return balloon.craftmanurl
        default: return nil
        }
    }

    private func headlineProperty(_ headline: Headline, prop: String) -> String? {
        switch prop {
        case "name": return headline.name
        case "path": return headline.path
        case "craftmanw": return headline.craftmanw
        case "craftmanurl": return headline.craftmanurl
        default: return nil
        }
    }

    private func pluginProperty(_ plugin: PropertyPlugin, prop: String) -> String? {
        switch prop {
        case "name": return plugin.name
        case "path": return plugin.path
        case "id": return plugin.id
        case "craftmanw": return plugin.craftmanw
        case "craftmanurl": return plugin.craftmanurl
        default: return nil
        }
    }

    private func parseNamedAccess(key: String, listName: String) -> (identifier: String, prop: String)? {
        let prefix = "\(listName)("
        guard key.hasPrefix(prefix), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: prefix.count)
        let identifier = String(key[start..<close])
        let tail = String(key[key.index(after: close)...])
        guard tail.first == "." else { return nil }
        return (identifier, String(tail.dropFirst()))
    }

    private func parseIndexAccess(key: String, listName: String) -> (index: Int, prop: String)? {
        let prefix = "\(listName).index("
        guard key.hasPrefix(prefix), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: prefix.count)
        guard let index = Int(String(key[start..<close])) else { return nil }
        let tail = String(key[key.index(after: close)...])
        guard tail.first == "." else { return nil }
        return (index, String(tail.dropFirst()))
    }
}

/// Provides rateofuselist.* properties.
/// Supported keys:
/// - rateofuselist.count
/// - rateofuselist(name).prop
/// - rateofuselist.index(n).prop
final class RateOfUsePropertyProvider: PropertyProvider {
    private let entries: [RateOfUseEntry]

    init(entries: [RateOfUseEntry] = []) {
        self.entries = entries
    }

    func get(key: String) -> String? {
        if key == "count" {
            return String(entries.count)
        }

        if let (index, prop) = parseIndex(key: key), entries.indices.contains(index) {
            return value(entries[index], prop: prop)
        }

        if let (name, prop) = parseNamedAccess(key: key),
           let entry = entries.first(where: { $0.name == name || $0.sakuraname == name }) {
            return value(entry, prop: prop)
        }

        return nil
    }

    private func value(_ entry: RateOfUseEntry, prop: String) -> String? {
        switch prop {
        case "name": return entry.name
        case "sakuraname": return entry.sakuraname
        case "keroname": return entry.keroname
        case "boottime": return String(entry.boottime)
        case "bootminute": return String(entry.bootminute)
        case "percent": return String(entry.percent)
        default: return nil
        }
    }

    private func parseNamedAccess(key: String) -> (String, String)? {
        guard key.hasPrefix("("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 1)
        let name = String(key[start..<close])
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        return (name, String(rest.dropFirst()))
    }

    private func parseIndex(key: String) -> (Int, String)? {
        guard key.hasPrefix("index("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 6)
        guard let idx = Int(String(key[start..<close])) else { return nil }
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        return (idx, String(rest.dropFirst()))
    }
}
