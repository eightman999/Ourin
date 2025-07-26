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
