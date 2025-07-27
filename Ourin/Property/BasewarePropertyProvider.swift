import Foundation

/// `baseware.*` 系の値を提供するプロバイダ。
final class BasewarePropertyProvider: PropertyProvider {
    func get(key: String) -> String? {
        switch key {
        case "name":
            return "Ourin"
        case "version":
            if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                return v
            }
            return nil
        default:
            return nil
        }
    }
}
