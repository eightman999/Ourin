import Foundation

/// インストール済みNARパッケージの情報
struct NarPackage: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let version: String
    let installPath: String
    let installDate: Date
    
    init(name: String, version: String = NSLocalizedString("不明", comment: "Unknown version"), installPath: String, installDate: Date = Date()) {
        self.name = name
        self.version = version
        self.installPath = installPath
        self.installDate = installDate
    }
}