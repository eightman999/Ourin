import Foundation

public final class SaoriRegistry {
    public private(set) var searchPaths: [URL]
    private var cache: [String: SaoriLoader] = [:]
    private let fm: FileManager

    public init(searchPaths: [URL] = [], fileManager: FileManager = .default) {
        self.fm = fileManager
        self.searchPaths = searchPaths.isEmpty ? Self.defaultSearchPaths() : searchPaths
    }

    public func setSearchPaths(_ paths: [URL]) {
        searchPaths = paths
    }

    public func addSearchPath(_ path: URL) {
        guard !searchPaths.contains(path) else { return }
        searchPaths.append(path)
    }

    public func discoverSaoriDirectory(under base: URL) {
        let candidates = [
            base.appendingPathComponent(".saori", isDirectory: true),
            base.appendingPathComponent("ghost/master/.saori", isDirectory: true),
            base.appendingPathComponent("ghost/master/saori", isDirectory: true)
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            addSearchPath(candidate)
        }
    }

    public func resolveModuleURL(named name: String) -> URL? {
        let variants = Self.normalizedModuleNames(for: name)
        for path in searchPaths {
            for variant in variants {
                let candidate = path.appendingPathComponent(variant)
                if fm.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    public func loadModule(named name: String) throws -> SaoriLoader {
        let key = cacheKey(for: name)
        if let cached = cache[key] {
            return cached
        }
        guard let url = resolveModuleURL(named: name) else {
            throw NSError(
                domain: "SaoriRegistry",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "SAORI module not found: \(name)"]
            )
        }
        let loader = try SaoriLoader(url: url)
        cache[key] = loader
        return loader
    }

    public func unloadModule(named name: String) {
        let key = cacheKey(for: name)
        guard let loader = cache.removeValue(forKey: key) else { return }
        loader.unload()
    }

    public func unloadAll() {
        for loader in cache.values {
            loader.unload()
        }
        cache.removeAll()
    }

    private func cacheKey(for name: String) -> String {
        URL(fileURLWithPath: name).lastPathComponent.lowercased()
    }

    private static func defaultSearchPaths() -> [URL] {
        var paths: [URL] = []
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(appSupport.appendingPathComponent("Ourin/saori", isDirectory: true))
        }
        if let appURL = Bundle.main.bundleURL as URL? {
            paths.append(appURL.appendingPathComponent("Contents/Resources/saori", isDirectory: true))
        }
        return paths
    }

    private static func normalizedModuleNames(for name: String) -> [String] {
        let base = URL(fileURLWithPath: name).lastPathComponent
        let stem: String
        if let dot = base.lastIndex(of: ".") {
            stem = String(base[..<dot])
        } else {
            stem = base
        }
        let variants = [
            base,
            "\(stem).dylib",
            "lib\(stem).dylib",
            "\(stem).so",
            "lib\(stem).so",
            "\(stem).bundle"
        ]
        return Array(NSOrderedSet(array: variants)) as? [String] ?? variants
    }
}
