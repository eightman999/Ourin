import Foundation

/// Ourin 本体の UserDefaults（`furin-lab.Ourin` ドメイン）への最小限の書き込み。
public struct OurinPreferences {
    public static let bundleIdentifier = "furin-lab.Ourin"
    /// 本体が起動時に読むキー（値はゴーストのディレクトリ名）。OurinApp.swift と同じ。
    public static let startupGhostKey = "OurinStartupGhost"

    let defaults: UserDefaults

    public init?(suiteName: String = OurinPreferences.bundleIdentifier) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        self.defaults = defaults
    }

    public var startupGhost: String? {
        defaults.string(forKey: Self.startupGhostKey)
    }

    /// 起動ゴーストを設定する。nil なら設定を消し、本体既定（同梱 emily4）に任せる。
    public func setStartupGhost(_ directory: String?) {
        if let directory, !directory.isEmpty {
            defaults.set(directory, forKey: Self.startupGhostKey)
        } else {
            defaults.removeObject(forKey: Self.startupGhostKey)
        }
        defaults.synchronize()
    }
}
