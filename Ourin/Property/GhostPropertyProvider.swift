import Foundation

/// Represents a ghost entry used for property values.
public struct Ghost {
    public let name: String
    public let sakuraname: String
    public let keroname: String
    public let craftmanw: String
    public let craftmanurl: String
    public let path: String
    public let icon: String
    public let homeurl: String
    public var username: String?
    public var configuration: GhostConfiguration?

    public init(name: String, sakuraname: String = "", keroname: String = "",
                craftmanw: String = "", craftmanurl: String = "",
                path: String, icon: String = "", homeurl: String = "", username: String? = nil,
                configuration: GhostConfiguration? = nil) {
        self.name = name
        self.sakuraname = sakuraname.isEmpty ? name : sakuraname
        self.keroname = keroname
        self.craftmanw = craftmanw
        self.craftmanurl = craftmanurl
        self.path = path
        self.icon = icon
        self.homeurl = homeurl
        self.username = username
        self.configuration = configuration
    }

    /// Initialize from a GhostConfiguration.
    public init(from config: GhostConfiguration, path: String, username: String? = nil) {
        self.name = config.name
        self.sakuraname = config.sakuraName
        self.keroname = config.keroName ?? ""
        self.craftmanw = config.craftmanw ?? ""
        self.craftmanurl = config.craftmanurl ?? ""
        self.path = path
        self.icon = config.icon ?? ""
        self.homeurl = config.homeurl ?? ""
        self.username = username
        self.configuration = config
    }
}

/// Represents a shell entry.
public struct Shell {
    public let name: String
    public let path: String
    public var menu: String // "hidden" or ""

    public init(name: String, path: String, menu: String = "") {
        self.name = name
        self.path = path
        self.menu = menu
    }
}

/// Provides ghost related properties such as `ghostlist.*`,
/// `activeghostlist.*` and `currentghost.*`.
final class GhostPropertyProvider: PropertyProvider {
    enum Mode {
        case ghostlist
        case activeghostlist
        case currentghost
    }

    private let mode: Mode
    private let ghosts: [Ghost]
    private let activeIndices: [Int]
    private var shells: [Shell]
    private var currentShellIndex: Int

    // Scope-related runtime data (for currentghost mode)
    private var scopeData: [Int: ScopeData]

    struct ScopeData {
        var surfaceNum: Int
        var surfaceX: Int
        var surfaceY: Int
        var x: Int
        var y: Int
        var rect: String  // "left,top,right,bottom"
        var name: String
        var defaultSurface: Int
    }

    init(mode: Mode, ghosts: [Ghost], activeIndices: [Int],
         shells: [Shell] = [], currentShellIndex: Int = 0,
         scopeData: [Int: ScopeData] = [:]) {
        self.mode = mode
        self.ghosts = ghosts
        self.activeIndices = activeIndices
        self.shells = shells
        self.currentShellIndex = currentShellIndex
        self.scopeData = scopeData
    }

    func get(key: String) -> String? {
        switch mode {
        case .ghostlist:
            return ghostlist(key: key)
        case .activeghostlist:
            return activeghostlist(key: key)
        case .currentghost:
            return currentghost(key: key)
        }
    }

    func set(key: String, value: String) -> Bool {
        guard mode == .currentghost else { return false }

        // Handle currentghost.shelllist(name).menu
        if key.hasPrefix("shelllist(") {
            if let (shellName, prop) = parseNamedAccess(key: key, prefix: "shelllist") {
                if prop == "menu", let idx = shells.firstIndex(where: { $0.name == shellName }) {
                    shells[idx].menu = value
                    return true
                }
            }
        }

        return false
    }

    // MARK: - ghostlist
    private func ghostlist(key: String) -> String? {
        if key == "count" {
            return String(ghosts.count)
        }

        // ghostlist(name/sakuraname/path).property
        if let (identifier, prop) = parseNamedAccess(key: key, prefix: "") {
            if let g = findGhost(by: identifier) {
                return getGhostProperty(g, prop: prop)
            }
        }

        // ghostlist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard ghosts.indices.contains(index) else { return nil }
            return getGhostProperty(ghosts[index], prop: prop)
        }

        return nil
    }

    // MARK: - activeghostlist
    private func activeghostlist(key: String) -> String? {
        if key == "count" {
            return String(activeIndices.count)
        }

        // activeghostlist(name/sakuraname/path).property
        if let (identifier, prop) = parseNamedAccess(key: key, prefix: "") {
            if let g = findActiveGhost(by: identifier) {
                return getGhostProperty(g, prop: prop)
            }
        }

        // activeghostlist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard activeIndices.indices.contains(index) else { return nil }
            return getGhostProperty(ghosts[activeIndices[index]], prop: prop)
        }

        return nil
    }

    // MARK: - currentghost
    private func currentghost(key: String) -> String? {
        guard let idx = activeIndices.first, ghosts.indices.contains(idx) else {
            return nil
        }
        let g = ghosts[idx]

        // Simple properties
        if let value = getGhostProperty(g, prop: key) {
            return value
        }

        // status
        if key == "status" {
            return "online"
        }

        // shelllist properties
        if key.hasPrefix("shelllist") {
            return handleShelllist(key: key)
        }

        // scope properties
        if key.hasPrefix("scope") {
            return handleScope(key: key)
        }

        return nil
    }

    // MARK: - Shell handling
    private func handleShelllist(key: String) -> String? {
        if key == "shelllist.count" {
            return String(shells.count)
        }

        if key == "shelllist.current.name" {
            guard shells.indices.contains(currentShellIndex) else { return nil }
            return shells[currentShellIndex].name
        }

        if key == "shelllist.current.path" {
            guard shells.indices.contains(currentShellIndex) else { return nil }
            return shells[currentShellIndex].path
        }

        if key == "shelllist.current.menu" {
            guard shells.indices.contains(currentShellIndex) else { return nil }
            return shells[currentShellIndex].menu
        }

        // shelllist(name/path).property
        if key.hasPrefix("shelllist(") {
            if let (identifier, prop) = parseNamedAccess(key: key, prefix: "shelllist") {
                if let shell = findShell(by: identifier) {
                    return getShellProperty(shell, prop: prop)
                }
            }
        }

        // shelllist.index(n).property
        if key.hasPrefix("shelllist.index(") {
            let subkey = String(key.dropFirst("shelllist.".count))
            if let (index, prop) = parseIndex(key: subkey) {
                guard shells.indices.contains(index) else { return nil }
                return getShellProperty(shells[index], prop: prop)
            }
        }

        return nil
    }

    // MARK: - Scope handling
    private func handleScope(key: String) -> String? {
        if key == "scope.count" {
            return String(scopeData.count)
        }

        // scope(n).property
        if key.hasPrefix("scope(") {
            if let (scopeId, prop) = parseScopeAccess(key: key) {
                guard let data = scopeData[scopeId] else { return nil }
                return getScopeProperty(data, prop: prop)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func getGhostProperty(_ ghost: Ghost, prop: String) -> String? {
        switch prop {
        case "name":
            return ghost.name
        case "sakuraname":
            return ghost.sakuraname
        case "keroname":
            return ghost.keroname
        case "craftmanw":
            return ghost.craftmanw
        case "craftmanurl":
            return ghost.craftmanurl
        case "path":
            return ghost.path
        case "icon":
            return ghost.icon
        case "homeurl":
            return ghost.homeurl
        case "username":
            return ghost.username
        default:
            return nil
        }
    }

    private func getShellProperty(_ shell: Shell, prop: String) -> String? {
        switch prop {
        case "name":
            return shell.name
        case "path":
            return shell.path
        case "menu":
            return shell.menu.isEmpty ? nil : shell.menu
        default:
            return nil
        }
    }

    private func getScopeProperty(_ scope: ScopeData, prop: String) -> String? {
        switch prop {
        case "surface.num":
            return String(scope.surfaceNum)
        case "seriko.defaultsurface":
            return String(scope.defaultSurface)
        case "surface.x":
            return String(scope.surfaceX)
        case "surface.y":
            return String(scope.surfaceY)
        case "x":
            return String(scope.x)
        case "y":
            return String(scope.y)
        case "rect":
            return scope.rect
        case "name":
            return scope.name
        default:
            return nil
        }
    }

    private func findGhost(by identifier: String) -> Ghost? {
        return ghosts.first { g in
            g.name == identifier || g.sakuraname == identifier || g.path == identifier
        }
    }

    private func findActiveGhost(by identifier: String) -> Ghost? {
        return activeIndices.compactMap { idx in
            ghosts.indices.contains(idx) ? ghosts[idx] : nil
        }.first { g in
            g.name == identifier || g.sakuraname == identifier || g.path == identifier
        }
    }

    private func findShell(by identifier: String) -> Shell? {
        return shells.first { s in
            s.name == identifier || s.path == identifier
        }
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

    /// Parse `(identifier).property` or `prefix(identifier).property` format
    private func parseNamedAccess(key: String, prefix: String) -> (String, String)? {
        let searchKey = prefix.isEmpty ? key : String(key.dropFirst(prefix.count))
        guard searchKey.hasPrefix("("), let close = searchKey.firstIndex(of: ")") else {
            return nil
        }
        let start = searchKey.index(searchKey.startIndex, offsetBy: 1)
        let identifier = String(searchKey[start..<close])
        let rest = String(searchKey[searchKey.index(after: close)...])
        guard rest.first == "." else { return (identifier, "") }
        let prop = String(rest.dropFirst())
        return (identifier, prop)
    }

    /// Parse `scope(n).property` format
    private func parseScopeAccess(key: String) -> (Int, String)? {
        guard key.hasPrefix("scope("), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: 6)
        let idString = String(key[start..<close])
        guard let scopeId = Int(idString) else { return nil }
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        let prop = String(rest.dropFirst())
        return (scopeId, prop)
    }
}
