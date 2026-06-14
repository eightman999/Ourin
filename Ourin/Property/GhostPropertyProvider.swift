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
    // PROPERTY/1.0M §4.12 汎用プロパティ名（未設定時は空 → nil 相当）
    public var thumbnail: String
    public var updateResult: String
    public var updateTime: String
    /// `shiori.<変数名>` で参照する SHIORI 由来の値（必要に応じて外部から設定）
    public var shioriVars: [String: String]

    public init(name: String, sakuraname: String = "", keroname: String = "",
                craftmanw: String = "", craftmanurl: String = "",
                path: String, icon: String = "", homeurl: String = "", username: String? = nil,
                configuration: GhostConfiguration? = nil,
                thumbnail: String = "", updateResult: String = "", updateTime: String = "",
                shioriVars: [String: String] = [:]) {
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
        self.thumbnail = thumbnail
        self.updateResult = updateResult
        self.updateTime = updateTime
        self.shioriVars = shioriVars
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
        self.thumbnail = ""
        self.updateResult = ""
        self.updateTime = ""
        self.shioriVars = [:]
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
    private var mouseCursor: [String: String]
    private var balloonMouseCursor: [String: String]
    // SERIKO カーソルは scope → リスト種別(mouseup/down/hover/wheel) → 名前 → パス
    private var serikoCursor: [Int: [String: [String: String]]]
    private var serikoTooltips: [Int: [String: String]]

    /// PROPERTY/1.0M の `mouse????list` 4種（当たり判定リスト）
    private static let cursorListKinds = ["mouseuplist", "mousedownlist", "mousehoverlist", "mousewheellist"]
    private var serikoSurfaceListAll: String
    private var serikoSurfaceListDefined: String
    /// `(sakura|kero|char*).bind.menu` のメニュー表示状態（currentghost の runtime 状態、SET 可）
    private var bindMenus: [String: String] = [:]

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
         scopeData: [Int: ScopeData] = [:],
         mouseCursor: [String: String] = [:],
         balloonMouseCursor: [String: String] = [:],
         serikoCursor: [Int: [String: [String: String]]] = [:],
         serikoTooltips: [Int: [String: String]] = [:],
         serikoSurfaceListAll: String = "",
         serikoSurfaceListDefined: String = "") {
        self.mode = mode
        self.ghosts = ghosts
        self.activeIndices = activeIndices
        self.shells = shells
        self.currentShellIndex = currentShellIndex
        self.scopeData = scopeData
        self.mouseCursor = mouseCursor
        self.balloonMouseCursor = balloonMouseCursor
        self.serikoCursor = serikoCursor
        self.serikoTooltips = serikoTooltips
        self.serikoSurfaceListAll = serikoSurfaceListAll
        self.serikoSurfaceListDefined = serikoSurfaceListDefined
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

        if key.hasPrefix("mousecursor.") {
            let subKey = String(key.dropFirst("mousecursor.".count))
            mouseCursor[subKey] = value
            return true
        }

        if key.hasPrefix("balloon.mousecursor.") {
            let subKey = String(key.dropFirst("balloon.mousecursor.".count))
            balloonMouseCursor[subKey] = value
            return true
        }

        if key.hasPrefix("seriko.tooltip.scope(") {
            return setSerikoTooltip(key: key, value: value)
        }

        if key.hasPrefix("seriko.cursor.scope(") {
            return setSerikoCursor(key: key, value: value)
        }

        // (sakura|kero|char*).bind.menu の表示状態（SET 有効：PROPERTY/1.0M §5）
        if key.hasSuffix(".bind.menu") {
            let scope = String(key.dropLast(".bind.menu".count))
            if scope == "sakura" || scope == "kero" || scope.hasPrefix("char") {
                bindMenus[scope] = value
                return true
            }
        }

        return false
    }

    func writableProperties() -> [String] {
        guard mode == .currentghost else { return [] }
        var props: [String] = []
        for shell in shells {
            props.append("shelllist(\(shell.name)).menu")
        }
        props.append(contentsOf: [
            "mousecursor.text",
            "mousecursor.wait",
            "mousecursor.hand",
            "mousecursor.grip",
            "mousecursor.arrow",
            "balloon.mousecursor.text",
            "balloon.mousecursor.wait",
            "balloon.mousecursor.arrow",
            "sakura.bind.menu",
            "kero.bind.menu"
        ])
        return props
    }

    // MARK: - ghostlist
    private func ghostlist(key: String) -> String? {
        if key == "count" {
            return String(ghosts.count)
        }

        // ghostlist(name/sakuraname/path).property
        if let (identifier, prop) = parseNamedAccess(key: key, prefix: "") {
            if let g = findGhost(by: identifier) {
                let idx = ghosts.firstIndex { $0.name == g.name && $0.path == g.path }
                return getGhostProperty(g, prop: prop, index: idx)
            }
        }

        // ghostlist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard ghosts.indices.contains(index) else { return nil }
            return getGhostProperty(ghosts[index], prop: prop, index: index)
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
                let idx = activeIndices.firstIndex { ghosts.indices.contains($0) && ghosts[$0].name == g.name && ghosts[$0].path == g.path }
                return getGhostProperty(g, prop: prop, index: idx)
            }
        }

        // activeghostlist.index(n).property
        if let (index, prop) = parseIndex(key: key) {
            guard activeIndices.indices.contains(index) else { return nil }
            return getGhostProperty(ghosts[activeIndices[index]], prop: prop, index: index)
        }

        return nil
    }

    // MARK: - currentghost
    private func currentghost(key: String) -> String? {
        if key == "status" {
            return ShioriStatusStore.shared.currentStatus
        }

        guard let idx = activeIndices.first, ghosts.indices.contains(idx) else {
            return nil
        }
        let g = ghosts[idx]

        // Simple properties（汎用名・index・shiori.<var>・*.bind.menu を含む）
        if let value = getGhostProperty(g, prop: key, index: idx) {
            return value
        }

        // shelllist properties
        if key.hasPrefix("shelllist") {
            return handleShelllist(key: key)
        }

        // scope properties
        if key.hasPrefix("scope") {
            return handleScope(key: key)
        }

        if key.hasPrefix("mousecursor.") {
            let subKey = String(key.dropFirst("mousecursor.".count))
            return mouseCursor[subKey]
        }

        if key.hasPrefix("balloon.mousecursor.") {
            let subKey = String(key.dropFirst("balloon.mousecursor.".count))
            return balloonMouseCursor[subKey]
        }

        if key == "seriko.surfacelist.all" {
            return serikoSurfaceListAll.isEmpty ? nil : serikoSurfaceListAll
        }

        if key == "seriko.surfacelist.defined" {
            return serikoSurfaceListDefined.isEmpty ? nil : serikoSurfaceListDefined
        }

        if key.hasPrefix("seriko.tooltip.scope(") {
            return getSerikoTooltip(key: key)
        }

        if key.hasPrefix("seriko.cursor.scope(") {
            return getSerikoCursor(key: key)
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

    /// 汎用プロパティ名を解決する（PROPERTY/1.0M §4.12）。
    /// - Parameter index: `index` プロパティ用のリスト内順位（不明なら nil）。
    private func getGhostProperty(_ ghost: Ghost, prop: String, index: Int? = nil) -> String? {
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
        case "thumbnail":
            return ghost.thumbnail.isEmpty ? nil : ghost.thumbnail
        case "update_result":
            return ghost.updateResult.isEmpty ? nil : ghost.updateResult
        case "update_time":
            return ghost.updateTime.isEmpty ? nil : ghost.updateTime
        case "index":
            return index.map(String.init)
        default:
            // shiori.<変数名>
            if prop.hasPrefix("shiori.") {
                let varName = String(prop.dropFirst("shiori.".count))
                return ghost.shioriVars[varName]
            }
            // (sakura|kero|char*).bind.menu : currentghost の runtime 状態（bindMenus）から解決
            if prop.hasSuffix(".bind.menu") {
                let scope = String(prop.dropLast(".bind.menu".count))
                return bindMenus[scope]
            }
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

    private func getSerikoTooltip(key: String) -> String? {
        // seriko.tooltip.scope(ID).textlist(...)
        guard let (scopeID, scopeTail) = parseScopePrefix(key: key, prefix: "seriko.tooltip.scope") else {
            return nil
        }
        let list = serikoTooltips[scopeID] ?? [:]
        if scopeTail == "textlist.count" {
            return String(list.count)
        }

        if let (name, prop) = parseNamedAccess(key: scopeTail, prefix: "textlist") {
            switch prop {
            case "text":
                return list[name]
            case "name":
                return name
            default:
                return nil
            }
        }

        if scopeTail.hasPrefix("textlist.index(") {
            let sub = String(scopeTail.dropFirst("textlist.".count))
            if let (idx, prop) = parseIndex(key: sub) {
                let names = list.keys.sorted()
                guard names.indices.contains(idx) else { return nil }
                let name = names[idx]
                if prop == "name" { return name }
                if prop == "text" { return list[name] }
            }
        }
        return nil
    }

    private func getSerikoCursor(key: String) -> String? {
        // seriko.cursor.scope(ID).mouse????list(...)  (???? = up / down / hover / wheel)
        guard let (scopeID, scopeTail) = parseScopePrefix(key: key, prefix: "seriko.cursor.scope") else {
            return nil
        }
        guard let listName = Self.cursorListKinds.first(where: {
            scopeTail == "\($0).count" || scopeTail.hasPrefix("\($0)(") || scopeTail.hasPrefix("\($0).index(")
        }) else {
            return nil
        }
        let list = serikoCursor[scopeID]?[listName] ?? [:]
        if scopeTail == "\(listName).count" {
            return String(list.count)
        }

        if let (name, prop) = parseNamedAccess(key: scopeTail, prefix: listName) {
            switch prop {
            case "path":
                return list[name]
            case "name":
                return name
            default:
                return nil
            }
        }

        if scopeTail.hasPrefix("\(listName).index(") {
            let sub = String(scopeTail.dropFirst("\(listName).".count))
            if let (idx, prop) = parseIndex(key: sub) {
                let names = list.keys.sorted()
                guard names.indices.contains(idx) else { return nil }
                let name = names[idx]
                if prop == "name" { return name }
                if prop == "path" { return list[name] }
            }
        }
        return nil
    }

    private func setSerikoTooltip(key: String, value: String) -> Bool {
        guard let (scopeID, scopeTail) = parseScopePrefix(key: key, prefix: "seriko.tooltip.scope") else {
            return false
        }
        guard let (name, prop) = parseNamedAccess(key: scopeTail, prefix: "textlist"), prop == "text" else {
            return false
        }
        var tooltips = serikoTooltips[scopeID] ?? [:]
        if value.isEmpty {
            tooltips.removeValue(forKey: name)
        } else {
            tooltips[name] = value
        }
        serikoTooltips[scopeID] = tooltips
        return true
    }

    private func setSerikoCursor(key: String, value: String) -> Bool {
        guard let (scopeID, scopeTail) = parseScopePrefix(key: key, prefix: "seriko.cursor.scope") else {
            return false
        }
        guard let listName = Self.cursorListKinds.first(where: { scopeTail.hasPrefix("\($0)(") }) else {
            return false
        }
        guard let (name, prop) = parseNamedAccess(key: scopeTail, prefix: listName), prop == "path" else {
            return false
        }
        var byKind = serikoCursor[scopeID] ?? [:]
        var cursors = byKind[listName] ?? [:]
        if value.isEmpty {
            cursors.removeValue(forKey: name)
        } else {
            cursors[name] = value
        }
        // 空になった種別は削除し、scope ごと空なら除去（PROPERTY/1.0M: 空文字で定義削除）
        if cursors.isEmpty {
            byKind.removeValue(forKey: listName)
        } else {
            byKind[listName] = cursors
        }
        serikoCursor[scopeID] = byKind.isEmpty ? nil : byKind
        return true
    }

    private func parseScopePrefix(key: String, prefix: String) -> (Int, String)? {
        let expected = "\(prefix)("
        guard key.hasPrefix(expected), let close = key.firstIndex(of: ")") else {
            return nil
        }
        let start = key.index(key.startIndex, offsetBy: expected.count)
        guard let scopeID = Int(String(key[start..<close])) else { return nil }
        let rest = String(key[key.index(after: close)...])
        guard rest.first == "." else { return nil }
        return (scopeID, String(rest.dropFirst()))
    }
}
