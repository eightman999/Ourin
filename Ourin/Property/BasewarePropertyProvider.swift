import Foundation

/// `baseware.*` 系の値を提供するプロバイダ。
final class BasewarePropertyProvider: PropertyProvider {
    func get(key: String) -> String? {
        let info = Bundle.main.infoDictionary
        switch key {
        case "name":
            return "Ourin"
        case "version":
            return info?["CFBundleShortVersionString"] as? String
        case "shortversion":
            return info?["CFBundleShortVersionString"] as? String
        case "build":
            return info?["CFBundleVersion"] as? String
        case "path":
            return Bundle.main.bundlePath
        case "rootpath", "ssp.rootpath":
            return try? OurinPaths.baseDirectory().path
        case "datapath", "data.path":
            return SSPCompat.dataDirectory()?.path
        case "temppath", "temp.path":
            return SSPCompat.tempDirectory()?.path
        case "profilepath", "profile.path":
            return SSPCompat.dataDirectory()?
                .appendingPathComponent("profile", isDirectory: true)
                .path
        case "calendarpath", "calendar.path":
            return try? OurinPaths.subdirectory("calendar").path
        case "calendar.skin.path":
            return try? OurinPaths.subdirectory("calendar")
                .appendingPathComponent("skin", isDirectory: true)
                .path
        case "calendar.plugin.path":
            return try? OurinPaths.subdirectory("calendar")
                .appendingPathComponent("plugin", isDirectory: true)
                .path
        case "mcp.path":
            return SSPCompat.executableURL(for: .mcp)?.path
        case "ssph.path":
            return SSPCompat.executableURL(for: .ssph)?.path
        case "ssp.path":
            return Bundle.main.bundlePath
        default:
            return nil
        }
    }
}
