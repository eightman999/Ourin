import Foundation

/// Parsed metadata from descript.txt
public struct PluginMeta {
    public let name: String
    public let id: String
    public let filename: String
    public let secondChangeInterval: Int?
    public let otherGhostTalk: Bool?
}

/// Registry for discovering and managing plugins
public final class PluginRegistry {
    public private(set) var plugins: [Plugin] = []
    public private(set) var metas: [Plugin: PluginMeta] = [:]

    public init() {}

    /// Discover plugin bundles and load them
    public func discoverAndLoad() {
        for dir in PluginRegistry.searchPaths() {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for item in items where item.pathExtension == "plugin" || item.pathExtension == "bundle" {
                do {
                    let plug = try Plugin(url: item)
                    if let load = plug.load {
                        _ = load(item.path)
                    }
                    plugins.append(plug)
                    if let meta = PluginRegistry.readMeta(from: plug.bundle) {
                        metas[plug] = meta
                    }
                } catch {
                    NSLog("Plugin load failed: \(error)")
                }
            }
        }
    }

    /// Unload all loaded plugins
    public func unloadAll() {
        for p in plugins { p.unload?() }
        plugins.removeAll()
        metas.removeAll()
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

    // MARK: Utilities
    private static func searchPaths() -> [URL] {
        var urls: [URL] = []
        if let builtIn = Bundle.main.builtInPlugInsURL {
            urls.append(builtIn)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(appSupport.appendingPathComponent("Ourin/PlugIns", isDirectory: true))
        }
        return urls
    }

    private static func readMeta(from bundle: Bundle) -> PluginMeta? {
        guard let url = bundle.url(forResource: "descript", withExtension: "txt") else { return nil }
        guard let raw = try? Data(contentsOf: url) else { return nil }
        // Determine charset using first line if available
        var encoding: String.Encoding = .utf8
        if let firstLine = String(data: raw, encoding: .utf8)?.split(whereSeparator: { $0.isNewline }).first {
            let lower = firstLine.lowercased()
            if lower.starts(with: "charset") {
                let value = lower.split(separator: ",", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
                if ["shift_jis", "windows-31j", "cp932", "ms932", "sjis"].contains(value) {
                    encoding = .shiftJIS
                }
            }
        }
        guard let text = String(data: raw, encoding: encoding) else { return nil }
        var name = ""
        var id = ""
        var filename = ""
        var second: Int? = nil
        var other: Bool? = nil
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "name": name = value
            case "id": id = value
            case "filename": filename = value
            case "secondchangeinterval": second = Int(value)
            case "otherghosttalk": other = (value == "true" || value == "1")
            default: break
            }
        }
        guard !name.isEmpty, !id.isEmpty, !filename.isEmpty else { return nil }
        return PluginMeta(name: name, id: id, filename: filename, secondChangeInterval: second, otherGhostTalk: other)
    }
}
