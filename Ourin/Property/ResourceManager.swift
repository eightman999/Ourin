import Foundation
import AppKit

/// Manages SHIORI Resource values that should persist across sessions.
/// Based on https://ssp.shillest.net/ukadoc/manual/list_shiori_resource.html
///
/// SHIORI Resources are simple key-value pairs (not SakuraScript) that control
/// ghost behavior and store user preferences.
public final class ResourceManager {
    private let defaults: UserDefaults
    private let prefix = "OurinResource."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Generic Accessors

    /// Get a SHIORI resource value.
    public func get(_ key: String) -> String? {
        return defaults.string(forKey: prefix + key)
    }

    /// Set a SHIORI resource value.
    public func set(_ key: String, value: String) {
        defaults.set(value, forKey: prefix + key)
    }

    /// Remove a SHIORI resource value.
    public func remove(_ key: String) {
        defaults.removeObject(forKey: prefix + key)
    }

    // MARK: - Commonly Used Resources

    /// User's name (username resource)
    public var username: String? {
        get { get("username") }
        set { if let v = newValue { set("username", value: v) } else { remove("username") } }
    }

    /// Ghost home URL for updates (homeurl resource)
    public var homeurl: String? {
        get { get("homeurl") }
        set { if let v = newValue { set("homeurl", value: v) } else { remove("homeurl") } }
    }

    // MARK: - Character Position Resources

    /// Sakura (scope 0) default X position
    public var sakuraDefaultLeft: Int? {
        get { get("sakura.defaultleft").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaultleft", value: String(v)) } else { remove("sakura.defaultleft") } }
    }

    /// Sakura (scope 0) default Y position
    public var sakuraDefaultTop: Int? {
        get { get("sakura.defaulttop").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaulttop", value: String(v)) } else { remove("sakura.defaulttop") } }
    }

    /// Kero (scope 1) default X position
    public var keroDefaultLeft: Int? {
        get { get("kero.defaultleft").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaultleft", value: String(v)) } else { remove("kero.defaultleft") } }
    }

    /// Kero (scope 1) default Y position
    public var keroDefaultTop: Int? {
        get { get("kero.defaulttop").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaulttop", value: String(v)) } else { remove("kero.defaulttop") } }
    }

    /// Sakura base X coordinate
    public var sakuraDefaultX: Int? {
        get { get("sakura.defaultx").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaultx", value: String(v)) } else { remove("sakura.defaultx") } }
    }

    /// Sakura base Y coordinate
    public var sakuraDefaultY: Int? {
        get { get("sakura.defaulty").flatMap(Int.init) }
        set { if let v = newValue { set("sakura.defaulty", value: String(v)) } else { remove("sakura.defaulty") } }
    }

    /// Kero base X coordinate
    public var keroDefaultX: Int? {
        get { get("kero.defaultx").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaultx", value: String(v)) } else { remove("kero.defaultx") } }
    }

    /// Kero base Y coordinate
    public var keroDefaultY: Int? {
        get { get("kero.defaulty").flatMap(Int.init) }
        set { if let v = newValue { set("kero.defaulty", value: String(v)) } else { remove("kero.defaulty") } }
    }

    // MARK: - Character-specific positions (char*.default*)

    /// Get default left position for character at scope
    public func getCharDefaultLeft(scope: Int) -> Int? {
        switch scope {
        case 0: return sakuraDefaultLeft
        case 1: return keroDefaultLeft
        default: return get("char\(scope).defaultleft").flatMap(Int.init)
        }
    }

    /// Set default left position for character at scope
    public func setCharDefaultLeft(scope: Int, value: Int?) {
        let key = scope == 0 ? "sakura.defaultleft" : scope == 1 ? "kero.defaultleft" : "char\(scope).defaultleft"
        if let v = value { set(key, value: String(v)) } else { remove(key) }
    }

    /// Get default top position for character at scope
    public func getCharDefaultTop(scope: Int) -> Int? {
        switch scope {
        case 0: return sakuraDefaultTop
        case 1: return keroDefaultTop
        default: return get("char\(scope).defaulttop").flatMap(Int.init)
        }
    }

    /// Set default top position for character at scope
    public func setCharDefaultTop(scope: Int, value: Int?) {
        let key = scope == 0 ? "sakura.defaulttop" : scope == 1 ? "kero.defaulttop" : "char\(scope).defaulttop"
        if let v = value { set(key, value: String(v)) } else { remove(key) }
    }

    // MARK: - Update Configuration

    /// Whether to use 1-based file numbering for updates (useorigin1 resource)
    public var useOrigin1: Bool {
        get { get("useorigin1") == "1" }
        set { set("useorigin1", value: newValue ? "1" : "0") }
    }

    // MARK: - Helper Methods

    /// Save current window positions from GhostManager
    public func saveWindowPositions(from windows: [Int: NSWindow]) {
        for (scope, window) in windows {
            let frame = window.frame
            setCharDefaultLeft(scope: scope, value: Int(frame.origin.x))
            setCharDefaultTop(scope: scope, value: Int(frame.origin.y))
        }
    }

    /// Restore window positions to GhostManager windows
    public func restoreWindowPositions(to windows: [Int: NSWindow]) {
        for (scope, window) in windows {
            if let x = getCharDefaultLeft(scope: scope),
               let y = getCharDefaultTop(scope: scope) {
                var frame = window.frame
                frame.origin.x = CGFloat(x)
                frame.origin.y = CGFloat(y)
                window.setFrame(frame, display: false)
            }
        }
    }

    /// Clear all stored resources (for debugging/reset)
    public func clearAll() {
        let allKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}
