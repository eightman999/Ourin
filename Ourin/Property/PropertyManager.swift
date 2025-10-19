import Foundation

/// 登録されたプロバイダを用いてプロパティを解決する管理クラス。
public final class PropertyManager {
    /// プレフィックス（例: `system`）毎のプロバイダ一覧。
    private var providers: [String: PropertyProvider] = [:]

    /// 既定のプロバイダを登録して初期化する。
    public init() {
        register("system", provider: SystemPropertyProvider())
        register("baseware", provider: BasewarePropertyProvider())

        // Emily4をベースゴーストとして設定
        let sampleGhosts = [
            Ghost(name: "Emily/Phase4.5", sakuraname: "Emily", keroname: "Teddy",
                  craftmanw: "Yuyuko", craftmanurl: "https://emily.shillest.net/",
                  path: "emily4", icon: "emily4/ghost/master/icon.ico",
                  homeurl: "https://emily.shillest.net/")
        ]
        let sampleShells = [
            Shell(name: "ULTIMATE FORM", path: "emily4/shell/master"),
            Shell(name: "Casual", path: "emily4/shell/casual")
        ]
        let sampleBalloons = [
            Balloon(name: "SSP Default", path: "/path/to/balloon", craftmanw: "SSP Team", craftmanurl: "")
        ]
        let sampleHeadlines = [
            Headline(name: "News Feed", path: "/path/to/headline")
        ]
        let samplePlugins = [
            PropertyPlugin(name: "Sample Plugin", path: "/path/to/plugin", id: "plugin001")
        ]

        let active = [0]
        register("ghostlist", provider: GhostPropertyProvider(mode: .ghostlist, ghosts: sampleGhosts, activeIndices: active, shells: sampleShells))
        register("activeghostlist", provider: GhostPropertyProvider(mode: .activeghostlist, ghosts: sampleGhosts, activeIndices: active))
        register("currentghost", provider: GhostPropertyProvider(mode: .currentghost, ghosts: sampleGhosts, activeIndices: active, shells: sampleShells))
        register("balloonlist", provider: BalloonPropertyProvider(mode: .balloonlist, balloons: sampleBalloons))
        register("headlinelist", provider: HeadlinePropertyProvider(headlines: sampleHeadlines))
        register("pluginlist", provider: PluginPropertyProvider(plugins: samplePlugins))
    }

    /// `prefix.*` を処理するプロバイダを登録する。
    public func register(_ prefix: String, provider: PropertyProvider) {
        providers[prefix.lowercased()] = provider
    }

    /// 例: `system.year` のような完全キーから値を取得する。
    public func get(_ key: String) -> String? {
        let lower = key.lowercased()
        guard let dot = lower.firstIndex(of: ".") else { return nil }
        let prefix = String(lower[..<dot])
        let rest = String(lower[lower.index(after: dot)...])
        guard let provider = providers[prefix] else { return nil }
        return provider.get(key: rest)
    }

    /// 書き込み可能な場合に値を設定する。
    @discardableResult
    public func set(_ key: String, value: String) -> Bool {
        let lower = key.lowercased()
        guard let dot = lower.firstIndex(of: ".") else { return false }
        let prefix = String(lower[..<dot])
        let rest = String(lower[lower.index(after: dot)...])
        guard let provider = providers[prefix] else { return false }
        return provider.set(key: rest, value: value)
    }
}

/// 文字列中の `%property[...]` を展開するユーティリティ。
public extension PropertyManager {
    func expand(text: String) -> String {
        var result = text
        // `%property[...]` を単純に検索する正規表現
        let pattern = "%property\\[([^\\]]+)\\]"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        for m in matches.reversed() {
            if let r = Range(m.range(at: 1), in: text) {
                let key = String(text[r])
                let value = get(key) ?? ""
                if let full = Range(m.range(at: 0), in: result) {
                    result.replaceSubrange(full, with: value)
                }
            }
        }
        return result
    }
}
