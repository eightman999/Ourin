import Foundation

/// Named Windows SHIORI modules with a pinned macOS implementation bundled by Ourin.
enum BundledShioriEngine: String, CaseIterable {
    case kagari

    static func recognize(moduleName: String, ghostRoot: URL) -> Self? {
        let normalized = moduleName.replacingOccurrences(of: "\\", with: "/")
        let stem = URL(fileURLWithPath: normalized).deletingPathExtension().lastPathComponent.lowercased()
        return ["kagari", "libkagari"].contains(stem) ? .kagari : nil
    }

    /// A ghost-local macOS module takes precedence over the bundled engine.
    static func resolveModuleURL(moduleName: String, ghostURL: URL, ghostRoot: URL) -> URL? {
        if let local = ShioriLoader.find(name: moduleName, in: ShioriLoader.searchPaths(base: ghostURL)) { return local }
        guard let engine = recognize(moduleName: moduleName, ghostRoot: ghostRoot) else { return nil }
        return bundledURL(for: engine)
    }

    static func bundledURL(for engine: Self) -> URL? {
        if let override = ProcessInfo.processInfo.environment["OURIN_KAGARI_ENGINE"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        var directories: [URL] = []
        if let frameworks = Bundle.main.privateFrameworksURL { directories.append(frameworks) }
        if let executable = Bundle.main.executableURL {
            directories.append(executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks"))
        }
        if let resources = Bundle.main.resourceURL { directories.append(resources.appendingPathComponent("Engines")) }
        for directory in directories {
            for name in ["libkagari.dylib", "kagari.dylib", "libkagari.so"] {
                if let url = UkagakaModuleABI.resolveCaseInsensitive(name, in: directory) { return url }
            }
        }
        return nil
    }
}
