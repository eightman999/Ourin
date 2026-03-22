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
        default:
            return nil
        }
    }
}
