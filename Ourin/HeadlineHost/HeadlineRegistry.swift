import Foundation

/// Parsed metadata from headline descript.txt
public struct HeadlineMeta {
    public let name: String
    public let filename: String
    public let url: String
    public let openurl: String
    public let charset: String.Encoding
}

/// Registry for discovering HEADLINE modules
public final class HeadlineRegistry {
    public private(set) var modules: [HeadlineModule] = []
    public private(set) var metas: [HeadlineModule: HeadlineMeta] = [:]

    public init() {}

    /// Discover bundles and load them
    public func discoverAndLoad() {
        for dir in HeadlineRegistry.searchPaths() {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for item in items where item.pathExtension == "plugin" || item.pathExtension == "bundle" {
                do {
                    let mod = try HeadlineModule(url: item)
                    if let load = mod.load {
                        _ = load(item.path)
                    }
                    modules.append(mod)
                    if let meta = HeadlineRegistry.readMeta(from: mod.bundle) {
                        metas[mod] = meta
                    }
                } catch {
                    NSLog("Headline module load failed: \(error)")
                }
            }
        }
    }

    public func unloadAll() {
        for m in modules { m.unload?() }
        modules.removeAll()
        metas.removeAll()
    }

    // MARK: - Utilities
    private static func searchPaths() -> [URL] {
        var urls: [URL] = []
        if let builtIn = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Headline", isDirectory: true) {
            urls.append(builtIn)
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(appSupport.appendingPathComponent("Ourin/Headline", isDirectory: true))
        }
        return urls
    }

    private static func readMeta(from bundle: Bundle) -> HeadlineMeta? {
        guard let url = bundle.url(forResource: "descript", withExtension: "txt") else { return nil }
        guard let raw = try? Data(contentsOf: url) else { return nil }
        // determine charset
        var encoding: String.Encoding = .utf8
        if let first = String(data: raw.prefix(128), encoding: .utf8)?.split(whereSeparator: { $0.isNewline }).first {
            let lower = first.lowercased()
            if lower.starts(with: "charset") {
                let value = lower.split(separator: ",", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
                if ["shift_jis","windows-31j","cp932","ms932","sjis"].contains(value) {
                    encoding = .shiftJIS
                }
            }
        }
        guard let text = String(data: raw, encoding: encoding) else { return nil }
        var name = ""
        var filename = ""
        var dllname = ""
        var urlStr = ""
        var openurl = ""
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "name": name = value
            case "filename": filename = value
            case "dllname": dllname = value
            case "url": urlStr = value
            case "openurl": openurl = value
            case "charset":
                if ["shift_jis","windows-31j","cp932","ms932","sjis"].contains(value.lowercased()) {
                    encoding = .shiftJIS
                }
            default: break
            }
        }
        // Prefer filename over dllname (2.0M spec), but accept dllname for 2.0 compatibility
        let finalFilename = !filename.isEmpty ? filename : dllname
        guard !name.isEmpty, !finalFilename.isEmpty else { return nil }
        return HeadlineMeta(name: name, filename: finalFilename, url: urlStr, openurl: openurl, charset: encoding)
    }
}
