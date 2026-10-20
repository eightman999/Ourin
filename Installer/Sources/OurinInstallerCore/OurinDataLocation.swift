import Foundation

/// Ourin のデータ置き場（本体の `OurinPaths.baseDirectory()` と同じ規則）。
///
/// 本番は `~/Documents/Ourin`。Documents が使えなければ
/// `~/Library/Application Support/Ourin` へフォールバックする。
public struct OurinDataLocation: Equatable {
    public let base: URL

    public init(base: URL) {
        self.base = base
    }

    public static func resolve(fileManager fm: FileManager = .default) throws -> OurinDataLocation {
        if let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let base = docs.appendingPathComponent("Ourin", isDirectory: true)
            if (try? fm.createDirectory(at: base, withIntermediateDirectories: true)) != nil {
                return OurinDataLocation(base: base)
            }
        }
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let base = appSupport.appendingPathComponent("Ourin", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return OurinDataLocation(base: base)
    }

    public var ghostDirectory: URL { base.appendingPathComponent("ghost", isDirectory: true) }
    public var balloonDirectory: URL { base.appendingPathComponent("balloon", isDirectory: true) }

    /// インストール済みゴーストのディレクトリ名（Ourin の起動ゴースト設定はこの名前で引く）。
    public func installedGhostDirectories(fileManager fm: FileManager = .default) -> [String] {
        let children = (try? fm.contentsOfDirectory(at: ghostDirectory,
                                                    includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }
}
