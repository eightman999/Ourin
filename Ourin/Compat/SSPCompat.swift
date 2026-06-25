import Foundation

enum SSPCompat {
    enum ExecutableKind: String {
        case mcp = "mcp.exe"
        case ssph = "ssph.exe"
        case ssp = "ssp.exe"
    }

    static let windowsRootAliases: Set<String> = ["ssp", "ourin"]
    static let rootSubfolders: Set<String> = [
        "ghost", "balloon", "plugin", "headline",
        "calendar", "data", "temp", "package", "saori"
    ]

    static func dataDirectory() -> URL? {
        try? OurinPaths.subdirectory("data")
    }

    static func executableURL(for kind: ExecutableKind) -> URL? {
        guard let dataDir = dataDirectory() else { return nil }
        let preferredName: String
        switch kind {
        case .mcp:
            preferredName = "mcp.exe"
        case .ssph:
            preferredName = "SSPH.exe"
        case .ssp:
            return Bundle.main.bundleURL
        }
        let preferred = dataDir.appendingPathComponent(preferredName)
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }
        return dataDir.appendingPathComponent(kind.rawValue)
    }

    static func tempDirectory() -> URL? {
        try? OurinPaths.subdirectory("temp")
    }

    static func executableKind(for url: URL) -> ExecutableKind? {
        ExecutableKind(rawValue: url.lastPathComponent.lowercased())
    }

    static func executableKind(forRawPath rawPath: String) -> ExecutableKind? {
        let last = normalizedPathString(rawPath)
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map { String($0).lowercased() }
        guard let last else { return nil }
        return ExecutableKind(rawValue: last)
    }

    static func resolvePath(_ rawPath: String, relativeTo relativeBase: URL?) -> URL {
        let expanded = expandWindowsEnvironment(in: rawPath)
        let normalized = normalizedPathString(expanded)

        if normalized.hasPrefix("file://"), let url = URL(string: normalized) {
            return url
        }

        if let base = try? OurinPaths.baseDirectory(),
           let rootRelative = stripWindowsRootAlias(from: normalized) {
            return base.appendingPathComponent(rootRelative)
        }

        if let base = try? OurinPaths.baseDirectory(),
           let first = normalized.split(separator: "/", omittingEmptySubsequences: true).first?.lowercased(),
           rootSubfolders.contains(String(first)) {
            return base.appendingPathComponent(normalized)
        }

        if let kind = executableKind(forRawPath: normalized),
           kind != .ssp {
            return executableURL(for: kind) ?? URL(fileURLWithPath: normalized)
        }

        if normalized.hasPrefix("/") {
            return URL(fileURLWithPath: normalized)
        }

        return (relativeBase ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .appendingPathComponent(normalized)
    }

    static func knownDataFile(_ relativePath: String) -> URL? {
        guard let dataDir = dataDirectory() else { return nil }
        let normalized = normalizedPathString(relativePath)
        guard !normalized.hasPrefix("/"), !normalized.contains("../") else { return nil }
        return dataDir.appendingPathComponent(normalized)
    }

    private static func normalizedPathString(_ rawPath: String) -> String {
        rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
    }

    private static func stripWindowsRootAlias(from path: String) -> String? {
        let withoutDrive: String
        if path.count >= 3,
           path[path.index(path.startIndex, offsetBy: 1)] == ":",
           path[path.index(path.startIndex, offsetBy: 2)] == "/" {
            withoutDrive = String(path.dropFirst(3))
        } else if path.hasPrefix("/") {
            withoutDrive = String(path.drop { $0 == "/" })
        } else {
            return nil
        }

        let parts = withoutDrive.split(separator: "/", omittingEmptySubsequences: true)
        guard let first = parts.first?.lowercased(), windowsRootAliases.contains(String(first)) else {
            return nil
        }
        return parts.dropFirst().joined(separator: "/")
    }

    private static func expandWindowsEnvironment(in path: String) -> String {
        var result = path
        let replacements: [String: String] = [
            "%TEMP%": tempDirectory()?.path ?? NSTemporaryDirectory(),
            "%TMP%": tempDirectory()?.path ?? NSTemporaryDirectory(),
            "%USERPROFILE%": FileManager.default.homeDirectoryForCurrentUser.path,
            "%APPDATA%": (try? OurinPaths.baseDirectory().path) ?? FileManager.default.homeDirectoryForCurrentUser.path,
            "%COMSPEC%": "/bin/zsh",
            "%SYSTEMROOT%": "/System",
            "%SYSTEM%": "/System"
        ]
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value, options: [.caseInsensitive])
        }
        return result
    }
}
